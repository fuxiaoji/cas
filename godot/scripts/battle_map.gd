extends "res://scripts/sea_map.gd"
## Interaction and authorized overlays. The inherited map owns the shared sea style.
signal draft_changed
signal weapon_order(request: Dictionary)
signal interaction_hint(text: String)
signal training_signal(name: String)
signal aim_state_changed(active: bool)
signal selection_cleared
var inspect_command: Callable
var editing := false
var draft_leader := 0
var readonly := false
var ranges_visible := true
var preview: Dictionary = {}
var reform_preview: Dictionary = {}
var torpedo_settings: Dictionary = {}
var gesture: Dictionary = {}
var surface: Dictionary = {}
var last_aim_ms := 0

func _process(_delta: float) -> void:
	if not gesture.is_empty() and gesture.get("weapon") == "torpedo" and not gesture.get("contact", {}).is_empty() and not gesture.has("anchor") and not gesture.get("cancelled", false):
		if Time.get_ticks_msec() - int(gesture.get("hover_ms", Time.get_ticks_msec())) >= 250:
			gesture.anchor = gesture.cursor
			_query_aim(false)
			queue_redraw()

func _ship(id: int) -> Dictionary:
	for row in view.get("ships", []):
		if int(row.id) == id:
			return row
	return {}

func _tracks() -> Array:
	var result: Array = view.get("contacts", []).duplicate()
	for radar in view.get("radarContacts", []):
		result.append(radar)
	return result

func _nearest(pointer: Vector2, weapon := "", ship := 0) -> Dictionary:
	var closest: Dictionary = {}
	var distance := 32.0
	for row in _tracks():
		if str(row.id).begins_with("R") and not weapon.is_empty():
			var key := "usableForShipIds" if weapon == "gun" else "torpedoForShipIds"
			if not row.get(key, []).has(ship):
				continue
		var next := project(pos(row)).distance_to(pointer)
		if next < distance:
			distance = next
			closest = row
	return closest

func begin_weapon(ship: int, weapon: String, pointer: Vector2) -> void:
	if readonly:
		interaction_hint.emit("回放只读，不能下达命令。")
		return
	selected_ship = ship
	gesture = {"ship": ship, "weapon": weapon, "start": pointer, "cursor": pointer, "contact": {}, "cancelled": false}
	aim_state_changed.emit(true)
	queue_redraw()

func cancel_pending() -> bool:
	if not gesture.is_empty():
		gesture = {}
		aim_state_changed.emit(false)
		interaction_hint.emit("已取消预令，未消耗弹药。")
		training_signal.emit("fireCancelled")
		queue_redraw()
		return true
	return false

func _cancel_area() -> Rect2:
	return Rect2(Vector2(size.x * 0.38, size.y - 83), Vector2(size.x * 0.24, 60))

