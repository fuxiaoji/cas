extends "res://scripts/coastal_architecture.gd"
## Original reusable 3D salvage-coast architecture. Geometry and art metadata only.
## X/Z are ground metres, Y is elevation. No account, combat or construction state.

var catalog: Array[Dictionary] = []

func build(height_at: Callable) -> void:
	_height_at = height_at
	_palette()
	for child: Node in get_children(): child.free()
	buildings.clear()
	catalog.clear()
	_ruined_tower(Vector2(-96,-91))
	_relic_machine_room(Vector2(-121,-82))
	_salvage_market(Vector2(107,39))
	_ship_workshop(Vector2(148,39))
	_tank_farm(Vector2(107,77))
	_repair_dock(Vector2(148,77))
	_armored_coastal_gun(Vector2(28,207))
	_machine_gun_bunker(Vector2(-30,207))
	_mortar_position(Vector2(-64,207))
	_defense_perimeter()

func _palette() -> void:
	super._palette()
	var colors: Dictionary = {
		"w_concrete":"a5a99b", "w_spall":"c2baa3", "w_salt":"dcd8bd",
		"w_rust":"a75c3c", "w_rust_dark":"714c3a", "w_steel":"536b69",
		"w_teal":"77a39a", "w_blue":"779ca8", "w_olive":"7b8660",
		"w_sand":"c4b488", "w_black":"334846", "w_canvas":"d3bc82",
		"w_canvas_red":"c97e59", "w_cloth_blue":"76a2ad", "w_vine":"6c914b",
		"w_warning":"ddbd62", "w_glass":"3d707a", "w_pale":"d1d9c5"
	}
	for key: String in colors:
		if _materials.has(key): continue
		var material:=StandardMaterial3D.new()
		material.resource_name="SalvageCoast_"+key
		material.albedo_color=Color(str(colors[key]))
		material.roughness=.91
		_materials[key]=material

func _plot(id: String, label: String, point: Vector2, size: Vector2, yaw: float=0) -> Node3D:
	var root: Node3D=_root(self,label,point,size,yaw)
	root.set_meta("facility_id",id)
	root.set_meta("display_name",label)
	root.set_meta("visual_family","salvage_coast")
	catalog.append({"id":id,"name":label,"ground_xz":point,"footprint_m":size,"yaw_rad":yaw,"art_only":true})
	return root

func _base(b: Dictionary, width: float, depth: float) -> void:
	_box(b,"w_rust_dark",Vector3(0,-.24,0),Vector3(width,.48,depth))
	_box(b,"w_concrete",Vector3(0,.025,0),Vector3(width-.15,.12,depth-.15))
	# Broken expansion joints and seam repairs give the ground a human scale.
	for x: float in [-width*.33,0,width*.33]: _box(b,"w_black",Vector3(x,.093,0),Vector3(.035,.01,depth-.3))
	for z: float in [-depth*.25,depth*.25]: _box(b,"w_black",Vector3(0,.093,z),Vector3(width-.3,.01,.035))

func _pipe(b: Dictionary, color: String, from: Vector3, to: Vector3, radius: float=.17) -> void:
	var direction: Vector3=to-from
	if direction.length()<.02: return
	var y: Vector3=direction.normalized()
	var x: Vector3=y.cross(Vector3.FORWARD).normalized() if absf(y.dot(Vector3.FORWARD))<.98 else y.cross(Vector3.UP).normalized()
	var z: Vector3=x.cross(y).normalized()
	_cylinder(b,color,(from+to)*.5,radius,direction.length(),10,Basis(x,y,z))

func _ladder(b: Dictionary, base: Vector3, height: float, width: float=.85) -> void:
	for side: float in [-1.0,1.0]: _pipe(b,"w_steel",base+Vector3(side*width*.5,0,0),base+Vector3(side*width*.5,height,0),.055)
	for step: int in range(ceili(height/.36)):
		_pipe(b,"w_rust",base+Vector3(-width*.5,.22+step*.36,0),base+Vector3(width*.5,.22+step*.36,0),.048)

func _railing(b: Dictionary, start: Vector3, end: Vector3, height: float=1.05) -> void:
	var count: int=maxi(1,ceili(start.distance_to(end)/1.3))
	for i: int in range(count+1):
		var p: Vector3=start.lerp(end,float(i)/count)
		_pipe(b,"w_steel",p,p+Vector3.UP*height,.045)
	for y: float in [.35,height]: _pipe(b,"w_steel",start+Vector3.UP*y,end+Vector3.UP*y,.045)

func _patch_panel(b: Dictionary, at: Vector3, size: Vector2, yaw: float=0, color: String="w_teal") -> void:
	var basis:=Basis(Vector3.UP,yaw)
	_box(b,color,at,Vector3(size.x,size.y,.12),basis)
	for i: int in range(maxi(2,ceili(size.x/.38))):
		var p: Vector3=Vector3(-size.x*.5+.14+i*.38,0,-.085)
		_box(b,"w_rust_dark",at+basis*p,Vector3(.045,size.y-.06,.04),basis)
	for side: float in [-1.0,1.0]:
		for y: float in [-.35,.35]:
			_box(b,"w_salt",at+basis*Vector3(side*(size.x*.5-.16),y*size.y,-.11),Vector3(.09,.09,.035),basis)

