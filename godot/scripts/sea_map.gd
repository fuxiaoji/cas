class_name CasSeaMap
extends Control
signal point_selected(point: Vector2)
signal object_selected(kind: String, object: Dictionary)
var view: Dictionary = {}
var cards: Dictionary = {}
var textures: Dictionary = {}
var chibis := true
var planned: Array[Vector2] = []
var selected_ship := 0
var selected_contact := ""
var intel_contact := ""
var zoom := 1.0
var pan := Vector2.ZERO
## Screen pixels only. Keep pan and every world coordinate free of recoil.
var combat_offset := Vector2.ZERO
var projectile_rate := 0.0
var projectile_readonly := false
var projectile_epoch := 0
var projectiles: Node
var dragging := false
var last_mouse := Vector2.ZERO
const Design = preload("res://scripts/ui_design.gd")
const Art = preload("res://scripts/character_art.gd")
const HistoricalMap = preload("res://scripts/historical_map.gd")
@export var historical_satellite_enabled := true
var font: Font
var sea_background: ColorRect
var sea_material: ShaderMaterial
var stylized_environment := true
var cinematic := false
var weather_paused := false
var grid_visible := false
var environment_layer: Control
var shore_signature := ""
var monster_intel: Control
var enemy_animation := preload("res://scripts/enemy_animation.gd").new()

func is_historical_chart() -> bool:
	return HistoricalMap.is_historical(view)

func has_satellite_chart() -> bool:
	return not HistoricalMap.registration(view).is_empty()

func uses_anime_environment() -> bool:
	return stylized_environment and not is_historical_chart()

func focus_fleet() -> void:
	if view.get("ships", []).is_empty() or size.x < 1:
		return
	var center := Vector2.ZERO
	for ship in view.ships:
		center += pos(ship)
	center /= view.ships.size()
	zoom = 2.2
	pan = Vector2.ZERO
	pan = Vector2(size.x * 0.26, size.y * 0.63) - project(center) + combat_offset
	queue_redraw()

func _ready() -> void:
	clip_contents = true
	font = Design.font(500)
	sea_background = ColorRect.new()
	sea_background.name = "AnimeSea"
	sea_background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sea_background.show_behind_parent = true
	add_child(sea_background)
	sea_background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	sea_material = ShaderMaterial.new()
	sea_material.shader = preload("res://shaders/salvage_sea.gdshader")
	sea_background.material = sea_material
	environment_layer = preload("res://scripts/anime_environment.gd").new()
	environment_layer.name = "CloudsAndIslands"
	environment_layer.sea = self
	add_child(environment_layer)
	environment_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	monster_intel = preload("res://scenes/ui/monster_intel.tscn").instantiate()
	add_child(monster_intel)
	projectiles = preload("res://scripts/projectile_renderer.gd").new()
	projectiles.name = "ProjectilePresentation"
	projectiles.sea = self
	add_child(projectiles)

func project(p: Vector2) -> Vector2:
	var field := Vector2(float(view.get("width", 24000)), float(view.get("height", 14000)))
	var scale_factor: float = minf(size.x / field.x, size.y / field.y) * zoom
	var centered := p - field / 2.0
	centered.y = -centered.y
	return centered * scale_factor + size / 2.0 + pan + combat_offset

func unproject(p: Vector2) -> Vector2:
	var field := Vector2(float(view.get("width", 24000)), float(view.get("height", 14000)))
	var scale_factor: float = minf(size.x / field.x, size.y / field.y) * zoom
	var centered := (p - size / 2.0 - pan - combat_offset) / scale_factor
	centered.y = -centered.y
	return centered + field / 2.0

func pos(row: Dictionary) -> Vector2:
	return Vector2(float(row.get("x", 0)), float(row.get("y", 0)))

