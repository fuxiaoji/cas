extends SceneTree
const VERSION:String="cas-island-war-v4"
const OUTPUT:String="res://../artifacts/island-war-v4/home/"
var checks:int=0
var failures:Array[String]=[]
var account
var home
var core
var app
var formal_hash:String
var backup_hash:String
var ui_complete:bool=false
var actual_input_events:int=0
var deployment_points:Dictionary={}
func _initialize()->void:call_deferred("run")
func check(value:bool,message:String)->bool:
	checks+=1
	if not value:failures.append(message);push_error(message)
	return value
func inject(event:InputEvent)->void:
	actual_input_events+=1;root.push_input(event,true)
func frames(count:int=4)->void:
	for index in range(count):await process_frame
func reveal(node:Control)->void:
	var ancestor:Node=node.get_parent()
	while ancestor!=null:
		if ancestor is ScrollContainer:ancestor.ensure_control_visible(node)
		ancestor=ancestor.get_parent()
	await frames(2)
func click(node:Control)->void:
	if not check(node!=null,"real requested control exists"):return
	await reveal(node)
	await create_timer(.03).timeout
	var point:Vector2=node.get_global_transform_with_canvas()*(node.size*.5)
	if OS.get_environment("CAS_HOME_V4_TRACE")=="1":
		print("CLICK ",node.name," ",point," rect=",node.get_global_rect()," focus=",root.has_focus()," globalmask=",Input.get_mouse_button_mask())
		node.gui_input.connect(func(event):print("GUI ",node.name," ",event.as_text()),CONNECT_ONE_SHOT)
		if node is Button:
			node.button_down.connect(func():print("DOWN ",node.name),CONNECT_ONE_SHOT)
			node.button_up.connect(func():print("UP ",node.name),CONNECT_ONE_SHOT)
			node.pressed.connect(func():print("PRESSED ",node.name),CONNECT_ONE_SHOT)
	var motion:=InputEventMouseMotion.new();motion.position=point;inject(motion);await process_frame
	if OS.get_environment("CAS_HOME_V4_TRACE")=="1":print("HOVER ",root.gui_get_hovered_control())
	for pressed in [true,false]:
		var event:=InputEventMouseButton.new();event.position=point;event.button_index=MOUSE_BUTTON_LEFT;event.button_mask=MOUSE_BUTTON_MASK_LEFT if pressed else 0;event.pressed=pressed;inject(event);await create_timer(.03).timeout
	await frames(5)
func button_text(root_node:Node,text:String)->Button:
	if root_node==null:return null
	for node in root_node.find_children("*","Button",true,false):
		if node.text==text and node.is_visible_in_tree():return node
	return null
func drag_on(node:Control,from:Vector2,to:Vector2)->void:
	var transform:Transform2D=node.get_global_transform_with_canvas()
	await create_timer(.03).timeout
	var press:=InputEventMouseButton.new();press.position=transform*from;press.button_index=MOUSE_BUTTON_LEFT;press.button_mask=MOUSE_BUTTON_MASK_LEFT;press.pressed=true;inject(press);await create_timer(.03).timeout
	var motion:=InputEventMouseMotion.new();motion.position=transform*to;motion.relative=transform.basis_xform(to-from);motion.button_mask=MOUSE_BUTTON_MASK_LEFT;inject(motion);await create_timer(.03).timeout
	var release:=InputEventMouseButton.new();release.position=transform*to;release.button_index=MOUSE_BUTTON_LEFT;release.pressed=false;inject(release);await frames(5)
func shot(name:String)->void:
	if DisplayServer.get_name()=="headless":return
	await frames(3);RenderingServer.force_draw()
	check(root.get_texture().get_image().save_png(ProjectSettings.globalize_path(OUTPUT+name+".png"))==OK,"GPU evidence "+name)
func snapshot()->String:return str(core.request({"op":"save","serialized":true}).get("serialized",""))
func fixture()->void:
	account.state.active_run={};account.state.commander.level=30;account.state.progression.first_voyage_canon.active=false
	home.state().unlocked=true;home.state().tutorial_complete=true;home.state().drag_tutorial_completed=true
	for key in home.RESOURCE_NAMES:home.state().resources[key]=15000
	for id in ["IBS-U-USN-ERMA-IOWA","CAS-H-USN-ENTERPRISE-1942","CAS-O-LHA-RETURNLIGHT"]:
		account.state.owned[id]=account._new_owned(id);account.state.owned[id].hp=100;account.state.owned[id].ammo=100
	for row in home.v4_units():
		home._own_unit(str(row.id));home.state().units[str(row.id)].condition=100;home.state().units[str(row.id)].at=home._now()
		if home.state().units[str(row.id)].has("vehicle_condition_v3"):home.state().units[str(row.id)].erase("vehicle_condition_v3")
	home.state().garrison=["IBS-U-USN-ERMA-IOWA","CAS-O-LHA-RETURNLIGHT"];home.state().tactical_garrison=["MCP-034","MCP-088","MCP-006"]
	account.state.wallet.ammo_stock=50000
	home.state().buildings=home.state().buildings.filter(func(row):return str(row.id)!="qa-v2-depot")
	home.state().buildings.append({"id":"qa-v2-depot","kind":"depot","level":2,"cell":{"x":5,"y":4},"hp":83})