func _tarp(b: Dictionary, at: Vector3, width: float, depth: float, color: String) -> void:
	for i: int in range(8):
		var x0: float=-width*.5+width*i/8.0
		var x1: float=-width*.5+width*(i+1)/8.0
		var y0: float=-.46*sin(PI*float(i)/8.0)
		var y1: float=-.46*sin(PI*float(i+1)/8.0)
		_quad(b,color,at+Vector3(x0,y0,-depth*.5),at+Vector3(x0,y0,depth*.5),at+Vector3(x1,y1,depth*.5),at+Vector3(x1,y1,-depth*.5))
		_quad(b,color,at+Vector3(x1,y1-.035,-depth*.5),at+Vector3(x1,y1-.035,depth*.5),at+Vector3(x0,y0-.035,depth*.5),at+Vector3(x0,y0-.035,-depth*.5))
	# Sewn edge and a separate repair patch, never an entire-scene image.
	_box(b,"w_canvas",at+Vector3(width*.22,-.25,.3),Vector3(width*.18,.055,depth*.31),Basis(Vector3.FORWARD,.10))
	for side: float in [-1.0,1.0]: _beam(b,"w_canvas",at+Vector3(-width*.5,.01,side*depth*.5),at+Vector3(width*.5,.01,side*depth*.5),.08,.08)

func _scatter_rubble(b: Dictionary, at: Vector3, amount: int, seed_value: int) -> void:
	var rng:=RandomNumberGenerator.new()
	rng.seed=seed_value
	for i: int in range(amount):
		var p: Vector3=at+Vector3(rng.randf_range(-5.6,5.6),rng.randf_range(.1,.35),rng.randf_range(-3.5,3.5))
		_box(b,"w_spall" if i%3 else "w_rust",p,Vector3(rng.randf_range(.4,1.5),rng.randf_range(.22,.8),rng.randf_range(.4,1.2)),Basis(Vector3.UP,rng.randf()*TAU)*Basis(Vector3.RIGHT,rng.randf_range(-.3,.3)))

func _ivy(b: Dictionary, at: Vector3, count: int=6) -> void:
	for i: int in range(count):
		var p: Vector3=at+Vector3(sin(i*1.83)*.25,-i*.35,cos(i*1.73)*.07)
		_box(b,"w_vine",p,Vector3(.42,.20,.31),Basis(Vector3.FORWARD,float(i)*.75))

func _slab(b: Dictionary, outline: PackedVector2Array, top: float, thickness: float) -> void:
	var indices: PackedInt32Array=Geometry2D.triangulate_polygon(outline)
	for index: int in range(0,indices.size(),3):
		var p: Vector2=outline[indices[index]]
		var q: Vector2=outline[indices[index+1]]
		var r: Vector2=outline[indices[index+2]]
		_tri(b,"w_concrete",Vector3(p.x,top,p.y),Vector3(r.x,top,r.y),Vector3(q.x,top,q.y))
		_tri(b,"w_rust_dark",Vector3(p.x,top-thickness,p.y),Vector3(q.x,top-thickness,q.y),Vector3(r.x,top-thickness,r.y))
	for i: int in range(outline.size()):
		var p: Vector2=outline[i]
		var q: Vector2=outline[(i+1)%outline.size()]
		_quad(b,"w_spall",Vector3(p.x,top-thickness,p.y),Vector3(q.x,top-thickness,q.y),Vector3(q.x,top,q.y),Vector3(p.x,top,p.y))