func _query_aim(adjusted: bool) -> void:
	if gesture.is_empty() or gesture.get("contact", {}).is_empty() or not inspect_command.is_valid():
		return
	var request := {"op": "aim", "ship": int(gesture.ship), "weapon": str(gesture.weapon), "target": str(gesture.contact.id)}
	if gesture.weapon == "torpedo":
		request.merge(torpedo_settings.get(int(gesture.ship), {}), true)
		if adjusted and gesture.has("heading"):
			request.heading = gesture.heading
	var response: Dictionary = inspect_command.call(request)
	gesture.aim = response.get("data", {}) if response.get("ok", false) else {"valid": false, "error": response.get("error", "无法解算")}
	if not adjusted and gesture.weapon == "torpedo" and gesture.aim.has("heading"):
		gesture.heading = float(gesture.aim.heading)
		gesture.base_heading = float(gesture.aim.heading)
	if gesture.weapon == "torpedo" and gesture.get("aim", {}).get("valid", false):
		if adjusted and absf(float(gesture.get("heading", 0)) - float(gesture.get("base_heading", 0))) > 0.15:
			training_signal.emit("torpedoAdjusted")
		else:
			training_signal.emit("torpedoAimed")
	last_aim_ms = Time.get_ticks_msec()

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse: Vector2 = event.position
		if event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN] and event.pressed:
			var world := unproject(mouse)
			zoom = clampf(zoom * (1.12 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 1.12), 0.7, 8.0)
			pan += mouse - project(world)
			queue_redraw()
			accept_event()
			return
		if event.button_index == MOUSE_BUTTON_RIGHT:
			if event.pressed and cancel_pending():
				return
			dragging = event.pressed
			last_mouse = mouse
			return
		if event.button_index != MOUSE_BUTTON_LEFT:
			return
		if event.pressed:
			var active := _ship(selected_ship)
			if not active.is_empty() and not readonly:
				for index in range(2):
					var badge := project(pos(active)) + Vector2(-24 + index * 48, -48)
					if badge.distance_to(mouse) < 21:
						begin_weapon(selected_ship, "gun" if index == 0 else "torpedo", mouse)
						return
			for i in range(planned.size()):
				if editing and project(planned[i]).distance_to(mouse) < 15:
					surface = {"start": mouse, "waypoint": i}
					return
			surface = {"start": mouse, "pan": pan}
		else:
			if not gesture.is_empty():
				_finish_weapon(mouse)
				return
			var press := surface
			surface = {}
			if press.is_empty() or mouse.distance_to(press.start) > 8 or press.has("waypoint"):
				if press.has("waypoint"):
					draft_changed.emit()
				return
			if editing and not readonly:
				point_selected.emit(unproject(mouse))
				return
			for ship in view.get("ships", []):
				if project(pos(ship)).distance_to(mouse) < 27:
					selected_ship = int(ship.id)
					object_selected.emit("ship", ship)
					queue_redraw()
					return
			var contact := _nearest(mouse)
			if not contact.is_empty():
				object_selected.emit("contact", contact)
				return
			for ruin in view.get("salvage", {}).get("ruins", []):
				if project(pos(ruin.p)).distance_to(mouse) < 30:
					object_selected.emit("ruin", ruin)
					return
			for i in range(view.get("salvage", {}).get("exits", []).size()):
				var exit: Dictionary = view.salvage.exits[i]
				if project(pos(exit)).distance_to(mouse) < 31:
					object_selected.emit("exit", {"index": i, "p": exit})
					return
			selection_cleared.emit()
		queue_redraw()
	elif event is InputEventMouseMotion:
		var mouse: Vector2 = event.position
		if not gesture.is_empty():
			gesture.cursor = mouse
			gesture.cancelled = _cancel_area().has_point(mouse)
			if gesture.get("weapon") == "torpedo" and gesture.has("anchor"):
				var source := _ship(int(gesture.ship))
				var anchor: Vector2 = unproject(gesture.anchor) - pos(source)
				var cursor: Vector2 = unproject(mouse) - pos(source)
				var difference := rad_to_deg(atan2(cursor.x, cursor.y) - atan2(anchor.x, anchor.y))
				gesture.heading = fposmod(float(gesture.base_heading) + difference, 360.0)
				if Time.get_ticks_msec() - last_aim_ms >= 80:
					_query_aim(true)
			else:
				var target := _nearest(mouse, str(gesture.weapon), int(gesture.ship))
				if target.get("id", "") != gesture.get("contact", {}).get("id", ""):
					gesture.contact = target
					gesture.erase("aim")
					gesture.hover_ms = Time.get_ticks_msec()
					if gesture.weapon == "gun" and not target.is_empty():
						_query_aim(false)
			queue_redraw()
		elif dragging:
			pan += mouse - last_mouse
			last_mouse = mouse
			queue_redraw()
		elif not surface.is_empty():
			if surface.has("waypoint"):
				planned[int(surface.waypoint)] = unproject(mouse)
			elif not editing and mouse.distance_to(surface.start) > 4:
				pan = surface.pan + mouse - surface.start
			queue_redraw()

