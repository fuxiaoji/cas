extends SceneTree
const Bridge = preload("res://scripts/core_bridge.gd")
const Sea = preload("res://scripts/sea_map.gd")
const Ruin = preload("res://scripts/ruin_renderer.gd")
const Monster = preload("res://scripts/monster_renderer.gd")
var core = Bridge.new()
var checks := 0
var failures: Array[String] = []
var snapshots: Array[String] = []
var samples: Array[Dictionary] = []
var fixture := false
var output := ""
var map
func _initialize() -> void:call_deferred("review")
func check(condition: bool,label: String) -> void:
	checks+=1
	if not condition:failures.append(label);push_error(label)
func start(seed_value: int,version: String) -> Dictionary:
	var result: Dictionary=core.request({"op":"new_salvage","seed":seed_value,"start":{"content":version,"fleet":[{"id":"IBS-U-USN-FLETCHER","hp":100,"ammo":100,"level":1 if version=="salvage-v1" else 0,"equipment":false,"command":false}]}})
	check(result.get("ok",false),"native "+version+" seed "+str(seed_value))
	return core.view.duplicate(true)
func capture(label: String) -> void:
	if DisplayServer.get_name()=="headless":return
	map.queue_redraw();await process_frame;await process_frame;await RenderingServer.frame_post_draw
	var path:=output.path_join(label+".png")
	check(root.get_texture().get_image().save_png(path)==OK,"saved "+label)
	snapshots.append(path)
func review() -> void:
	fixture=OS.get_cmdline_user_args().has("--fixture")
	output=ProjectSettings.globalize_path("res://../artifacts/godot/salvage-v3-environment"+("-fixture" if fixture else ""))
	DirAccess.make_dir_recursive_absolute(output)
	map=Sea.new();root.add_child(map);map.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	map.chibis=false;map.cinematic=true;map.environment_layer.set_process(false)
	if fixture:
		for i in range(4):samples.append({"seed":i,"view":fixture_view(i)})
	else:
		var found: Array[String]=[]
		for seed_value in range(40,72):
			var view:=start(seed_value,"salvage-v3")
			var theme:=str(view.get("salvage",{}).get("terrainTheme",""))
			if theme.is_empty():check(false,"v3 terrainTheme contract present");break
			if not found.has(theme):found.append(theme);samples.append({"seed":seed_value,"view":view})
			if samples.size()==4:break
		check(samples.size()==4,"four native terrain themes discovered")
	for sample in samples:
		var source: Dictionary=sample.view.duplicate(true)
		var theme:=str(source.salvage.terrainTheme)
		if not fixture:
			var repeat:=start(int(sample.seed),"salvage-v3")
			check(repeat.islands==source.islands and repeat.salvage.landmarks==source.salvage.landmarks,"same seed reproduces geometry and landmarks: "+theme)
		map.view=source.duplicate(true);map.zoom=1.0;map.pan=Vector2.ZERO
		map.environment_layer.weather.current.clear();map.environment_layer.visual_time=0;map.environment_layer.drift=Vector2.ZERO
		map.environment_layer._process(0)
		await process_frame
		check(map.environment_layer.land_nodes.size()==source.islands.size(),"all source islands retained: "+theme)
		check(map.environment_layer.ruin_nodes.size()==source.salvage.landmarks.size(),"all charted landmarks drawn: "+theme)
		for node in map.environment_layer.ruin_nodes:
			check(node.source==source.salvage.landmarks.filter(func(entry:Dictionary):return entry.id==node.source.id)[0],"source landmark preserved")
			var island:=PackedVector2Array()
			for point in source.islands[int(node.source.island_index)]:island.append(Vector2(float(point.x),float(point.y)))
			for building in node.buildings:
				var legal:=true
				for point in building.corners:legal=legal and Geometry2D.is_point_in_polygon(point,island)
				check(legal,"building base remains inside authoritative collision island")
			if node.local_sprite!=null:
				var legal:=true
				for x in [-.5,0.0,.5]:
					for y in [-.5,0.0,.5]:
						legal=legal and Geometry2D.is_point_in_polygon(Vector2(float(node.source.x),float(node.source.y))+Vector2(float(x)*node.sprite_ground_width,float(y)*node.sprite_ground_depth),island)
				check(legal,"illustrated building base fits real island in nine ground samples")
			var repeat:=Ruin.new();repeat.configure(node.source)
			check(repeat.buildings==node.buildings,"same landmark seed preserves exact decorative layout")
			repeat.free()
		await capture(theme+"-overview")
		if DisplayServer.get_name()!="headless":
			var original_pixels:=root.get_texture().get_image().get_data()
			map.view=source.duplicate(true);map.environment_layer._process(0);map.queue_redraw()
			await process_frame;await process_frame;await RenderingServer.frame_post_draw
			check(root.get_texture().get_image().get_data()==original_pixels,"same source and visual time render identical pixels: "+theme)
		if not source.salvage.landmarks.is_empty():
			var landmark: Dictionary=source.salvage.landmarks[0]
			if theme=="drowned_city":
				var towers:Array=source.salvage.landmarks.filter(func(entry:Dictionary):return entry.kind=="drowned_tower")
				if not towers.is_empty():landmark=towers[0]
			map.zoom=7.0;map.pan=Vector2.ZERO
			map.pan=map.size*.5-map.project(Vector2(float(landmark.x),float(landmark.y)))
			if fixture:map.environment_layer.weather.current.cloud=0.0
			map.environment_layer._process(0)
			await capture(theme+"-landmark")
		check(map.view==source,"render leaves all public observation unchanged: "+theme)
		var hidden:=source.duplicate(true)
		for landmark in hidden.salvage.landmarks:landmark.charted=false
		map.view=hidden;map.environment_layer._process(0)
		check(map.environment_layer.ruin_nodes.is_empty(),"uncharted landmark never rendered: "+theme)
	check(not Monster.is_creature({"id":"C1"}),"ordinary unidentified contact reveals no monster identity")
	check(Monster.is_creature({"id":"C1","entityKind":"monster"}),"only public monster flag enables creature projection")
	if fixture:
		map.view=fixture_view(3);map.zoom=2.1;map.pan=Vector2.ZERO
		map.pan=map.size*.5-map.project(Vector2(7000,4000));map.environment_layer._process(0)
		await capture("visible-creature-and-real-radius-fixture")
	else:
		for version in ["salvage-v1","salvage-v2"]:
			map.view=start(42,version);map.environment_layer._process(0)
			check(map.environment_layer.ruin_nodes.is_empty(),version+" keeps original environment, no new buildings")
			check(not map.view.salvage.has("landmarks"),version+" public shape frozen")
	for path in ["res://scripts/anime_environment.gd","res://scripts/procedural_island.gd","res://scripts/ruin_renderer.gd"]:
		var code:=FileAccess.get_file_as_string(path)
		check(not code.contains("anime-cloud-v2.png") and not code.contains("anime-island-v2.png"),"no fixed map photo reference: "+path)
	var seed_summary: Array[Dictionary]=[]
	for sample in samples:seed_summary.append({"seed":sample.seed,"theme":sample.view.salvage.terrainTheme,"islands":sample.view.islands.size(),"landmarks":sample.view.salvage.landmarks.size()})
	var receipt:={"source":"explicit renderer fixtures" if fixture else "real native salvage-v3 public observation","checks":checks,"passed":checks-failures.size(),"failures":failures,"gpu":DisplayServer.get_name()!="headless","seeds":seed_summary,"screenshots":snapshots}
	if not fixture:receipt["core_sha256"]=FileAccess.get_sha256(OS.get_environment("CAS_SIM_PATH") if OS.has_environment("CAS_SIM_PATH") else ProjectSettings.globalize_path("res://../target/release/cas-sim.exe"))
	var file:=FileAccess.open(output.path_join("receipt-headless.json" if DisplayServer.get_name()=="headless" else "receipt.json"),FileAccess.WRITE);file.store_string(JSON.stringify(receipt,"\t"));file.close()
	core.close();map.queue_free();await process_frame
	print(JSON.stringify(receipt));quit(0 if failures.is_empty() else 1)
