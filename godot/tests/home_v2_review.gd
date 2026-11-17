extends SceneTree
const VERSION:String="cas-island-war-v2"
const OUTPUT:String="res://../artifacts/island-war-v2/home/"
var checks:int=0
var failures:Array[String]=[]
var account
var home
var core
var app
var formal_hash:String
var backup_hash:String
var deployment_points:Dictionary={}
func _initialize()->void:call_deferred("run")
func check(value:bool,message:String)->bool:
	checks+=1
	if not value:failures.append(message);push_error(message)
	return value
func frames(count:int=4)->void:
	for index in range(count):await process_frame
func click(node:Control)->void:
	if not check(node!=null,"real requested control exists"):return
	var ancestor:Node=node.get_parent()
	while ancestor!=null:
		if ancestor is ScrollContainer:ancestor.ensure_control_visible(node)
		ancestor=ancestor.get_parent()
	await frames(2)
	var point:Vector2=node.get_viewport().get_screen_transform()*(node.get_global_transform_with_canvas()*(node.size*.5))
	for pressed in [true,false]:
		var event:=InputEventMouseButton.new();event.position=point;event.button_index=MOUSE_BUTTON_LEFT;event.pressed=pressed;Input.parse_input_event(event);await process_frame
	await frames(5)
func button_text(root_node:Node,text:String)->Button:
	if root_node==null:return null
	for node in root_node.find_children("*","Button",true,false):
		if node.text==text and node.is_visible_in_tree():return node
	return null
func drag_on(node:Control,from:Vector2,to:Vector2)->void:
	var transform:Transform2D=node.get_viewport().get_screen_transform()*node.get_global_transform_with_canvas()
	var press:=InputEventMouseButton.new();press.position=transform*from;press.button_index=MOUSE_BUTTON_LEFT;press.pressed=true;Input.parse_input_event(press);await process_frame
	var motion:=InputEventMouseMotion.new();motion.position=transform*to;motion.relative=transform.basis_xform(to-from);motion.button_mask=MOUSE_BUTTON_MASK_LEFT;Input.parse_input_event(motion);await process_frame
	var release:=InputEventMouseButton.new();release.position=transform*to;release.button_index=MOUSE_BUTTON_LEFT;release.pressed=false;Input.parse_input_event(release);await frames(5)
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
	for row in home.v2_units():home._own_unit(str(row.id));home.state().units[str(row.id)].condition=100;home.state().units[str(row.id)].at=home._now()
	home.state().garrison=["IBS-U-USN-ERMA-IOWA","CAS-O-LHA-RETURNLIGHT"];home.state().tactical_garrison=["MCP-034","MCP-088","MCP-006"]
	account.state.wallet.ammo_stock=50000
	home.state().buildings.append({"id":"qa-v2-depot","kind":"depot","level":2,"cell":{"x":5,"y":4},"hp":83})
