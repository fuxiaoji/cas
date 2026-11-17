class_name CasProceduralIsland
extends Node2D
## Generated from authoritative shoreline. The runtime distance field is algorithmic,
## never a loaded image. Polygon2D still clips every pixel to the original geometry.
const LAND = preload("res://shaders/procedural_island.gdshader")
var shoreline := PackedVector2Array()
var bounds := Rect2()
var surface: Polygon2D
var field: ImageTexture
var generated_seed := 0

func configure(points: PackedVector2Array, seed_value: int, theme: String = "", landmarks: Array = []) -> void:
	shoreline = points.duplicate()
	generated_seed = seed_value
	bounds = Rect2(points[0],Vector2.ZERO)
	for point in points:
		bounds = bounds.expand(point)
	field = _distance_field(points,bounds)
	surface = Polygon2D.new()
	surface.texture = field
	var coordinates := PackedVector2Array()
	for point in points:
		coordinates.append((point-bounds.position)/bounds.size*Vector2(field.get_width(),field.get_height()))
	surface.uv = coordinates
	var material := ShaderMaterial.new()
	material.shader = LAND
	material.set_shader_parameter("shore_field",field)
	material.set_shader_parameter("world_origin",bounds.position)
	material.set_shader_parameter("world_span",bounds.size)
	material.set_shader_parameter("island_seed",float(seed_value%9971))
	material.set_shader_parameter("terrain_style",["","atoll","fractured","fjord","drowned_city"].find(theme))
	material.set_shader_parameter("urban_foundation",theme=="drowned_city" and not landmarks.is_empty())
	var ruin_zones := PackedVector3Array()
	for landmark in landmarks.slice(0,16):
		var center := Vector2(float(landmark.x),float(landmark.y))
		var radius := 0.0
		for point in landmark.get("footprint",[]):
			radius = maxf(radius,center.distance_to(Vector2(float(point.x),float(point.y))))
		ruin_zones.append(Vector3(center.x,center.y,radius*1.35))
	material.set_shader_parameter("ruin_count",ruin_zones.size())
	ruin_zones.resize(16)
	material.set_shader_parameter("ruin_zones",ruin_zones)
	surface.material = material
	add_child(surface)

func update_camera(map: Control, time: float, night: float, overcast: float) -> void:
	var projected := PackedVector2Array()
	for point in shoreline:
		projected.append(map.project(point))
	surface.polygon = projected
	surface.material.set_shader_parameter("visual_time",time)
	surface.material.set_shader_parameter("night_amount",night)
	surface.material.set_shader_parameter("overcast",overcast)

static func _distance_field(points: PackedVector2Array, rectangle: Rect2) -> ImageTexture:
	# Scanline raster + two-pass chamfer distance is O(pixels + scanlines * edges).
	# Exact geometry does the final clipping; this field controls shading only.
	var unit := maxf(rectangle.size.x,rectangle.size.y)/128.0
	unit = maxf(unit,.01)
	var width := maxi(3,int(ceil(rectangle.size.x/unit)))
	var height := maxi(3,int(ceil(rectangle.size.y/unit)))
	var distances := PackedFloat32Array()
	distances.resize(width*height)
	distances.fill(0.0)
	for y in range(height):
		var sample_y := rectangle.position.y+(float(y)+.5)*unit
		var crosses: Array[float] = []
		for i in range(points.size()):
			var a := points[i]
			var b := points[(i+1)%points.size()]
			if (a.y<=sample_y and b.y>sample_y) or (b.y<=sample_y and a.y>sample_y):
				crosses.append(a.x+(sample_y-a.y)*(b.x-a.x)/(b.y-a.y))
		crosses.sort()
		for i in range(0,crosses.size()-1,2):
			var left := clampi(int(ceil((crosses[i]-rectangle.position.x)/unit-.5)),0,width-1)
			var right := clampi(int(floor((crosses[i+1]-rectangle.position.x)/unit-.5)),0,width-1)
			for x in range(left,right+1):
				distances[y*width+x] = .5 if x==0 or x==width-1 or y==0 or y==height-1 else 10000.0
	for y in range(height):
		for x in range(width):
			var i := y*width+x
			if x>0:
				distances[i] = minf(distances[i],distances[i-1]+1.0)
			if y>0:
				distances[i] = minf(distances[i],distances[i-width]+1.0)
				if x>0:
					distances[i] = minf(distances[i],distances[i-width-1]+1.414214)
				if x+1<width:
					distances[i] = minf(distances[i],distances[i-width+1]+1.414214)
	for y in range(height-1,-1,-1):
		for x in range(width-1,-1,-1):
			var i := y*width+x
			if x+1<width:
				distances[i] = minf(distances[i],distances[i+1]+1.0)
			if y+1<height:
				distances[i] = minf(distances[i],distances[i+width]+1.0)
				if x>0:
					distances[i] = minf(distances[i],distances[i+width-1]+1.414214)
				if x+1<width:
					distances[i] = minf(distances[i],distances[i+width+1]+1.414214)
	var image := Image.create(width,height,false,Image.FORMAT_RF)
	var extent := maxf(rectangle.size.x,rectangle.size.y)
	for y in range(height):
		for x in range(width):
			image.set_pixel(x,y,Color(distances[y*width+x]*unit/extent,0,0,1))
	return ImageTexture.create_from_image(image)