func _ruined_tower(point: Vector2) -> void:
	var root: Node3D=_plot("submerged_tower","潮痕断楼",point,Vector2(24,24),-.15)
	# Ruins straddle the sea level rather than inheriting a cliff-top corner pad.
	# Submerged piles connect the old foundation to the bed below the first slab.
	root.position.y=clampf(float(_height_at.call(point.x,point.y)),-3.1,-1.6)
	root.set_meta("waterline_local_m",-root.position.y)
	var b: Dictionary={}
	for x: float in [-7.6,7.6]:
		for z: float in [-4.0,7.5]: _box(b,"w_rust_dark",Vector3(x,-2.5,z),Vector3(1.1,5.0,1.1))
	# Open slabs, missing façade and exposed rebar. The water covers the bottom.
	for level: int in range(6):
		var y: float=level*3.3
		var bite: float=1.7+float(level%3)*1.15
		var outline:=PackedVector2Array([Vector2(-8,-6),Vector2(-3,-6),Vector2(-2,-6+bite),Vector2(2,-4+bite),Vector2(7,-3+bite),Vector2(8,1),Vector2(8,8),Vector2(-8,8)])
		if level<4:
			_slab(b,outline,y,.42)
		else:
			# A missing upper-floor centre exposes the lower structure from the
			# normal south-east camera; six complete slabs read as one blank plane.
			_slab(b,PackedVector2Array([Vector2(-8,-6),Vector2(-4.4,-6),Vector2(-3.5,-2.2),Vector2(-4,2.8),Vector2(-4,5.1),Vector2(-8,5.1)]),y,.42)
			_slab(b,PackedVector2Array([Vector2(-8,5.1),Vector2(-2,5.1),Vector2(-.7,6.1),Vector2(3.6,5.0),Vector2(8,6.1),Vector2(8,8),Vector2(-8,8)]),y,.42)
			if level==4:
				_slab(b,PackedVector2Array([Vector2(5.5,2.6),Vector2(8,2.1),Vector2(8,6.1),Vector2(4.8,5.0)]),y,.42)
			for z: float in [-4.8,-2.4,.2,2.5]: _pipe(b,"w_rust",Vector3(-3.8,y,z),Vector3(-2.9,y+.25,z+.2),.045)
			for x: float in [-1.2,1.0,3.0,5.4]: _pipe(b,"w_rust",Vector3(x,y,5.7),Vector3(x+.18,y+.3,4.8),.045)
		for x: float in [-7.6,-2.6,2.6,7.6]:
			if level==5 and x>2: continue
			_box(b,"w_concrete",Vector3(x,y+1.45,7.5),Vector3(.62,3.3,.65))
			_box(b,"w_spall",Vector3(x,y+2.4,7.13),Vector3(.73,.38,.16))
			if level<4: _box(b,"w_teal",Vector3(x,y+1.45,-5.5 if x<0 else 3.3),Vector3(.55,3.3,.55))
		for x: float in [-5.1,0,5.1]:
			_box(b,"w_teal",Vector3(x,y+.6,7.6),Vector3(4.3,1.0,.28))
			if (level+int(x))%3==0: _patch_panel(b,Vector3(x,y+1.9,7.38),Vector2(2.1,1.3),0,"w_blue")
		if level<5:
			_box(b,"w_rust_dark",Vector3(-7.6,y+1.3,2.8),Vector3(.5,2.5,7.5))
			for z: float in [-1.2,2.8,6.5]: _window(b,Vector3(-7.91,y+1.8,z),1.9,1.5,PI*.5,false,false)
		if level<4:
			# Surviving window skeletons on the camera-facing east wall have
			# actual openings, missing sashes and short, broken wall sections.
			for z: float in [3.2,6.2]:
				for side: float in [-1.0,1.0]: _box(b,"w_spall",Vector3(8.12,y+1.8,z+side*1.0),Vector3(.18,1.85,.14))
				_box(b,"w_spall",Vector3(8.12,y+2.7,z),Vector3(.18,.14,2.12))
				_box(b,"w_teal",Vector3(8.12,y+.91,z),Vector3(.25,.24,2.15))
				if (level+int(z))%2==0: _box(b,"w_steel",Vector3(8.15,y+1.75,z),Vector3(.07,1.65,.055),Basis(Vector3.RIGHT,.19))
			if level%2==0: _box(b,"w_rust",Vector3(8.19,y+.4,4.5),Vector3(.15,.7,2.8))
			# Near-side windows follow the jagged slab edge. At the tactical
			# camera angle these frames separate floors that overlap in projection.
			for bay: Vector3 in [Vector3(-5.35,0,-6.12),Vector3(1.0,0,-4.65+bite),Vector3(5.0,0,-3.55+bite)]:
				for side: float in [-1.0,1.0]: _box(b,"w_spall",bay+Vector3(side*1.22,y+1.6,0),Vector3(.19,2.35,.20))
				_box(b,"w_spall",bay+Vector3(0,y+2.75,0),Vector3(2.65,.18,.23))
				_box(b,"w_teal",bay+Vector3(0,y+.48,0),Vector3(2.7,.75,.25))
				if level%2==0: _box(b,"w_steel",bay+Vector3(.25,y+1.7,-.05),Vector3(.07,1.8,.07),Basis(Vector3.FORWARD,.19))
		for i: int in range(5):
			var x: float=-2.0+i*1.6
			_pipe(b,"w_rust",Vector3(x,y,-3.9+bite),Vector3(x+.3*sin(i),y+1.2,-3.4+bite),.045)
	_box(b,"w_rust",Vector3(-8.0,8.0,3),Vector3(.16,13.0,1.0))
	_ladder(b,Vector3(-8.15,1.0,1.7),12.0)
	_pipe(b,"w_rust",Vector3(8.1,13.6,4.3),Vector3(8.7,10.4,3.8),.16)
	_pipe(b,"w_rust",Vector3(8.7,10.4,3.8),Vector3(9.0,7.1,1.1),.16)
	_pipe(b,"w_black",Vector3(8.0,12.9,6.5),Vector3(8.8,9.2,5.7),.075)
	_patch_panel(b,Vector3(8.26,7.0,6.0),Vector2(2.4,1.3),-PI*.5,"w_rust")
	for p: Vector3 in [Vector3(5.2,3.1,-.2),Vector3(8.8,3.1,-.2)]: _pipe(b,"w_rust_dark",p,p+Vector3.UP*2.8,.07)
	_tarp(b,Vector3(7.0,5.9,.8),4.1,3.4,"w_blue")
	_scatter_rubble(b,Vector3(2,.3,-4),24,194)
	for at: Vector3 in [Vector3(-7.85,14,-1),Vector3(7.9,10,6),Vector3(-3,16.5,-3),Vector3(-8,6,4)]: _ivy(b,at,10)
	_finish(root,b)

