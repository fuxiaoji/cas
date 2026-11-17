@tool
extends RefCounted
const GroundMesh=preload("res://scripts/littoral_ground_mesh.gd")
## Native polygons own traversal and cover; this only shades those exact regions.
static var materials:Dictionary={}
static var scenery:Dictionary={}
static var scatter_cache:Dictionary={}
static var surface_cache:Dictionary={}
static var rock_layer_cache:Dictionary={}
static var rim_cache:Dictionary={}
const V4_PALETTE={
	"beach":["f1dba5","cebc8d",.78],"landing_zone":["ebd8a7","c9bc8b",.53],
	"cliff":["d3bf99","8a9683",.88],"swamp":["89ad88","426f67",.72],
	"river":["69d3d1","338f9f",.98],"forest":["83ad66","467858",.48],
	"bush":["afc774","6e9d62",.38],"road":["708b91","566e79",1.0],
	"ford":["c5c6a6","929d91",1.0]
}
const PALETTE={"beach":["f3dfa9","d8be8d"],"landing_zone":["efdda4","d5c18f"],"cliff":["c6b899","8c927b"],"swamp":["9dbb91","5d8b77"],"river":["73d8d0","459eaf"],"ford":["b9e1d2","77b7b3"],"forest":["91bf7d","588969"],"bush":["b2cb85","82a96f"]}
static func points(raw:Variant)->PackedVector2Array:
	var result:PackedVector2Array=[]
	if raw is Array:for point in raw:result.append(Vector2(float(point.get("x",0)),float(point.get("y",0))))
	return result
static func material(kind:String)->Texture2D:
	if materials.has(kind):return materials[kind]
	var colors:Array=PALETTE.get(kind,PALETTE.bush);var light:=Color(str(colors[0]));var dark:=Color(str(colors[1]))
	var image:=Image.create(96,96,false,Image.FORMAT_RGBA8);var noise:=FastNoiseLite.new()
	noise.seed=int(hash(kind));noise.frequency=.065;noise.fractal_octaves=3
	for y in range(96):
		for x in range(96):
			var n:float=noise.get_noise_2d(x,y)*.5+.5
			var grain:float=sin(x*12.3+y*41.7)*.025
			image.set_pixel(x,y,dark.lerp(light,clampf(.3+n*.7+grain,0,1)))
	image.generate_mipmaps();materials[kind]=ImageTexture.create_from_image(image);return materials[kind]
static func texture(kind:String)->Texture2D:
	if scenery.has(kind):return scenery[kind]
	var path:String="res://assets/home/environment/%s.png"%kind
	if not ResourceLoader.exists(path):return null
	var tex:Texture2D=load(path);var region:Rect2i=tex.get_image().get_used_rect()
	var crop:=AtlasTexture.new();crop.atlas=tex;crop.region=region;scenery[kind]=crop;return crop
static func scatter(feature:Dictionary,seed:int)->Array:
	var signature:int=hash([feature,seed])
	if scatter_cache.has(signature):return scatter_cache[signature]
	var polygon:PackedVector2Array=points(feature.get("polygon",[]));var result:Array=[]
	if polygon.size()<3:return result
	var bounds:=Rect2(polygon[0],Vector2.ZERO)
	for point in polygon:bounds=bounds.expand(point)
	var rng:=RandomNumberGenerator.new();rng.seed=signature
	var kind:String=str(feature.get("kind",""));var count:int=clampi(int(bounds.get_area()/18000),12,120) if kind=="forest" else clampi(int(bounds.get_area()/35000),8,65)
	for attempt in range(count*5):
		var at:=Vector2(rng.randf_range(bounds.position.x,bounds.end.x),rng.randf_range(bounds.position.y,bounds.end.y))
		if not Geometry2D.is_point_in_polygon(at,polygon):continue
		result.append({"at":at,"size":rng.randf_range(23,37) if kind=="forest" else rng.randf_range(10,19)})
		if result.size()>=count:break
	result.sort_custom(func(a,b):return (a.at.x-a.at.y)<(b.at.x-b.at.y))
	while scatter_cache.size()>=24:scatter_cache.erase(scatter_cache.keys()[0])
	scatter_cache[signature]=result;return result
