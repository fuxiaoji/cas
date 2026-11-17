extends SceneTree
## Explicit maintenance generator. It can only create a NEW file below artifacts/.
## It never installs, repairs or overwrites the normal user account.
const Economy=preload("res://scripts/economy.gd")
const Meta=preload("res://scripts/meta_economy.gd")
const Growth=preload("res://scripts/player_growth.gd")
const Resources=preload("res://scripts/test_account_resources.gd")
const Fleets=preload("res://scripts/fleet_manager.gd")
const Progression=preload("res://scripts/progression.gd")
const Arena=preload("res://scripts/arena_service.gd")
const Home=preload("res://scripts/home_service.gd")
const Core=preload("res://scripts/core_bridge.gd")
const Rules=preload("res://data/player-growth.tres")
var account
var output:String=""
var checks:int=0
var failures:Array[String]=[]
var receipt:Dictionary={}
var template_counter:int=0
var normal_hashes:Dictionary={}
func _initialize()->void:call_deferred("run")
func check(ok:bool,label:String)->bool:
	checks+=1
	if not ok:failures.append(label);push_error(label)
	return ok
func maximum_template(meta,kind:String,slot:String,gear_type:String="")->Dictionary:
	var max_quality:int=0
	for tier in meta.config.gear_tiers:max_quality=maxi(max_quality,int(tier.quality))
	# Use the production item generator to obtain a legal maximum-tier template;
	# no bonus values, substat formulas, rarity names or new gear are invented.
	for attempt in range(100000):
		template_counter+=1
		var item:Dictionary={"id":"qa-template-%d"%template_counter,"kind":kind,"location":"warehouse"}
		meta.decorate(item,"gear-v3")
		if int(item.quality)==max_quality and str(item.slot)==slot and (gear_type.is_empty() or str(item.get("gear_type",""))==gear_type):return item
	check(false,"find production maximum template "+slot+" "+gear_type);return {}
func give_item(template:Dictionary,location:String="warehouse")->String:
	account.state.item_sequence=int(account.state.item_sequence)+1
	var id:String="%s-%d"%[str(template.kind),int(account.state.item_sequence)]
	var item:Dictionary=template.duplicate(true);item.id=id;item.location=location
	account.state.item_instances[id]=item
	return id
func fill_resources(home)->void:
	for key in Resources.WALLET_FLOORS:account.state.wallet[key]=int(Resources.WALLET_FLOORS[key])
	for key in Resources.INVENTORY_FLOORS:account.state.inventory[key]=int(Resources.INVENTORY_FLOORS[key])
	var meta=Meta.new(account)
	account.state.stamina={"value":int(meta.config.stamina_max),"at":int(Time.get_unix_time_from_system())}
	for key in Home.RESOURCE_NAMES:home.state().resources[key]=Home.RESOURCE_CAP
	home.state().tickets=int(Resources.WALLET_FLOORS.tickets)
