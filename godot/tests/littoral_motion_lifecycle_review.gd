extends "res://tests/littoral_drag_v2_review.gd"
## Same real v1 raid as the diagnostic: layout updates must not become world events.
func run()->void:
	output_dir="res://../artifacts/littoral-motion-v3/lifecycle/"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_dir))
	main_hash=FileAccess.get_sha256("user://cas_port_v1.json");backup_hash=FileAccess.get_sha256("user://cas_port_v1.json.bak")
	profile=output_dir+"isolated-%d.json"%OS.get_process_id()
	var account=load("res://scripts/economy.gd").new(profile);account.load_state()
	app=load("res://scenes/main.tscn").instantiate();app.economy=account;app.boot_to_title=false;app.fullscreen_battle=true
	root.content_scale_size=Vector2i(1600,900);root.size=Vector2i(1280,720);root.add_child(app);await frames();app.set_process(false);app.page_motion=false
	var saved:String=FileAccess.get_file_as_string("res://../artifacts/home-review/npc-raid-save.json")
	check(app.core.request({"op":"replay","serialized":saved,"tick":90}).get("ok",false),"real v1 recorded raid opens without changing native rules")
	app.show_page("battle");controller().replay_mode=true;controller().set_primary_map("land");await frames();app.update_battle()
	app.core.request({"op":"replay","serialized":saved,"tick":90.1});app.running=true;app.update_battle()
	var land:Control=controller().ui.get_node("LandWindow/Map");var moving_before:int=land.actors.values().filter(func(row):return row.moving).size()
	var ids:Dictionary={};var clock_before:Dictionary={}
	for id in land.actors:ids[str(id)]=land.actors[id].get_instance_id();clock_before[str(id)]=land.actors[id].animation_time
	app.update_battle();var moving_after:int=land.actors.values().filter(func(row):return row.moving).size()
	check(moving_before>0 and moving_before==moving_after,"same-tick HUD refresh preserves all real moving bodies")
	await shot("real-raid-stable-walk")
	controller().set_primary_map("sea");await frames();controller().set_primary_map("land");await frames();app.update_battle()
	var recreated:int=0
	for id in land.actors:
		if ids.has(str(id)) and int(ids[str(id)])!=land.actors[id].get_instance_id():recreated+=1
	check(recreated==0,"map round trip retains every live animation instance")
	check(land.actors.values().filter(func(row):return row.moving).size()==moving_before,"map round trip does not reset walking")
	app.running=false;app.update_battle();await frames()
	var paused:Dictionary={}
	for id in land.actors:paused[id]={"frame":land.actors[id].frame_index,"time":land.actors[id].animation_time,"position":land.actors[id].position}
	await create_timer(.25).timeout
	for id in paused:
		check(land.actors[id].frame_index==paused[id].frame and land.actors[id].animation_time==paused[id].time and land.actors[id].position==paused[id].position,"pause freezes real actor "+str(id))
	await shot("real-raid-round-trip-paused")
	app.core.request({"op":"replay","serialized":saved,"tick":80});app.update_battle()
	check(land.actors.values().all(func(row):return row.hurt_until<0 and row.fire_until<0 and row.defeated_at<0),"backward replay primes current bodies without replaying historical hits")
	FileAccess.open(output_dir+"diagnostic.json",FileAccess.WRITE).store_string(JSON.stringify({"same_tick_moving_before":moving_before,"same_tick_moving_after":moving_after,"actors_recreated_after_map_round_trip":recreated,"actor_count":land.actors.size(),"source":"same real recorded v1 raid90.1 as baseline; authority untouched","main_account_written":false},"  "))
	finish()