static func paint(canvas:CanvasItem,terrain:Dictionary,projector:Callable,seed:int,detail:int,town:Dictionary={},flat_projector:Callable=Callable())->void:
	if str(terrain.get("version",""))=="tactical-terrain-v4":
		_paint_v4(canvas,terrain,projector,seed,detail,town,flat_projector)
		return
	if str(terrain.get("version","")) not in ["tactical-terrain-v2","tactical-terrain-v4"]:return
	for feature in terrain.get("features",[]):
		var kind:String=str(feature.get("kind",""));var polygon:PackedVector2Array=points(feature.get("polygon",[]))
		if polygon.size()<3:continue
		var bounds:=Rect2(polygon[0],Vector2.ZERO)
		for at in polygon:bounds=bounds.expand(at)
		var screen:PackedVector2Array=[];var uv:PackedVector2Array=[]
		for at in polygon:screen.append(projector.call(at));uv.append((at-bounds.position)/bounds.size)
		var opacity:float=float({"forest":.44,"bush":.38,"cliff":.68,"swamp":.72}.get(kind,.92))
		GroundMesh.paint(canvas,polygon,projector,Color(1,1,1,opacity),material(kind),uv)
		if kind in ["river","ford","swamp"]:
			var edge:PackedVector2Array=screen.duplicate();edge.append(screen[0])
			canvas.draw_polyline(edge,Color(.81,.93,.75,.7) if kind!="swamp" else Color(.42,.52,.32,.6),1.5,true)
		if detail<2:continue
		if kind in ["forest","bush","swamp","cliff"]:
			var tex:Texture2D=texture("tree_cluster" if kind=="forest" else "rock_cluster" if kind=="cliff" else "grass_patch")
			if tex==null:continue
			for decoration in scatter(feature,seed):
				if _occupied(decoration.at,float(decoration.size)*.35,town):continue
				var at:Vector2=projector.call(decoration.at);var width:float=at.distance_to(projector.call(decoration.at+Vector2(float(decoration.size),0)))
				if width<1.5:continue
				var dimensions:=Vector2(width,width*tex.get_height()/maxf(1,tex.get_width()))
				canvas.draw_texture_rect(tex,Rect2(at-dimensions*Vector2(.5,.8),dimensions),false,Color(.91,1,.86) if kind=="forest" else Color.WHITE)
		if kind=="landing_zone":
			# Low-key landing lanes share the authoritative footprint, not new walls.
			for index in range(0,screen.size(),2):canvas.draw_line(screen[index],screen[(index+1)%screen.size()],Color(.98,.92,.67,.65),2,true)

static func _bounds(polygon:PackedVector2Array)->Rect2:
	var result:=Rect2(polygon[0],Vector2.ZERO)
	for at in polygon:result=result.expand(at)
	return result

static func _edge_distance(at:Vector2,polygon:PackedVector2Array)->float:
	var nearest:float=INF
	for i in range(polygon.size()):
		nearest=minf(nearest,at.distance_to(Geometry2D.get_closest_point_to_segment(at,polygon[i],polygon[(i+1)%polygon.size()])))
	return nearest

