extends Control
## Visual-only world layers. Reads the same seat observation as the map.
## Coast geometry, detection, simulation RNG and commands are never modified.
var sea: Control
var clouds: Array[ColorRect] = []
var cloud_shadows: Array[ColorRect] = []
var redraw_elapsed := 0.0
var night := 0.0
var land_nodes: Array[Node2D] = []
var land_signature := 0
var visual_seed := 0
const Island = preload("res://scripts/procedural_island.gd")
const Ruin = preload("res://scripts/ruin_renderer.gd")
var ruin_nodes: Array[Node2D] = []
var weather = preload("res://scripts/weather_visual.gd").new()
var weather_overlay: ColorRect
var visual_time := 0.0
var manual_time := -1.0
var drift := Vector2.ZERO
var wake_history: Dictionary = {}
var last_tick := -1
var expedition_scenery: Node2D
const CLOUD = preload("res://shaders/anime_cloud.gdshader")

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	show_behind_parent = true
	for i in range(12):
		for shadow in [true, false]:
			var puff := ColorRect.new()
			puff.mouse_filter = Control.MOUSE_FILTER_IGNORE
			puff.show_behind_parent = shadow
			var material := ShaderMaterial.new()
			material.shader = CLOUD
			material.set_shader_parameter("shadow", shadow)
			material.set_shader_parameter("variant", float(i))
			puff.material = material
			add_child(puff)
			if shadow:
				cloud_shadows.append(puff)
			else:
				clouds.append(puff)

	expedition_scenery = preload("res://scripts/expedition_scenery.gd").new()
	expedition_scenery.name = "ProceduralExpeditionSetPieces"
	add_child(expedition_scenery)
	weather_overlay = ColorRect.new()
	weather_overlay.name = "RainAndMist"
	weather_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var atmosphere := ShaderMaterial.new()
	atmosphere.shader = preload("res://shaders/weather_overlay.gdshader")
	weather_overlay.material = atmosphere
	add_child(weather_overlay)
	weather_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

func _process(delta: float) -> void:
	if sea == null or sea.view.is_empty():
		return
	visible = sea.uses_anime_environment()
	if not visible:
		return
	weather.update(sea.view, delta, sea.weather_paused)
	visual_time = manual_time if manual_time >= 0 else visual_time + delta
	night = float(weather.current.night)
	var weather_wind: Vector2 = weather.wind_vector()
	drift += weather_wind * float(weather.current.wind) * delta * 4.0
	var uniforms := {"visual_time":visual_time,"night_amount":night,"overcast":weather.current.overcast,"roughness":weather.current.roughness,"rain_amount":weather.current.rain,"fog_amount":weather.current.fog,"wind_speed":weather.current.wind,"wind_direction":weather_wind}
	# New adventure biomes have a distinct water colour; historic and saved maps retain their palette.
	var salvage: Dictionary = sea.view.get("salvage", {})
	uniforms["adventure_theme"] = ["", "atoll", "fractured", "fjord", "drowned_city"].find(str(salvage.get("terrainTheme", ""))) if salvage.has("adventure") else 0
	uniforms["expedition_scene"] = ["", "sunken_metropolis", "cult_relay", "storm_wrecks", "thermal_vent", "refugee_causeway"].find(str(salvage.get("expedition",{}).get("scene","")))
	for entry in uniforms:
		sea.sea_material.set_shader_parameter(entry,uniforms[entry])
	weather_overlay.material.set_shader_parameter("visual_time",visual_time)
	weather_overlay.material.set_shader_parameter("rain_amount",weather.current.rain)
	weather_overlay.material.set_shader_parameter("fog_amount",weather.current.fog)
	weather_overlay.material.set_shader_parameter("night_amount",night)
	weather_overlay.material.set_shader_parameter("viewport_size",size)
	weather_overlay.material.set_shader_parameter("wind",Vector2(weather_wind.x,-weather_wind.y))
	_update_islands()
	expedition_scenery.update_camera(sea,visual_time)
	_update_wake_history()
	var field := Vector2(float(sea.view.get("width", 24000)), float(sea.view.get("height", 14000)))
	var unit_scale: float = sea.project(Vector2(1000, 0)).distance_to(sea.project(Vector2.ZERO)) / 1000.0
	for i in range(clouds.size()):
		var fraction := Vector2(fposmod(.18 + i * .397 + float(visual_seed%113)*.017, 1.0), fposmod(.13 + i * .317 + float(visual_seed%79)*.021, 1.0))
		var world := Vector2(fposmod(fraction.x * field.x + drift.x, field.x + 3500.0) - 800.0, fposmod(fraction.y * field.y+drift.y,field.y+2200.0)-600.0)
		var extent := Vector2(2900.0 + (i % 3) * 1150.0, 1900.0 + (i%2)*510.0) * unit_scale
		# Scale is geographic. Only previously detected units are drawn above clouds.
		clouds[i].position = sea.project(world) - extent * .5
		clouds[i].size = extent
		var clearings := PackedVector3Array()
		var visible_units: Array = sea.view.get("ships", []).duplicate()
		visible_units.append_array(sea.view.get("contacts", []))
		visible_units.append_array(sea.view.get("torpedoes", []))
		for unit in visible_units.slice(0,32):
			var position: Vector2 = sea.project(sea.pos(unit)) - clouds[i].position
			var radius := 42.0
			if unit.has("characterId"):
				position.y -= 22.0
				radius = 65.0
			clearings.append(Vector3(position.x,position.y,radius))
		clouds[i].material.set_shader_parameter("clear_count",clearings.size())
		clearings.resize(32)
		clouds[i].material.set_shader_parameter("clear_zones",clearings)
		clouds[i].material.set_shader_parameter("quad_size",extent)
		cloud_shadows[i].position = clouds[i].position + Vector2(250, -290) * unit_scale
		cloud_shadows[i].size = extent * 1.07
		var opacity := clampf(float(weather.current.cloud)*12.0-float(i),0.0,1.0)
		clouds[i].visible = opacity > .005
		cloud_shadows[i].visible = opacity > .005
		clouds[i].material.set_shader_parameter("cloud_opacity",opacity)
		cloud_shadows[i].material.set_shader_parameter("cloud_opacity",opacity)
		clouds[i].material.set_shader_parameter("variant",float(i)+float(visual_seed%9971)*.01)
		cloud_shadows[i].material.set_shader_parameter("variant",float(i)+float(visual_seed%9971)*.01)
		clouds[i].material.set_shader_parameter("visual_time",visual_time)
		cloud_shadows[i].material.set_shader_parameter("visual_time",visual_time)
		clouds[i].material.set_shader_parameter("overcast",weather.current.overcast)
		clouds[i].material.set_shader_parameter("night_amount", night)
		cloud_shadows[i].material.set_shader_parameter("night_amount", night)
	redraw_elapsed += delta
	if redraw_elapsed > .05:
		redraw_elapsed = 0.0
		queue_redraw()