func _relic_machine_room(point: Vector2) -> void:
	var root: Node3D=_plot("relic_machine_room","半淹遗迹机房",point,Vector2(19,19),.16)
	root.position.y=clampf(float(_height_at.call(point.x,point.y)),-2.0,-1.0)
	root.set_meta("waterline_local_m",-root.position.y)
	var b: Dictionary={}
	_base(b,19,19)
	_box(b,"w_concrete",Vector3(-7,3,1),Vector3(1.2,6,13))
	_box(b,"w_concrete",Vector3(-4.7,3,7),Vector3(5.6,6,1.0))
	_box(b,"w_concrete",Vector3(4.9,1.8,7),Vector3(4.2,3.6,1.0))
	_box(b,"w_spall",Vector3(.6,5.5,7),Vector3(5.1,.65,1.05))
	for z: float in [-2,2.5,6.5]: _box(b,"w_concrete",Vector3(7,2.0,z),Vector3(.75,4.0,.75))
	_box(b,"w_spall",Vector3(7,4.15,4.5),Vector3(.85,.4,4.8))
	_box(b,"w_teal",Vector3(7,1.15,4.5),Vector3(.45,.55,3.9))
	# A large central roof break makes the machinery visible from the overview.
	_slab(b,PackedVector2Array([Vector2(-7.5,-5.5),Vector2(-3.6,-5.5),Vector2(-2.3,-2.6),Vector2(-3.6,.9),Vector2(-2.5,3.7),Vector2(-7.5,5.6)]),6.15,.45)
	_slab(b,PackedVector2Array([Vector2(-7.5,5.6),Vector2(-2.5,3.7),Vector2(-.8,4.9),Vector2(1.6,4.0),Vector2(7,5.9),Vector2(7,7.5),Vector2(-7.5,7.5)]),6.15,.45)
	_box(b,"w_spall",Vector3(3.3,1.7,2),Vector3(4.2,.4,3.1),Basis(Vector3.RIGHT,-.39)*Basis(Vector3.UP,.12))
	for z: float in [-4.4,-2.3,.2,2.4]: _pipe(b,"w_rust",Vector3(-3.2,6.0,z),Vector3(-1.8,6.3,z+.3),.045)
	for x: float in [-.7,1.2,3.7,5.5]: _pipe(b,"w_rust",Vector3(x,6.0,5.3),Vector3(x+.2,6.2,4.3),.045)
	for i: int in range(4):
		var x: float=-4.8+i*3.1
		# Server machinery sits in the exposed cutaway, not underneath the roof.
		_box(b,"w_steel",Vector3(x,1.7,-1.5),Vector3(1.9,3.0,1.3))
		_box(b,"w_black",Vector3(x,1.8,-2.21),Vector3(1.6,2.4,.06))
		for row: int in range(6):
			_box(b,"w_teal",Vector3(x,1.0+row*.34,-2.27),Vector3(1.35,.18,.07))
			_box(b,"w_warning",Vector3(x+.5,1.0+row*.34,-2.32),Vector3(.10,.10,.04))
	_pipe(b,"w_rust",Vector3(-5,1,-6),Vector3(-5,1,4),.28)
	_pipe(b,"w_rust",Vector3(-5,1,-6),Vector3(2,1,-6),.28)
	_box(b,"w_teal",Vector3(4,1.6,-3),Vector3(3,3,2.2))
	for i: int in range(3): _box(b,"w_steel",Vector3(4,1+i*.6,-4.15),Vector3(2.5,.10,.07))
	_box(b,"w_steel",Vector3(-.5,2.3,-.6),Vector3(9.5,.2,3.7))
	for x: float in [-3.1,0,3.1]:
		_box(b,"w_teal",Vector3(x,3.2,-.3),Vector3(1.65,1.6,1.25))
		_box(b,"w_black",Vector3(x,3.3,-.95),Vector3(1.4,.75,.06))
		for row: int in range(3): _box(b,"w_steel",Vector3(x,2.7+row*.17,-.99),Vector3(1.2,.075,.07))
		_box(b,"w_warning",Vector3(x+.5,3.55,-1.0),Vector3(.15,.12,.07))
	_pipe(b,"w_rust",Vector3(6.9,5.8,4.9),Vector3(7.8,3.6,3.8),.18)
	_pipe(b,"w_rust",Vector3(7.8,3.6,3.8),Vector3(8.5,1.0,2.1),.18)
	_patch_panel(b,Vector3(7.45,2.8,5.2),Vector2(1.8,1.3),-PI*.5,"w_rust")
	_scatter_rubble(b,Vector3(-1,.25,-2),18,227)
	for at: Vector3 in [Vector3(-7.6,6,5),Vector3(5,4,7.5)]: _ivy(b,at,8)
	_finish(root,b)

