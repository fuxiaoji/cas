class_name CasRuinRenderer
extends Node2D
## Public charted landmark, drawn from the core footprint. No collision or loot lives here.
var source: Dictionary = {}
var footprint := PackedVector2Array()
var buildings: Array[Dictionary] = []
var sea: Control
var visual_time := 0.0
var night := 0.0
var overcast := 0.0
var local_sprite: Texture2D
var sprite_region := Rect2()
var foundation_clearance := 0.0
var sprite_ground_width := 0.0
var sprite_ground_depth := 0.0

func configure(landmark: Dictionary) -> void:
	source = landmark.duplicate(true)
	var asset := {"drowned_tower":"res://assets/environment/drowned-tower-v1.png","industrial_ruin":"res://assets/environment/industrial-ruin-v1.png"}.get(str(source.get("kind","")),"") as String
	if not asset.is_empty() and ResourceLoader.exists(asset):
		local_sprite=load(asset)
		sprite_region=Rect2(local_sprite.get_image().get_used_rect())
		# Registered alpha bounds exclude invisible canvas padding, not the building silhouette.
		if str(source.get("kind",""))=="drowned_tower":sprite_region=Rect2(231,0,749,1254)
		elif str(source.get("kind",""))=="industrial_ruin":sprite_region=Rect2(27,1,1495,1023)
	for point in source.get("footprint", []):
		footprint.append(Vector2(float(point.x),float(point.y)))
	if footprint.size()<3:
		return
	var anchor := Vector2(float(source.get("x",0)),float(source.get("y",0)))
	foundation_clearance=INF
	for i in range(footprint.size()):
		foundation_clearance=minf(foundation_clearance,anchor.distance_to(Geometry2D.get_closest_point_to_segment(anchor,footprint[i],footprint[(i+1)%footprint.size()])))
	var rng := RandomNumberGenerator.new()
	rng.seed = int(source.get("seed", 1))
	var bounds := Rect2(footprint[0],Vector2.ZERO)
	for point in footprint:
		bounds = bounds.expand(point)
	var kind := str(source.get("kind", "drowned_tower"))
	# Fit the object's shallow oblique base into the real polygon, instead of wasting a wide quay.
	var depth_ratio := .32 if kind=="drowned_tower" else .55
	var low := 0.0
	var high := bounds.size.x
	for attempt in range(14):
		var width := (low+high)*.5
		var legal := true
		for x in [-.5,0.0,.5]:
			for y in [-.5,0.0,.5]:
				legal = legal and Geometry2D.is_point_in_polygon(anchor+Vector2(float(x)*width,float(y)*width*depth_ratio),footprint)
		if legal:low=width
		else:high=width
	sprite_ground_width=low*.97
	sprite_ground_depth=sprite_ground_width*depth_ratio
	var grid := 3 if kind=="flooded_dock" else (2 if kind=="industrial_ruin" else 1)
	for row in range(grid):
		for column in range(grid):
			var cell := bounds.size/float(grid)
			var center := bounds.position+cell*Vector2(column+.5,row+.5)
			var extent := cell*(.36 if grid==2 else .40)
			if kind=="flooded_dock":extent.x*=.45
			var corners := PackedVector2Array([center+Vector2(-extent.x,-extent.y),center+Vector2(extent.x,-extent.y),center+extent,center+Vector2(-extent.x,extent.y)])
			var legal := true
			for point in corners:
				legal = legal and Geometry2D.is_point_in_polygon(point,footprint)
			if not legal:
				continue
			buildings.append({"corners":corners,"height":float(source.get("height_m",120))*(1.0 if grid==1 else rng.randf_range(.42,.95)),"damage":rng.randf_range(.15,.75),"variant":rng.randi_range(0,9999),"rust":rng.randf_range(.2,.8)})
	# The source footprint is itself valid land; do not invent an off-island fallback.
	if buildings.is_empty():
		var extent:=foundation_clearance*.64
		var inset:=PackedVector2Array([anchor+Vector2(-extent,-extent),anchor+Vector2(extent,-extent),anchor+Vector2(extent,extent),anchor+Vector2(-extent,extent)])
		buildings.append({"corners":inset,"height":float(source.get("height_m",120)),"damage":.4,"variant":int(source.get("seed",1))%9999,"rust":.5})
	buildings.sort_custom(func(a: Dictionary,b: Dictionary): return center_of(a.corners).y>center_of(b.corners).y)

