extends SceneTree
const Settle=preload("res://tests/transition_settle.gd")
var app
var checks:=0
var failures:Array[String]=[]
var output:="res://../artifacts/godot/tide-expansion/"
func _initialize()->void:call_deferred("run")
func check(ok:bool,title:String)->void:
	checks+=1
	if not ok:failures.append(title);push_error(title)
func shot(name:String)->void:
	if DisplayServer.get_name()=="headless":return
	await process_frame;await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path(output+name+".png"))
func click(node:Control)->void:
	await Settle.wait_for_route(self,app)
	var point:Vector2=node.get_viewport().get_screen_transform()*node.get_global_transform_with_canvas()*(node.size*.5)
	var down:=InputEventMouseButton.new();down.button_index=MOUSE_BUTTON_LEFT;down.pressed=true;down.position=point;Input.parse_input_event(down);await process_frame
	var up:=InputEventMouseButton.new();up.button_index=MOUSE_BUTTON_LEFT;up.position=point;Input.parse_input_event(up);await process_frame;await process_frame
func run()->void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	root.size=Vector2i(1280,720);root.gui_embed_subwindows=true
	app=load("res://scenes/main.tscn").instantiate();app.boot_to_title=false
	app.economy=load("res://scripts/economy.gd").new("user://tests/tide-expansion-%d.json"%OS.get_process_id());root.add_child(app);app.set_process(false);await process_frame;await process_frame;app.page_motion=false
	for route in ["tide_event","tide_story"]:
		app.show_page(route);await process_frame;await process_frame
		check(app.page.get_child_count()>0,"actual editable route "+route);await shot(route)
	app.set_meta("tide_tab","shop");app.show_page("tide_event");await process_frame;await process_frame
	var event_service=load("res://scripts/tide_event_service.gd").new(app.economy)
	app.economy.state.wallet.tide_tokens=100
	var origins:int=int(app.economy.wallet().origins)
	check(event_service.purchase("origins").get("ok",false),"event currency exchange commits")
	check(int(app.economy.wallet().origins)==origins+80 and int(app.economy.wallet().tide_tokens)==60,"event exchange conserves price and grant")
	check(not event_service.purchase("up_ticket").get("ok",false),"insufficient event balance rejects")
	await shot("event-shop")
	app.set_meta("next_tide_seed",42);app.launch_tide(str(app.economy.formation[0]),"normal",null,"cas-event-tide-v1");await process_frame;await process_frame
	check(app.screen=="battle" and app.core.view.has("tide"),"real native event enters dedicated battle HUD")
	check(app.page.has_node("TideBattleHud"),"dedicated clean event scene is used")
	await shot("event-battle")
	var active:String=str(app.run.run_id);var before:Dictionary=app.core.view.duplicate(true)
	check(app.checkpoint(),"event checkpoint succeeds")
	app.save_leave();app.resume_run();await process_frame;await process_frame
	check(str(app.run.run_id)==active and JSON.stringify(app.core.view)==JSON.stringify(before),"event resumes exact world without new run")
	app.abandon();await process_frame
	check(app.screen=="result" and app.economy.state.active_run.is_empty(),"real event abandon settles once")
	var last:Dictionary=app.last_receipt.duplicate(true)
	check(event_service.settle(app.core.view,str(app.core.request({"op":"save","serialized":true}).serialized)).get("duplicate",false),"repeat event settlement is idempotent")
	await shot("event-result")
	var fuel=load("res://scripts/fuel_service.gd").new(app.economy)
	var prepared:Dictionary=app.economy.preview_sortie(42,false,{"kind":"salvage","id":"calm"})
	check(prepared.get("ok",false),"ordinary sortie prepares fuel and two warehouses")
	if prepared.get("ok",false):
		var native:Dictionary=app.economy.native_start(prepared)
		var estimate:Dictionary=app.core.request({"op":"fuel_preview","start":native})
		check(estimate.get("ok",false),"native validates fuel preview")
		check(int(estimate.get("data",{}).get("capacity",-1))==int(fuel.preview(prepared.fleet).capacity),"account and native tonnage capacity agree")
	app.show_page("warehouse");load("res://scripts/cargo_presentation.gd").open_stash(app,"fleet");await process_frame;await process_frame
	check(app.modal.get_node("CargoHold").has_node("Warehouse_fleet"),"fleet and base warehouse tabs exist")
	await shot("fleet-warehouse");app.close_modal()
	app.show_page("formation");load("res://scripts/cargo_presentation.gd").open_loadout(app);await process_frame;await process_frame
	check(app.modal.find_child("FuelLoadSlider",true,false) is HSlider,"fuel uses slider")
	await shot("fuel-preparation");app.close_modal()
	load("res://scripts/munition_setup.gd").open(app);await process_frame;await process_frame
	check(app.modal.get_node("MunitionSetup/Scroll/Ships").get_child(0).get_node("Margin/Body/Choices/Reserve") is HSlider,"reserve quantity uses slider")
	app.close_modal()
	app.set_meta("next_tide_seed",42);app.launch_tide("IBS-U-USN-FLETCHER","normal",null,"cas-event-tide-v1");await process_frame;await process_frame
	var upgrade_count:=0
	var iterations:=0
	var priorities:Array=["damage","haste","magnet","blast","multishot","torpedo","repair","shield","maneuver"]
	while app.core.view.get("result")==null and iterations<700:
		iterations+=1
		var view:Dictionary=app.core.view;var tide:Dictionary=view.tide
		if not tide.choices.is_empty():
			var choices:Array=tide.choices.duplicate()
			choices.sort_custom(func(a,b):return priorities.find(str(a.id))<priorities.find(str(b.id)))
			var button:Button=app.page.get_node("TideBattleHud/Upgrades/Choices/Upgrade_"+str(choices[0].id))
			check(button.is_visible_in_tree(),"actual upgrade choice exists "+str(choices[0].id))
			if upgrade_count==0:await shot("event-upgrade")
			var previous_offer:int=int(tide.offer_id)
			await click(button);upgrade_count+=1
			check(int(app.core.view.tide.offer_id)!=previous_offer or app.core.view.tide.choices.is_empty(),"pointer commits actual offered upgrade")
			continue
		var ship:Dictionary=view.ships[0];var position:=Vector2(float(ship.x),float(ship.y))
		var target:=Vector2(12000,7000)+Vector2.from_angle((int(view.tick)+12)*.105)*2000
		var drops:Array=tide.drops.duplicate();drops.sort_custom(func(a,b):return Vector2(float(a.x),float(a.y)).distance_to(position)<Vector2(float(b.x),float(b.y)).distance_to(position))
		if not drops.is_empty():target=Vector2(float(drops[0].x),float(drops[0].y))
		for contact in view.contacts:
			if bool(contact.get("boss",false)):target=Vector2(float(contact.x),float(contact.y))+Vector2.from_angle(int(view.tick)*.18)*1700;break
		var direction:Vector2=(target-position).normalized();var best:=direction;var best_score:=-INF
		for i in range(24):
			var candidate:=Vector2.from_angle(i*TAU/24.0);var score:float=candidate.dot(direction)
			for warning in view.salvage.telegraphs:
				var dt:float=minf(3,float(warning.impact_tick)-int(view.tick));var distance:float=(position+candidate*308*dt).distance_to(Vector2(float(warning.x),float(warning.y)))
				if distance<float(warning.radius)+80:score-=10*(1-distance/(float(warning.radius)+80))
			if score>best_score:best_score=score;best=candidate
		target=position+best*1500;target.x=clampf(target.x,500,23500);target.y=clampf(target.y,500,13500)
		var point:Vector2=app.sea.project(target)
		var global:Vector2=app.sea.get_viewport().get_screen_transform()*app.sea.get_global_transform_with_canvas()*point
		var motion:=InputEventMouseMotion.new();motion.position=global;Input.parse_input_event(motion)
		var down:=InputEventMouseButton.new();down.button_index=MOUSE_BUTTON_LEFT;down.pressed=true;down.position=global;Input.parse_input_event(down);await process_frame
		var up:=InputEventMouseButton.new();up.button_index=MOUSE_BUTTON_LEFT;up.position=global;Input.parse_input_event(up);await process_frame
		var response:Dictionary=app.core.request({"op":"step","seconds":1});check(response.get("ok",false),"real event tick "+str(app.core.view.get("tick",0)));app.update_battle();await process_frame
		if int(app.core.view.get("tick",0)) in [60,120,150]:await shot("event-wave-"+str(app.core.view.tick));print("EVENT_PLAY ",app.core.view.tick)
	var outcome:Dictionary=app.core.view.get("tide",{}).get("outcome",{}) if app.core.view.get("tide",{}).get("outcome") is Dictionary else {}
	check(bool(outcome.get("success",false)),"actual pointer-driven event defeats final boss")
	var balance_before:int=int(app.economy.state.wallet.tide_tokens)
	app.finish_battle();await process_frame
	check(app.screen=="result" and bool(app.last_receipt.get("success",false)),"event victory reaches real settlement page")
	check(int(app.economy.state.wallet.tide_tokens)>balance_before and app.economy.state.active_run.is_empty(),"actual event tokens settle and unlock account")
	await shot("event-victory")
	var winning_record:Dictionary=app.last_receipt.duplicate(true)
	var frozen_wallet:Dictionary=app.economy.wallet().duplicate(true)
	app.start_replay(winning_record);await process_frame;await process_frame
	check(app.battle_controller.replay_mode and app.battle_controller.archive_replay,"event archive enters read-only replay")
	app.battle_controller.seek(60);await process_frame
	check(int(app.core.view.tick)==60 and not app.page.get_node("TideBattleHud/Upgrades").visible,"event replay seeks without live upgrade modal")
	app.battle_controller.open_pause_menu();await process_frame
	check(app.modal.find_child("ReplaySeek",true,false) is HSlider,"event replay uses timeline slider")
	app.close_modal();app.battle_controller.seek(180);await process_frame
	check(bool(app.core.view.tide.outcome.success),"event archive restores exact winning terminal")
	check(app.economy.wallet()==frozen_wallet and app.economy.state.active_run.is_empty(),"replay does not grant rewards or open a new run")
	app.battle_controller.end_replay();await process_frame
	check(app.screen=="archives","event replay returns to archives")
	app.core.close();app.queue_free();await process_frame
	var core_manifest:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://bin/core-current.json"))
	var report:Dictionary={"checks":checks,"failures":failures,"passed":failures.is_empty(),"core_manifest":core_manifest,"abandon_receipt":last,"victory_receipt":winning_record}
	var file:=FileAccess.open(output+"receipt.json",FileAccess.WRITE);file.store_string(JSON.stringify(report,"  "));file.close()
	print("TIDE_EXPANSION ",JSON.stringify({"checks":checks,"failures":failures,"passed":failures.is_empty(),"victory_kills":winning_record.kills,"victory_rewards":winning_record.rewards,"core_manifest":core_manifest}));quit(0 if failures.is_empty() else 1)