func run()->void:
	for name in ["cas_port_v1.json","cas_port_v1.json.bak"]:normal_hashes[name]=FileAccess.get_sha256("user://"+name)
	output=ProjectSettings.globalize_path("res://../artifacts/boot-loading-20261114/max-level-test-account-%d.json"%OS.get_process_id()).simplify_path()
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--output="):output=ProjectSettings.globalize_path(argument.trim_prefix("--output=")).simplify_path()
	var allowed:String=ProjectSettings.globalize_path("res://../artifacts/").simplify_path().trim_suffix("/")+"/"
	if not check(output.to_lower().begins_with(allowed.to_lower()) and output.ends_with(".json"),"output is an isolated artifacts JSON path"):finish();return
	if not check(not FileAccess.file_exists(output) and not FileAccess.file_exists(output+".bak"),"refuse to overwrite an existing account or backup"):finish();return
	account=Economy.new(output)
	if not check(account.load_state().get("ok",false),"create ordinary profile through real Economy factory"):finish();return
	check(account.load_state().get("ok",false),"apply ordinary first-load migrations")
	var progression=Progression.new(account)
	var fleets=Fleets.new(account)
	var arena=Arena.new(account)
	var home=Home.new(account)
	account.state.test_account=Resources.MARKER
	account.state.commander.level=Rules.commander_max_level;account.state.commander.xp=0
	var max_ascension:int=Rules.ascensions.size()
	var template_growth:Dictionary=account.growth_profile(str(account.state.owned.keys()[0]))
	var ship_cap:int=int(template_growth.max_level)
	var mastery_cap:int=int(template_growth.mastery_max)
	for card in account.catalog:
		if not bool(card.get("playable",false)):continue
		var id:String=str(card.id)
		if not account.state.owned.has(id):account.state.owned[id]=account._new_owned(id)
		var row:Dictionary=account.state.owned[id]
		row.level=ship_cap;row.ascension=max_ascension;row.mastery=mastery_cap;row.xp=0
		row.hp=100;row.ammo=100;row.protected=false;row.canNavigate=true
	Meta.new(account).ensure()
	var meta=Meta.new(account)
	var equipment:Dictionary={};var crew:Dictionary={}
	for gear in Rules.gear_types:equipment[str(gear.id)]=maximum_template(meta,"equipment","equipment",str(gear.id))
	for slot in meta.config.crew_slots:crew[str(slot)]=maximum_template(meta,"command",str(slot))
	if not failures.is_empty():finish();return
	for id in account.state.owned:
		var row:Dictionary=account.state.owned[id]
		var kind:String=str(account._cards[id].get("type",""))
		var choice:String="propulsion" if kind=="DD" else "ballistics" if kind in ["CL","CA"] else "fire_control" if kind in ["BB","BC"] else "balanced"
		row.equipment=give_item(equipment[choice],str(id))
		for slot in meta.config.crew_slots:row.crews[str(slot)]=give_item(crew[str(slot)],str(id))
		row.command=str(row.crews.command)
	# Keep finite, real warehouse instances. Inflating aggregate equipment counters
	# would cause migrations to manufacture millions of items and stall startup.
	for template in equipment.values():give_item(template)
	for template in crew.values():give_item(template)
	account.state.inventory.equipment=equipment.size();account.state.inventory.command=crew.size()
	for unit in home.released():home._own_unit(str(unit.id))
	# This is an explicit QA asset grant, separate from earned mission completion.
	# Tutorials and stories remain replayable with their original uncompleted state.
	home.state().unlocked=true
	home.state()["qa_island_grant"]={"source":"explicit full-level test-account request","tutorial_completion_granted":false}
	fill_resources(home)
	# Existing building progression is exercised through its real transaction API.
	for kind in Home.BUILDINGS:
		if kind=="hq":continue
		var found:bool=false
		for y in range(Home.GRID.y):
			if found:break
			for x in range(Home.GRID.x):
				var cell:=Vector2i(x,y)
				if home.is_land(cell) and home.building_at(cell).is_empty():
					check(home.place(str(kind),cell).get("ok",false),"grant real building "+str(kind));found=true;break
	for building in home.state().buildings:
		while home.upgrade(str(building.id)).get("ok",false):pass
	fill_resources(home)
	var amphibious:Array=["CAS-H-USN-ENTERPRISE-1942","CAS-H-IJN-SHOKAKU-1942","CAS-O-LHA-RETURNLIGHT","CAS-O-APV-TIDEBRIDGE"]
	account.state.fleet_book=[{"id":"fleet-1","name":"测试主力舰队","ships":account.formation.duplicate()},{"id":"fleet-amphibious","name":"两栖航空试验队","ships":amphibious.duplicate()}]
	account.state.active_fleet_id="fleet-1";account.state.sortie_fleet_ids=["fleet-1"]
	check(home.set_garrison(amphibious).get("ok",false),"real naval garrison transaction")
	check(home.set_tactical_garrison(["MCP-034","MCP-001","MCP-022"]).get("ok",false),"real tactical garrison transaction")
	var profiles:Array=["coord","gunnery","torpedo"]
	for profile in progression.ai_catalog:
		if not profiles.has(str(profile.id)):profiles.append(str(profile.id))
	account.state.progression.profiles=profiles
	account.state["qa_account_generation"]={"version":"max-level-test-2026-11-14","source":"new production profile; no restored old progress","catalogue_only":true,"commander_cap":Rules.commander_max_level,"ship_cap":ship_cap,"ascension_cap":max_ascension,"mastery_cap":mastery_cap,"tactical_growth":"No tactical XP or level mechanics exist; all released personalities at actual 100% readiness.","island_access":"Explicit QA island grant; tutorial_complete and all battle clears remain false/unearned.","at":int(Time.get_unix_time_from_system())}
	check(account.save_state().get("ok",false),"commit full test account through journaled production save")
	var reloaded=Economy.new(output)
	check(reloaded.load_state().get("ok",false),"production reload accepts completed account")
	var check_home=Home.new(reloaded);var check_growth=Growth.new(reloaded)
	var playable:int=0;var max_quality:int=0
	for tier in meta.config.gear_tiers:max_quality=maxi(max_quality,int(tier.quality))
	for card in reloaded.catalog:
		if not bool(card.get("playable",false)):continue
		playable+=1;var id:String=str(card.id)
		check(reloaded.state.owned.has(id),"real playable ship owned "+id)
		var row:Dictionary=reloaded.state.owned[id]
		check(int(row.level)==check_growth.cap(row) and int(row.level)==ship_cap,"actual ship level cap "+id)
		check(int(row.mastery)==mastery_cap and int(row.ascension)==max_ascension,"actual mastery and breakthrough caps "+id)
		check(int(row.hp)==100 and int(row.ammo)==100,"fully prepared real ship "+id)
		for item_id in [str(row.equipment)]+row.crews.values():
			var item:Dictionary=reloaded.state.item_instances.get(str(item_id),{})
			check(int(item.get("quality",-1))==max_quality and str(item.get("location",""))==id,"real top-tier equipped instance "+str(item_id))
	check(reloaded.state.owned.size()==playable,"no nonplayable or fabricated ship identities")
	check(int(reloaded.player_profile().level)==Rules.commander_max_level,"commander uses actual authored maximum")
	check(check_home.state().units.size()==check_home.released().size(),"all actually released tactical personalities owned")
	for unit in check_home.released():check(is_equal_approx(check_home.condition(str(unit.id)),100),"actual tactical readiness cap "+str(unit.id))
	check(not bool(check_home.state().tutorial_complete),"home tutorial is uncompleted and can be played")
	check(reloaded.state.progression.campaign.is_empty() and reloaded.state.progression.challenge.is_empty(),"no campaign or challenge wins fabricated")
	check(reloaded.state.active_run.is_empty() and reloaded.state.settled.is_empty(),"new account has no fabricated active run or settlements")
	for key in Resources.WALLET_FLOORS:check(int(reloaded.state.wallet.get(key,0))>=int(Resources.WALLET_FLOORS[key]),"resource floor "+str(key))
	var unit_results:Array=[]
	for unit in check_home.released():
		var roster:Array=[str(unit.id),"MCP-034" if str(unit.id)!="MCP-034" else "MCP-001"]
		var prepared:Dictionary=check_home.prepare_littoral("raid",29143,roster,amphibious,"transport")
		check(prepared.get("ok",false),"current native can deploy real tactical unit "+str(unit.id)+" "+str(prepared.get("message","")))
		unit_results.append({"id":str(unit.id),"ready":prepared.get("ok",false),"message":prepared.get("message","")})
	# Check ordinary tutorial preparation remains reachable despite the QA access grant.
	for lesson in ["sea_control","landing","combined"]:check(check_home.prepare_littoral("tutorial",42,[],[],"balanced",Home.BATTLE_VERSION,lesson).get("ok",false),"real tutorial remains playable "+lesson)
	receipt["summary"]={"ships":reloaded.state.owned.size(),"tactical_units":check_home.state().units.size(),"commander_level":reloaded.player_profile().level,"ship_level":ship_cap,"ascension":max_ascension,"mastery":mastery_cap,"equipment_quality":max_quality,"equipped_instances":playable*(1+meta.config.crew_slots.size()),"warehouse_instances":equipment.size()+crew.size(),"home_buildings":check_home.state().buildings.size(),"tutorial_complete":false,"campaign_clears":0,"active_run":false}
	receipt["tactical_native_deployment"]=unit_results
	receipt["profile_sha256"]=FileAccess.get_sha256(output)
	finish()
func finish()->void:
	for name in normal_hashes:check(FileAccess.get_sha256("user://"+str(name))==normal_hashes[name],"normal user file untouched "+str(name))
	receipt.merge({"passed":failures.is_empty(),"checks":checks,"failures":failures,"profile":output,"normal_profile_written":false,"normal_hashes":normal_hashes,"template_candidates_tested":template_counter})
	var receipt_path:String=ProjectSettings.globalize_path("res://../artifacts/boot-loading-20261114/max-level-test-account-receipt.json")
	FileAccess.open(receipt_path,FileAccess.WRITE).store_string(JSON.stringify(receipt,"  "))
	print("MAX_LEVEL_TEST_ACCOUNT "+JSON.stringify(receipt));quit(0 if failures.is_empty() else 1)