func fixture_view(index: int) -> Dictionary:
	var poly: Array=[]
	for p in [Vector2(3000,2500),Vector2(5900,2500),Vector2(6100,5000),Vector2(4700,6100),Vector2(2900,5200)]:poly.append({"x":p.x,"y":p.y})
	var kinds:=["drowned_tower","industrial_ruin","flooded_dock","radio_mast","cult_pylon"]
	var landmarks: Array=[]
	for i in range(5):
		var center:=Vector2(3600+(i%3)*700,3400+floori(i/3.0)*1200)
		var footprint: Array=[]
		for offset in [Vector2(-240,-200),Vector2(240,-200),Vector2(240,200),Vector2(-240,200)]:footprint.append({"x":center.x+offset.x,"y":center.y+offset.y})
		landmarks.append({"id":i,"kind":kinds[i],"x":center.x,"y":center.y,"seed":900+i,"island_index":0,"height_m":320 if i==0 else 170,"flood":.35,"footprint":footprint,"charted":true,"collision":"island"})
	var contacts: Array=[]
	var species:=["scavenger","spitter","warden","leviathan","aversion"]
	for i in range(5):contacts.append({"id":"C"+str(i),"x":6500+(i%2)*900,"y":3000+i*500,"heading":90,"entityKind":"monster","species":species[i],"visualType":species[i],"boss":i>2,"health_fraction":.7,"phase":1})
	return {"tick":30,"width":11000,"height":8000,"environment":{"light":"day","sea_state":2,"visibility":100,"precipitation":false},"ships":[],"contacts":contacts,"islands":[poly],"salvage":{"generatorVersion":"archipelago-3","terrainTheme":["atoll","fractured","fjord","drowned_city"][index],"landmarks":landmarks,"ruins":[],"exits":[],"telegraphs":[{"id":1,"kind":"pulse","x":7000,"y":4200,"radius":800,"start_tick":0,"impact_tick":60,"source_contact":"C3"}]}}