static func center_of(points: PackedVector2Array) -> Vector2:
	var result := Vector2.ZERO
	for point in points:
		result += point
	return result/float(maxi(1,points.size()))

func update_camera(map: Control,time: float,dark: float,cloud: float) -> void:
	sea = map
	visual_time = time
	night = dark
	overcast = cloud
	queue_redraw()

func shade(color: Color) -> Color:
	var result := color.lerp(Color(color.r*.68,color.g*.76,color.b*.83,color.a),overcast*.7)
	return result.lerp(Color(color.r*.22,color.g*.35,color.b*.52,color.a),night)

func projected(points: PackedVector2Array, lift := 0.0) -> PackedVector2Array:
	var result := PackedVector2Array()
	var scale: float = sea.project(Vector2(1,0)).distance_to(sea.project(Vector2.ZERO))
	for point in points:
		result.append(sea.project(point)+Vector2(-lift*scale*.18,-lift*scale*.78))
	return result

func _draw() -> void:
	if sea==null or footprint.size()<3:
		return
	var base := projected(footprint)
	var bound := Rect2(base[0],Vector2.ZERO)
	for point in base:
		bound = bound.expand(point)
	if not bound.grow(200).intersects(Rect2(Vector2.ZERO,sea.size)):
		return
	# The island already owns the visible quay. A second translucent rectangular
	# plate around every landmark used to make each building look like a token.
	# Broken ground details stay within the registered footprint instead.
	_draw_ground_scars(base)
	if local_sprite!=null and sprite_region.has_area():
		var scale: float=sea.project(Vector2(1,0)).distance_to(sea.project(Vector2.ZERO))
		var width := sprite_ground_width*scale
		var extent := Vector2(width,width*sprite_region.size.y/sprite_region.size.x)
		var reference_height := 130.0 if str(source.get("kind",""))=="drowned_tower" else 40.0
		extent.y *= clampf(float(source.get("height_m",reference_height))/reference_height,.85,1.20)*(1.0-clampf(float(source.get("flood",0)),0,1)*.12)
		var sprite_anchor: Vector2=sea.project(Vector2(float(source.x),float(source.y)))+Vector2(0,sprite_ground_depth*scale*.48)
		draw_texture_rect_region(local_sprite,Rect2(sprite_anchor-Vector2(extent.x*.5,extent.y),extent),sprite_region,shade(Color.WHITE))
		return
	for building in buildings:
		_draw_building(building)

func _draw_ground_scars(base:PackedVector2Array) -> void:
	var rng:=RandomNumberGenerator.new();rng.seed=int(source.get("seed",1))+37
	var center:=center_of(base)
	var scale:float=sea.project(Vector2(1,0)).distance_to(sea.project(Vector2.ZERO))
	# Disconnected oxidized reinforcement and slabs suggest a larger drowned
	# structure. They never add an apparent water channel through solid land.
	for i in range(6):
		var edge_index:=rng.randi_range(0,base.size()-1)
		var edge_point:=base[edge_index].lerp(base[(edge_index+1)%base.size()],rng.randf_range(.12,.88))
		var point:=center.lerp(edge_point,rng.randf_range(.70,.94))
		var tangent:Vector2=(base[(edge_index+1)%base.size()]-base[edge_index]).normalized()
		var length:=minf(point.distance_to(center)*.2,30.0*scale)
		draw_line(point-tangent*length,point+tangent*length,shade(Color(.34,.28,.20,.68)),maxf(.6,scale*4),true)
		if scale>.2:
			draw_line(point,point+Vector2(-8,-14)*scale,shade(Color(.46,.37,.23,.8)),maxf(.7,scale*3),true)