func _salvage_market(point: Vector2) -> void:
	var root: Node3D=_plot("salvage_market","拼装海货集市",point,Vector2(30,27),-.06)
	var b: Dictionary={}
	_base(b,30,27)
	for row: int in range(2):
		for col: int in range(3):
			var at:=Vector3(-9.8+col*9.6,0,-6.5+row*13.0)
			var color: String=["w_canvas_red","w_cloth_blue","w_canvas"][(row+col)%3]
			for side: float in [-1.0,1.0]:
				for end: float in [-1.0,1.0]: _pipe(b,"w_rust",at+Vector3(side*3.6,.1,end*2.6),at+Vector3(side*3.6,4.1,end*2.6),.08)
			_tarp(b,at+Vector3(0,4.2,0),8.4,6.5,color)
			_patch_panel(b,at+Vector3(0,1.3,2.55),Vector2(7.0,2.4),0,"w_teal" if col%2 else "w_rust")
			_box(b,"wood",at+Vector3(0,1,-1.2),Vector3(6.8,1.8,1.5))
			_box(b,"wood_light",at+Vector3(0,1.98,-1.2),Vector3(7.0,.15,1.7))
			for i: int in range(3):
				_crate(b,at+Vector3(-2+i*1.8,2.1,-1.2),.85)
				_cylinder(b,"w_steel",at+Vector3(-2.5+i*2.2,.45,1.3),.38,.8,10)
			_box(b,"w_canvas",at+Vector3(2.5,3,-2.9),Vector3(1.2,.8,.06),Basis(Vector3.FORWARD,-.08))
	for i: int in range(4): _crate(b,Vector3(12,.12,-9+i*2.0),1.2)
	_finish(root,b)

func _hull(b: Dictionary, at: Vector3, length: float, width: float, height: float) -> void:
	var outline:=PackedVector2Array([Vector2(-width*.35,-length*.5),Vector2(width*.35,-length*.5),Vector2(width*.5,-length*.25),Vector2(width*.5,length*.28),Vector2(0,length*.54),Vector2(-width*.5,length*.28),Vector2(-width*.5,-length*.25)])
	for i: int in range(outline.size()):
		var a: Vector2=outline[i]
		var c: Vector2=outline[(i+1)%outline.size()]
		_quad(b,"w_teal",at+Vector3(a.x*.66,0,a.y*.86),at+Vector3(c.x*.66,0,c.y*.86),at+Vector3(c.x,height,c.y),at+Vector3(a.x,height,a.y))
		_beam(b,"w_rust",at+Vector3(a.x,height,a.y),at+Vector3(c.x,height,c.y),.15,.15)
		_pipe(b,"w_salt",at+Vector3(a.x*.84,height*.55,a.y*.95),at+Vector3(c.x*.84,height*.55,c.y*.95),.045)

func _ship_workshop(point: Vector2) -> void:
	var root: Node3D=_plot("hull_workshop","旧船壳工棚",point,Vector2(30,26),.07)
	var b: Dictionary={}
	_base(b,30,26)
	_hull(b,Vector3(-2,.4,0),22,11,3.6)
	_box(b,"wood",Vector3(-2,3.7,0),Vector3(8,.25,15))
	for side: float in [-1.0,1.0]:
		for z: float in [-7,0,7]: _pipe(b,"w_rust_dark",Vector3(-2+side*4.7,3.3,z),Vector3(-2+side*4.7,7.3,z),.11)
	_tarp(b,Vector3(-2,7.4,0),12,18,"w_cloth_blue")
	_patch_panel(b,Vector3(-2,5.2,7.4),Vector2(8.9,3.0),0,"w_rust")
	_patch_panel(b,Vector3(-6.65,5.1,2),Vector2(8.0,2.9),PI*.5,"w_teal")
	for step: int in range(7): _box(b,"w_spall",Vector3(-2,.27+step*.47,-10.6+step*.48),Vector3(3.1,.47,.65))
	_railing(b,Vector3(-3.8,1,-10.6),Vector3(-3.8,3.8,-7.2))
	_box(b,"w_teal",Vector3(10.3,2.2,2),Vector3(6,4.2,11))
	for z: float in [-2.8,-2,-1.2,-.4,.4,1.2,2,2.8,3.6,4.4,5.2,6.0]: _box(b,"w_rust",Vector3(13.35,2.2,z),Vector3(.08,3.9,.08))
	_box(b,"w_black",Vector3(10.3,2,-3.56),Vector3(4.5,3.0,.07))
	for z: float in [-6,1,7]: _crate(b,Vector3(-11,.1,z),1.7)
	for i: int in range(3): _pipe(b,"w_rust",Vector3(8,.7,-8.5+i*.6),Vector3(12,.7,-8.5+i*.6),.24)
	_finish(root,b)

func _tank_farm(point: Vector2) -> void:
	var root: Node3D=_plot("oil_tank_farm","锈潮储油场",point,Vector2(29,29),-.08)
	var b: Dictionary={}
	_base(b,29,29)
	for x: float in [-6.8,6.1]:
		_cylinder(b,"w_concrete",Vector3(x,.4,3),5.0,.6,20)
		_cylinder(b,"w_teal",Vector3(x,4.6,3),4.45,8.0,24)
		_cylinder(b,"w_salt",Vector3(x,8.7,3),4.5,.25,24)
		for y: float in [1.0,3.2,5.5,8.2]: _cylinder(b,"w_rust",Vector3(x,y,3),4.49,.14,24)
		for i: int in range(6):
			var a: float=TAU*i/6+.3
			var p:=Vector3(x+4.48*cos(a),5.7,3+4.48*sin(a))
			_box(b,"w_rust",p,Vector3(.65,1.7,.075),Basis(Vector3.UP,-a+PI*.5))
		_ladder(b,Vector3(x,1.0,-1.65),8.0)
		_cylinder(b,"w_steel",Vector3(x,9,3),.45,.7,10)
		_pipe(b,"w_rust",Vector3(x,1,-1.6),Vector3(x,1,-7.5),.26)
		_pipe(b,"w_rust",Vector3(x,1,-7.5),Vector3(0,1,-7.5),.26)
	_box(b,"w_olive",Vector3(0,1.3,-8),Vector3(4,2.3,3.4))
	for x: float in [-11.3,11.3]: _box(b,"w_concrete",Vector3(x,.8,0),Vector3(.65,1.45,25))
	_box(b,"w_concrete",Vector3(0,.8,12),Vector3(22,1.45,.65))
	for i: int in range(3):
		_cylinder(b,"w_rust",Vector3(-10+i*2.0,.8,-10.2),.65,1.5,12)
		_cylinder(b,"w_salt",Vector3(-10+i*2.0,1.1,-10.2),.67,.13,12)
	_finish(root,b)