func pure_account()->void:
	var ordinary:Dictionary=account.state.duplicate(true)
	check(not home.unlock_test_units_v2().ok and home._same(account.state,ordinary),"normal profile is not silently given27 personalities")
	check(home.state().units.size()<27,"opening the new catalogue does not grant its unowned personalities")
	check(home.v4_cards.size()==27 and home.v4_units().size()==27,"27 card identities are sourced from the new native catalogue")
	fixture();home.development()
	new_personality_acquisition()
	var unit_models:Dictionary={}
	for card in home.v4_units():
		check(is_equal_approx(float(card.body_stats.hp),float(card.body_stats.baseline_hp)*4.0),"native v4 base body health is4x "+str(card.id))
		check(card.weapon_composition.size()==int(card.personnel_per_company),"per-company weapon slots cover every actual body "+str(card.id))
		check(bool(card.get("fixed_transport",false)) and card.transport_options.size()==1 and str(card.transport_options[0].kind)==str(card.default_transport),"personality has exactly one fixed native landing method "+str(card.id))
		check(home.v4_transport_option(str(card.id),"not-this-personality-transport").is_empty(),"service rejects free replacement of the fixed landing equipment "+str(card.id))
		for slot in card.weapon_composition:check(home.v4_weapons.has(str(slot.weapon_id)),"body weapon exists in same native table")
		var first_model:String=str(card.weapon_composition[0].weapon_id)
		check(not unit_models.has(first_model),"different personalities use distinct concrete primary weapon models "+str(card.id));unit_models[first_model]=str(card.id)
		if str(card.role)=="antiarmor":check(card.weapon_composition.filter(func(slot):return str(home.v4_weapons[str(slot.weapon_id)].get("family_id",slot.weapon_id))=="rocket").size()==1,"antiarmor company has exactly one rocket specialist")
		if str(card.role)=="artillery":check(card.combat_vehicles.size()==1 and card.weapon_composition.all(func(slot):return str(home.v4_weapons[str(slot.weapon_id)].get("family_id",slot.weapon_id))=="pistol"),"artillery bodies only carry pistols alongside one real SPG")
	for weapon in home.v4_weapons.values():
		check(not str(weapon.get("family_id","")).is_empty() and str(weapon.id)!=str(weapon.family_id),"concrete weapon identity is distinct from its family "+str(weapon.id))
		check(float(weapon.get("fire_interval_s",0))>0 and float(weapon.get("magazine_reload_s",0))>0 and int(weapon.get("burst_size",0))>0 and int(weapon.get("magazine_capacity",0))>0,"native concrete model separates fire interval and magazine reload "+str(weapon.id))
	check(int(home.tactical_profile("MCP-006").deployed_bodies)==6,"six actual infantry bodies are not duplicated into free pilots or passengers")
	for id in ["MCP-022","MCP-103","MCP-087","MCP-027","MCP-006"]:
		var combined:Dictionary=home.v4_profile(id)
		check(combined.combat_vehicles.size()==1 and int(combined.combat_vehicles[0].get("count_per_company",0))==1 and bool(combined.combat_vehicles[0].get("separate_vehicle_hp",false)) and int(combined.combat_vehicles[0].get("min_crew",-1))==0,"one independently controlled vehicle per company with no free driver body "+id)
	check(int(home.v4_profile("MCP-022").personnel_per_company)==6,"armored company retains six actual rifle bodies beside its tank")
	check(int(home.v4_profile("MCP-022").combat_vehicles[0].passenger_seats)==0,"tank has no free passenger bodies or infantry seating")
	vehicle_maintenance()
	check(int(home.tactical_profile("MCP-088").deployed_bodies)==50,"88th five ten-body companies are finite")
	for row in home.v4_units():
		var id:String=str(row.id);var stats:Dictionary=home.v4_profile(id)
		check(int(home.tactical_profile(id).deployed_bodies)==int(stats.company_count)*int(stats.personnel_per_company),"progression finite count matches native "+id)
		check(not stats.combat.is_empty() and not stats.ability.is_empty() and not stats.transport_options.is_empty(),"combat ability and transport profile "+id)
	var no_meta:Dictionary=home.state().units["MCP-006"].duplicate(true);home.state().units["MCP-006"]={"condition":83.0,"at":home._now(),"losses":3,"vehicle_condition_v3":{"1":63.0}}
	var fixed_before:Dictionary=account.state.duplicate(true);var illegal_transport:Dictionary=home.prepare_exercise_v4(["MCP-006"],home.state().garrison,"balanced",[{"id":"MCP-006","kind":"kayak"}])
	check(not illegal_transport.get("ok",false) and home._same(fixed_before,account.state),"illegal replacement of the helicopter with a kayak fails with no account effects")
	var before:Dictionary=account.state.duplicate(true);var exercise:Dictionary=home.prepare_exercise_v4(["MCP-088","MCP-006"],home.state().garrison)
	if not check(exercise.get("ok",false),"real own-v-own exercise preview: "+str(exercise.get("message",""))):return
	check(home._same(before,account.state),"first exercise preview does not add progression defaults or charge anything")
	check(exercise.request.defender.roster==home.state().tactical_garrison and exercise.request.defender.ships.size()==home.state().garrison.size(),"defender contains exactly actual saved own garrison")
	check(exercise.request.vehicle_condition.any(func(row):return row.id=="MCP-006" and float(row.hp_percent)==63) and exercise.request.defender.vehicle_condition.any(func(row):return row.id=="MCP-006" and float(row.hp_percent)==63),"own exercise copies actual63% vehicle health on both sides without healing")
	check(core.request(exercise.request).get("ok",false),"native constructs own damaged-vehicle exercise")
	var native_vehicles:Array=core.view.get("littoral",{}).get("land",{}).get("combat_vehicles",[])
	check(native_vehicles.any(func(row):return row.unit_id=="MCP-006" and is_equal_approx(float(row.hp)/float(row.max_hp),.63)),"real native exercise vehicle starts at persisted health rather than full health")
	check(int(exercise.request.island.forts.filter(func(row):return row.id=="qa-v2-depot")[0].hp)==83,"own real damaged facility is copied without healing")
	home.state().units["MCP-006"]=no_meta
	var saved_garrison:Array=home.state().tactical_garrison.duplicate();home.state().tactical_garrison=[]
	before=account.state.duplicate(true);check(not home.prepare_exercise_v4(["MCP-006"],home.state().garrison).ok and home._same(before,account.state),"missing own garrison fails rather than borrowing NPC defenders");home.state().tactical_garrison=saved_garrison
	account.state.active_run={"run_id":"preserved-voyage","mode":"littoral","ruleset":"cas-island-war-v1","request":{"opaque":true},"snapshot":"frozen"}
	before=account.state.duplicate(true);exercise=home.prepare_exercise_v4(["MCP-006"],home.state().garrison);check(exercise.get("ok",false) and home._same(before,account.state),"independent exercise preview preserves an active voyage and all account state");account.state.active_run={}
	check(core.request(exercise.request).get("ok",false),"real core starts the isolated exercise")
	var initial:String=snapshot();check(bool(core.view.get("island_war",{}).get("exercise",false)),"native observation labels exercise")
	before=account.state.duplicate(true);check(not home.begin(exercise.request,initial).ok and home._same(before,account.state),"exercise can never bind account voyage or deduct ammo")
	check(not home.settle(core.view,initial).ok and home._same(before,account.state),"exercise can never enter paid settlement")
	FileAccess.open(OUTPUT+"exercise-request.json",FileAccess.WRITE).store_string(JSON.stringify(exercise.request,"  "))
	FileAccess.open(OUTPUT+"exercise-initial.json",FileAccess.WRITE).store_string(initial)
	check(home.set_tactical_garrison_v4(["MCP-006"]).ok,"one-company006 is a valid separate own garrison")
	check(home.v4_training("landing").get("ok",false),"new borrowed landing course comes from authoritative lesson catalogue")
	check(home.latest_training_lessons().size()==6,"all six real native training courses are reachable")
	for lesson in ["landing","weapons","artillery","airborne","roles","combined_arms"]:
		var course:Dictionary=home.v4_training(lesson);before=account.state.duplicate(true)
		check(course.get("ok",false) and core.request(course.get("request",{})).get("ok",false),"every visible v3 course is a real constructible native lesson "+lesson)
		if course.get("ok",false) and core.view.get("island_war",{}).get("version")==VERSION:
			var course_save:Variant=JSON.parse_string(snapshot());check(course_save is Dictionary and int(course_save.seed)==int(course.request.seed),"borrowed lesson preserves authoritative terrain seed "+lesson)
		check(home._same(before,account.state),"course preview preserves account "+lesson)
	before=account.state.duplicate(true);check(not home.v4_training("not-a-lesson").get("ok",false) and home._same(before,account.state),"invalid course has no account effect")
	home.state().tactical_garrison=saved_garrison
	# All building transactions use real native placement, then one atomic ledger write.
	for kind in ["land_mine","beach_position","sea_mine"]:
		var quote:Dictionary={}
		for point in [Vector2(.2,.5),Vector2(.35,.7),Vector2(.6,.5),Vector2(-.5,.5),Vector2(1.15,.5),Vector2(.5,-.5),Vector2(.5,1.15)]:
			quote=home.island_v4().placement_preview(kind,point.x,point.y)
			if quote.get("ok",false):deployment_points[kind]=point;break
		if not check(quote.get("ok",false),"native-valid "+kind+" position found"):continue
		before=account.state.duplicate(true);var stock:Dictionary=home.state().resources.duplicate(true);var entry:Dictionary=quote.entry
		check(home._same(before,account.state),"placement preview/cancel leaves account unchanged")
		var transaction:String="qa-place-"+kind;var paid:Dictionary=home.island_v4().place(kind,float(entry.x),float(entry.y),transaction,quote.cost)
		if not check(paid.get("ok",false),"confirmed native-valid deployment commits "+kind+": "+str(paid.get("message",""))):continue
		for key in quote.cost:check(int(home.state().resources[key])==int(stock[key])-int(quote.cost[key]),"exact deployment charge "+kind+" "+key)
		var after:Dictionary=account.state.duplicate(true);check(home.island_v4().place(kind,float(entry.x),float(entry.y),transaction,quote.cost).get("duplicate",false) and home._same(after,account.state),"repeated deploy confirmation is idempotent "+kind)
	before=account.state.duplicate(true);check(not home.island_v4().place("sea_mine",.5,.5,"qa-bad-water").ok and home._same(before,account.state),"illegal water-mine placement has no partial charge")
	var resources:Dictionary=home.state().resources.duplicate(true);var old:Dictionary=home.island_v4().deployables()[0] if not home.island_v4().deployables().is_empty() else {}
	if not old.is_empty():
		check(home.island_v4().remove(str(old.id),"qa-remove").ok and home.state().resources==resources,"deployment removal does not mint materials")
		before=account.state.duplicate(true);check(home.island_v4().remove(str(old.id),"qa-remove").get("duplicate",false) and home._same(before,account.state),"deployment removal is idempotent")
	var loaded=load("res://scripts/economy.gd").new(account.save_path);check(loaded.load_state().ok,"new defense and27 progress ledger reloads")
	var restored=load("res://scripts/home_service.gd").new(loaded);check(home._same(restored.island_v2().deployables(),home.island_v4().deployables()),"actual paid positions persist across account reload")