static func _surface(feature:Dictionary,seed:int)->Texture2D:
	var kind:String=str(feature.get("kind",""));var polygon:PackedVector2Array=points(feature.get("polygon",[]))
	if polygon.size()<3 or not V4_PALETTE.has(kind):return null
	var key:int=hash(["biome-v4",kind,polygon,seed])
	if surface_cache.has(key):return surface_cache[key]
	var bounds:Rect2=_bounds(polygon)
	var palette:Array=V4_PALETTE[kind];var light:=Color(str(palette[0]));var dark:=Color(str(palette[1]))
	var image:=Image.create(160,160,false,Image.FORMAT_RGBA8)
	var noise:=FastNoiseLite.new();noise.seed=seed^int(hash(kind));noise.frequency=.022;noise.fractal_octaves=3
	var grain:=FastNoiseLite.new();grain.seed=noise.seed^0x32a1;grain.frequency=.27;grain.fractal_octaves=2
	var feather:float=clampf(minf(bounds.size.x,bounds.size.y)*.10,4,28)
	for y in range(160):
		for x in range(160):
			var world:Vector2=bounds.position+(Vector2(x,y)+Vector2(.5,.5))/160.0*bounds.size
			var broad:float=noise.get_noise_2dv(world)*.5+.5;var fine:float=grain.get_noise_2dv(world)
			var color:Color=dark.lerp(light,clampf(.30+broad*.64+fine*.06,0,1))
			var opacity:float=float(palette[2])
			if kind not in ["road","ford"]:
				# Feather only inside the native footprint. No decorative expansion
				# can imply a larger beach, forest, traversable ford or collision.
				opacity*=smoothstep(0,feather*(.8+broad*.4),_edge_distance(world,polygon))
			if kind in ["beach","landing_zone"]:
				color=color.lerp(Color("fbebc5"),maxf(0,sin(world.x*.21+world.y*.37+fine)*.5-.36)*.30)
			elif kind=="swamp":
				color=color.lerp(Color("5ca49a"),smoothstep(.55,.80,broad)*.46)
			elif kind=="cliff":
				color=color.lerp(Color("efe1bd"),maxf(0,sin(world.y*.09+fine)*.5-.26)*.30)
			color.a=opacity;image.set_pixel(x,y,color)
	image.generate_mipmaps()
	while surface_cache.size()>=64:surface_cache.erase(surface_cache.keys()[0])
	surface_cache[key]=ImageTexture.create_from_image(image)
	return surface_cache[key]

static func _paint_surface(canvas:CanvasItem,feature:Dictionary,projector:Callable,seed:int)->void:
	var polygon:PackedVector2Array=points(feature.get("polygon",[]))
	if polygon.size()<3:return
	var bounds:Rect2=_bounds(polygon)
	if minf(bounds.size.x,bounds.size.y)<.001:return
	var uv:PackedVector2Array=[]
	for at in polygon:uv.append((at-bounds.position)/bounds.size)
	GroundMesh.paint(canvas,polygon,projector,Color.WHITE,_surface(feature,seed),uv)

static func highland_surface(feature:Dictionary,seed:int)->Texture2D:
	var polygon:PackedVector2Array=points(feature.get("polygon",[]))
	if polygon.size()<3:return null
	var key:int=hash(["highland-contact-v1",polygon,seed])
	if surface_cache.has(key):return surface_cache[key]
	var bounds:Rect2=_bounds(polygon);var image:=Image.create(192,192,false,Image.FORMAT_RGBA8)
	var noise:=FastNoiseLite.new();noise.seed=seed^int(hash(polygon));noise.frequency=.032;noise.fractal_octaves=3
	var detail:=FastNoiseLite.new();detail.seed=noise.seed^0x2e39;detail.frequency=.17;detail.fractal_octaves=2
	for y in range(192):
		for x in range(192):
			var world:Vector2=bounds.position+(Vector2(x,y)+Vector2(.5,.5))/192.0*bounds.size
			var broad:float=noise.get_noise_2dv(world)*.5+.5;var fine:float=detail.get_noise_2dv(world)
			var distance:float=_edge_distance(world,polygon)
			var lip:float=13+broad*23+fine*6
			var grass_amount:float=smoothstep(lip*.12,lip,distance)
			var soil:Color=Color("c5b58a").lerp(Color("ded0a2"),broad*.65)
			var exposed:float=smoothstep(.52,.72,broad+fine*.18)*(1-smoothstep(4,lip*.8,distance))
			soil=soil.lerp(Color("ded4b3"),exposed*.72)
			var grass:Color=Color("77aa6d").lerp(Color("9ac17b"),broad)
			grass=grass.lerp(Color("b4bd84"),smoothstep(.50,.76,broad+fine*.28)*.35)
			var color:Color=soil.lerp(grass,grass_amount)
			# Jagged little grass roots and pale stones interrupt the lip without
			# changing a vertex, creating a ledge or painting beyond the polygon.
			color=color.lerp(Color("648d5e"),maxf(0,fine-.24)*(1-grass_amount)*.30)
			color.a=.88;image.set_pixel(x,y,color)
	image.generate_mipmaps()
	while surface_cache.size()>=64:surface_cache.erase(surface_cache.keys()[0])
	surface_cache[key]=ImageTexture.create_from_image(image);return surface_cache[key]

