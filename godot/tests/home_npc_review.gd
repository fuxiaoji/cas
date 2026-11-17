extends SceneTree
const Economy=preload("res://scripts/economy.gd")
const Service=preload("res://scripts/home_service.gd")
const Bridge=preload("res://scripts/core_bridge.gd")
const OUTPUT:String="res://../artifacts/home-review/"
var checks:int=0
var failures:Array[String]=[]
var account
var service
var core
var commands:Array=[]
var report:Dictionary={}
func _initialize()->void:call_deferred("run")
func check(ok:bool,label:String)->bool:
	checks+=1
	if not ok:failures.append(label);push_error(label)
	return ok
func ask(command:Dictionary)->Dictionary:
	commands.append(command.duplicate(true));return core.request(command)
func run()->void:
	var source:String="user://cas_port_v1.json";var source_hash:String=FileAccess.get_sha256(source);var backup_hash:String=FileAccess.get_sha256(source+".bak")
	var previous:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(OUTPUT+"receipt.json"))
	var profile:String=OUTPUT+"isolated-npc-%d.json"%OS.get_process_id()
	check(DirAccess.copy_absolute(str(previous.profile),ProjectSettings.globalize_path(profile))==OK,"clone completed legitimate tutorial profile")
	account=Economy.new(profile);check(account.load_state().get("ok",false),"load isolated normal conservation profile");service=Service.new(account);core=Bridge.new()
	var npc_rows:Array=[]
	for island in Service.NPC_ISLANDS:
		var plan:Dictionary=service.prepare_littoral("raid",int(island.seed),Service.RELEASED,["IBS-U-USN-ERMA-MISSOURI","IBS-U-USN-ERMA-IOWA","IBS-U-USN-ERMA-DES-MOINES"],"transport")
		check(plan.get("ok",false),"prepare actual owned forces for "+str(island.name))
		if not plan.get("ok",false):continue
		var world:Dictionary=ask(plan.request)
		check(world.get("ok",false),"native accepts real registered defenses for "+str(island.name))
		if not world.get("ok",false):continue
		check(world.data.littoral.land.buildings.size()==island.layout.size(),"native contains every NPC building for "+str(island.name))
		var saved:String=str(core.request({"op":"save","serialized":true}).serialized)
		var tampered:Dictionary=plan.request.duplicate(true);tampered.defense[0].level=3
		var before:Dictionary=account.state.duplicate(true);var disk:String=FileAccess.get_sha256(profile)
		check(not service.begin(tampered,saved).get("ok",false),"registered NPC layout cannot be forged for "+str(island.name))
		check(service._same(before,account.state) and FileAccess.get_sha256(profile)==disk,"failed NPC bind preserves all account bytes")
		npc_rows.append({"name":island.name,"seed":island.seed,"request":plan.request,"building_count":world.data.littoral.land.buildings.size()})
	check(service.npc_layout(42).is_empty(),"legacy tutorial seed receives no NPC defense override")
	report["islands"]=npc_rows
	var av:String="";var draws:int=0;var draw_evidence:Array=[]
	for batch in range(400):
		var result:Dictionary=account.recruit(10,"home-av-review-%d"%batch,"standard")
		if not check(result.get("ok",false),"real standard recruitment transaction for transport selection"):break
		draws+=10
		for row in result.get("draws",[]):
			if str(row.id) in ["IBS-U-IJN-NISSHIN","IBS-U-IJN-CHITOSE"]:av=str(row.id);draw_evidence.append(row)
		if not av.is_empty():break
	check(not av.is_empty() and account.state.owned.has(av),"transport support identity is actually acquired through paid standard recruitment")
	if not av.is_empty():
		var plan:Dictionary=service.prepare_littoral("raid",18031,Service.RELEASED,[av,"IBS-U-USN-ERMA-MISSOURI"],"transport")
		check(plan.get("ok",false),"actual acquired AV can carry all five real released tactical teams with escort")
		if plan.get("ok",false):
			var world:Dictionary=ask(plan.request);check(world.get("ok",false),"native accepts owned AV transport plan")
			if world.get("ok",false):
				var groups:Array=world.data.littoral.groups
				check(groups.size()==5 and groups.all(func(row):return int(row.carrier)>0),"all five tactical teams are assigned real carrier slots")
				var saved:String=str(core.request({"op":"save","serialized":true}).serialized)
				check(service.begin(plan.request,saved).get("ok",false),"acquired AV sortie begins as a real account transaction")
				var driver:Dictionary=play_raid()
				report["raid_driver"]=driver
				var terminal:Dictionary=core.view.duplicate(true);var terminal_save:String=str(core.request({"op":"save","serialized":true}).serialized)
				check(terminal.get("result")!=null and bool(terminal.littoral.outcome.get("success",false)),"named NPC raid genuinely wins and physically extracts")
				if terminal.get("result")!=null:
					var result:Dictionary=service.settle(terminal,terminal_save);check(result.get("ok",false),"real NPC raid account settlement independently replays exact proof")
					FileAccess.open(OUTPUT+"npc-raid-receipt.json",FileAccess.WRITE).store_string(JSON.stringify(result,"  "))
				FileAccess.open(OUTPUT+"npc-raid-save.json",FileAccess.WRITE).store_string(terminal_save)
				FileAccess.open(OUTPUT+"npc-raid-view.json",FileAccess.WRITE).store_string(JSON.stringify(terminal,"  "))
	report["transport"]={"id":av,"draws":draws,"actual_draws":draw_evidence}
	if not av.is_empty() and account.state.active_run.is_empty():
		var app=load("res://scenes/main.tscn").instantiate();app.boot_to_title=false;app.economy=account;app.page_motion=false;root.content_scale_size=Vector2i(1600,900);root.size=Vector2i(1280,720);root.add_child(app);await process_frame;app.page_motion=false
		app.set_meta("home_battle_mode","salvage");app.show_page("home");await process_frame
		var home:Control=app.page.find_child("HomeIsland",true,false)
		check(home!=null and home.get_node("Layout/Bottom/Sortie").text=="带队搜索遗迹","expedition source points to the real salvage launch action")
		home._sortie();await process_frame
		var av_choice:Button=app.modal.find_child("Sortie_"+av,true,false)
		check(av_choice!=null,"actually recruited AV is selectable as its own naval portrait in sortie modal")
		if av_choice!=null:
			av_choice.button_pressed=true;check(home.naval_selection.has(av),"native selection control includes actual owned AV in outgoing identities")
		check(app.modal.find_child("DeploymentShips",true,false) is ScrollContainer,"outgoing ship selection is a scrollable native control")
		check(app.modal.find_child("NPCIsland",true,false).item_count==3,"all three actual NPC islands are selectable in native UI")
		app.close_modal();app.core.close();app.queue_free();await process_frame
	report["runtime"]=load("res://tests/home_runtime_evidence.gd").capture(core)
	if not OS.has_environment("CAS_SIM_PATH"):check(bool(report.runtime.verified_default),"NPC and AV actual native PID match default manifest without override")
	core.close();check(FileAccess.get_sha256(source)==source_hash,"real source account remains untouched");check(FileAccess.get_sha256(source+".bak")==backup_hash,"real source backup remains untouched")
	report.merge({"checks":checks,"failures":failures,"passed":failures.is_empty(),"profile":ProjectSettings.globalize_path(profile),"native_override":OS.get_environment("CAS_SIM_PATH"),"source_sha256":source_hash,"backup_sha256":backup_hash})
	FileAccess.open(OUTPUT+"npc-receipt.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	FileAccess.open(OUTPUT+"npc-commands.json",FileAccess.WRITE).store_string(JSON.stringify(commands,"  "))
	print("HOME_NPC "+JSON.stringify({"checks":checks,"failures":failures,"transport":av,"draws":draws}));quit(0 if failures.is_empty() else 1)

func play_raid()->Dictionary:
	var deployed:Dictionary={};var ordered:Dictionary={};var retreated:Dictionary={};var routed:bool=false
	var target:Dictionary={}
	for building in core.view.littoral.land.buildings:
		if str(building.kind)=="hq":target=building;break
	ask({"op":"route","fleet":1,"speed":30,"points":[{"x":13000,"y":11500}]})
	for half in range(958):
		var view:Dictionary=core.view
		if view.get("result")!=null:break
		var all_recovered:bool=true
		for group in view.littoral.groups:
			var id:String=str(group.id);var carrier:Dictionary={}
			for ship in view.ships:
				if int(ship.id)==int(group.carrier):carrier=ship;break
			if str(group.stage)=="embarked" and not deployed.has(id) and not carrier.is_empty():
				var at:Vector2=Vector2(float(carrier.x),float(carrier.y));var sea:Dictionary=view.littoral.beaches[1].sea
				if at.distance_to(Vector2(float(sea.x),float(sea.y)))<800:
					var accepted:Dictionary=ask({"op":"littoral_deploy","unit_id":id,"beach":2,"insertion":"landing"})
					if accepted.get("ok",false):deployed[id]=true
			if str(group.stage)=="ground" and not ordered.has(id):
				var accepted:Dictionary=ask({"op":"littoral_order","unit_id":id,"action":"attack","x":target.x,"y":target.y})
				if accepted.get("ok",false):ordered[id]=true
			var objective:bool=view.littoral.objectives.all(func(row):return bool(row.complete))
			if objective and str(group.stage)=="ground" and not retreated.has(id):
				var accepted:Dictionary=ask({"op":"littoral_order","unit_id":id,"action":"retreat"})
				if accepted.get("ok",false):retreated[id]=true
			if str(group.stage) not in ["recovered","lost"]:all_recovered=false
		if not deployed.is_empty() and all_recovered and not routed:
			routed=ask({"op":"route","fleet":1,"speed":30,"points":[{"x":5500,"y":13500}]}).get("ok",false)
		if routed:
			ask({"op":"littoral_extract"})
			if core.view.get("result")!=null:break
		ask({"op":"step","seconds":.5})
	return {"deployed":deployed,"ordered":ordered,"retreated":retreated,"exit_ordered":routed,"tick":core.view.tick,"result":core.view.get("result")}