func old_v2_load()->void:
	var plan:Dictionary=home.prepare_island_v2("raid","shoal_watch",["MCP-088","MCP-006"],home.state().garrison,"balanced",[],714)
	if not check(plan.get("ok",false) and core.request(plan.request).get("ok",false),"published v2 still constructs on original path"):return
	var initial:String=snapshot();check(home.begin(plan.request,initial).get("ok",false),"existing v2 voyage binds without being rewritten to v3")
	check(str(account.state.active_run.ruleset)=="cas-island-war-v2" and core.request({"op":"load","serialized":initial}).get("ok",false),"v2 saved voyage loads unchanged")
	check(snapshot()==initial,"v2 serialized save remains byte-for-byte unchanged")
	check(core.request({"op":"littoral_abandon"}).get("ok",false) and home.settle(core.view,snapshot(),true).get("ok",false),"v2 saved voyage settles on frozen v2 account service")
	fixture();home.development()
func old_v3_load()->void:
	var plan:Dictionary=home.prepare_island_v3("raid","shoal_watch",["MCP-088","MCP-006"],home.state().garrison,"balanced",[],714)
	if not check(plan.get("ok",false) and core.request(plan.request).get("ok",false),"published v3 still constructs on original path"):return
	var initial:String=snapshot();check(home.begin(plan.request,initial).get("ok",false),"existing v3 voyage binds without being rewritten to v3")
	check(str(account.state.active_run.ruleset)=="cas-island-war-v3" and core.request({"op":"load","serialized":initial}).get("ok",false),"v3 saved voyage loads unchanged")
	check(snapshot()==initial,"v3 serialized save remains byte-for-byte unchanged")
	check(core.request({"op":"littoral_abandon"}).get("ok",false) and home.settle(core.view,snapshot(),true).get("ok",false),"v3 saved voyage settles on frozen v3 account service")
	fixture();home.development()
func new_personality_acquisition()->void:
	var original:Dictionary=account.state.duplicate(true);var ids:Array=["MCP-301","MCP-302","MCP-303","MCP-304","MCP-305"]
	for id in ids:home.state().units.erase(id)
	home.state().tickets=10
	for index in range(ids.size()):
		# Labelled account fixture at the existing unseen-personality pity boundary.
		home.state().pity=19;var tickets:int=int(home.state().tickets)
		var result:Dictionary=home.draw_units(1,"v4-real-recruit-%d"%index)
		check(result.get("ok",false) and result.results.size()==1 and ids.has(result.results[0].id) and not bool(result.results[0].duplicate),"normal paid pity draw acquires a real new personality")
		check(int(home.state().tickets)==tickets-1,"new-personality draw consumes one actual ticket")
		var id:String=str(result.results[0].id);var frozen:Dictionary=account.state.duplicate(true)
		check(home.draw_units(1,"v4-real-recruit-%d"%index).get("duplicate",false) and home._same(frozen,account.state),"replayed new-personality recruitment is idempotent")
		var quote:Dictionary=home.development(true).training_preview(id,1);check(quote.get("ok",false) and quote.ready,"new personality shares real growth preview "+id)
		check(home.development(true).train(id,1,"v4-train-"+id).get("ok",false) and int(home.state().units[id].get("xp",0))>0,"new personality gains actual training progress "+id)
	for id in ids:check(home.state().units.has(id),"all five new personalities are ownable through normal recruitment "+id)
	account.state=original;account.save_state()
