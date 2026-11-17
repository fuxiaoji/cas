extends Node2D
## Small procedural set pieces on charted solid footprints. The ocean and map remain procedural.
var sea: Control
var clock := 0.0
const SCENES := ["sunken_metropolis","cult_relay","storm_wrecks","thermal_vent","refugee_causeway"]

func update_camera(map: Control,time: float) -> void:
	sea=map;clock=time;queue_redraw()

func _draw() -> void:
	if sea==null:return
	var expedition: Dictionary=sea.view.get("salvage",{}).get("expedition",{})
	var scene := str(expedition.get("scene",""))
	if not scene in SCENES:return
	for landmark in sea.view.get("salvage",{}).get("landmarks",[]):
		if not bool(landmark.get("charted",false)) or str(landmark.get("collision",""))!="island":continue
		var world: Vector2=sea.pos(landmark)
		var point: Vector2=sea.project(world)
		if not Rect2(Vector2(-100,-100),sea.size+Vector2(200,200)).has_point(point):continue
		var footprint := PackedVector2Array()
		for vertex in landmark.get("footprint",[]):footprint.append(sea.pos(vertex))
		if footprint.size()<3:continue
		var clearance := INF
		for i in range(footprint.size()):
			clearance=minf(clearance,world.distance_to(Geometry2D.get_closest_point_to_segment(world,footprint[i],footprint[(i+1)%footprint.size()])))
		var radius: float=sea.project(world+Vector2(clearance*.76,0)).distance_to(point)
		if radius<3:continue
		var rng:=RandomNumberGenerator.new();rng.seed=int(landmark.get("seed",0))+27419
		if scene=="cult_relay":
			for ring in range(2):
				draw_arc(point,radius*(.54+ring*.24),0,TAU,32,Color(.71,.53,.81,.26+sin(clock*1.5)*.08),1.3,true)
			for i in range(6):
				var direction:=Vector2.from_angle(i*TAU/6.0)
				draw_line(point+direction*radius*.35,point+direction*radius*.85,Color(.79,.61,.89,.55),1.4,true)
				draw_circle(point+direction*radius*.80,maxf(1.5,radius*.04),Color("e5b1e2"))
		elif scene=="thermal_vent":
			for i in range(5):
				var local:=point+Vector2.from_angle(rng.randf()*TAU)*radius*rng.randf_range(.18,.60)
				draw_circle(local,radius*.15,Color(.18,.18,.20,.92))
				draw_arc(local,radius*.13,0,TAU,16,Color(.95,.50,.23,.65),maxf(1.4,radius*.06),true)
				var rise:=fposmod(clock*.13+i*.21,1.0)
				draw_circle(local+Vector2(7,-26)*rise, radius*(.08+rise*.17),Color(.80,.86,.83,(1-rise)*.18))
		elif scene=="refugee_causeway":
			for i in range(5):
				var at:=point+Vector2((i-2)*radius*.30,sin(i*2.0)*radius*.13)
				var box:=Rect2(at-Vector2(radius*.13,radius*.12),Vector2(radius*.26,radius*.24))
				draw_rect(box,Color("9a947b") if i%2==0 else Color("687c7b"))
				draw_line(box.position,box.end,Color(.88,.79,.57,.8),1.2,true)
				draw_line(at,at+Vector2(0,-radius*.24),Color("464f50"),1,true)
				draw_colored_polygon(PackedVector2Array([at+Vector2(0,-radius*.24),at+Vector2(radius*.13,-radius*.20),at+Vector2(0,-radius*.14)]),Color("d5ae70"))
		elif scene=="storm_wrecks":
			for i in range(6):
				var at:=point+Vector2.from_angle(rng.randf()*TAU)*radius*rng.randf_range(.1,.70)
				var heading:=rng.randf()*TAU
				var long:=Vector2.from_angle(heading)*radius*.24
				var across:=long.orthogonal()*.27
				draw_colored_polygon(PackedVector2Array([at-long-across,at+long*.8-across,at+long+across,at-long*.6+across]),Color("6f6b5c"))
				draw_line(at-long*.8,at+long*.7,Color("b29370"),1.2,true)
		else:
			# Roof plans and submerged road fragments only; no fake navigable avenues.
			for i in range(4):
				var at:=point+Vector2((i%2-.5)*radius*.7,(i/2-.5)*radius*.65)
				var roof:=Rect2(at-Vector2.ONE*radius*.13,Vector2.ONE*radius*.26)
				draw_rect(roof,Color(.47,.60,.59,.80))
				draw_rect(roof.grow(-radius*.04),Color(.26,.39,.42,.90),false,1.2)
