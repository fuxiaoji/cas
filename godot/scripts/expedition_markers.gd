extends RefCounted
## All markers are public observation coordinates, never world authority or inferred spawns.
const STATUS := {"offered":"可接取", "accepted":"已接取", "working":"作业中", "complete":"已完成", "abandoned":"已放弃"}

static func tooltip(map: Control, view: Dictionary, at: Vector2) -> String:
	for task in view.get("salvage",{}).get("expedition",{}).get("tasks",[]):
		if not task.has_all(["x","y"]):continue
		if map.project(map.pos(task)).distance_to(at)<22.0:
			return str(task.get("title","临时任务"))+" · "+str(STATUS.get(str(task.get("status","")),""))
	return ""

static func draw(map: Control, view: Dictionary, clock: float) -> void:
	var expedition: Dictionary=view.get("salvage",{}).get("expedition",{})
	if expedition.is_empty():return
	for task in expedition.get("tasks",[]):
		if not task.has_all(["x","y"]):continue
		var point: Vector2=map.project(map.pos(task))
		var status := str(task.get("status","offered"))
		var focused := status in ["accepted","working"]
		var color := Color("f0d491") if focused else Color(.72,.83,.82,.65)
		if status=="complete":color=Color(.51,.88,.72,.55)
		elif status=="abandoned":color=Color(.57,.62,.64,.38)
		var extent := 13.0 if focused else 9.0
		var diamond := PackedVector2Array([point+Vector2(0,-extent),point+Vector2(extent,0),point+Vector2(0,extent),point+Vector2(-extent,0),point+Vector2(0,-extent)])
		map.draw_colored_polygon(diamond,Color(.025,.12,.16,.88 if focused else .55))
		map.draw_polyline(diamond,color,1.8 if focused else 1.1,true)
		if status=="complete":
			map.draw_polyline(PackedVector2Array([point+Vector2(-4,0),point+Vector2(-1,3),point+Vector2(5,-4)]),color,1.7,true)
		elif status=="abandoned":
			map.draw_line(point-Vector2(3,3),point+Vector2(3,3),color,1.3,true)
			map.draw_line(point-Vector2(-3,3),point+Vector2(-3,3),color,1.3,true)
		else:
			map.draw_circle(point,2.5,color)
		if status=="working":
			var fraction := clampf(float(task.get("progress",0))/maxf(1,float(task.get("duration",1))),0,1)
			map.draw_arc(point,extent+5,-PI*.5,-PI*.5+TAU*fraction,32,color,2.2,true)
	var boss: Dictionary=expedition.get("boss",{})
	if str(boss.get("status",""))!="announced" or not boss.has_all(["x","y","radius"]):return
	var point: Vector2=map.project(map.pos(boss))
	var radius: float=point.distance_to(map.project(map.pos(boss)+Vector2(float(boss.radius),0)))
	var color := Color(.96,.50,.42,.68)
	map.draw_circle(point,radius,Color(.72,.20,.25,.035))
	for i in range(16):
		var angle := float(i)*TAU/16.0
		map.draw_arc(point,radius,angle,angle+TAU/24.0,8,color,1.8,true)
	var remaining := maxi(0,int(boss.get("spawn_tick",view.get("tick",0)))-int(view.get("tick",0)))
	if not map.cinematic:
		var label := "异动海域 · %ds" % remaining
		var at := point+Vector2(-51,-radius-12)
		map.draw_string_outline(map.font,at,label,HORIZONTAL_ALIGNMENT_LEFT,-1,14,3,Color("123748"))
		map.draw_string(map.font,at,label,HORIZONTAL_ALIGNMENT_LEFT,-1,14,color)