func pure_account()->void:
	var ordinary:Dictionary=account.state.duplicate(true)
	check(not home.unlock_test_units_v2().ok and home._same(account.state,ordinary),"normal profile is not silently given22 personalities")
	check(home.v2_cards.size()==22 and home.v2_units().size()==22,"22 card identities are sourced from the new native catalogue")
	fixture();home.development()
	check(int(home.tactical_profile("MCP-006").deployed_bodies)==6,"six helicopter bodies are six bodies, not free infantry plus pilots")
	check(int(home.tactical_profile("MCP-088").deployed_bodies)==50,"88th five ten-body companies are finite")
	for row in home.v2_units():
		var id:String=str(row.id);var stats:Dictionary=home.v2_profile(id)
		check(int(home.tactical_profile(id).deployed_bodies)==int(stats.company_count)*int(stats.personnel_per_company),"progression finite count matches native "+id)
		check(not stats.combat.is_empty() and not stats.ability.is_empty() and not stats.transport_options.is_empty(),"combat ability and transport profile "+id)
	var no_meta:Dictionary=home.state().units["MCP-006"].duplicate(true);home.state().units["MCP-006"]={"condition":83.0,"at":home._now(),"losses":3}
	var before:Dictionary=account.state.duplicate(true);var exercise:Dictionary=home.prepare_exercise(["MCP-088","MCP-006"],home.state().garrison)
	if not check(exercise.get("ok",false),"real own-v-own exercise preview: "+str(exercise.get("message",""))):return
	check(home._same(before,account.state),"first exercise preview does not add progression defaults or charge anything")
	check(exercise.request.defender.roster==home.state().tactical_garrison and exercise.request.defender.ships.size()==home.state().garrison.size(),"defender contains exactly actual saved own garrison")
	check(int(exercise.request.island.forts.filter(func(row):return row.id=="qa-v2-depot")[0].hp)==83,"own real damaged facility is copied without healing")
	home.state().units["MCP-006"]=no_meta
	var saved_garrison:Array=home.state().tactical_garrison.duplicate();home.state().tactical_garrison=[]
	before=account.state.duplicate(true);check(not home.prepare_exercise(["MCP-006"],home.state().garrison).ok and home._same(before,account.state),"missing own garrison fails rather than borrowing NPC defenders");home.state().tactical_garrison=saved_garrison
	account.state.active_run={"run_id":"preserved-voyage","mode":"littoral","ruleset":"cas-island-war-v1","request":{"opaque":true},"snapshot":"frozen"}
	before=account.state.duplicate(true);exercise=home.prepare_exercise(["MCP-006"],home.state().garrison);check(exercise.get("ok",false) and home._same(before,account.state),"independent exercise preview preserves an active voyage and all account state");account.state.active_run={}
	check(core.request(exercise.request).get("ok",false),"real core starts the isolated exercise")
	var initial:String=snapshot();check(bool(core.view.get("island_war",{}).get("exercise",false)),"native observation labels exercise")
	before=account.state.duplicate(true);check(not home.begin(exercise.request,initial).ok and home._same(before,account.state),"exercise can never bind account voyage or deduct ammo")
	check(not home.settle(core.view,initial).ok and home._same(before,account.state),"exercise can never enter paid settlement")
	FileAccess.open(OUTPUT+"exercise-request.json",FileAccess.WRITE).store_string(JSON.stringify(exercise.request,"  "))
	FileAccess.open(OUTPUT+"exercise-initial.json",FileAccess.WRITE).store_string(initial)
	check(home.set_tactical_garrison_v2(["MCP-006"]).ok,"one-company006 is a valid separate own garrison")
	home.state().tactical_garrison=saved_garrison
	# All building transactions use real native placement, then one atomic ledger write.
	for kind in ["land_mine","beach_position","sea_mine"]:
		var quote:Dictionary={}
		for point in [Vector2(.2,.5),Vector2(.35,.7),Vector2(.6,.5),Vector2(-.5,.5),Vector2(1.15,.5),Vector2(.5,-.5),Vector2(.5,1.15)]:
			quote=home.island_v2().placement_preview(kind,point.x,point.y)
			if quote.get("ok",false):deployment_points[kind]=point;break
		if not check(quote.get("ok",false),"native-valid "+kind+" position found"):continue
		before=account.state.duplicate(true);var stock:Dictionary=home.state().resources.duplicate(true);var entry:Dictionary=quote.entry
		check(home._same(before,account.state),"placement preview/cancel leaves account unchanged")
		var transaction:String="qa-place-"+kind;var paid:Dictionary=home.island_v2().place(kind,float(entry.x),float(entry.y),transaction,quote.cost)
		if not check(paid.get("ok",false),"confirmed native-valid deployment commits "+kind+": "+str(paid.get("message",""))):continue
		for key in quote.cost:check(int(home.state().resources[key])==int(stock[key])-int(quote.cost[key]),"exact deployment charge "+kind+" "+key)
		var after:Dictionary=account.state.duplicate(true);check(home.island_v2().place(kind,float(entry.x),float(entry.y),transaction,quote.cost).get("duplicate",false) and home._same(after,account.state),"repeated deploy confirmation is idempotent "+kind)
	before=account.state.duplicate(true);check(not home.island_v2().place("sea_mine",.5,.5,"qa-bad-water").ok and home._same(before,account.state),"illegal water-mine placement has no partial charge")
	var resources:Dictionary=home.state().resources.duplicate(true);var old:Dictionary=home.island_v2().deployables()[0] if not home.island_v2().deployables().is_empty() else {}
	if not old.is_empty():
		check(home.island_v2().remove(str(old.id),"qa-remove").ok and home.state().resources==resources,"deployment removal does not mint materials")
		before=account.state.duplicate(true);check(home.island_v2().remove(str(old.id),"qa-remove").get("duplicate",false) and home._same(before,account.state),"deployment removal is idempotent")
	var loaded=load("res://scripts/economy.gd").new(account.save_path);check(loaded.load_state().ok,"new defense and22 progress ledger reloads")
	var restored=load("res://scripts/home_service.gd").new(loaded);check(home._same(restored.island_v2().deployables(),home.island_v2().deployables()),"actual paid positions persist across account reload")