static func rock_face_material(seed:int,edge_length_m:float,height_m:float)->Texture2D:
	# Face-local metre coordinates keep the strata calm on both short ramp
	# sides and long plateau walls instead of stretching one noise image.
	var length:float=maxf(1,edge_length_m);var height:float=maxf(1,height_m)
	var key:int=hash(["rock-strata-v1",seed,roundf(length*.5),roundf(height*.5)])
	if rock_layer_cache.has(key):return rock_layer_cache[key]
	var columns:int=clampi(ceili(length/1.7),96,320);var rows:int=clampi(ceili(height/1.4),64,160)
	var image:=Image.create(columns,rows,false,Image.FORMAT_RGBA8)
	var broad:=FastNoiseLite.new();broad.seed=seed^0x533b;broad.frequency=.024;broad.fractal_octaves=2
	var grain:=FastNoiseLite.new();grain.seed=seed^0x1809;grain.frequency=.19;grain.fractal_octaves=2
	for y in range(rows):
		for x in range(columns):
			var across:float=(x+.5)/columns*length;var depth:float=(y+.5)/rows*height
			var n:float=broad.get_noise_2d(across,depth);var fine:float=grain.get_noise_2d(across,depth)
			var strata:float=depth/17.0+sin(across*.014)*.30+n*.43
			var layer:float=fposmod(strata,1.0)
			var color:Color=Color("c9b68a").lerp(Color("e2d0a4"),clampf(.42+n*.55+fine*.13,0,1))
			color=color.lerp(Color("b1b49a"),smoothstep(.35,.78,layer)*.38)
			var seam:float=(1-smoothstep(.015,.065,layer))*.13
			var joint:float=absf(sin(across*.031+n*.25))
			var broken:float=(1-smoothstep(.009,.035,joint))*smoothstep(-.2,.3,fine)*.13
			color=color.darkened(seam+broken)
			var roots:float=(1-smoothstep(3,15+n*8,depth))*smoothstep(-.15,.24,n)*.40
			color=color.lerp(Color("8caa76"),roots)
			color=color.lerp(Color("d5c8a3"),smoothstep(height-10,height,depth)*.17)
			image.set_pixel(x,y,color)
	image.generate_mipmaps()
	while rock_layer_cache.size()>=64:rock_layer_cache.erase(rock_layer_cache.keys()[0])
	rock_layer_cache[key]=ImageTexture.create_from_image(image);return rock_layer_cache[key]

static func _highland_rim(feature:Dictionary,seed:int)->Array:
	var polygon:PackedVector2Array=points(feature.get("polygon",[]))
	var key:int=hash(["highland-rim-v1",polygon,seed])
	if rim_cache.has(key):return rim_cache[key]
	var result:Array=[];var rng:=RandomNumberGenerator.new();rng.seed=key
	for i in range(polygon.size()):
		var a:Vector2=polygon[i];var b:Vector2=polygon[(i+1)%polygon.size()]
		var side:Vector2=(b-a).normalized().orthogonal()
		var count:int=clampi(ceili(a.distance_to(b)/53.0),1,7)
		for step in range(count):
			var t:float=(step+rng.randf_range(.2,.8))/count
			var at:Vector2=a.lerp(b,t)+side*rng.randf_range(7,18)
			if not Geometry2D.is_point_in_polygon(at,polygon):at=a.lerp(b,t)-side*rng.randf_range(7,18)
			if not Geometry2D.is_point_in_polygon(at,polygon) or _edge_distance(at,polygon)<5:continue
			result.append({"at":at,"size":rng.randf_range(5,9),"rock":rng.randf()<.44})
			if result.size()>=42:break
		if result.size()>=42:break
	while rim_cache.size()>=24:rim_cache.erase(rim_cache.keys()[0])
	rim_cache[key]=result;return result