func _repair_dock(point: Vector2) -> void:
	var root: Node3D=_plot("repair_cradle","船坞维修架",point,Vector2(30,32),.04)
	var b: Dictionary={}
	_base(b,30,32)
	for x: float in [-5,5]:
		_box(b,"w_black",Vector3(x,.25,0),Vector3(.32,.35,27))
		for z: float in [-10,-6,-2,2,6,10]:
			_box(b,"w_spall",Vector3(x,1.1,z),Vector3(2.5,1.8,1.4))
			_box(b,"wood",Vector3(x,2.1,z),Vector3(2.7,.3,1.5))
	_hull(b,Vector3(0,2.4,1),21,9.8,3.4)
	for z: float in [-9,9]:
		for x: float in [-11,11]:
			_box(b,"w_rust",Vector3(x,6.2,z),Vector3(.7,12,.7))
			_beam(b,"w_rust_dark",Vector3(x-1.4,.2,z),Vector3(x,5,z),.3,.3)
		_box(b,"w_warning",Vector3(0,12.4,z),Vector3(23,.9,1.0))
		for i: int in range(9): _box(b,"w_rust_dark",Vector3(-10+i*2.5,12.4,z-.53),Vector3(.55,.8,.07),Basis(Vector3.BACK,-.35))
		_pipe(b,"w_steel",Vector3(-1,12,z),Vector3(-1,8,z),.07)
		_pipe(b,"w_steel",Vector3(1,12,z),Vector3(1,8,z),.07)
		_beam(b,"w_rust_dark",Vector3(-1.4,8,z),Vector3(1.4,8,z),.4,.4)
	_ladder(b,Vector3(-11.5,.2,8),12.4)
	for x: float in [-11.2,11.2]:
		_box(b,"w_steel",Vector3(x,5.84,0),Vector3(1.0,.22,17.0))
		_railing(b,Vector3(x,6,-8),Vector3(x,6,8))
	for i: int in range(4): _crate(b,Vector3(-12.6,.1,-10+i*2.0),1.2)
	_patch_panel(b,Vector3(12,2.0,7),Vector2(3.5,3.5),PI*.5,"w_teal")
	_finish(root,b)

func _dish(b: Dictionary, at: Vector3, radius: float, yaw: float) -> void:
	var basis:=Basis(Vector3.UP,yaw)*Basis(Vector3.RIGHT,-.18)
	for i: int in range(16):
		var a: float=TAU*i/16
		var c: float=TAU*(i+1)/16
		var p: Vector3=Vector3(cos(a)*radius,sin(a)*radius,.24*radius)
		var q: Vector3=Vector3(cos(c)*radius,sin(c)*radius,.24*radius)
		_tri(b,"w_pale",at,at+basis*q,at+basis*p)
		_beam(b,"w_steel",at+basis*p,at+basis*q,.065,.065)
		if i%4==0: _beam(b,"w_rust_dark",at+basis*p,at+basis*Vector3(0,0,-radius*.65),.05,.05)
	_cylinder(b,"w_steel",at+basis*Vector3(0,0,-radius*.7),.13,.65,8,Basis(Vector3.RIGHT,PI*.5))