func paid_voyage(mode:String="raid")->void:
	account.state.active_run={}
	var plan:Dictionary=home.prepare_island_v2(mode,"shoal_watch",["MCP-088","MCP-006"],home.state().garrison,"balanced",[],714)
	if not check(plan.get("ok",false),"native v2 "+mode+" plan succeeds: "+str(plan.get("message",""))):return
	check(core.request(plan.request).get("ok",false),"actual v2 paid battle starts");var initial:String=snapshot();var ammunition:int=int(account.state.wallet.ammo_stock)
	var begun:Dictionary=home.begin(plan.request,initial)
	if not check(begun.get("ok",false),"v2 native configuration binds exactly: "+str(begun.get("message",""))):return
	check(int(account.state.wallet.ammo_stock)==ammunition-int(plan.loaded_ammo),"paid v2 launch deducts previewed ammunition once")
	check(core.request({"op":"littoral_abandon"}).get("ok",false),"explicit retreat produces real terminal record")
	var terminal:String=snapshot();var actual:Dictionary=core.view.duplicate(true);var result:Dictionary=home.settle(actual,terminal,true)
	if not check(result.get("ok",false),"v2 real retreat settles: "+str(result.get("message",""))):return
	if mode=="defense":
		var building_rows:Array=actual.get("littoral",{}).get("outcome",{}).get("buildings",[])
		check(building_rows.size()==plan.request.island.forts.size(),"defense terminal includes every actual own facility")
		for row in building_rows:
			for building in home.state().buildings:
				if str(building.id)==str(row.id):check(int(building.get("hp",100))==int(floor(float(row.hp_percent))),"real facility hp persisted "+str(row.id))
	check(result.receipt.rewards.is_empty(),"retreat does not invent rewards")
	var before:Dictionary=account.state.duplicate(true);check(home.settle(actual,terminal,true).get("duplicate",false) and home._same(before,account.state),"paid v2 settlement cannot repeat charge or reward")
	var replay:Dictionary=home.replay_record(str(result.receipt.run_id));check(replay.get("ok",false) and str(replay.record.ruleset)==VERSION,"paid v2 battle has complete versioned recording")
