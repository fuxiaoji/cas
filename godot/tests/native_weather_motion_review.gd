extends SceneTree
## Real native sortie weather; no visual weather fixtures and no altered observation.
const Bridge = preload("res://scripts/core_bridge.gd")
const Sea = preload("res://scripts/sea_map.gd")
const Design = preload("res://scripts/ui_design.gd")
var core = Bridge.new()
var content_version := "salvage-v2" if OS.get_cmdline_user_args().has("--salvage-v2") else "salvage-v1"
var failures: Array[String] = []
var phases: Array[Dictionary] = []
var output := ""
var map
var environment
var label: Label
var last_kind := ""
func _initialize() -> void:
	call_deferred("record")
func record() -> void:
	output = ProjectSettings.globalize_path("res://../artifacts/godot/weather-motion/native-frames")
	DirAccess.make_dir_recursive_absolute(output)
	var made: Dictionary = core.request({"op":"new_salvage","seed":6109,"start":{"content":content_version,"fleet":[{"id":"IBS-U-USN-FLETCHER","hp":100,"ammo":60,"level":1,"equipment":false,"command":false},{"id":"IBS-U-USN-PERKINS","hp":100,"ammo":60,"level":1,"equipment":false,"command":false}]}})
	if not made.get("ok",false) or not core.view.has("weather"):
		push_error("native weather unavailable: "+str(made));core.close();quit(1);return
	var initial_deployment: Array[Dictionary] = []
	for ship in core.view.ships:
		initial_deployment.append({"id":ship.id,"identity":ship.get("characterId",""),"x":ship.x,"y":ship.y,"heading":ship.heading,"speed":ship.speed})
	var binary_path := OS.get_environment("CAS_SIM_PATH") if OS.has_environment("CAS_SIM_PATH") else ProjectSettings.globalize_path("res://../target/release/cas-sim.exe")
	var binary_hash := FileAccess.get_sha256(binary_path)
	map = Sea.new()
	root.add_child(map)
	map.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	map.view = core.view.duplicate(true)
	map.cinematic = true
	map.chibis = false
	environment = map.environment_layer
	environment.set_process(false)
	label = Label.new()
	label.position = Vector2(28,22)
	label.add_theme_font_override("font",Design.font(500))
	label.add_theme_font_size_override("font_size",21)
	label.add_theme_color_override("font_color",Color.WHITE)
	label.add_theme_color_override("font_outline_color",Color(.05,.15,.20,.9))
	label.add_theme_constant_override("outline_size",6)
	root.add_child(label)
	await process_frame
	var names := {"clear":"晴","cloudy":"多云","overcast":"阴","rain":"雨","fog":"雾"}
	var paused_snapshot := ""
	var paused_weather := ""
	var paused_animation := 0.0
	var coastline := Vector2.ZERO
	for p in core.view.islands[0]:
		coastline += map.pos(p)
	coastline /= core.view.islands[0].size()
	for frame in range(840):
		if frame < 600:
			var result: Dictionary = core.request({"op":"step","seconds":2})
			if not result.get("ok",false):
				failures.append("native step")
			map.view = core.view.duplicate(true)
		else:
			map.weather_paused = true
			if frame == 600:
				paused_snapshot = JSON.stringify(map.view)
				paused_weather = JSON.stringify(environment.weather.current)
				paused_animation = environment.visual_time
		var kind: String = str(map.view.weather.kind)
		if kind!=last_kind:
			phases.append({"frame":frame,"tick":map.view.tick,"weather":map.view.weather.duplicate(true),"environment":map.view.environment.duplicate(true)})
			last_kind = kind
		var tick := int(map.view.tick)
		label.text = "实机航次  /  %s    %02d:%02d  ·  60×模拟时钟验收" % [names[kind],tick/60,tick%60]
		if frame >= 600:
			label.text = "实机近岸  /  已暂停  ·  天气与战局固定，海浪继续流动"
		var camera_blend := smoothstep(0.0,1.0,clampf(float(frame-320)/280.0,0.0,1.0))
		map.zoom = lerpf(1.0,2.5,camera_blend)
		map.pan = Vector2.ZERO
		map.pan = (map.size*.5-map.project(coastline))*camera_blend
		var before := JSON.stringify(map.view)
		environment._process(1.0/30.0)
		map.queue_redraw()
		environment.queue_redraw()
		await process_frame
		await RenderingServer.frame_post_draw
		var image := root.get_texture().get_image()
		if image.save_png(output.path_join("frame-%04d.png"%frame))!=OK:
			failures.append("frame save")
		if frame in [70,190,310,430,550,839]:
			image.save_png(output.get_base_dir().path_join("native-%03d-%s.png"%[frame,kind]))
		if JSON.stringify(map.view)!=before:
			failures.append("observation mutated during render")
	if JSON.stringify(map.view)!=paused_snapshot or JSON.stringify(environment.weather.current)!=paused_weather:
		failures.append("paused weather or core state advanced")
	if environment.visual_time<=paused_animation:
		failures.append("paused water animation stopped")
	var kinds: Array[String] = []
	for phase in phases:
		if not kinds.has(str(phase.weather.kind)):
			kinds.append(str(phase.weather.kind))
	if kinds.size()!=5:
		failures.append("native film did not traverse all five seeded weather states")
	var report := {"content_version":content_version,"native_binary_sha256":binary_hash,"initial_deployment":initial_deployment,"frames":840,"fps":30,"seed":6109,"native_steps":600,"simulation_seconds_per_frame":2,"simulation_speed":60,"pause_seconds":8,"phases":phases,"unique_weather":kinds,"failures":failures,"observation_modified":false,"weather_source":"new_salvage native cas-sim.exe observation.weather; never fixture","capture":"actual GPU framebuffer PNG sequence; no synthesized frames"}
	var file := FileAccess.open(output.get_base_dir().path_join("native-render-test.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t"))
	core.close()
	print(JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)