func exit_region(index: int) -> Rect2:
	# Public world bounds only. Never infer a larger extraction area from drawn ships.
	var exits: Array = view.get("salvage",{}).get("exits",[])
	if index<0 or index>=exits.size():
		return Rect2()
	var exit: Dictionary = exits[index]
	if str(exit.get("shape",""))!="rectangle":
		return Rect2()
	var bounds: Dictionary = exit.get("bounds",{})
	if not bounds.has_all(["min_x","min_y","max_x","max_y"]):
		return Rect2()
	return Rect2(Vector2(float(bounds.min_x),float(bounds.min_y)),Vector2(float(bounds.max_x)-float(bounds.min_x),float(bounds.max_y)-float(bounds.min_y)))

func exit_screen_region(index: int) -> Rect2:
	var region := exit_region(index)
	if not region.has_area():
		return Rect2()
	return Rect2(project(region.position),project(region.end)-project(region.position)).abs()

func exit_tooltip(index: int) -> String:
	if exit_region(index).has_area():
		return "集结撤离：所有可航行舰艇进入标示的矩形集合海域后开始撤离；以区域边界为准。"
	return "撤离：所有可航行舰艇进入此点 1000 米范围后开始撤离。"

func _get_tooltip(at_position: Vector2) -> String:
	var task_tip: String = preload("res://scripts/expedition_markers.gd").tooltip(self,view,at_position)
	if not task_tip.is_empty(): return task_tip
	var exits: Array = view.get("salvage",{}).get("exits",[])
	for index in range(exits.size()):
		if project(pos(exits[index])).distance_to(at_position)<31.0:
			return exit_tooltip(index)
	return ""

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			zoom = minf(zoom * 1.2, 6.0)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			zoom = maxf(zoom / 1.2, 0.7)
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			dragging = event.pressed
			last_mouse = event.position
		elif event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			var salvage: Dictionary = view.get("salvage", {})
			for ruin in salvage.get("ruins", []):
				if project(pos(ruin.get("p", {}))).distance_to(event.position) < 30:
					object_selected.emit("ruin", ruin)
					return
			for i in range(salvage.get("exits", []).size()):
				var exit: Dictionary = salvage.exits[i]
				if project(pos(exit)).distance_to(event.position) < 32:
					object_selected.emit("exit", {"index": i, "p": exit})
					return
			for contact in view.get("contacts", []):
				if project(pos(contact)).distance_to(event.position) < 30:
					object_selected.emit("contact", contact)
					return
			for ship in view.get("ships", []):
				if project(pos(ship)).distance_to(event.position) < 30:
					selected_ship = int(ship.id)
					object_selected.emit("ship", ship)
					return
			point_selected.emit(unproject(event.position))
		queue_redraw()
	elif event is InputEventMouseMotion and dragging:
		pan += event.position - last_mouse
		last_mouse = event.position
		queue_redraw()

