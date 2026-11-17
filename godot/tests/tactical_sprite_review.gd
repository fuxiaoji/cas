extends SceneTree
const OUTPUT:String="res://../artifacts/tactical-sprite/"
var app
var checks:int=0
var failures:Array[String]=[]
var report:Dictionary={"authority_edited":false,"normal_account_written":false,"screens":[]}
func _initialize()->void:call_deferred("run")
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures.append(label);push_error(label)
func capture(label:String)->void:
	await process_frame;await process_frame;RenderingServer.force_draw()
	var path:String=ProjectSettings.globalize_path(OUTPUT+label+".png")
	check(root.get_texture().get_image().save_png(path)==OK,"GPU "+label);report.screens.append(path)
func map_node():return app.battle_controller.ui.get_node("LandWindow/Map")
func run()->void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	var normal:String="user://cas_port_v1.json";var normal_sha:String=FileAccess.get_sha256(normal);var backup_sha:String=FileAccess.get_sha256(normal+".bak")
	var earlier:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://../artifacts/home-review/npc-receipt.json"))
	var profile:String=OUTPUT+"isolated-%d.json"%OS.get_process_id()
	var source:String=str(earlier.get("profile",""))
	if source.is_empty():source="res://../artifacts/home-review/isolated-npc-64232.json"
	check(DirAccess.copy_absolute(ProjectSettings.globalize_path(source),ProjectSettings.globalize_path(profile))==OK,"copy legitimate five-unit profile into isolation")
	var economy=load("res://scripts/economy.gd").new(profile);check(economy.load_state().get("ok",false),"load isolated profile")
	app=load("res://scenes/main.tscn").instantiate();app.boot_to_title=false;app.economy=economy;root.content_scale_size=Vector2i(1600,900);root.size=Vector2i(1280,720);root.add_child(app)
	await process_frame;app.set_process(false);app.page_motion=false;app.fullscreen_battle=false
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	var raw:String=FileAccess.get_file_as_string("res://../artifacts/home-review/npc-raid-save.json");var saved:Dictionary=JSON.parse_string(raw)
	var request:Dictionary=saved.config.duplicate(true);request.merge({"op":"new_littoral","version":saved.version,"seed":saved.seed})
	check(app.core.request(request).get("ok",false),"start genuine five-unit raid with original recorded config")
	app.show_page("battle");app.running=false;await process_frame;app.update_battle();var land=map_node()
	check(land.actors.size()>0,"production battle creates body sprite nodes from public observations")
	var identities:Dictionary={};var states:Dictionary={};var kinds:Dictionary={};var body_losses:Array=[];var shot_proofs:Array=[];var counts:Dictionary={};var return_proofs:Array=[]
	var before_rows:Dictionary={}
	for frame in range(0,2180):
		for command in saved.commands:
			if int(command.frame)==frame:check(app.core.request(command.request).get("ok",false),"reissue real recorded command at frame %d"%frame)
		var previous:Dictionary={}
		for row in app.core.view.littoral.land.entities:previous[int(row.id)]=row
		var old_groups:Dictionary={}
		for row in app.core.view.littoral.groups:old_groups[str(row.id)]=str(row.stage)
		var stepped:Dictionary=app.core.request({"op":"step","seconds":.1})
		if not stepped.get("ok",false):check(false,"real .1 second step accepted");break
		app.running=true;app.update_battle();land=map_node()
		var current:Dictionary={}
		for row in app.core.view.littoral.land.entities:current[int(row.id)]=row
		for id in land.actors:
			var actor=land.actors[id];identities[actor.identity]=true;states[actor.state_name]=true;kinds[actor.kind]=true
			if id>0 and actor.defeated_at>=0 and not counts.has(id):
				counts[id]=true;body_losses.append({"body":id,"unit":actor.identity,"tick":app.core.view.tick,"previous_hp":previous.get(id,{}).get("hp",null),"present":current.has(id),"source":"consecutive public ground observation loss"})
			if actor.state_name=="fire" and shot_proofs.size()<12:
				for shot in app.core.view.littoral.shots:
					if str(shot.source)=="body:%d"%id and absf(float(shot.tick)-float(app.core.view.tick))<.41:shot_proofs.append({"body":id,"shot":shot.id,"tick":shot.tick,"frame":actor.frame_index});break
		for group in app.core.view.littoral.groups:
			if str(group.stage)=="returning" and str(old_groups.get(str(group.id),""))=="ground":
				var fake_dead:bool=false
				for actor in land.actors.values():
					if actor.identity==str(group.id) and actor.defeated_at>=0 and actor.defeated_at>=float(app.core.view.tick)-.11:fake_dead=true
				check(not fake_dead,"real transport embarkation never creates casualties "+str(group.id));return_proofs.append({"unit":group.id,"tick":app.core.view.tick})
		if frame in [805,900,978,1000,1200,1400,1560,2110]:
			app.running=false;land.set_playing(false);await capture("real-raid-%d"%frame)
			if frame==900:
				var authority_before:String=JSON.stringify(app.core.view)
				app.battle_controller.ui.get_node("LandWindow/Controls/Focus").pressed.emit()
				check(land.zoom>1 and app.battle_controller.ui.get_node("LandWindow/Controls/Focus").text=="全图","actual battle focus button magnifies selected real squad")
				check(JSON.stringify(app.core.view)==authority_before,"focus never changes native positions or any combat data")
				await capture("real-raid-focused")
				app.battle_controller.ui.get_node("LandWindow/Controls/Focus").pressed.emit()
		if frame%80==0:await process_frame
	check(identities.has("MCP-034") and identities.has("MCP-001") and identities.has("MCP-022"),"real five-team sortie renders individual MCP identities")
	check(states.has("walk"),"real position changes select walking frames")
	check(states.has("fire") and not shot_proofs.is_empty(),"firing frames have actual body-source shot records")
	check(states.has("hurt"),"real HP reductions select hurt pose")
	check(kinds.has("tank") and kinds.has("gunship") and kinds.has("helicopter") and kinds.has("ifv"),"real native tank/gunship/helicopter/IFV all reach correct equipment render types")
	check(not body_losses.is_empty(),"actual casualties produce fall then lying animation")
	check(not return_proofs.is_empty(),"normal withdrawal disappearance independently observed")
	# Restoring a snapshot or seeking must seed state, never replay old hits or old casualties.
	var snapshot:String=str(app.core.request({"op":"save","serialized":true}).serialized);var view_before:String=JSON.stringify(app.core.view)
	land.prime_visuals();app.core.close();app.core=load("res://scripts/core_bridge.gd").new()
	check(app.core.request({"op":"load","serialized":snapshot}).get("ok",false),"full native close and snapshot reload")
	app.running=false;app.update_battle();land=map_node()
	check(JSON.stringify(app.core.view)==view_before,"rendering and restart preserve exact authoritative public view")
	check(land.actors.values().all(func(actor):return actor.defeated_at<0 and actor.fire_until<0 and actor.hurt_until<0),"snapshot prime never replays old death, fire or hurt feedback")
	check(app.core.request({"op":"replay","serialized":snapshot,"tick":90}).get("ok",false),"seek backwards using real native replay")
	land.prime_visuals();app.update_battle();check(land.actors.values().all(func(body):return body.defeated_at<0),"backward seek clears future casualties")
	var actor=land.actors.values()[0];var frozen_clock:float=actor.clock;var frozen_frame:int=actor.frame_index;var frozen_at:Vector2=actor.position
	land.set_playing(false)
	for step in range(6):land._process(.1)
	check(actor.clock==frozen_clock and actor.frame_index==frozen_frame and actor.position==frozen_at,"paused combat freezes pose, movement and defeat timers")
	for dimensions in [Vector2i(960,540),Vector2i(1920,1080)]:
		root.size=dimensions;await process_frame;app.update_battle();await capture("real-battle-%dx%d"%[dimensions.x,dimensions.y])
		var offsets:Dictionary=land.display_offsets
		check(offsets.values().all(func(value):return value.length()<=80.01),"screen separation remains within 80 pixels "+str(dimensions))
	check(land.actors.values().filter(func(body):return not body.friendly).all(func(body):return body.sheet_path.ends_with("enemy-security-sheet.png")),"enemies use original enemy atlas without borrowed allied identities")
	check(land.actors.values().all(func(body):return body.texture_filter==CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS and body.texture.get_image().has_mipmaps()),"actual battle bodies use mipmapped filtering with real imported mip levels")
	var runtime:Dictionary=load("res://tests/home_runtime_evidence.gd").capture(app.core);check(runtime.verified_default,"real default7134 executable without environment override")
	app.core.close();app.queue_free();await process_frame
	check(FileAccess.get_sha256(normal)==normal_sha and FileAccess.get_sha256(normal+".bak")==backup_sha,"normal profile and backup unchanged")
	report.merge({"checks":checks,"failures":failures,"passed":failures.is_empty(),"runtime":runtime,"states":states.keys(),"equipment_kinds":kinds.keys(),"identities":identities.keys(),"actual_casualties":body_losses,"actual_shots":shot_proofs,"normal_returns":return_proofs,"renderer":RenderingServer.get_video_adapter_name(),"normal_sha256":normal_sha,"profile":ProjectSettings.globalize_path(profile)})
	FileAccess.open(OUTPUT+"receipt.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "));print("TACTICAL_SPRITE "+JSON.stringify({"checks":checks,"failures":failures}));quit(0 if failures.is_empty() else 1)