func _finish_weapon(mouse: Vector2) -> void:
	var order := gesture
	gesture = {}
	aim_state_changed.emit(false)
	queue_redraw()
	if order.get("cancelled", false) or _cancel_area().has_point(mouse):
		interaction_hint.emit("已取消预令，未消耗弹药。")
		training_signal.emit("fireCancelled")
		return
	if readonly or order.get("contact", {}).is_empty():
		interaction_hint.emit("未下令：请拖至本席可用的敌方接触。")
		return
	if order.weapon == "torpedo" and not order.has("anchor"):
		interaction_hint.emit("未发射：在目标上停留片刻，等待推荐射向。")
		return
	if not order.get("aim", {}).get("valid", false):
		var reason: Variant = order.get("aim", {}).get("error")
		interaction_hint.emit(str(reason) if reason != null and not str(reason).is_empty() else "射界或解算尚不可用。")
		return
	var request := {"op": "fire", "ship": int(order.ship), "weapon": str(order.weapon), "target": str(order.contact.id)}
	if order.weapon == "torpedo":
		request.merge(torpedo_settings.get(int(order.ship), {}), true)
		request.heading = float(order.get("heading", 0))
	weapon_order.emit(request)

func _draw() -> void:
	# The base map's legacy draft starts at the first hull. Render the selected
	# fleet's real preview here instead, without changing the persistent draft.
	var draft: Array[Vector2] = planned
	planned = []
	super._draw()
	planned = draft
	if view.is_empty():
		return
	if not _draw_command_overlays():return
	var compass := Vector2(size.x - 42, 190)
	draw_arc(compass, 20, 0, TAU, 32, Color("a6bbbd"), 1, true)
	draw_line(compass + Vector2(0, 22), compass - Vector2(0, 24), Color("d4bb7d"), 1.2, true)
	draw_colored_polygon(PackedVector2Array([compass + Vector2(0, -19), compass + Vector2(-5, 3), compass + Vector2(0, -2), compass + Vector2(5, 3)]), Color("e2c98a"))
	draw_string(font, compass + Vector2(-5, -28), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color("e2c98a"))
	var selected := _ship(selected_ship)
	var scale_m := project(Vector2(1000, 0)).distance_to(project(Vector2.ZERO)) / 1000.0
	var scale_distance: float = 1000 if scale_m * 1000 > 70 else 2000
	var scale_start := Vector2(28, size.y - 218)
	draw_line(scale_start, scale_start + Vector2(scale_distance * scale_m, 0), Color("b1c6cd"), 1.2, true)
	draw_string(font, scale_start + Vector2(0, -7), "%.0f km" % (scale_distance / 1000), HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color("a9c1c9"))
	if not selected.is_empty() and ranges_visible:
		for info in [["gunRange", Color(0.76, 0.88, 0.83, 0.25)], ["torpedoRange", Color(0.83, 0.72, 0.45, 0.25)], ["sightRange", Color(0.48, 0.80, 0.70, 0.18)], ["seenRange", Color(0.81, 0.55, 0.47, 0.18)], ["radarRange", Color(0.48, 0.71, 0.94, 0.3)]]:
			var radius := float(selected.get(info[0], 0)) * scale_m
			if radius > 0:
				draw_arc(project(pos(selected)), radius, 0, TAU, 96, info[1], 1.2, true)
	for radar in view.get("radarContacts", []):
		var at := project(pos(radar))
		draw_arc(at, 11, 0, TAU, 16, Color("91b5e3"), 1, true)
		draw_string(font, at + Vector2(13, 0), str(radar.id), HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color("91b5e3"))
	for light in view.get("illuminations", []):
		draw_circle(project(pos(light)), float(light.get("radius", 0)) * scale_m, Color(0.94, 0.82, 0.49, 0.10))
	for smoke in view.get("smoke", []):
		draw_circle(project(pos(smoke)), 90.0 * scale_m + 7, Color(0.52, 0.59, 0.61, 0.3))
	if not planned.is_empty():
		var sketch := PackedVector2Array()
		var leader := _ship(draft_leader)
		if not leader.is_empty():
			sketch.append(project(pos(leader)))
		for i in range(planned.size()):
			var p := project(planned[i])
			sketch.append(p)
			draw_circle(p, 5, Color("e2c98a"))
			draw_string(font, p + Vector2(8, -8), str(i + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color("e2c98a"))
		if not preview.get("valid", false) and sketch.size() > 1:
			draw_polyline(sketch, Color("db9b7d"), 1, true)
	for plan in [preview, reform_preview]:
		for path in plan.get("paths", []):
			var points := PackedVector2Array()
			for p in path.get("points", []):
				points.append(project(pos(p)))
			if points.size() > 1:
				draw_polyline(points, Color("c4d49c") if plan.get("valid", false) else Color("d58e79"), 1.4, true)
	for torpedo in view.get("torpedoes", []):
		var points := PackedVector2Array()
		for p in torpedo.get("trail", []):
			points.append(project(pos(p)))
		points.append(project(pos(torpedo)))
		if points.size() > 1:
			draw_polyline(points, Color("c9dd9e") if torpedo.get("own", false) else Color("f0a28a"), 1.6, true)
	if not selected.is_empty() and not readonly:
		for index in range(2):
			var at := project(pos(selected)) + Vector2(-24 + index * 48, -48)
			draw_circle(at, 18, Color("163e4d"))
			draw_arc(at, 18, 0, TAU, 20, Color("dfc68c"), 1, true)
			draw_string(font, at + Vector2(-8, 6), "炮" if index == 0 else "雷", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color("f1d398"))
	if not gesture.is_empty():
		var source := _ship(int(gesture.ship))
		var from := project(pos(source))
		var cursor: Vector2 = gesture.cursor
		var color := Color("d68c78") if gesture.get("cancelled", false) else Color("e3c486")
		draw_line(from, cursor, color, 1.6, true)
		if gesture.has("heading"):
			var radians := deg_to_rad(float(gesture.heading))
			var extent := float(gesture.get("aim", {}).get("range", 7000)) * scale_m
			draw_line(from, from + Vector2(sin(radians), -cos(radians)) * extent, color, 2, true)
		var aim: Dictionary = gesture.get("aim", {})
		if gesture.weapon == "torpedo":
			var radius := minf(float(aim.get("range", 0)) * scale_m, maxf(size.x, size.y))
			for arc in aim.get("arcs", []):
				var start := deg_to_rad(float(arc.get("from", 0)) - 90)
				var finish := deg_to_rad(float(arc.get("to", 0)) - 90)
				if finish < start:
					finish += TAU
				var wedge := PackedVector2Array([from])
				for i in range(33):
					var angle := lerpf(start, finish, i / 32.0)
					wedge.append(from + Vector2(cos(angle), sin(angle)) * radius)
				draw_colored_polygon(wedge, Color(0.82, 0.73, 0.43, 0.09))
				draw_arc(from, radius, start, finish, 32, Color(0.87, 0.78, 0.49, 0.55), 1, true)
		var text := "炮击" if gesture.weapon == "gun" else "鱼雷瞄准"
		if aim.has("chance"):
			text += "  命中率 %d%%" % int(round(float(aim.chance)))
		var reason: Variant = aim.get("error")
		text += "  " + (str(reason) if reason != null and not str(reason).is_empty() else "松手下令" if aim.get("valid", false) else "拖向敌方接触")
		var warning := "注意：已知友舰可能进入雷迹" if aim.get("friendly", false) else ""
		var width := maxf(font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x, font.get_string_size(warning, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x)
		var text_at := Vector2(clampf(cursor.x + 16, 12, maxf(12, size.x - width - 12)), clampf(cursor.y - 18, 26, size.y - 150))
		draw_style_box(_aim_plate(), Rect2(text_at - Vector2(10, 22), Vector2(width + 20, 56 if not warning.is_empty() else 32)))
		draw_string(font, text_at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color("173c50"))
		if not warning.is_empty():
			draw_string(font, text_at + Vector2(0, 24), warning, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color("b5523e"))
		draw_rect(_cancel_area(), Color("233542"))
		draw_rect(_cancel_area(), color, false, 1)
		draw_string(font, _cancel_area().position + Vector2(15, 38), "拖到这里取消预令", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, color)

func _aim_plate() -> StyleBoxFlat:
	var plate := StyleBoxFlat.new()
	plate.bg_color = Color(0.96, 0.97, 0.92, 0.97)
	plate.set_corner_radius_all(6)
	return plate

func _draw_command_overlays()->bool:return true