func _draw() -> void:
	if is_instance_valid(monster_intel):
		var guide:Control=get_parent().get_node_or_null("ChapterBattleGuide")
		var teaching:bool=guide!=null and guide.get_node("Card").visible and (str(guide.step_id).begins_with("entity_") or str(guide.step_id)=="boss_evade")
		monster_intel.update_observation(view, intel_contact, cinematic, teaching)
	var painted: bool = uses_anime_environment()
	var world_background:bool=_has_world_background()
	var satellite: bool = is_historical_chart() and historical_satellite_enabled and has_satellite_chart()
	if is_instance_valid(sea_background):
		sea_background.visible = painted and not world_background
		if painted and not world_background:
			sea_material.set_shader_parameter("world_origin", unproject(Vector2.ZERO))
			sea_material.set_shader_parameter("world_span", unproject(size) - unproject(Vector2.ZERO))
			var signature := str(hash(view.get("islands", [])))
			if signature != shore_signature:
				shore_signature = signature
				var shoals := PackedVector3Array()
				for island in view.get("islands", []).slice(0,32):
					var center := Vector2.ZERO
					for point in island:
						center += pos(point)
					center /= maxf(island.size(),1)
					var radius := 0.0
					for point in island:
						radius += center.distance_to(pos(point))
					radius /= maxf(island.size(),1)
					shoals.append(Vector3(center.x,center.y,radius))
				sea_material.set_shader_parameter("shoal_count",shoals.size())
				shoals.resize(32)
				sea_material.set_shader_parameter("shoals",shoals)
	if is_instance_valid(environment_layer):
		environment_layer.visible = painted and not world_background
		environment_layer.queue_redraw()
	if not painted and not world_background:
		draw_rect(Rect2(Vector2.ZERO, size), Color("102335"))
	if satellite:
		HistoricalMap.paint(self)
	if view.is_empty():
		return
	if (grid_visible or (not painted and not satellite)) and not cinematic:
		for x in range(0, int(view.get("width", 24000)) + 1, 2000):
			draw_line(project(Vector2(x, 0)), project(Vector2(x, float(view.get("height", 14000)))), Color(0.31, 0.55, 0.62, 0.13))
		for y in range(0, int(view.get("height", 14000)) + 1, 2000):
			draw_line(project(Vector2(0, y)), project(Vector2(float(view.get("width", 24000)), y)), Color(0.31, 0.55, 0.62, 0.13))
	if not painted and not satellite and not world_background:
		for island in view.get("islands", []):
			var polygon := PackedVector2Array()
			for p in island:
				polygon.append(project(pos(p)))
			if polygon.size() >= 3:
				draw_colored_polygon(polygon, Color("3d605e"))
				var outline := PackedVector2Array()
				for i in range(polygon.size()):
					outline.append(polygon[i])
					outline.append(polygon[(i + 1) % polygon.size()])
				draw_multiline(outline, Color("82a39b"), 1, false)
	_draw_additional_terrain()
	var salvage: Dictionary = view.get("salvage", {})
	# Telegraph areas are already filtered by the core to visible sources.
	var visual_clock := float(environment_layer.visual_time) if is_instance_valid(environment_layer) else 0.0
	enemy_animation.update(view,visual_clock)
	preload("res://scripts/monster_renderer.gd").draw_defeated(self,view,visual_clock,textures)
	preload("res://scripts/expedition_markers.gd").draw(self,view,visual_clock)
	for telegraph in salvage.get("telegraphs",[]):
		preload("res://scripts/monster_renderer.gd").draw_telegraph(self,telegraph,int(view.get("tick",0)),visual_clock)
	var chapter: Dictionary = view.get("chapter",{})
	var objective: Dictionary = chapter.get("objective",{})
	if objective.get("beacon") is Dictionary:
		var beacon := project(pos(objective.beacon))
		var beacon_color := Color("a4e6d2")
		var shared := false
		for exit in salvage.get("exits",[]):
			shared = shared or pos(exit).distance_to(pos(objective.beacon))<1.0
		if not shared:draw_arc(beacon,24,0,TAU,32,Color(beacon_color.r,beacon_color.g,beacon_color.b,.45),1.2,true)
		draw_colored_polygon(PackedVector2Array([beacon+Vector2(0,-13),beacon+Vector2(8,8),beacon+Vector2(0,4),beacon+Vector2(-8,8)]),beacon_color)
		if not cinematic and not shared:
			draw_string_outline(font,beacon+Vector2(-31,43),"返航信标",HORIZONTAL_ALIGNMENT_LEFT,-1,15,3,Color("12374b"))
			draw_string(font,beacon+Vector2(-31,43),"返航信标",HORIZONTAL_ALIGNMENT_LEFT,-1,15,beacon_color)
	for i in range(salvage.get("exits", []).size()):
		var p := project(pos(salvage.exits[i]))
		var region := exit_screen_region(i)
		if region.has_area():
			draw_rect(region,Color(.43,.87,.72,.055))
			draw_rect(region,Color(.59,.94,.80,.72),false,1.5,true)
		draw_arc(p, 25, 0, TAU, 48, Color("87d8bd"), 2, true)
		if not cinematic:
			var title := "集结撤离" if region.has_area() else "撤离 %d" % (i + 1)
			if objective.get("beacon") is Dictionary and pos(salvage.exits[i]).distance_to(pos(objective.beacon))<1.0:title="返航信标"
			var offset := Vector2(-34,48) if region.has_area() else Vector2(-23,48)
			if region.has_area():
				draw_string_outline(font,p+offset,title,HORIZONTAL_ALIGNMENT_LEFT,-1,17,3,Color(.02,.12,.18,.9))
			draw_string(font,p+offset,title,HORIZONTAL_ALIGNMENT_LEFT,-1,17,Color("edfff8"))
	for ruin in salvage.get("ruins", []):
		var p := project(pos(ruin.p))
		var c := Color("65858c") if ruin.get("collected", false) else Color("e6c27b")
		var archive := objective.get("archiveRuinId")!=null and int(ruin.id)==int(objective.archiveRuinId)
		if archive and not ruin.get("collected",false):c=Color("e2b9f1")
		draw_rect(Rect2(p - Vector2(7, 7), Vector2(14, 14)), c, false, 2)
		if archive:
			draw_line(p+Vector2(-3,-3),p+Vector2(3,-3),c,1.2,true)
			draw_line(p+Vector2(-3,1),p+Vector2(3,1),c,1.2,true)
		if not cinematic and zoom > 2.0:
			draw_string(font, p + Vector2(12, -4), "信标档案" if archive else "残骸 %d" % int(ruin.id), HORIZONTAL_ALIGNMENT_LEFT, -1, 16, c)
	for fleet in view.get("fleets", []):
		for path in fleet.get("paths", []):
			var route := PackedVector2Array()
			for p in path.get("points", []):
				route.append(project(pos(p)))
			if route.size() > 1:
				draw_polyline(route, Color(0.5, 0.86, 0.83, 0.45), 2, true)
	for ship in view.get("ships", []):
		_draw_ship(ship, false)
	for contact in view.get("contacts", []):
		_draw_ship(contact, true)
	for torpedo in view.get("torpedoes", []):
		var p := project(pos(torpedo))
		var direction := Vector2(sin(deg_to_rad(float(torpedo.heading))), -cos(deg_to_rad(float(torpedo.heading))))
		draw_line(p - direction * 9, p + direction * 9, Color("f5b58b"), 2, true)
	if is_instance_valid(projectiles):
		projectiles.observe(view, projectile_readonly, projectile_epoch)
		projectiles.paint(self)
	if not planned.is_empty():
		var route := PackedVector2Array()
		if not view.get("ships", []).is_empty():
			route.append(project(pos(view.ships[0])))
		for p in planned:
			route.append(project(p))
			draw_circle(project(p), 5, Color("f1d38c"))
		if route.size() > 1:
			draw_polyline(route, Color("f1d38c"), 2, true)
	if not cinematic:
		_draw_minimap()

