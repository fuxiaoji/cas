extends Node3D
## True 3D water/reeds for the shared demo river and bog. No rule simulation.
var _geo: RefCounted
var _ground: Callable

func build(geography: RefCounted, ground_height: Callable, grain: Texture2D) -> void:
	_geo=geography
	_ground=ground_height
	_build_water(grain)
	_build_reeds()

func _point(x: float,z: float) -> Vector3:
	return Vector3(x,float(_geo.call("water_level_at",x,z)),z)

func _depth(point: Vector3) -> float:
	return point.y-float(_ground.call(point.x,point.z))-.035

func _clip_shore(points: Array[Vector3]) -> Array[Vector3]:
	# Clip each shore triangle by water depth. Keeping only entirely wet
	# triangles made a coarse staircase along the muddy bank.
	var clipped: Array[Vector3]=[]
	for i: int in range(points.size()):
		var a: Vector3=points[i]
		var b: Vector3=points[(i+1)%points.size()]
		var da: float=_depth(a)
		var db: float=_depth(b)
		if da>=0.0: clipped.append(a)
		if (da>=0.0)!=(db>=0.0):
			clipped.append(a.lerp(b,clampf(da/(da-db),0.0,1.0)))
	return clipped

func _build_water(grain: Texture2D) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var count: int=0
	for row: int in range(109):
		for col: int in range(48):
			var x: float=-216.0+col*2.4
			var z: float=-60.0+row*2.4
			var corners: Array[Vector3]=[_point(x,z),_point(x+2.4,z),_point(x,z+2.4),_point(x+2.4,z+2.4)]
			for tri: Vector3i in [Vector3i(0,1,2),Vector3i(1,3,2)]:
				var clipped: Array[Vector3]=_clip_shore([corners[tri.x],corners[tri.y],corners[tri.z]])
				for fan: int in range(1,clipped.size()-1):
					for point: Vector3 in [clipped[0],clipped[fan],clipped[fan+1]]:
						st.set_normal(Vector3.UP)
						st.add_vertex(point)
					count+=1
	if count==0: return
	var mesh := MeshInstance3D.new()
	mesh.name="BogPoolsAndRiver"
	st.index()
	mesh.mesh=st.commit()
	var material := ShaderMaterial.new()
	material.shader=load("res://shaders/inland_water.gdshader")
	material.set_shader_parameter("grain",grain)
	mesh.material_override=material
	mesh.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mesh)
	set_meta("inland_water_triangles",count)

func _triangle(st: SurfaceTool,a: Vector3,b: Vector3,c: Vector3,tint: Color) -> void:
	var normal: Vector3=(b-a).cross(c-a).normalized()
	for p: Vector3 in [a,b,c]:
		st.set_normal(normal)
		st.set_color(tint.srgb_to_linear())
		st.add_vertex(p)

func _stem(st: SurfaceTool,a: Vector3,height: float,angle: float,rng: RandomNumberGenerator) -> void:
	var sway: Vector3=Vector3(cos(angle),0,sin(angle))*.12
	var top: Vector3=a+Vector3.UP*height+sway
	var side: Vector3=Vector3(cos(angle+PI*.5),0,sin(angle+PI*.5))*.036
	var green: Color=Color("5f7e41").lerp(Color("859650"),rng.randf())
	_triangle(st,a-side,a+side,top+side,green)
	_triangle(st,a-side,top+side,top-side,green)
	for k: int in range(3):
		var direction: Vector3=Vector3(cos(angle+k*2.1),0,sin(angle+k*2.1))
		var base: Vector3=a+Vector3.UP*height*.22
		var leaf_tip: Vector3=a+direction*rng.randf_range(.55,.94)+Vector3.UP*height*rng.randf_range(.55,.85)
		var leaf_side: Vector3=direction.cross(Vector3.UP)*.12
		_triangle(st,base-leaf_side,base+leaf_side,leaf_tip,green)
	var brown: Color=Color("6a4d35")
	var tip: Vector3=top+Vector3.UP*.26
	for k: int in range(5):
		var p: Vector3=Vector3(cos(k*TAU/5.0),0,sin(k*TAU/5.0))*.075
		var q: Vector3=Vector3(cos((k+1)*TAU/5.0),0,sin((k+1)*TAU/5.0))*.075
		_triangle(st,top+p,tip+p,tip+q,brown)
		_triangle(st,top+p,tip+q,top+q,brown)

func _build_reeds() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed=int(_geo.get("seed_value"))+31991
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var clumps: int=0
	for attempt: int in range(700):
		var x: float=rng.randf_range(-197,-118)
		var z: float=rng.randf_range(94,183)
		if float(_geo.call("swamp_weight",x,z))<.45: continue
		var h: float=float(_ground.call(x,z))
		if h>2.6 or h<.65: continue
		for stem: int in range(rng.randi_range(3,6)):
			_stem(st,Vector3(x+rng.randf_range(-.7,.7),h,z+rng.randf_range(-.7,.7)),rng.randf_range(1.1,2.15),rng.randf()*TAU,rng)
		clumps+=1
		if clumps>=82: break
	var mesh := MeshInstance3D.new()
	mesh.name="CattailReedClusters"
	st.index()
	mesh.mesh=st.commit()
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo=true
	material.cull_mode=BaseMaterial3D.CULL_DISABLED
	material.roughness=.95
	mesh.material_override=material
	add_child(mesh)
	set_meta("reed_clumps",clumps)