static func _paint_highland(canvas:CanvasItem,feature:Dictionary,clearance:Array,projector:Callable,flat_projector:Callable,seed:int,detail:int,town:Dictionary)->void:
	var polygon:PackedVector2Array=points(feature.get("polygon",[]))
	if polygon.size()<3:return
	var surface_projector:Callable=projector
	if flat_projector.is_valid():
		var scale:float=_flat_scale(projector,flat_projector,polygon[0])
		var rise:float=float(feature.get("elevation_m",0))*scale
		# Same native flat top as the elevation renderer; boundary points must
		# not fall to the low side of point-in-polygon and expose a green frame.
		surface_projector=func(at:Vector2)->Vector2:return flat_projector.call(at)-Vector2(0,rise)
	var bounds:Rect2=_bounds(polygon);var uv:PackedVector2Array=[]
	for at in polygon:uv.append((at-bounds.position)/bounds.size)
	GroundMesh.paint(canvas,polygon,surface_projector,Color.WHITE,highland_surface(feature,seed),uv)
	if detail<2:return
	for decoration in _highland_rim(feature,seed):
		var world:Vector2=decoration.at;var meters:float=float(decoration.size)
		if _occupied(world,meters*.65,town) or _native_route_or_water(world,meters*.65,clearance):continue
		var tex:Texture2D=texture("rock_cluster" if decoration.rock else "grass_patch")
		if tex==null:continue
		var at:Vector2=surface_projector.call(world);var scale:float=_flat_scale(projector,flat_projector,world)
		var width:float=meters*scale
		if width<2:continue
		var dimensions:=Vector2(width,width*tex.get_height()/maxf(1,tex.get_width()))
		var limit:float=(8 if decoration.rock else 4)*scale
		if dimensions.y>limit:dimensions*=limit/dimensions.y
		if canvas is Control and not Rect2(at-dimensions*Vector2(.5,.94),dimensions).intersects(Rect2(Vector2.ZERO,canvas.size),true):continue
		canvas.draw_texture_rect(tex,Rect2(at-dimensions*Vector2(.5,.94),dimensions),false,Color(1.03,1.01,.94))

static func _paint_v4(canvas:CanvasItem,terrain:Dictionary,projector:Callable,seed:int,detail:int,town:Dictionary,flat_projector:Callable)->void:
	var clearance:Array=[]
	for feature in terrain.get("features",[]):
		if str(feature.get("kind","")) in ["road","ford","river"]:
			var boundary:PackedVector2Array=points(feature.get("polygon",[]))
			if boundary.size()>2:clearance.append(boundary)
	for feature in terrain.get("features",[]):
		if str(feature.get("kind",""))=="highland":
			_paint_highland(canvas,feature,clearance,projector,flat_projector,seed,detail,town)
	# Elevation owns highland/lowland/ramp. Unknown features must never fall
	# back to a bush rectangle and obscure the authoritative height surface.
	for feature in terrain.get("features",[]):
		var kind:String=str(feature.get("kind",""))
		if not V4_PALETTE.has(kind) or kind in ["road","ford"]:continue
		_paint_surface(canvas,feature,projector,seed)
		if detail>=2 and kind in ["forest","bush","swamp","cliff"]:
			_paint_scenery(canvas,feature,clearance,projector,seed,town,flat_projector)
	# Linear routes remain readable over the natural ground. Crossings are
	# drawn once, after Town.paint_ground, by the public paint_crossings hook.
	for feature in terrain.get("features",[]):
		if str(feature.get("kind",""))!="road":continue
		_paint_surface(canvas,feature,projector,seed)
		_route_edges(canvas,feature,projector,detail,false)