func geometry_review()->void:
	var before:Dictionary=account.state.duplicate(true);var disk:String=FileAccess.get_sha256(account.save_path)
	for building in home.state().buildings:
		if str(building.kind)=="hq":building.level=1
	var low:Dictionary=home.geometry_v4();check(low.get("ok",false) and float(low.width_m)==3200 and float(low.height_m)==4400,"HQ1 native island is3200x4400 metres")
	for building in home.state().buildings:
		if str(building.kind)=="hq":building.level=5
	var high:Dictionary=home.geometry_v4();check(high.get("ok",false) and float(high.width_m)==8000 and float(high.height_m)==10000,"HQ5 native island is8000x10000 metres")
	check(high.construction_grid.buildable_cells.size()>low.construction_grid.buildable_cells.size() and high.construction_grid.buildable_cells.size()>1000,"real level expansion unlocks native land rather than enlarging a fixed12x9 picture")
	check(home._same(high.construction_grid.origin,low.construction_grid.origin) and float(high.construction_grid.cell_size_m)==120,"HQ upgrades preserve absolute construction origin and120 metre grid")
	var low_hq:Dictionary=low.land.buildings.filter(func(row):return row.kind=="hq")[0];var high_hq:Dictionary=high.land.buildings.filter(func(row):return row.kind=="hq")[0]
	check(home._same(low_hq.world_position,high_hq.world_position),"existing HQ world position never drifts on enlargement")
	var projector=load("res://scripts/home_projection_v4.gd").new();projector.bind(high);projector.screen=Rect2(0,0,2000,1600)
	var sampled:int=0
	for raw in high.construction_grid.buildable_cells:
		if sampled%41==0:
			var cell:=Vector2i(int(raw.x),int(raw.y));var world:Vector2=projector.world(Vector2(cell));var point:Vector2=projector.project(world);var picked:Vector2=projector.unproject(point)
			if projector.cell_at(point)==cell:check(true,"visible native elevated cell round-trips exact picking "+str(cell))
			else:check(projector.height(picked)>projector.height(world) and projector.project(picked).distance_to(point)<.1,"overlapping cliff projection selects the genuinely higher visible surface "+str(cell))
		sampled+=1
	var choice:=Vector2i(-10000,-10000);var nearest:float=INF
	for raw in high.construction_grid.buildable_cells:
		var cell:=Vector2i(int(raw.x),int(raw.y))
		if cell.x>=0 and cell.x<12 and cell.y>=0 and cell.y<9:continue
		var distance:float=Vector2(cell-Vector2i(6,4)).length_squared()
		if distance<nearest and home.building_at(cell).is_empty():choice=cell;nearest=distance
	check(choice.x!=-10000,"a legal native construction address exists beyond the old12x9 rectangle")
	var quote:Dictionary=home.geometry_candidate_v4("recycler",choice);check(quote.get("ok",false),"native validates an expanded-island construction cell")
	check(FileAccess.get_sha256(account.save_path)==disk,"geometry and construction preview never write account")
	var stock:Dictionary=home.state().resources.duplicate(true);var count:int=home.state().buildings.size()
	var placed:Dictionary=home.place("recycler",choice);check(placed.get("ok",false),"actual expanded cell construction is accepted")
	for key in home.BUILDINGS.recycler.cost:check(int(home.state().resources[key])==int(stock[key])-int(home.BUILDINGS.recycler.cost[key]),"expanded construction charges only exact advertised cost "+str(key))
	check(home.state().buildings.size()==count+1 and not home.building_at(choice).is_empty(),"expanded construction preserves actual negative or greater-than-old addresses")
	var frozen:Dictionary=account.state.duplicate(true);check(not home.place("recycler",choice).get("ok",false) and home._same(frozen,account.state),"repeat occupied placement cannot duplicate facility or charge")
	check(not home.place("recycler",Vector2i(10000,10000)).get("ok",false) and home._same(frozen,account.state),"outside native island placement cannot charge")
	account.state=before;fixture();home.development();account.save_state()
func vehicle_maintenance()->void:
	var id:String="MCP-022";var original:Dictionary=home.state().units[id].duplicate(true)
	var before:Dictionary=account.state.duplicate(true)
	var healthy:Array=home.v4_vehicle_profiles(id)
	check(not healthy.is_empty() and healthy.all(func(row):return float(row.hp_percent)==100) and home._same(before,account.state),"unrecorded vehicle health defaults to100 without writing account")
	home.state().units[id]["vehicle_condition_v3"]={"1":0.0,"2":45.5}
	before=account.state.duplicate(true);var quote:Dictionary=home.development(true).vehicle_repair_preview(id,80,1)
	check(quote.get("ok",false) and quote.ready and home._same(before,account.state),"vehicle repair preview and cancel are pure")
	var native:Dictionary=healthy[0].repair_cost_full
	for key in native:check(int(quote.cost[key])==int(ceil(float(native[key])*.8)),"proportional vehicle repair cost comes only from native catalogue "+str(key))
	check(not home.development(true).repair_vehicles(id,80,1,"wrong-vehicle-quote",{"scrap":0}).get("ok",false) and home._same(before,account.state),"stale vehicle price cannot partially charge")
	var body_hp:float=home.condition(id);var stock:Dictionary=home.state().resources.duplicate(true)
	check(home.development(true).repair_vehicles(id,80,1,"vehicle-repair-once",quote.cost).get("ok",false),"confirmed per-company vehicle repair succeeds")
	check(float(home.state().units[id].vehicle_condition_v3["1"])==80 and float(home.state().units[id].vehicle_condition_v3["2"])==45.5 and is_equal_approx(home.condition(id),body_hp),"repair changes only selected vehicle, never other company or body condition")
	for key in quote.cost:check(int(home.state().resources[key])==int(stock[key])-int(quote.cost[key]),"vehicle repair single real resource charge "+str(key))
	before=account.state.duplicate(true)
	check(home.development(true).repair_vehicles(id,80,1,"vehicle-repair-once",quote.cost).get("duplicate",false) and home._same(before,account.state),"vehicle repair repeat request cannot charge twice")
	var plan:Dictionary=home.prepare_island_v4("raid","shoal_watch",[id],home.state().garrison,"balanced",[],714)
	if check(plan.get("ok",false),"partially repaired fixed vehicle can prepare a real paid raid"):
		var forged:Dictionary=plan.request.duplicate(true)
		for row in forged.vehicle_condition:row.hp_percent=100.0
		check(core.request(forged).get("ok",false),"native can construct a standalone full-health comparison fixture")
		var serialized:String=snapshot();before=account.state.duplicate(true)
		check(not home.begin(forged,serialized).get("ok",false) and home._same(before,account.state),"account rejects a forged full-health vehicle snapshot without charging or healing")
	home.state().units[id].vehicle_condition_v3["1"]=0.0
	before=account.state.duplicate(true)
	var denied:Dictionary=home.prepare_exercise_v4([id],home.state().garrison)
	check(not denied.get("ok",false) and home._same(before,account.state),"unrepaired zero-hp fixed combat vehicle cannot respawn free on next departure")
	home.state().units[id]=original