func _draw_building(building: Dictionary) -> void:
	var kind := str(source.get("kind","drowned_tower"))
	var flood := clampf(float(source.get("flood",0)),0,1)
	var height := float(building.height)*(1.0-flood*.64)
	var base := projected(building.corners)
	var roof := projected(building.corners,height)
	var scale: float = sea.project(Vector2(1,0)).distance_to(sea.project(Vector2.ZERO))
	var rng := RandomNumberGenerator.new();rng.seed=int(building.variant)
	var lift := height*scale*.78
	var shadow := base.duplicate()
	for i in range(shadow.size()):
		shadow[i] += Vector2(lift*.35,-lift*.22)
	draw_colored_polygon(shadow,Color(.04,.15,.19,.22))
	var wall_color := Color("a1a598") if kind=="drowned_tower" else Color("8f988b")
	if kind=="cult_pylon": wall_color=Color("565f70")
	# Bottom-facing and right-facing walls are exposed in this fixed oblique projection.
	for i in range(base.size()):
		var next := (i+1)%base.size()
		if (base[i].y+base[next].y)*.5<center_of(base).y:
			continue
		var side := PackedVector2Array([base[i],base[next],roof[next],roof[i]])
		draw_colored_polygon(side,shade(wall_color.darkened(.19)))
		if lift>8:
			_windows(base[i],base[next],roof[i],roof[next],rng,building,kind)
	# The other oblique edge remains visible even when the source footprint has reversed winding.
	var right := 0
	for i in range(base.size()):
		if base[i].x>base[right].x: right=i
	var neighbor := (right+1)%base.size()
	if base[neighbor].y>base[right].y: neighbor=(right-1+base.size())%base.size()
	draw_colored_polygon(PackedVector2Array([base[right],base[neighbor],roof[neighbor],roof[right]]),shade(wall_color.darkened(.35)))
	if lift>8:
		_windows(base[right],base[neighbor],roof[right],roof[neighbor],rng,building,kind)
	# Broken roof: a recessed dark fracture with ragged reinforcing beams.
	draw_colored_polygon(roof,shade(wall_color.lightened(.14)))
	# Chipped parapet, missing corner and exposed slab edges break the pristine box silhouette.
	var broken := roof.duplicate()
	broken.append(roof[0])
	draw_polyline(broken,shade(Color("c0bd9f")),maxf(.8,scale*4.0),true)
	for i in range(roof.size()):
		var edge_point := roof[i].lerp(roof[(i+1)%roof.size()],rng.randf_range(.2,.8))
		var inset := center_of(roof).lerp(edge_point,.68)
		var tangent := (roof[(i+1)%roof.size()]-roof[i]).normalized()*scale*12
		var chip := PackedVector2Array([edge_point-tangent,edge_point+tangent,inset])
		if absf(tangent.cross(inset-edge_point))>.001:
			draw_colored_polygon(chip,shade(Color("59625b")))
	var center := center_of(roof)
	var crater := PackedVector2Array()
	for i in range(9):
		var angle := float(i)/9.0*TAU
		var extent := maxf(2.0,base[0].distance_to(base[1])*.19)
		crater.append(center+Vector2(cos(angle),sin(angle)*.56)*extent*rng.randf_range(.65,1.25))
	draw_colored_polygon(crater,shade(Color("343f42")))
	for i in range(0,crater.size(),2):
		draw_line(crater[i],center+(crater[i]-center)*1.34,shade(Color("a39778")),maxf(.7,scale*7),true)
	if kind=="industrial_ruin":
		_draw_tank(center+Vector2(lift*.13,0),maxf(2.0,base[0].distance_to(base[1])*.23),lift*.65)
	elif kind=="radio_mast":
		_draw_mast(center,lift*.9+10*scale)
	elif kind=="cult_pylon":
		var apex := center+Vector2(0,-lift*.5)
		var points := PackedVector2Array([center+Vector2(-lift*.12,0),apex,center+Vector2(lift*.12,0),center+Vector2(0,lift*.08)])
		draw_colored_polygon(points,shade(Color("4f5668")))
		draw_line(apex,center,shade(Color("af7c96")),maxf(1.0,scale*6),true)
	elif kind=="flooded_dock":
		for i in range(4):
			var q := roof[0].lerp(roof[1],float(i+1)/5.0)
			draw_line(q,q+Vector2(0,-lift*.55),shade(Color("777b72")),maxf(1.0,scale*13),true)
	# The waterline uses the reported flood amount; it never creates navigable geometry.
	if flood>.05:
		for i in range(base.size()):
			var next := (i+1)%base.size()
			if (base[i].y+base[next].y)*.5<center_of(base).y:continue
			draw_line(base[i]+Vector2(0,-2),base[next]+Vector2(0,-2),shade(Color(.57,.84,.74,.65)),1.5,true)
		for i in range(base.size()):
			var next: int=(i+1)%base.size()
			if (base[i].y+base[next].y)*.5<center_of(base).y:continue
			var top_a:=base[i].lerp(roof[i],flood*.16)
			var top_b:=base[next].lerp(roof[next],flood*.16)
			# At overview scale the algae band can be subpixel; the waterline above already represents it.
			if base[i].distance_to(top_a)>.6:
				draw_colored_polygon(PackedVector2Array([base[i],base[next],top_b,top_a]),shade(Color(.13,.41,.36,.56)))