func _draw_additional_terrain()->void:
	pass

func _has_world_background()->bool:return false

func _draw_minimap() -> void:
	var rectangle := Rect2(Vector2(size.x - 205, size.y - 186), Vector2(180, 104))
	draw_rect(rectangle, Color(0.02, 0.07, 0.11, 0.9))
	draw_rect(rectangle, Color("547a88"), false, 1)
	var field := Vector2(float(view.get("width", 24000)), float(view.get("height", 14000)))
	for ship in view.get("ships", []):
		var relative := pos(ship) / field
		draw_circle(rectangle.position + Vector2(relative.x, 1.0 - relative.y) * rectangle.size, 3, Color("9ce1da"))
	var exits: Array = view.get("salvage",{}).get("exits",[])
	for index in range(exits.size()):
		var exit: Dictionary = exits[index]
		var region := exit_region(index)
		if region.has_area():
			var top_left := Vector2(region.position.x/field.x,1.0-region.end.y/field.y)
			var area := Rect2(rectangle.position+top_left*rectangle.size,region.size/field*rectangle.size)
			draw_rect(area,Color(.43,.87,.72,.14))
			draw_rect(area,Color(.59,.94,.80,.8),false,1.0)
		var relative := pos(exit) / field
		draw_arc(rectangle.position + Vector2(relative.x, 1.0 - relative.y) * rectangle.size, 5, 0, TAU, 12, Color("e8d196"), 1)
	for contact in view.get("contacts", []):
		var relative := pos(contact) / field
		draw_circle(rectangle.position + Vector2(relative.x, 1.0 - relative.y) * rectangle.size, 2, Color("f18d80"))