func paid_voyage(mode:String="raid")->void:
	account.state.active_run={}
	for id in ["MCP-006","MCP-088"]:home.state().units[id].erase("vehicle_condition_v3")
	var plan:Dictionary=home.prepare_island_v4(mode,"shoal_watch",["MCP-088","MCP-006"],home.state().garrison,"balanced",[],714)
	if not check(plan.get("ok",false),"native v4 "+mode+" plan succeeds: "+str(plan.get("message",""))):return
	check(core.request(plan.request).get("ok",false),"actual v3 paid battle starts");var initial:String=snapshot();var ammunition:int=int(account.state.wallet.ammo_stock)
	var begun:Dictionary=home.begin(plan.request,initial)
	if not check(begun.get("ok",false),"v3 native configuration binds exactly: "+str(begun.get("message",""))):return
	check(int(account.state.wallet.ammo_stock)==ammunition-int(plan.loaded_ammo),"paid v4 launch deducts previewed ammunition once")
	check(core.request({"op":"littoral_abandon"}).get("ok",false),"explicit retreat produces real terminal record")
	var terminal:String=snapshot();var actual:Dictionary=core.view.duplicate(true);var result:Dictionary=home.settle(actual,terminal,true)
	if not check(result.get("ok",false),"v3 real retreat settles: "+str(result.get("message",""))):return
	if mode=="defense":
		var building_rows:Array=actual.get("littoral",{}).get("outcome",{}).get("buildings",[])
		check(building_rows.size()==plan.request.island.forts.size(),"defense terminal includes every actual own facility")
		for row in building_rows:
			for building in home.state().buildings:
				if str(building.id)==str(row.id):check(int(building.get("hp",100))==int(floor(float(row.hp_percent))),"real facility hp persisted "+str(row.id))
	check(result.receipt.rewards.is_empty(),"retreat does not invent rewards")
	var vehicles:Array=actual.get("littoral",{}).get("outcome",{}).get("vehicles",[])
	check(vehicles.size()==plan.request.vehicle_condition.size(),"terminal vehicle ledger covers every actual independent company vehicle")
	if mode=="raid":check(vehicles.all(func(row):return bool(row.recovered) and not bool(row.lost) and is_equal_approx(float(row.recovered_hp_percent),100)),"never-deployed vehicles aboard a surviving ship are safely retained on real retreat")
	for row in vehicles:check(is_equal_approx(float(home.state().units[str(row.unit_id)].vehicle_condition_v3[str(int(row.company))]),float(row.recovered_hp_percent)),"native recovered vehicle health persisted without mixing body losses")
	var before:Dictionary=account.state.duplicate(true);check(home.settle(actual,terminal,true).get("duplicate",false) and home._same(before,account.state),"paid v4 settlement cannot repeat charge or reward")
	var replay:Dictionary=home.replay_record(str(result.receipt.run_id));check(replay.get("ok",false) and str(replay.record.ruleset)==VERSION,"paid v4 battle has complete versioned recording")
func geometry_ui(island)->void:
	var canvas=island.canvas
	if OS.get_environment("CAS_HOME_V4_TRACE")=="1":canvas.gui_input.connect(func(event):print("CANVAS ",event.as_text()))
	check(canvas.has_native_geometry(),"ordinary home canvas uses native v4 geometry")
	await shot("home-native-hq-focus")
	var reset:Button=island.get_node("Layout/Top/ResetView");await click(reset);check(is_equal_approx(canvas.zoom,1),"real overview button fits the whole native island");await shot("home-native-whole-island")
	await click(reset);check(is_equal_approx(canvas.zoom,24),"real overview button returns to readable HQ camera")
	var transform:Transform2D=canvas.get_global_transform_with_canvas()
	var wheel:=InputEventMouseButton.new();wheel.position=transform*Vector2(420,310);wheel.button_index=MOUSE_BUTTON_WHEEL_UP;wheel.pressed=true;var old_zoom:float=canvas.zoom;inject(wheel);var wheel_release:InputEventMouseButton=wheel.duplicate();wheel_release.pressed=false;inject(wheel_release);await frames(3)
	check(canvas.zoom>old_zoom,"mouse wheel truly zooms native home")
	var old_pan:Vector2=canvas.pan;await drag_on(canvas,Vector2(490,470),Vector2(580,510));check(canvas.pan.distance_to(old_pan)>50,"mouse drag pans native island rather than selecting an unrelated building")
	var before:Dictionary=account.state.duplicate(true);var disk:String=FileAccess.get_file_as_string(account.save_path)
	old_zoom=canvas.zoom
	for index in [0,1]:
		var event:=InputEventScreenTouch.new();event.position=transform*Vector2(510+index*180,330);event.index=index;event.pressed=true;inject(event);await process_frame
	for index in [0,1]:
		var event:=InputEventScreenDrag.new();event.position=transform*Vector2(470+index*260,330);event.index=index;event.relative=Vector2(-40 if index==0 else 40,0);inject(event);await process_frame
	for index in [0,1]:
		var event:=InputEventScreenTouch.new();event.position=transform*Vector2(470+index*260,330);event.index=index;event.pressed=false;inject(event);await process_frame
	await frames(3);check(canvas.zoom>old_zoom,"actual two-finger pinch enlarges native home")
	check(home._same(before,account.state) and FileAccess.get_file_as_string(account.save_path)==disk,"camera gestures never modify home economy or disk")
	island._choose_building("solar");await frames();var target:=Vector2i(12,4)
	if not home.buildable(target) or not home.building_at(target).is_empty():
		for cell in canvas.grid_cells():
			if (cell.x<0 or cell.x>=12 or cell.y<0 or cell.y>=9) and home.building_at(cell).is_empty():target=cell;break
	canvas.focus_cell(target,8);await frames();var to:Vector2=canvas.point(Vector2(target));await drag_on(canvas,to-Vector2(80,25),to)
	check(canvas.placement_cell==target and canvas.placement_valid,"real drag previews an expanded native land address beyond old12x9")
	var cancel:Button=island.get_node("Layout/Placement/Body/Cancel")
	await shot("home-native-expanded-placement");await click(cancel);check(island.building_kind.is_empty(),"real cancel closes construction");check(home._same(before,account.state),"construction cancel preserves complete memory");check(FileAccess.get_file_as_string(account.save_path)==disk,"construction cancel preserves exact disk")
	canvas.focus_base();await frames()