func _windows(a: Vector2,b: Vector2,top_a: Vector2,top_b: Vector2,rng: RandomNumberGenerator,building: Dictionary,kind: String) -> void:
	var length := a.distance_to(b)
	var height := a.distance_to(top_a)
	var columns := clampi(int(length/7),2,12)
	var floors := clampi(int(height/8),1,14)
	# Stained concrete floor plates remain legible without drawing a text label.
	for floor_index in range(1,floors):
		var amount := float(floor_index)/float(floors)
		draw_line(a.lerp(top_a,amount),b.lerp(top_b,amount),shade(Color(.43,.48,.43,.48)),.75,true)
	for floor_index in range(floors):
		for column in range(columns):
			if rng.randf()<float(building.damage)*.3: continue
			var u := (float(column)+.5)/float(columns)
			var v := (float(floor_index)+.5)/float(floors)
			var p := a.lerp(b,u).lerp(top_a.lerp(top_b,u),v)
			var width := maxf(.8,length/float(columns)*.46)
			var color := Color("384e53") if rng.randf()>.23 else Color("607e7e")
			if kind=="cult_pylon":color=Color("69596b")
			draw_line(p,p+(b-a).normalized()*width,shade(color),maxf(1.0,height/float(floors)*.36),true)
			if rng.randf()<float(building.rust)*.24:
				draw_line(p,p+Vector2(0,height*.13),shade(Color(.43,.30,.19,.65)),maxf(.7,width*.18),true)

func _draw_tank(center: Vector2,radius: float,height: float) -> void:
	var lower := center+Vector2(0,radius*.30)
	var upper := lower+Vector2(0,-height)
	draw_rect(Rect2(upper-Vector2(radius,0),Vector2(radius*2,height)),shade(Color("797b6e")))
	var oval := PackedVector2Array()
	for i in range(20):oval.append(upper+Vector2(cos(i*TAU/20.0)*radius,sin(i*TAU/20.0)*radius*.42))
	draw_colored_polygon(oval,shade(Color("babaa0")))
	draw_line(lower+Vector2(radius*.45,0),upper+Vector2(radius*.45,0),shade(Color("635f4e")),maxf(1.0,radius*.17),true)

func _draw_mast(center: Vector2,height: float) -> void:
	var apex := center+Vector2(0,-height)
	for side in [-1.0,1.0]:draw_line(center+Vector2(height*.18*side,0),apex,shade(Color("b5c0b3")),1.2,true)
	for i in range(1,5):
		var t := float(i)/5.0
		var left := center+Vector2(-height*.18*(1-t),-height*t)
		var right := center+Vector2(height*.18*(1-t),-height*t)
		draw_line(left,right,shade(Color("89988c")),1.0,true)
		draw_line(left,apex.lerp(center,t),shade(Color("89988c")),.7,true)
	draw_arc(apex+Vector2(height*.12,height*.35),height*.13,-PI*.7,PI*.7,14,shade(Color("b0bcae")),2.0,true)