func tone(color: Color) -> Color:
	var daylight := color.lerp(Color(color.r*.67,color.g*.73,color.b*.80,color.a),float(weather.current.get("overcast",0.0))*.6)
	return daylight.lerp(Color(color.r * .22, color.g * .34, color.b * .52, color.a), night)

func _draw() -> void:
	if sea == null or not sea.stylized_environment:
		return
	var islands:Array=sea.view.get("islands",[])
	var urban_islands:Dictionary={}
	if str(sea.view.get("salvage",{}).get("terrainTheme",""))=="drowned_city":
		for landmark in sea.view.get("salvage",{}).get("landmarks",[]):
			if bool(landmark.get("charted",false)):urban_islands[int(landmark.get("island_index",-1))]=true
	for island_index in range(islands.size()):
		var island:Array=islands[island_index]
		var polygon := PackedVector2Array()
		for point in island:
			polygon.append(sea.project(sea.pos(point)))
		if polygon.size() >= 3:
			island_shape(polygon,urban_islands.has(island_index))
	for ship in sea.view.get("ships", []):
		wake(ship)
	for contact in sea.view.get("contacts", []):
		wake(contact)

func closed(points: PackedVector2Array) -> PackedVector2Array:
	var result := points.duplicate()
	result.append(points[0])
	return result

func island_shape(polygon: PackedVector2Array, urban_foundation:bool=false) -> void:
	var center := Vector2.ZERO
	var bounds := Rect2(polygon[0], Vector2.ZERO)
	for p in polygon:
		center += p
		bounds = bounds.expand(p)
	center /= polygon.size()
	if not bounds.grow(100).intersects(Rect2(Vector2.ZERO, size)):
		return
	var diameter := minf(bounds.size.x, bounds.size.y)
	# Expansions are translucent water, not land: solid shoreline stays exact.
	for band in range(12, 0, -1):
		var expansions := Geometry2D.offset_polygon(polygon, float(band) * clampf(diameter * .012, .7, 2.0))
		for expanded in expansions:
			draw_colored_polygon(expanded, tone(Color(.28,.93,.80,.014)))
	# Two offshore foam fronts advance and dissolve with distinct phases.
	for i in range(polygon.size()):
		var a := polygon[i]
		var b := polygon[(i+1)%polygon.size()]
		var outward := ((a+b)*.5-center).normalized()
		for wave in range(2):
			var phase := fposmod(visual_time*.24+float(wave)*.5+float(i)*.09,1.0)
			var distance := lerpf(clampf(diameter*.17,9,44),1.0,phase)
			var alpha := sin(phase*PI)*.45
			var segments:=3 if urban_foundation else 1
			if urban_foundation:distance=minf(distance,8.0)
			for segment in range(segments):
				var curve := PackedVector2Array()
				for point_index in range(9):
					var u := (.08+float(segment)*.31+float(point_index)*.018) if urban_foundation else (.10+float(point_index)*.09)
					curve.append(a.lerp(b,u)+outward*(distance+sin(u*PI)*3.0))
				draw_polyline(curve,tone(Color(.90,1.0,.95,alpha)),1.3+sin(phase*PI)*.65,true)