func ui_review()->void:
	account.state.active_run={};for id in home.state().garrison:account.state.owned[id].hp=100;account.state.owned[id].ammo=100
	for id in home.state().tactical_garrison:home.state().units[id].condition=100;home.state().units[id].at=home._now()
	account.save_state()
	app=load("res://scenes/main.tscn").instantiate();app.boot_to_title=false;app.deferred_startup=false;app.staged_navigation=false;app.immersive_fullscreen=false;app.economy=account;app.fullscreen_battle=false;root.content_scale_size=Vector2i(1600,900);root.size=Vector2i(1280,720);root.add_child(app);await frames(8);app.page_motion=false;app.page_transition.cancel();AudioServer.set_bus_mute(0,true);app.show_page("home");await frames(7)
	var island:Node=app.page.find_child("HomeIsland",true,false);await click(island.get_node("Layout/Top/IslandAffairs"));await click(app.modal.find_child("StartOwnIslandExercise",true,false))
	check(str(app.modal.name)=="HomeSortieV2","real exercise button opens new deployment")
	await click(app.modal.find_child("PreviewIslandV2",true,false));check(not app.modal.find_child("LaunchLittoral",true,false).disabled,"native checked exercise enables actual confirmation");await shot("exercise-deployment")
	var old_core=app.core;var prior_plan:Dictionary=home.prepare_island("raid","shoal_watch",["MCP-034","MCP-001"],["IBS-U-USN-ERMA-IOWA","CAS-H-USN-ENTERPRISE-1942"],"balanced",[],714)
	check(prior_plan.get("ok",false) and old_core.request(prior_plan.request).get("ok",false),"actual previous-version live native session exists before isolated exercise")
	var active:Dictionary={"run_id":"live-preserved-qa","mode":"littoral","ruleset":"cas-island-war-v1","request":prior_plan.request,"snapshot":str(old_core.request({"op":"save","serialized":true}).get("serialized",""))};account.state.active_run=active;app.run=active.duplicate(true);account.save_state()
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
	before=account.state.duplicate(true)
	if chart!=null and deployment_points.has("land_mine"):
		var point:Vector2=chart.project(chart.world(deployment_points.land_mine));await drag_on(chart,point-Vector2(12,0),point)
		check(not app.modal.find_child("ConfirmDefensePlacement",true,false).disabled,"real pointer drag validates actual native placement")
	await click(layer.find_child("CancelDefensePlacement",true,false));check(home._same(before,account.state),"actual planning cancel has no account effects")
	if chart!=null and deployment_points.has("land_mine"):
		var point:Vector2=chart.project(chart.world(deployment_points.land_mine));await drag_on(chart,point-Vector2(10,0),point);await click(app.modal.find_child("ConfirmDefensePlacement",true,false))
		check(home.island_v2().deployables().size()==before.home_v1.defense_v2.deployables.size()+1,"real pointer confirmation persists one deployable")
		for key in home.island_v2().DEPLOYABLES.land_mine.cost:check(int(home.state().resources[key])==int(before.home_v1.resources[key])-int(home.island_v2().DEPLOYABLES.land_mine.cost[key]),"pointer purchase deducts exactly published "+key)
	await click(app.modal.find_child("BackFromDefense",true,false));check(str(app.modal.name)=="HomeConflictPanel","defense back returns to island affairs")
	app.close_modal();island._unit_detail("MCP-006");await frames();await shot("six-body-profile");await click(app.modal.find_child("TacticalReplenishment",true,false));check(app.modal.find_child("ReplenishmentTarget",true,false) is HSlider,"six-body replacement is a slider");await click(app.modal.find_child("CancelTacticalReplenishment",true,false));app.close_modal()
	# The ordinary raid is a real paid pointer path, unlike the independent exercise.
	island._sortie();await frames();await click(app.modal.find_child("IslandMode_raid",true,false));var stock:int=int(account.state.wallet.ammo_stock)
	await click(app.modal.find_child("PreviewIslandV2",true,false));var ui=app.modal.get_meta("ui_owner");var fee:int=int(ui.plan.get("loaded_ammo",0));check(fee>0 and int(account.state.wallet.ammo_stock)==stock,"actual raid preview publishes a real fee without charging")
	await click(app.modal.find_child("LaunchLittoral",true,false));await frames(6);app.running=false
	if check(str(account.state.active_run.get("ruleset",""))==VERSION,"pointer raid creates a paid v2 account voyage"):
		check(int(account.state.wallet.ammo_stock)==stock-fee,"pointer raid charges exactly the previewed ammo once");check(not bool(app.core.view.get("island_war",{}).get("exercise",true)),"paid pointer raid is not the sandbox mode")
		check(app.core.request({"op":"littoral_abandon"}).get("ok",false),"paid UI raid ends through real native retreat");app.finish_battle();await frames(5);check(app.screen=="result" and account.state.active_run.is_empty(),"normal v2 terminal settles then renders real result")
		await click(button_text(app.page,"返回返航灯岛"));await frames(5);check(app.screen=="home","paid v2 result pointer returns to island")
	island=app.page.find_child("HomeIsland",true,false);island._units();await frames();await click(app.modal.find_child("Unit_MCP-088",true,false))
	var labels:Array=app.modal.find_children("*","Label",true,false);check(labels.any(func(node):return node.text.contains("霜铃")),"88th identity appears by name in the actual collection detail, never a question mark");check(int(home.tactical_profile("MCP-088").deployed_bodies)==50,"88th collection detail retains finite five-company count");await click(button_text(app.modal,"返回部队"));check(app.modal.find_child("Unit_MCP-088",true,false)!=null,"88th detail back returns to complete22 collection");app.close_modal()
	# Existing salvage remains versioned; switching mode opens the new island UI.
	island._legacy_sortie();await frames();check(app.modal.find_child("Deploy_MCP-088",true,false)==null and app.modal.find_child("Deploy_MCP-006",true,false)==null,"legacy version never offers two unsupported new identities as unknown cards")
	var mode_picker:OptionButton=app.modal.find_child("LittoralMode",true,false);mode_picker.item_selected.emit(0);await frames();check(str(app.modal.name)=="HomeSortieV2" and app.modal.get_meta("ui_owner").mode=="raid","legacy mode route signal opens v2 (component routing check, not popup pointer evidence)");app.close_modal()
	# Presentation-only fixture: intentionally not represented as a combat outcome.
	var saved:Dictionary=home.state().units["MCP-006"].duplicate(true);home.state().units["MCP-006"].condition=42.0;home.state().units["MCP-006"].at=home._now()
	var component:Control=load("res://scenes/ui/littoral_result.tscn").instantiate();app.page.add_child(component);component.bind(app,{"success":false,"request":{"version":VERSION},"units":[{"id":"MCP-006","hp_percent":100.0,"recovered_hp_percent":42.0,"partial_missing":true,"missing":false,"incapacitated":false}]});await frames()
	var result_labels:Array=component.find_children("*","Label",true,false);check(result_labels.any(func(node):return node.text.contains("整备 42.0%") and node.text.contains("部分连队未返舰")),"v2 result component states recovered condition and partial missing explicitly");var bars:Array=component.find_children("*","ProgressBar",true,false);check(not bars.is_empty() and is_equal_approx(float(bars[0].value),float(home.state().units["MCP-006"].condition)),"v2 result health bar matches the actual persisted-style condition fixture");component.queue_free();home.state().units["MCP-006"]=saved;await frames()
	app.core.close()