static func _scatter_v4(feature:Dictionary,seed:int)->Array:
	var signature:int=hash(["scenery-v4",feature,seed])
	if scatter_cache.has(signature):return scatter_cache[signature]
	var polygon:PackedVector2Array=points(feature.get("polygon",[]));var result:Array=[]
	if polygon.size()<3:return result
	var bounds:Rect2=_bounds(polygon);var kind:String=str(feature.get("kind",""))
	var density:float=9500 if kind=="forest" else 19000 if kind=="cliff" else 23000
	var count:int=clampi(int(bounds.get_area()/density),4,100)
	var rng:=RandomNumberGenerator.new();rng.seed=signature
	for attempt in range(count*7):
		var at:=Vector2(rng.randf_range(bounds.position.x,bounds.end.x),rng.randf_range(bounds.position.y,bounds.end.y))
		if not Geometry2D.is_point_in_polygon(at,polygon):continue
		var size:float=rng.randf_range(14,21) if kind=="forest" else rng.randf_range(7,13) if kind=="cliff" else rng.randf_range(5,9)
		if _edge_distance(at,polygon)<size*.35:continue
		result.append({"at":at,"size":size})
		if result.size()>=count:break
	result.sort_custom(func(a,b):return (a.at.x-a.at.y)<(b.at.x-b.at.y))
	while scatter_cache.size()>=48:scatter_cache.erase(scatter_cache.keys()[0])
	scatter_cache[signature]=result;return result

static func _paint_scenery(canvas:CanvasItem,feature:Dictionary,clearance:Array,projector:Callable,seed:int,town:Dictionary,flat_projector:Callable)->void:
	var kind:String=str(feature.get("kind",""))
	var tex:Texture2D=texture("tree_cluster" if kind=="forest" else "rock_cluster" if kind=="cliff" else "grass_patch")
	if tex==null:return
	for decoration in _scatter_v4(feature,seed):
		var world:Vector2=decoration.at;var meters:float=float(decoration.size)
		if _occupied(world,meters*.55,town) or _native_route_or_water(world,meters*.55,clearance):continue
		var at:Vector2=projector.call(world);var scale:float=_flat_scale(projector,flat_projector,world)
		if _straddles_height_edge(projector,flat_projector,world,meters*.45,scale):continue
		var width:float=meters*scale
		if width<1.25:continue
		var dimensions:=Vector2(width,width*tex.get_height()/maxf(1,tex.get_width()))
		# Tree art is a small cluster, not a portrait-sized landmark. A height
		# edge must never inflate it through a projected world-space delta.
		var maximum_height:float=(22.0 if kind=="forest" else 12.0 if kind=="cliff" else 6.0)*scale
		if dimensions.y>maximum_height:dimensions*=maximum_height/dimensions.y
		if canvas is Control and not Rect2(at-dimensions*Vector2(.5,.94),dimensions).intersects(Rect2(Vector2.ZERO,canvas.size),true):continue
		# The existing cluster's roots are near the bottom of its alpha crop.
		# Use a ground anchor, rather than centering trunks above their location.
		canvas.draw_texture_rect(tex,Rect2(at-dimensions*Vector2(.5,.94),dimensions),false,Color(1.02,1.02,.95) if kind=="forest" else Color.WHITE)

static func _flat_scale(projector:Callable,flat_projector:Callable,at:Vector2)->float:
	if flat_projector.is_valid():
		return (flat_projector.call(at) as Vector2).distance_to(flat_projector.call(at+Vector2.RIGHT))
	# Height changes only screen Y. The horizontal planar differential is a
	# bounded fallback for a caller that has not supplied its flat projector.
	var origin:Vector2=projector.call(at)
	var dx:float=absf((projector.call(at+Vector2.RIGHT) as Vector2).x-origin.x)
	var dy:float=absf((projector.call(at+Vector2.DOWN) as Vector2).x-origin.x)
	return maxf(dx,dy)*1.15470054 if minf(dx,dy)>.00001 else maxf(dx,dy)

static func _straddles_height_edge(projector:Callable,flat_projector:Callable,at:Vector2,radius:float,scale:float)->bool:
	if not flat_projector.is_valid() or scale<.00001:return false
	var low:float=INF;var high:float=-INF
	for offset in [Vector2.ZERO,Vector2(radius,0),Vector2(-radius,0),Vector2(0,radius),Vector2(0,-radius)]:
		var world:Vector2=at+offset
		var elevation:float=((flat_projector.call(world) as Vector2).y-(projector.call(world) as Vector2).y)/scale
		low=minf(low,elevation);high=maxf(high,elevation)
	return high-low>maxf(4,radius*.7)