func _armored_coastal_gun(point: Vector2) -> void:
	var root: Node3D=_plot("armored_antiarmor_gun","装甲雷达岸炮",point,Vector2(24,25),-.15)
	var b: Dictionary={}
	_base(b,24,25)
	_cylinder(b,"w_concrete",Vector3(0,.65,0),8.2,1.1,24)
	_cylinder(b,"w_rust",Vector3(0,1.25,0),5.3,.25,20)
	_cylinder(b,"w_steel",Vector3(0,2.0,0),3.1,1.5,16)
	_box(b,"w_steel",Vector3(0,3.5,.5),Vector3(7.2,3.2,6.3))
	_box(b,"w_olive",Vector3(0,4.0,-2.8),Vector3(7.8,3.3,.42),Basis(Vector3.RIGHT,-.23))
	_box(b,"w_teal",Vector3(0,5.2,.5),Vector3(7.9,.40,6.8))
	for side: float in [-1.0,1.0]:
		_box(b,"w_teal",Vector3(side*3.75,3.6,.5),Vector3(.36,3.0,5.8),Basis(Vector3.FORWARD,side*.14))
		for z: float in [-1.3,.5,2.3]: _box(b,"w_rust",Vector3(side*3.98,3.7,z),Vector3(.1,1.5,.5))
	_pipe(b,"w_steel",Vector3(0,4,-2.7),Vector3(0,4.6,-11),.28)
	_pipe(b,"w_rust_dark",Vector3(0,4.0,-2.8),Vector3(0,4.2,-5.3),.46)
	_pipe(b,"w_steel",Vector3(0,4.55,-10.5),Vector3(0,4.65,-11.5),.40)
	_box(b,"w_black",Vector3(0,4.65,-11.58),Vector3(.48,.45,.08))
	_box(b,"w_black",Vector3(-1.9,4.9,-3.16),Vector3(1.3,.38,.10))
	# Service hatch, bolts and welded reinforcement make this read as salvage
	# armour rather than a clean toy cube. The gun retains a distinct recoil sleeve.
	_cylinder(b,"w_steel",Vector3(-1.5,5.47,.3),.95,.13,16)
	_pipe(b,"w_black",Vector3(-1.8,5.57,.3),Vector3(-1.2,5.57,.3),.055)
	for x: float in [-2.8,-1.6,-.4,.8,2.0]:
		_box(b,"w_rust_dark",Vector3(x,3.5,3.7),Vector3(.045,2.4,.05))
		for y: float in [2.6,4.5]: _cylinder(b,"w_salt",Vector3(x,y,3.77),.07,.08,6,Basis(Vector3.RIGHT,PI*.5))
	for i: int in range(3): _box(b,"w_black",Vector3(-2.2+i*.9,5.43,2.3),Vector3(.60,.10,.9))
	_box(b,"w_rust",Vector3(2.4,2.0,4.4),Vector3(1.2,1.5,1.1))
	_pipe(b,"w_steel",Vector3(2.4,5.4,2.5),Vector3(2.4,8.7,2.5),.085)
	_dish(b,Vector3(2.4,8.5,2.5),1.65,-.45)
	_ladder(b,Vector3(-4.35,.3,1.7),4.9)
	for x: float in [-7.5,7.5]:
		_crate(b,Vector3(x,.1,3.0),1.7)
		_patch_panel(b,Vector3(x,1.4,-3.3),Vector2(3.6,2.4),0,"w_sand")
	for i: int in range(10): _box(b,"w_warning",Vector3(-6.7+i*1.5,.13,10.5),Vector3(.7,.08,.24),Basis(Vector3.UP,-.2))
	_finish(root,b)

func _machine_gun_bunker(point: Vector2) -> void:
	var root: Node3D=_plot("machine_gun_bunker","拼装机枪堡",point,Vector2(23,21),.1)
	var b: Dictionary={}
	_base(b,23,21)
	_box(b,"w_concrete",Vector3(0,1.1,0),Vector3(14,2.0,9))
	_box(b,"w_spall",Vector3(0,4.0,.4),Vector3(14.8,.75,10))
	for x: float in [-6.3,0,6.3]: _box(b,"w_concrete",Vector3(x,2.7,-4),Vector3(1.1,2.1,.95))
	for x: float in [-3.1,3.1]:
		_box(b,"w_black",Vector3(x,2.6,-3.3),Vector3(4.7,.9,.10))
		_pipe(b,"w_steel",Vector3(x,2.6,-3),Vector3(x,2.65,-6.1),.10)
		_box(b,"w_steel",Vector3(x,2.6,-3.8),Vector3(.7,.55,1.3))
	_box(b,"w_olive",Vector3(0,4.46,.3),Vector3(12.5,.15,7.8))
	_box(b,"w_teal",Vector3(-3.7,4.55,1.7),Vector3(3.4,.10,2.7),Basis(Vector3.UP,-.12))
	for i: int in range(9): _box(b,"w_rust",Vector3(-5.5+i*1.35,4.56,.3),Vector3(.05,.035,7.3))
	for side: float in [-1.0,1.0]:
		for i: int in range(6):
			_box(b,"w_sand",Vector3(side*8,.35+i%2*.3,-4+i*1.6),Vector3(1.1,.6,1.5),Basis(Vector3.UP,side*.14))
	_ladder(b,Vector3(-5,.3,5.6),3.9)
	for i: int in range(3): _crate(b,Vector3(7,.1,6-i*1.6),1.2)
	_ivy(b,Vector3(-7.25,4,-1.5),6)
	_finish(root,b)

func _mortar_position(point: Vector2) -> void:
	var root: Node3D=_plot("mortar_position","掩蔽迫击炮位",point,Vector2(22,21),-.1)
	var b: Dictionary={}
	_base(b,22,21)
	for side: int in range(3):
		var yaw: float=side*PI*.5
		var basis:=Basis(Vector3.UP,yaw)
		for row: int in range(3):
			for i: int in range(13):
				_box(b,"w_sand",basis*Vector3(-6+i+float(row%2)*.3,.3+row*.37,-6),Vector3(.96,.35,.66),basis)
	for x: float in [-4,3]:
		_box(b,"w_rust_dark",Vector3(x,.2,-1),Vector3(2.4,.25,2.5))
		_pipe(b,"w_steel",Vector3(x,.35,-1),Vector3(x,3.6,-3.0),.20)
		_pipe(b,"w_rust_dark",Vector3(x-.8,.3,-2),Vector3(x,1.8,-1.8),.075)
		_pipe(b,"w_rust_dark",Vector3(x+.8,.3,-2),Vector3(x,1.8,-1.8),.075)
		for i: int in range(3):
			_crate(b,Vector3(x-1+i,.1,3.7),.9)
			_cylinder(b,"w_olive",Vector3(x-1+i,1.2,3.7),.12,.6,8)
	for p: Vector3 in [Vector3(-8,0,7),Vector3(7,0,7),Vector3(-8,0,1),Vector3(7,0,1)]: _pipe(b,"wood",p,p+Vector3.UP*3.0,.08)
	_tarp(b,Vector3(-.5,3.1,5.3),17,5,"w_olive")
	_finish(root,b)