func ui_review()->void:
	account.state.active_run={};for id in home.state().garrison:account.state.owned[id].hp=100;account.state.owned[id].ammo=100
	for id in home.state().tactical_garrison:home.state().units[id].condition=100;home.state().units[id].at=home._now()
	for id in home.state().units:home.state().units[id].erase("vehicle_condition_v3")
	for building in home.state().buildings:
		if str(building.kind)=="hq":building.level=5
	account.save_state()
	app=load("res://scenes/main.tscn").instantiate();app.boot_to_title=false;app.deferred_startup=false;app.staged_navigation=false;app.immersive_fullscreen=false;app.economy=account;app.fullscreen_battle=false;root.content_scale_size=Vector2i(1600,900);root.size=Vector2i(1280,720);root.add_child(app);await frames(8);app.page_motion=false;app.page_transition.cancel();AudioServer.set_bus_mute(0,true);app.show_page("home");await frames(7)
	var island:Node=app.page.find_child("HomeIsland",true,false);await geometry_ui(island);await click(island.get_node("Layout/Top/IslandAffairs"));await click(app.modal.find_child("StartOwnIslandExercise",true,false))
	check(str(app.modal.name)=="HomeSortieV2","real exercise button opens new deployment")
	check(app.modal.find_children("CompanyTransport_*","OptionButton",true,false).is_empty(),"new deployment has no free landing-vehicle selection controls")
	check(not app.modal.find_children("CompanyTransport_*","Label",true,false).is_empty(),"fixed personality landing equipment is shown as read-only composition information")
	await click(app.modal.find_child("PreviewIslandV2",true,false));check(not app.modal.find_child("LaunchLittoral",true,false).disabled,"native checked exercise enables actual confirmation");await shot("exercise-deployment")
	var old_core=app.core;var prior_plan:Dictionary=home.prepare_island_v2("raid","shoal_watch",["MCP-034","MCP-001"],["IBS-U-USN-ERMA-IOWA","CAS-H-USN-ENTERPRISE-1942"],"balanced",[],714)
	check(prior_plan.get("ok",false) and old_core.request(prior_plan.request).get("ok",false),"actual previous-version live native session exists before isolated exercise")
	var active:Dictionary={"run_id":"live-preserved-qa","mode":"littoral","ruleset":"cas-island-war-v2","request":prior_plan.request,"snapshot":str(old_core.request({"op":"save","serialized":true}).get("serialized",""))};account.state.active_run=active;app.run=active.duplicate(true);account.save_state()
	var before:Dictionary=account.state.duplicate(true);var disk:String=FileAccess.get_file_as_string(account.save_path);var original:String=str(old_core.request({"op":"save","serialized":true}).get("serialized",""));var prior_run:Dictionary=app.run.duplicate(true)
	await click(app.modal.find_child("LaunchLittoral",true,false));await frames(8);app.running=false
	if not check(app.home_exercise_session!=null and app.home_exercise_session.active,"pointer launch creates an independent exercise session"):return
	FileAccess.open(OUTPUT+"exercise-account-before.json",FileAccess.WRITE).store_string(JSON.stringify(before,"  "));FileAccess.open(OUTPUT+"exercise-account-after-entry.json",FileAccess.WRITE).store_string(JSON.stringify(account.state,"  "));FileAccess.open(OUTPUT+"exercise-disk-before.json",FileAccess.WRITE).store_string(disk);FileAccess.open(OUTPUT+"exercise-disk-after-entry.json",FileAccess.WRITE).store_string(FileAccess.get_file_as_string(account.save_path))
	check(app.core!=old_core and home._same(before,account.state) and FileAccess.get_file_as_string(account.save_path)==disk,"exercise entry preserves entire live account and exact on-disk text")
	var advanced:Dictionary=app.core.request({"op":"step","seconds":31});check(advanced.get("ok",false) and float(app.core.view.get("tick",0))>=31,"exercise executes31 real native seconds beyond the checkpoint interval")
	app.battle_controller.update();check(app.checkpoint(),"exercise production checkpoint is a no-write success");check(home._same(before,account.state) and FileAccess.get_file_as_string(account.save_path)==disk,"running exercise and view update/checkpoint still preserve entire account and disk")
	await shot("own-exercise-battle")
	await click(button_text(app.page,"菜单"));await click(button_text(app.modal,"结束演习 · 返回海岛"));await frames(6)
	check(app.core==old_core and home._same(app.run,prior_run) and home._same(before,account.state) and FileAccess.get_file_as_string(account.save_path)==disk,"real pause-menu exit restores live core/run and all account/disk state")
	check(str(old_core.request({"op":"save","serialized":true}).get("serialized",""))==original,"original core serialized state is unchanged after independent exercise")
	island=app.page.find_child("HomeIsland",true,false);island._sortie();await frames();await click(app.modal.find_child("PreviewIslandV2",true,false));await click(app.modal.find_child("LaunchLittoral",true,false));await frames(6);app.running=false
	if app.home_exercise_session!=null and app.home_exercise_session.active:
		check(app.core.request({"op":"littoral_abandon"}).get("ok",false),"exercise reaches a real explicit terminal state");app.finish_battle();await frames();await shot("exercise-terminal-no-account-loss");await click(button_text(app.modal,"返回海岛"));await frames()
		check(app.core==old_core and home._same(before,account.state) and FileAccess.get_file_as_string(account.save_path)==disk,"actual terminal result returns without settlement or disk writes")
	app.staged_navigation=true;island=app.page.find_child("HomeIsland",true,false);island._sortie();await frames();await click(app.modal.find_child("PreviewIslandV2",true,false));await click(app.modal.find_child("LaunchLittoral",true,false));await app.wait_for_page("battle");await frames();app.running=false
	if app.home_exercise_session!=null and app.home_exercise_session.active:
		await click(button_text(app.page,"菜单"));await click(app.modal.find_child("ModalNavigateHome",true,false));await app.wait_for_page("harbor");await frames()
		check(app.screen=="harbor" and not app.home_exercise_session.active and app.core==old_core,"staged-navigation global home pointer restores the original core")
		check(home._same(before,account.state) and FileAccess.get_file_as_string(account.save_path)==disk,"staged global-home exit preserves all account and exact disk text")
	app.staged_navigation=false;app.show_page("home");await frames(6)
	account.state.active_run={};app.run={};account.save_state();island=app.page.find_child("HomeIsland",true,false);island.open_conflicts("defenses");await frames(5);await shot("native-defense-planning")
	var layer:Control=app.modal;var chart:Control=layer.find_child("HomeDefenseChart",true,false);check(chart!=null and not chart.placement.is_empty(),"actual defense screen uses native placement coordinates")
	for candidate in [Vector2(.2,.5),Vector2(.35,.7),Vector2(.6,.5),Vector2(.2,.2),Vector2(.75,.75)]:
		if home.island_v4().placement_preview("land_mine",candidate.x,candidate.y).get("ok",false):deployment_points.land_mine=candidate;break
	before=account.state.duplicate(true)
	if chart!=null and deployment_points.has("land_mine"):
		var point:Vector2=chart.project(chart.world(deployment_points.land_mine));await drag_on(chart,point-Vector2(12,0),point)
		check(not app.modal.find_child("ConfirmDefensePlacement",true,false).disabled,"real pointer drag validates actual native placement")
	await click(layer.find_child("CancelDefensePlacement",true,false));check(home._same(before,account.state),"actual planning cancel has no account effects")
	if chart!=null and deployment_points.has("land_mine"):
		var point:Vector2=chart.project(chart.world(deployment_points.land_mine));await drag_on(chart,point-Vector2(10,0),point);await click(app.modal.find_child("ConfirmDefensePlacement",true,false))
		check(home.island_v4().deployables().size()==before.home_v1.defense_v2.deployables.size()+1,"real pointer confirmation persists one deployable")
		for key in home.island_v4().DEPLOYABLES.land_mine.cost:check(int(home.state().resources[key])==int(before.home_v1.resources[key])-int(home.island_v4().DEPLOYABLES.land_mine.cost[key]),"pointer purchase deducts exactly published "+key)
	await click(app.modal.find_child("BackFromDefense",true,false));check(str(app.modal.name)=="HomeConflictPanel","defense back returns to island affairs")
	app.close_modal();island._unit_detail("MCP-006");await frames();await shot("six-body-profile");await click(app.modal.find_child("TacticalReplenishment",true,false));check(app.modal.find_child("ReplenishmentTarget",true,false) is HSlider,"six-body replacement is a slider");await click(app.modal.find_child("CancelTacticalReplenishment",true,false));app.close_modal()
	# The ordinary raid is a real paid pointer path, unlike the independent exercise.
	island._sortie();await frames();await click(app.modal.find_child("IslandMode_raid",true,false));var stock:int=int(account.state.wallet.ammo_stock)
	await click(app.modal.find_child("PreviewIslandV2",true,false));var ui=app.modal.get_meta("ui_owner");var fee:int=int(ui.plan.get("loaded_ammo",0));check(fee>0 and int(account.state.wallet.ammo_stock)==stock,"actual raid preview publishes a real fee without charging")
	await click(app.modal.find_child("LaunchLittoral",true,false));await frames(6);app.running=false
	if check(str(account.state.active_run.get("ruleset",""))==VERSION,"pointer raid creates a paid v4 account voyage"):
		check(int(account.state.wallet.ammo_stock)==stock-fee,"pointer raid charges exactly the previewed ammo once");check(not bool(app.core.view.get("island_war",{}).get("exercise",true)),"paid pointer raid is not the sandbox mode")
		check(app.core.request({"op":"littoral_abandon"}).get("ok",false),"paid UI raid ends through real native retreat");app.finish_battle();await frames(5);check(app.screen=="result" and account.state.active_run.is_empty(),"normal v4 terminal settles then renders real result")
		await click(button_text(app.page,"返回返航灯岛"));await frames(5);check(app.screen=="home","paid v4 result pointer returns to island")
	island=app.page.find_child("HomeIsland",true,false);island._units();await frames();await click(app.modal.find_child("Unit_MCP-088",true,false))
	var labels:Array=app.modal.find_children("*","Label",true,false);check(labels.any(func(node):return node.text.contains("霜铃")),"88th identity appears by name in the actual collection detail, never a question mark");check(int(home.tactical_profile("MCP-088").deployed_bodies)==50,"88th collection detail retains finite five-company count");await click(button_text(app.modal,"返回部队"));check(app.modal.find_child("Unit_MCP-088",true,false)!=null,"88th detail back returns to complete27 collection")
	for identity in ["MCP-301","MCP-302","MCP-303","MCP-304","MCP-305"]:
		await click(app.modal.find_child("Unit_"+identity,true,false));await click(app.modal.find_child("ExpandTacticalData",true,false));labels=app.modal.find_children("*","Label",true,false)
		var native:Dictionary=home.v4_profile(identity);var expected:String="基础身体耐久 %.0f"%float(native.body_stats.hp)
		check(labels.any(func(node):return node.text.contains(expected)),"new personality UI shows exact native4x body health "+identity)
		if identity in ["MCP-301","MCP-304"]:await shot("new-personality-"+identity+"-detail")
		await click(button_text(app.modal,"返回部队"))
	app.close_modal()
	home.state().units["MCP-087"]["vehicle_condition_v3"]={"1":40.0};account.save_state()
	island._unit_detail("MCP-087");await frames();await click(app.modal.find_child("ExpandTacticalData",true,false));await shot("artillery-native-weapon-groups");labels=app.modal.find_children("*","Label",true,false);check(labels.any(func(node):return node.text.contains("共同意识")) and labels.any(func(node):return node.text.contains("手枪")),"actual artillery detail shows independent SPG and pistol bodies with no added driver")
	for node in labels:
		if node.text.begins_with("自行火炮 · 每连"):
			await reveal(node.get_parent().get_parent());await shot("artillery-independent-vehicle-detail");break
	before=account.state.duplicate(true);disk=FileAccess.get_file_as_string(account.save_path);await click(app.modal.find_child("TacticalVehicleRepair",true,false));check(app.modal.find_child("VehicleRepairTarget",true,false) is HSlider,"actual vehicle repair amount uses a slider");await shot("vehicle-repair-preview");await click(app.modal.find_child("CancelTacticalVehicleRepair",true,false));check(home._same(before,account.state) and FileAccess.get_file_as_string(account.save_path)==disk,"pointer vehicle repair preview/cancel preserves complete account and disk")
	await click(app.modal.find_child("TacticalVehicleRepair",true,false));var vehicle_quote:Dictionary=home.development(true).vehicle_repair_preview("MCP-087",100);var vehicle_stock:Dictionary=home.state().resources.duplicate(true);await click(app.modal.find_child("ConfirmTacticalVehicleRepair",true,false))
	check(float(home.state().units["MCP-087"].vehicle_condition_v3["1"])==100,"pointer confirms real vehicle repair")
	for key in vehicle_quote.cost:check(int(home.state().resources[key])==int(vehicle_stock[key])-int(vehicle_quote.cost[key]),"pointer repair charges exact native cost once "+str(key))
	app.close_modal()
	island._training_lessons();await frames();check(app.modal.find_child("Lesson-roles",true,false)!=null and app.modal.find_child("Lesson-combined_arms",true,false)!=null,"six real courses including combined arms are reachable in ordinary island UI")
	before=account.state.duplicate(true);disk=FileAccess.get_file_as_string(account.save_path);await click(app.modal.find_child("Lesson-landing",true,false));await frames(7);app.running=false
	if check(app.home_exercise_session!=null and app.home_exercise_session.active,"ordinary training button launches real independent borrowed v4 session"):
		check(app.core.view.get("littoral",{}).get("training") is Dictionary,"new training has native lesson checklist")
		check(home._same(before,account.state) and FileAccess.get_file_as_string(account.save_path)==disk,"borrowed training does not charge or write account")
		await click(button_text(app.page,"菜单"));await click(button_text(app.modal,"结束演习 · 返回海岛"));await frames(5)
		check(home._same(before,account.state) and FileAccess.get_file_as_string(account.save_path)==disk,"borrowed training exit restores full account")
	# Existing salvage remains versioned; switching mode opens the new island UI.
	island=app.page.find_child("HomeIsland",true,false)
	island._legacy_sortie();await frames();check(app.modal.find_child("Deploy_MCP-088",true,false)==null and app.modal.find_child("Deploy_MCP-006",true,false)==null,"legacy version never offers two unsupported new identities as unknown cards")
	var mode_picker:OptionButton=app.modal.find_child("LittoralMode",true,false);mode_picker.item_selected.emit(0);await frames();check(str(app.modal.name)=="HomeSortieV2" and app.modal.get_meta("ui_owner").mode=="raid","legacy mode route signal opens the new v4 deployment (component routing check, not popup pointer evidence)");app.close_modal()
	# Presentation-only fixture: intentionally not represented as a combat outcome.
	var saved:Dictionary=home.state().units["MCP-006"].duplicate(true);home.state().units["MCP-006"].condition=42.0;home.state().units["MCP-006"].at=home._now()
	var component:Control=load("res://scenes/ui/littoral_result.tscn").instantiate();app.page.add_child(component);component.bind(app,{"success":false,"request":{"version":VERSION},"vehicles":[{"unit_id":"MCP-006","company":1,"kind":"attack_helicopter","recovered_hp_percent":0,"recovered":false,"lost":true}],"units":[{"id":"MCP-006","hp_percent":100.0,"recovered_hp_percent":42.0,"partial_missing":true,"missing":false,"incapacitated":false}]});await frames()
	var result_labels:Array=component.find_children("*","Label",true,false);check(result_labels.any(func(node):return node.text.contains("整备 42.0%") and node.text.contains("部分连队未返舰")),"v4 result component states recovered condition and partial missing explicitly");check(result_labels.any(func(node):return node.text.contains("1辆/架作战载具未回收")) and result_labels.any(func(node):return node.text.contains("作战载具 0/1归队") and node.text.contains("档案维修")),"labelled synthetic result fixture separates unrecovered vehicle from42% body condition");var bars:Array=component.find_children("*","ProgressBar",true,false);check(not bars.is_empty() and is_equal_approx(float(bars[0].value),float(home.state().units["MCP-006"].condition)),"v4 result health bar matches the actual persisted-style condition fixture");component.queue_free();home.state().units["MCP-006"]=saved;await frames()
	app.core.close();ui_complete=true