func _draw_ship(ship: Dictionary, enemy: bool) -> void:
	var p := project(pos(ship))
	var heading := deg_to_rad(float(ship.get("heading", 0)))
	var direction := Vector2(sin(heading), -cos(heading))
	var color := Color("f18d80") if enemy else Color("9ce1da")
	var sprite_drawn := false
	if enemy:
		var visual_clock := float(environment_layer.visual_time) if is_instance_valid(environment_layer) else 0.0
		sprite_drawn = preload("res://scripts/monster_renderer.gd").draw_contact(self,ship,p,zoom,visual_clock,textures,enemy_animation)
	# Use only own-seat geometry; never infer an unpublished vessel identity.
	if not enemy and ship.has("hullLengthM"):
		var half_length := float(ship.hullLengthM) / 2.0
		var world_direction := Vector2(sin(heading), cos(heading))
		draw_line(project(pos(ship) - world_direction * half_length), project(pos(ship) + world_direction * half_length), color, 3, true)
	elif not sprite_drawn:
		draw_circle(p, 4, color)
	if not enemy and chibis:
		var resolved: Dictionary = Art.resolve(cards,ship,false)
		var clock := float(environment_layer.visual_time) if is_instance_valid(environment_layer) else 0.0
		sprite_drawn = Art.draw(self,resolved.card,p,72.0 if int(ship.get("id",0))==selected_ship else 57.0,float(ship.get("speed",0))>1.0,clock)
	if not enemy and not sprite_drawn:
		var silhouette := PackedVector2Array()
		for point in [Vector2(0, -14), Vector2(-4, -6), Vector2(-4, 9), Vector2(0, 12), Vector2(4, 9), Vector2(4, -6)]:
			silhouette.append(p + point.rotated(heading))
		draw_colored_polygon(silhouette, color)
	if int(ship.get("id", -1)) == selected_ship and not enemy:
		draw_arc(p, 19, 0, TAU, 32, Color("f1d38c"), 2, true)
	draw_line(p, p + direction * 22, color, 1, true)
	var caption := str(ship.get("name", "")) if ship.get("name") != null else ""
	if caption.is_empty():
		caption = "接触 " + str(ship.get("id", ""))
	if enemy and str(ship.get("id", "")) != selected_contact:
		caption = str(ship.get("id", ""))
	var leader: int = int(view.get("fleets", [{}])[0].get("leader", -1)) if not view.get("fleets", []).is_empty() else -1
	var show_caption := (str(ship.get("id", "")) == selected_contact if enemy else (int(ship.get("id", -1)) == selected_ship or int(ship.get("id", -1)) == leader)) or zoom > 3
	if enemy and ship.has("attack"):
		show_caption=str(ship.get("id",""))==intel_contact
		if show_caption:caption=str(ship.get("name",ship.get("id","")))
	if enemy and bool(ship.get("boss",false)):show_caption=false
	if not cinematic and show_caption:
		draw_string_outline(font, p + Vector2(14, 18), caption, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, 3, Color("12374b"))
		draw_string(font, p + Vector2(14, 18), caption, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, color)