func run()->void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT));formal_hash=FileAccess.get_sha256("user://cas_port_v1.json");backup_hash=FileAccess.get_sha256("user://cas_port_v1.json.bak")
	account=load("res://scripts/economy.gd").new(OUTPUT+"isolated-%d.json"%OS.get_process_id());check(account.new_profile().ok,"ordinary isolated account created")
	home=load("res://scripts/home_service.gd").new(account);core=load("res://scripts/core_bridge.gd").new()
	if check(home.v2_cards.size()==22,"v2 exported native catalogue is present"):
		pure_account();paid_voyage();paid_voyage("defense")
		if OS.get_environment("CAS_HOME_V2_UI")=="1":await ui_review()
	core.close();check(FileAccess.get_sha256("user://cas_port_v1.json")==formal_hash and FileAccess.get_sha256("user://cas_port_v1.json.bak")==backup_hash,"formal main account and backup never changed")
	var executable:String=OS.get_environment("CAS_SIM_PATH")
	var report:Dictionary={"checks":checks,"failures":failures,"core_sha256":FileAccess.get_sha256(executable) if FileAccess.file_exists(executable) else "","formal_sha256":formal_hash,"backup_sha256":backup_hash,"scope":"22 identities, real native loadouts, exact own defenders, pure exercises, finite bodies, real cost/idempotence/invalid placement and untouched formal saves","ui_evidence":"production controls receive pointer events; legacy mode routing is a signal-level component check, and42% partial-loss result is a labelled synthetic presentation fixture" if OS.get_environment("CAS_HOME_V2_UI")=="1" else "not requested"};var name:String="receipt-ui" if OS.get_environment("CAS_HOME_V2_UI")=="1" else "receipt-account";FileAccess.open(OUTPUT+name+".json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "));print("HOME_V2 ",JSON.stringify(report));quit(0 if failures.is_empty() else 1)