func _update_islands() -> void:
	# Combined-arms terrain has its own native town/shore renderer. Keep this
	# layer alive for dynamic clouds, rain, wind and waves, without a second land.
	if str(sea.view.get("littoral",{}).get("version",""))=="cas-littoral-v4":
		visual_seed=int(sea.view.get("seed",0))
		for node in land_nodes:node.hide()
		for node in ruin_nodes:node.hide()
		return
	var salvage: Dictionary = sea.view.get("salvage",{})
	var modern := str(salvage.get("generatorVersion","")) in ["archipelago-3", "archipelago-adventure-1", "archipelago-adventure-2"]
	var landmarks: Array = salvage.get("landmarks",[]) if modern else []
	var theme := str(salvage.get("terrainTheme","")) if modern else ""
	var scene := str(salvage.get("expedition",{}).get("scene",""))
	var signature := hash([sea.view.get("islands", []),landmarks,theme,scene]) if modern else hash(sea.view.get("islands", []))
	if signature != land_signature:
		land_signature = signature
		visual_seed = absi(signature)
		for node in land_nodes:
			node.queue_free()
		land_nodes.clear()
		for node in ruin_nodes:
			node.queue_free()
		ruin_nodes.clear()
		var originals: Array = sea.view.get("islands", [])
		for index in range(originals.size()):
			var raw: Array = originals[index]
			var polygon := PackedVector2Array()
			for point in raw:
				polygon.append(sea.pos(point))
			if polygon.size()<3:
				continue
			var island := Island.new()
			island.show_behind_parent = false
			var local_landmarks: Array = []
			for landmark in landmarks:
				if int(landmark.get("island_index",-1))==index and bool(landmark.get("charted",false)) and str(landmark.get("collision",""))=="island":
					local_landmarks.append(landmark)
			island.configure(polygon,absi(hash(polygon)),theme,local_landmarks)
			island.surface.material.set_shader_parameter("expedition_style",["", "sunken_metropolis", "cult_relay", "storm_wrecks", "thermal_vent", "refugee_causeway"].find(scene))
			add_child(island)
			move_child(island,0)
			land_nodes.append(island)
		landmarks = landmarks.duplicate()
		landmarks.sort_custom(func(a: Dictionary,b: Dictionary):return float(a.get("y",0))>float(b.get("y",0)))
		for landmark in landmarks:
			if not bool(landmark.get("charted",false)) or str(landmark.get("collision",""))!="island":
				continue
			var ruin := Ruin.new()
			ruin.configure(landmark)
			add_child(ruin)
			# Buildings follow land and precede cloud/rain; all remain beneath tactical entities.
			move_child(ruin,land_nodes.size()+ruin_nodes.size())
			ruin_nodes.append(ruin)
	for island in land_nodes:
		island.update_camera(sea,visual_time,night,float(weather.current.overcast))
	# Scene floor plans, cabling and vents belong on the ground, beneath the existing ruin art.
	# Keeping this layer above roofs makes small set pieces read as stickers on buildings.
	if is_instance_valid(expedition_scenery):move_child(expedition_scenery,land_nodes.size())
	for ruin in ruin_nodes:
		ruin.update_camera(sea,visual_time,night,float(weather.current.overcast))

func _update_wake_history() -> void:
	var tick := int(sea.view.get("tick",0))
	if tick < last_tick:
		wake_history.clear()
	var units: Array = sea.view.get("ships",[]).duplicate()
	units.append_array(sea.view.get("contacts",[]))
	var current_ids: Array[String] = []
	for unit in units:
		var key := str(unit.get("id",""))
		current_ids.append(key)
		if not wake_history.has(key):
			wake_history[key] = []
		var history: Array = wake_history[key]
		if tick != last_tick:
			var point: Vector2 = sea.pos(unit)
			if history.is_empty() or point.distance_to(history[-1].p) > 5.0:
				history.append({"p":point,"tick":tick})
			while history.size() > 40 or (not history.is_empty() and tick-int(history[0].tick)>75):
				history.pop_front()
	for key in wake_history.keys():
		if not current_ids.has(str(key)):
			wake_history.erase(key)
	last_tick = tick

func wake(ship: Dictionary) -> void:
	var speed := float(ship.get("speed",0))
	if speed < 1:
		return
	var p: Vector2 = sea.project(sea.pos(ship))
	var heading := deg_to_rad(float(ship.get("heading",0)))
	var direction := Vector2(sin(heading),-cos(heading))
	var across := direction.orthogonal()
	var history: Array = wake_history.get(str(ship.get("id","")),[])
	for i in range(1,history.size()):
		var alpha := .32*float(i)/float(history.size())
		draw_line(sea.project(history[i-1].p),sea.project(history[i].p),tone(Color(.77,.98,.96,alpha)),2.0,true)
	var length := clampf(speed*2.2,18,80)
	for side in [-1.0,1.0]:
		for bead in range(7):
			var phase := fposmod(visual_time*.45+float(bead)/7.0,1.0)
			var center: Vector2 = p-direction*(8+phase*length)+across*side*(2+phase*12)
			var spread := 1.0+phase*2.8
			draw_line(center-across*spread,center+across*spread,tone(Color(.87,1.0,.98,(1.0-phase)*.44)),1.3,true)
