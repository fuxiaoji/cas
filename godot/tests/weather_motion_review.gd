extends SceneTree
## Captures actual Godot frames. Weather fixtures isolate each visual state;
## native weather progression has its own separate integration test.
const Bridge = preload("res://scripts/core_bridge.gd")
const Sea = preload("res://scripts/sea_map.gd")
const Weather = preload("res://scripts/weather_visual.gd")
const Design = preload("res://scripts/ui_design.gd")
var core = Bridge.new()
var failures: Array[String] = []
var frame_index := 0
var output := ""
var map
var environment
var label: Label
var differences: Dictionary = {}

func _initialize() -> void:
	call_deferred("review")

func capture() -> Image:
	map.queue_redraw()
	environment.queue_redraw()
	await process_frame
	await RenderingServer.frame_post_draw
	var frame := root.get_texture().get_image()
	if frame.save_png(output.path_join("frames/frame-%04d.png" % frame_index)) != OK:
		failures.append("frame save")
	frame_index += 1
	return frame

func changed_fraction(a: Image, b: Image) -> float:
	var changed := 0
	var samples := 0
	# Lower middle open water: no label, minimap or camera movement in this sample.
	for y in range(int(a.get_height()*.65),int(a.get_height()*.85),8):
		for x in range(int(a.get_width()*.3),int(a.get_width()*.7),8):
			var ca := a.get_pixel(x,y)
			var cb := b.get_pixel(x,y)
			if absf(ca.r-cb.r)+absf(ca.g-cb.g)+absf(ca.b-cb.b)>.025:
				changed += 1
			samples += 1
	return float(changed)/maxf(samples,1)

func review() -> void:
	output = ProjectSettings.globalize_path("res://../artifacts/godot/weather-motion")
	DirAccess.make_dir_recursive_absolute(output.path_join("frames"))
	var generated: Dictionary = core.request({"op":"new_salvage","seed":6106,"start":{"content":"salvage-v1","fleet":[{"id":"IBS-U-USN-FLETCHER","hp":100,"ammo":60,"level":1,"equipment":false,"command":false},{"id":"IBS-U-USN-PERKINS","hp":100,"ammo":60,"level":1,"equipment":false,"command":false}]}})
	if not generated.get("ok",false):
		push_error(str(generated)); core.close(); quit(1); return
	map = Sea.new()
	root.add_child(map)
	map.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	map.view = core.view.duplicate(true)
	map.chibis = false
	map.cinematic = true
	map.zoom = 1.3
	map.selected_ship = int(map.view.ships[0].id)
	environment = map.environment_layer
	environment.set_process(false)
	label = Label.new()
	label.position = Vector2(28,22)
	label.add_theme_font_override("font",Design.font(500))
	label.add_theme_font_size_override("font_size",21)
	label.add_theme_color_override("font_color",Color.WHITE)
	label.add_theme_color_override("font_outline_color",Color(.05,.15,.20,.85))
	label.add_theme_constant_override("outline_size",6)
	root.add_child(label)
	await process_frame
	var source := JSON.stringify(map.view)
	var native_observation: Dictionary = map.view.duplicate(true)
	var names := {"clear":"晴 · 流动碎浪","cloudy":"多云 · 云影掠过","overcast":"阴 · 漫射天光","rain":"雨 · 风雨与涟漪","fog":"雾 · 低空薄雾"}
	for kind in ["clear","cloudy","overcast","rain","fog"]:
		label.text = "环境表现验收  /  " + names[kind]
		map.view = native_observation.duplicate(true)
		var look: Dictionary = Weather.LOOKS[kind]
		map.view.weather = {"kind":kind,"next":kind,"transition_progress":0,"cloud_cover":look.cloud,"rain_intensity":look.rain,"fog_density":look.fog,"visual_wind_heading_deg":70,"visual_wind_speed":12}
		environment.weather.current.clear()
		var first: Image
		for frame in range(60):
			environment._process(1.0/15.0)
			var rendered: Image = await capture()
			if frame == 0:
				first = rendered
			if frame == 59:
				differences[kind] = changed_fraction(first,rendered)
				rendered.save_png(output.path_join(kind+".png"))
				if float(differences[kind])<.10:
					failures.append("motion below visible threshold "+kind)
	# Smooth transition freezes on pause; wave clock continues while observation is unchanged.
	label.text = "动态过渡验收  /  晴转雨 · 权威目标帧间平滑"
	map.view.weather = {"kind":"clear","next":"rain","transition_progress":1.0,"cloud_cover":.96,"rain_intensity":.78,"fog_density":.13,"visual_wind_heading_deg":150,"visual_wind_speed":12}
	for frame in range(90):
		environment._process(1.0/15.0)
		await capture()
	map.weather_paused = true
	var paused_weather := JSON.stringify(environment.weather.current)
	var paused_view := JSON.stringify(map.view)
	var previous_time: float = environment.visual_time
	label.text = "暂停验收  /  天气与战局停留 · 海浪仍流动"
	for frame in range(30):
		environment._process(1.0/15.0)
		await capture()
	if JSON.stringify(environment.weather.current)!=paused_weather:
		failures.append("paused weather advanced")
	if JSON.stringify(map.view)!=paused_view:
		failures.append("presentation changed paused observation")
	if environment.visual_time<=previous_time:
		failures.append("water clock stopped on pause")
	map.weather_paused = false
	# Recorded moving fleet uses real native route commands and actual positions only.
	map.view = core.view.duplicate(true)
	map.focus_fleet()
	map.zoom = 2.6
	var ship: Dictionary = core.view.ships[0]
	var route: Dictionary = core.request({"op":"route","fleet":int(ship.fleet),"mode":"follow","speed":18,"points":[{"x":float(ship.x)+3800,"y":float(ship.y)+1800}]})
	if not route.get("ok",false):
		failures.append("native route failed "+str(route))
	label.text = "航迹验收  /  原核航行位置 · 尾流连续扩散"
	for frame in range(60):
		var stepped: Dictionary = core.request({"op":"step","seconds":2})
		if not stepped.get("ok",false):
			failures.append("native step failed")
		map.view = core.view.duplicate(true)
		environment._process(1.0/15.0)
		await capture()
	root.get_texture().get_image().save_png(output.path_join("wake.png"))
	if environment.wake_history.get(str(ship.id),[]).size()<5:
		failures.append("real route did not build wake history")
	# Lost contacts must immediately lose their display-only trail.
	environment.wake_history["C-test-hidden"] = [{"p":Vector2.ZERO,"tick":0}]
	environment._update_wake_history()
	if environment.wake_history.has("C-test-hidden"):
		failures.append("hidden contact wake persisted")
	map.view = native_observation.duplicate(true)
	if JSON.stringify(map.view)!=source:
		failures.append("native source changed")
	if not environment.show_behind_parent:
		failures.append("weather could cover tactical entities")
	var report := {"frames":frame_index,"fps":15,"failures":failures,"motion_changed_fraction":differences,"observation_unchanged":JSON.stringify(map.view)==source,"weather_fixtures":"isolated look tests only; native weather authority validated separately","actual_native_route":route.get("ok",false),"pause":"weather fixed, sea animation continues","layer_order":"all environment layers behind known tactical entities"}
	var file := FileAccess.open(output.path_join("render-test.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t"))
	core.close()
	print(JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)

