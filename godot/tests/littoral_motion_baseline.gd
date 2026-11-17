extends "res://tests/littoral_drag_v2_review.gd"
## Diagnostic only, captures the pre-fix animation lifecycle using a real recorded raid.
func run()->void:
	output_dir="res://../artifacts/littoral-motion-v3/baseline/"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_dir))
	profile=output_dir+"isolated-%d.json"%OS.get_process_id()
	var account=load("res://scripts/economy.gd").new(profile);account.load_state()
	app=load("res://scenes/main.tscn").instantiate();app.economy=account;app.boot_to_title=false;app.fullscreen_battle=true
	root.content_scale_size=Vector2i(1600,900);root.size=Vector2i(1280,720);root.add_child(app);await frames();app.set_process(false);app.page_motion=false
	var saved:String=FileAccess.get_file_as_string("res://../artifacts/home-review/npc-raid-save.json")
	app.core.request({"op":"replay","serialized":saved,"tick":90});app.show_page("battle");controller().replay_mode=true;controller().set_primary_map("land");await frames();app.update_battle()
	app.core.request({"op":"replay","serialized":saved,"tick":90.1});app.running=true;app.update_battle()
	var land:Control=controller().ui.get_node("LandWindow/Map");var moving_before:int=land.actors.values().filter(func(row):return row.moving).size()
	app.update_battle();var moving_after:int=land.actors.values().filter(func(row):return row.moving).size()
	var ids:Dictionary={}
	for id in land.actors:ids[str(id)]=land.actors[id].get_instance_id()
	await shot("real-raid-before-switch")
	controller().set_primary_map("sea");await frames();controller().set_primary_map("land");await frames();app.update_battle()
	var recreated:int=0
	for id in land.actors:
		if ids.has(str(id)) and int(ids[str(id)])!=land.actors[id].get_instance_id():recreated+=1
	await shot("real-raid-after-switch")
	FileAccess.open(output_dir+"diagnostic.json",FileAccess.WRITE).store_string(JSON.stringify({"same_tick_moving_before":moving_before,"same_tick_moving_after":moving_after,"actors_recreated_after_map_round_trip":recreated,"actor_count":land.actors.size(),"source":"real recorded raid90.1; no world edits","main_account_written":false},"  "))
	app.core.close();app.queue_free();await frames();print("MOTION_BASELINE "+JSON.stringify({"moving_before":moving_before,"moving_after":moving_after,"recreated":recreated}));quit()