static func _native_route_or_water(at:Vector2,margin:float,clearance:Array)->bool:
	for polygon:PackedVector2Array in clearance:
		if Geometry2D.is_point_in_polygon(at,polygon) or _edge_distance(at,polygon)<margin:return true
	return false

static func _route_span(feature:Dictionary)->Dictionary:
	var polygon:PackedVector2Array=points(feature.get("polygon",[]))
	if polygon.size()!=4:return {}
	var first:int=0;var longest:float=0
	for i in range(4):
		var length:float=polygon[i].distance_squared_to(polygon[(i+1)%4])
		if length>longest:longest=length;first=i
	var a:Vector2=(polygon[first]+polygon[(first+3)%4])*.5
	var b:Vector2=(polygon[(first+1)%4]+polygon[(first+2)%4])*.5
	return {"a":a,"b":b,"side":(polygon[(first+3)%4]-polygon[first])*.5}

static func _world_line(canvas:CanvasItem,a:Vector2,b:Vector2,projector:Callable,color:Color,width:float)->void:
	# Sample long lines through the same height projector as the ground mesh.
	var steps:int=clampi(ceili(a.distance_to(b)/32.0),1,96);var path:PackedVector2Array=[]
	for i in range(steps+1):path.append(projector.call(a.lerp(b,float(i)/steps)))
	canvas.draw_polyline(path,color,width,true)

static func _route_edges(canvas:CanvasItem,feature:Dictionary,projector:Callable,detail:int,crossing:bool)->void:
	var span:Dictionary=_route_span(feature)
	if span.is_empty():return
	var a:Vector2=span.a;var b:Vector2=span.b;var side:Vector2=span.side
	var pixels:float=(projector.call(a+side) as Vector2).distance_to(projector.call(a-side))
	var edge_color:=Color("d5d8ba") if crossing else Color("b9c4b5")
	# Width is always the native 24m rectangle; no screen-space widening.
	if pixels>=1.1:
		for direction in [-1,1]:_world_line(canvas,a+side*direction*.94,b+side*direction*.94,projector,edge_color,clampf(pixels*.065,.55,1.8))
	if detail<2 or pixels<5:return
	var distance:float=a.distance_to(b);var forward:Vector2=(b-a).normalized()
	if crossing:
		# Shallow reinforced causeway, not a tall bridge or a new obstruction.
		# Transverse joints and short abutments sit strictly inside its footprint.
		var spacing:float=12.0
		for step in range(1,mini(160,int(distance/spacing))):
			var at:Vector2=a+forward*step*spacing
			_world_line(canvas,at-side*.91,at+side*.91,projector,Color(.35,.43,.40,.48),clampf(pixels*.025,.5,1.1))
		for end in [a+forward*5,b-forward*5]:
			_world_line(canvas,end-side*.94,end+side*.94,projector,Color("e0d8b7"),clampf(pixels*.16,1,4))
	else:
		for step in range(1,mini(100,int(distance/42.0))):
			var at:Vector2=a+forward*step*42.0
			_world_line(canvas,at-forward*5,at+forward*5,projector,Color(.90,.88,.65,.55),clampf(pixels*.045,.6,1.3))

static func paint_crossings(canvas:CanvasItem,terrain:Dictionary,projector:Callable,detail:int)->void:
	if str(terrain.get("version",""))!="tactical-terrain-v4":return
	for feature in terrain.get("features",[]):
		if str(feature.get("kind",""))!="ford":continue
		_paint_surface(canvas,feature,projector,0)
		_route_edges(canvas,feature,projector,detail,true)
static func _occupied(point:Vector2,margin:float,town:Dictionary)->bool:
	for building in town.get("buildings",[]):
		var polygon:PackedVector2Array=points(building.get("footprint",[]))
		if polygon.size()>2 and Geometry2D.is_point_in_polygon(point,polygon):return true
	for road in town.get("roads",[]):
		var path:PackedVector2Array=points(road.get("points",[]))
		for i in range(path.size()-1):
			if point.distance_to(Geometry2D.get_closest_point_to_segment(point,path[i],path[i+1]))<float(road.get("width",18))*.5+margin:return true
	return false