func run()->void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT));formal_hash=FileAccess.get_sha256("user://cas_port_v1.json");backup_hash=FileAccess.get_sha256("user://cas_port_v1.json.bak")
	account=load("res://scripts/economy.gd").new(OUTPUT+"isolated-%d.json"%OS.get_process_id());check(account.new_profile().ok,"ordinary isolated account created")
	home=load("res://scripts/home_service.gd").new(account);core=load("res://scripts/core_bridge.gd").new()
	if check(home.v4_cards.size()==27,"v4 exported native catalogue is present"):
		pure_account();old_v2_load();old_v3_load();geometry_review();paid_voyage();paid_voyage("defense")
		if OS.get_environment("CAS_HOME_V4_UI")=="1":
			await ui_review();check(ui_complete,"complete pointer review reaches its final state without a coroutine script error")
	core.close();check(FileAccess.get_sha256("user://cas_port_v1.json")==formal_hash and FileAccess.get_sha256("user://cas_port_v1.json.bak")==backup_hash,"formal main account and backup never changed")
	var executable:String=OS.get_environment("CAS_SIM_PATH")
	var report:Dictionary={"checks":checks,"failures":failures,"actual_input_events":actual_input_events,"input_transport":"Owned rootViewport.push_input with explicit viewport-local real mouse/touch InputEvent objects; no control signal is emitted for pointer tests","core_sha256":FileAccess.get_sha256(executable) if FileAccess.file_exists(executable) else "","formal_sha256":formal_hash,"backup_sha256":backup_hash,"scope":"27 identities, real native loadouts, exact own defenders, pure exercises, finite bodies, real cost/idempotence/invalid placement and untouched formal saves","ui_evidence":"production controls receive pointer events; legacy mode routing is a signal-level component check, and42% partial-loss result is a labelled synthetic presentation fixture" if OS.get_environment("CAS_HOME_V4_UI")=="1" else "not requested"};var name:String="receipt-ui" if OS.get_environment("CAS_HOME_V4_UI")=="1" else "receipt-account";FileAccess.open(OUTPUT+name+".json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "));print("HOME_V4 ",JSON.stringify(report));quit(0 if failures.is_empty() else 1)