func _wall_piece(start: Vector2, end: Vector2, label: String) -> void:
	var midpoint: Vector2=(start+end)*.5
	var direction: Vector2=end-start
	var width: float=direction.length()
	var yaw: float=-atan2(direction.y,direction.x)
	var root: Node3D=_plot("salvage_wall",label,midpoint,Vector2(width+1.0,3.1),yaw)
	var b: Dictionary={}
	# Keep stepped hillside walls visibly grounded even when neighbouring sections
	# inherit different elevations. Ground is queried at each metre of the span.
	var footing_count: int=maxi(1,ceili(width))
	for index: int in range(footing_count):
		var t: float=(float(index)+.5)/footing_count
		var ground: Vector2=start.lerp(end,t)
		var depth: float=maxf(.25,root.position.y-float(_height_at.call(ground.x,ground.y))+.3)
		_box(b,"w_rust_dark",Vector3(-width*.5+width*t,-depth*.5,0),Vector3(width/footing_count+.025,depth,2.1))
	_box(b,"w_spall",Vector3(0,.45,0),Vector3(width,.85,2.2))
	_box(b,"w_concrete",Vector3(0,1.9,0),Vector3(width,2.4,1.3))
	_box(b,"w_salt",Vector3(0,3.18,0),Vector3(width+.2,.24,1.55))
	for x: float in [-width*.5,width*.5]:
		_box(b,"w_rust_dark",Vector3(x,2.1,0),Vector3(.42,4.0,.42))
		_box(b,"w_steel",Vector3(x,4.05,-.3),Vector3(.10,.7,.9),Basis(Vector3.RIGHT,-.3))
	for i: int in range(maxi(1,floori(width/2.9))):
		var x: float=-width*.5+1.2+i*2.9
		_patch_panel(b,Vector3(x,1.8,-.72),Vector2(2.25,1.65),0,"w_teal" if i%2 else "w_rust")
	for y: float in [3.65,3.96,4.25]: _pipe(b,"w_rust_dark",Vector3(-width*.5,y,-.4),Vector3(width*.5,y,-.4),.025)
	for i: int in range(ceili(width/1.2)):
		var x: float=-width*.5+.3+i*1.2
		_beam(b,"w_rust_dark",Vector3(x,3.8,-.65),Vector3(x+.25,4.1,-.15),.025,.025)
	_finish(root,b)

func _defense_perimeter() -> void:
	var z: float=218.0
	for span: Vector2 in [Vector2(-84,-53),Vector2(-45,-4),Vector2(12,44),Vector2(52,84)]:
		var count: int=ceili((span.y-span.x)/9.0)
		for i: int in range(count):
			var x0: float=lerpf(span.x,span.y,float(i)/count)
			var x1: float=lerpf(span.x,span.y,float(i+1)/count)
			_wall_piece(Vector2(x0,z),Vector2(x1,z),"补丁防墙_%d_%d"%[int(span.x),i])
	# Real corner returns, with 16m central gate and two 8m side passages left open.
	for x: float in [-84,84]:
		_wall_piece(Vector2(x,z),Vector2(x,z+9),"防墙转角_%d"%int(x))
		_wall_piece(Vector2(x,z+9),Vector2(x,z+18),"防墙侧翼_%d"%int(x))
	var root: Node3D=_plot("main_gate","船板铰链大门",Vector2(4,z),Vector2(20,10))
	var b: Dictionary={}
	for side: float in [-1.0,1.0]:
		_box(b,"w_concrete",Vector3(side*8.6,2.2,0),Vector3(1.2,4.4,2.2))
		_box(b,"w_warning",Vector3(side*8.6,3.4,-1.13),Vector3(.5,1.4,.08))
		# Gate leaves stand open along the road shoulders; no invisible barrier.
		_patch_panel(b,Vector3(side*8.0,1.9,3.6),Vector2(7.0,3.1),PI*.5,"w_steel")
		for i: int in range(4): _box(b,"w_warning",Vector3(side*8.6,1.0+i*.65,-1.13),Vector3(1,.16,.10),Basis(Vector3.FORWARD,.2))
		_pipe(b,"w_steel",Vector3(side*8.6,4.3,0),Vector3(side*8.6,5.2,0),.06)
		_cylinder(b,"w_warning",Vector3(side*8.6,5.35,0),.26,.35,10)
	_finish(root,b)
	for gate_x: float in [-49,48]:
		var passage: Node3D=_plot("side_passage","侧翼步兵通路",Vector2(gate_x,z),Vector2(9,6))
		var detail: Dictionary={}
		for side: float in [-1.0,1.0]:
			_box(detail,"w_rust",Vector3(side*4.0,1.8,0),Vector3(.24,3.6,.24))
			_box(detail,"w_warning",Vector3(side*4.0,3.3,-.18),Vector3(.5,.7,.08))
		_finish(passage,detail)
