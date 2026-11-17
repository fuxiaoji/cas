@tool
extends RefCounted
const BiomeArt=preload("res://scripts/littoral_biome_art.gd")
## Seeded visual terrain. The original polygon alone defines solid land.
## Height/moisture and coast distance are runtime data, never map photographs.
const ShoreField=preload("res://scripts/procedural_island.gd")
const Town=preload("res://scripts/procedural_town.gd")
const GroundMesh=preload("res://scripts/littoral_ground_mesh.gd")
const CACHE_LIMIT:int=24
const RESOLUTION:int=384
static var cache:Dictionary={}
static var order:Array[String]=[]
static var textures:Dictionary={}
static var generated_count:int=0
static var slope_mesh_cache:Dictionary={}
static var micro_texture:Texture2D
static var rock_face_texture:Texture2D

static func points(raw:Variant)->PackedVector2Array:
	if raw is PackedVector2Array:return raw
	var result:PackedVector2Array=[]
	if raw is Array:
		for value in raw:
			if value is Dictionary:result.append(Vector2(float(value.get("x",0)),float(value.get("y",0))))
			elif value is Vector2:result.append(value)
	return result

static func signature(polygon:PackedVector2Array,seed:int)->String:
	return str(seed)+":"+str(hash(polygon))

static func terrain_data(polygon:PackedVector2Array,seed:int)->Dictionary:
	if polygon.size()<3:return {}
	var key:String=signature(polygon,seed)
	if cache.has(key):return cache[key]
	var bounds:Rect2=Rect2(polygon[0],Vector2.ZERO)
	for point in polygon:bounds=bounds.expand(point)
	if minf(bounds.size.x,bounds.size.y)<.001:return {}
	var coast:Image=ShoreField._distance_field(polygon,bounds).get_image()
	# Distance is low frequency; refine the cached material without rebuilding shore geometry.
	var longest:int=maxi(coast.get_width(),coast.get_height())
	coast.resize(maxi(3,coast.get_width()*RESOLUTION/longest),maxi(3,coast.get_height()*RESOLUTION/longest),Image.INTERPOLATE_BILINEAR)
	var dimensions:Vector2i=Vector2i(coast.get_width(),coast.get_height())
	var heights:PackedFloat32Array=[];heights.resize(dimensions.x*dimensions.y)
	var elevation:=FastNoiseLite.new();elevation.seed=seed;elevation.noise_type=FastNoiseLite.TYPE_SIMPLEX_SMOOTH;elevation.frequency=3.0/maxf(bounds.size.x,bounds.size.y);elevation.fractal_octaves=4
	var moisture:=FastNoiseLite.new();moisture.seed=seed^0x4d32;moisture.noise_type=FastNoiseLite.TYPE_SIMPLEX_SMOOTH;moisture.frequency=elevation.frequency*1.8;moisture.fractal_octaves=3
	var grain:=FastNoiseLite.new();grain.seed=seed^0x7831;grain.noise_type=FastNoiseLite.TYPE_SIMPLEX_SMOOTH;grain.frequency=elevation.frequency*28;grain.fractal_octaves=2
	var image:=Image.create(dimensions.x,dimensions.y,false,Image.FORMAT_RGBA8)
	for y in range(dimensions.y):
		for x in range(dimensions.x):
			var world:Vector2=bounds.position+(Vector2(x,y)+Vector2(.5,.5))/Vector2(dimensions)*bounds.size
			var distance:float=coast.get_pixel(x,y).r
			var shape:float=elevation.get_noise_2dv(world)*.5+.5
			heights[y*dimensions.x+x]=smoothstep(0,.075,distance)*(.20+shape*.8)
	for y in range(dimensions.y):
		for x in range(dimensions.x):
			var index:int=y*dimensions.x+x;var height:float=heights[index]
			var world:Vector2=bounds.position+(Vector2(x,y)+Vector2(.5,.5))/Vector2(dimensions)*bounds.size
			var distance:float=coast.get_pixel(x,y).r
			var damp:float=moisture.get_noise_2dv(world)*.5+.5
			var dx:float=heights[y*dimensions.x+mini(x+1,dimensions.x-1)]-heights[y*dimensions.x+maxi(x-1,0)]
			var dy:float=heights[mini(y+1,dimensions.y-1)*dimensions.x+x]-heights[maxi(y-1,0)*dimensions.x+x]
			var light:float=clampf(.97-dx*1.5+dy*1.2,.86,1.08)
			var terrace:float=floorf(height*7)/7*.65+height*.35
			var grass:Color=Color("68ae78").lerp(Color("b1ce83"),clampf(terrace*.7+damp*.18,0,1))
			var dry:Color=Color("b9bd89").lerp(Color("9bba7e"),damp)
			grass=grass.lerp(dry,smoothstep(.63,.84,height)*.32)
			var slope:float=Vector2(dx,dy).length()
			var stone:Color=Color("889f8a").lerp(Color("c7c4a3"),height)
			grass=grass.lerp(stone,smoothstep(.048,.11,slope)*smoothstep(.075,.14,distance)*.8)
			# Damp tide line, warm dry sand and fine wind grain share the same
			# seeded coast field; no fixed beach image defines this geography.
			var sand:Color=Color("b6c7a2").lerp(Color("f1d8a3"),smoothstep(.001,.021,distance))
			sand=sand.lerp(Color("dac28e"),damp*.12)
			var color:Color=sand.lerp(grass,smoothstep(.012,.052,distance))
			var detail:float=grain.get_noise_2dv(world)
			color=color.lerp(Color("c5cb8c"),maxf(0,detail)*.13)
			color=color.lerp(Color("618e6a"),maxf(0,-detail)*.10)
			color=Color(color.r*light,color.g*light,color.b*light,1)
			image.set_pixel(x,y,color)
	image.generate_mipmaps()
	var texture:ImageTexture=ImageTexture.create_from_image(image)
	var rng:=RandomNumberGenerator.new();rng.seed=seed^hash(polygon)
	var decor:Array=[]
	var beach_details:Array=[]
	for attempt in range(900):
		var at:Vector2=bounds.position+Vector2(rng.randf(),rng.randf())*bounds.size
		if not Geometry2D.is_point_in_polygon(at,polygon):continue
		var uv:Vector2=(at-bounds.position)/bounds.size
		var shore:float=coast.get_pixel(clampi(int(uv.x*dimensions.x),0,dimensions.x-1),clampi(int(uv.y*dimensions.y),0,dimensions.y-1)).r
		if shore>.001 and shore<.045:beach_details.append({"at":at,"angle":rng.randf()*TAU,"size":rng.randf_range(1.8,5.2),"kind":attempt%4})
		if beach_details.size()>=150:break
	for attempt in range(300):
		var at:Vector2=bounds.position+Vector2(rng.randf(),rng.randf())*bounds.size
		if not Geometry2D.is_point_in_polygon(at,polygon):continue
		var uv:Vector2=(at-bounds.position)/bounds.size
		var shore:float=coast.get_pixel(clampi(int(uv.x*dimensions.x),0,dimensions.x-1),clampi(int(uv.y*dimensions.y),0,dimensions.y-1)).r
		if shore<.035:continue
		var wet:float=moisture.get_noise_2dv(at)*.5+.5
		var kind:String="tree_cluster" if wet>.38 and attempt%4==0 else "grass_patch"
		decor.append({"at":at,"kind":kind,"scale":rng.randf_range(.78,1.22)})
		if decor.size()>=140:break
	var data:Dictionary={"polygon":polygon.duplicate(),"bounds":bounds,"texture":texture,"height":heights,"dimensions":dimensions,"decor":decor,"beach_details":beach_details,"seed":seed}
	# A reusable 2m grain material adds close-view detail without a giant map
	# texture. Cell UVs stay in [0,1], so no texture-repeat state leaks into sprites.
	var micro_cells:Array=[];var cell_meters:float=256
	var grid_start:=Vector2(floorf(bounds.position.x/cell_meters),floorf(bounds.position.y/cell_meters))*cell_meters
	for row in range(ceili((bounds.end.y-grid_start.y)/cell_meters)):
		for column in range(ceili((bounds.end.x-grid_start.x)/cell_meters)):
			var a:Vector2=grid_start+Vector2(column,row)*cell_meters;var b:Vector2=a+Vector2.ONE*cell_meters
			var cell:PackedVector2Array=[a,Vector2(b.x,a.y),b,Vector2(a.x,b.y)]
			for clipped in Geometry2D.intersect_polygons(cell,polygon):
				if clipped.size()>=3:micro_cells.append({"points":clipped,"origin":a})
	data["micro_cells"]=micro_cells
	cache[key]=data;order.append(key);generated_count+=1
	while order.size()>CACHE_LIMIT:cache.erase(order.pop_front())
	return data

static func _texture(kind:String)->Texture2D:
	if not textures.has(kind):
		var path:String="res://assets/home/environment/"+kind+".png"
		if ResourceLoader.exists(path):
			var original:Texture2D=load(path);var region:Rect2i=original.get_image().get_used_rect()
			var cropped:=AtlasTexture.new();cropped.atlas=original;cropped.region=region;cropped.filter_clip=true;textures[kind]=cropped
		else:textures[kind]=null
	return textures[kind]

static func paint(target:CanvasItem,raw:Variant,projector:Callable,seed:int,tick:float,detail:int=2,protected:Array=[],town:Dictionary={},terrain:Dictionary={},flat_projector:Callable=Callable(),include_coast_motion:bool=true)->void:
	var polygon:PackedVector2Array=points(raw)
	if polygon.size()<3 or not projector.is_valid():return
	var data:Dictionary=terrain_data(polygon,seed)
	if data.is_empty():return
	var screen:PackedVector2Array=[];var uv:PackedVector2Array=[]
	for point in polygon:
		screen.append(projector.call(point));uv.append((point-data.bounds.position)/data.bounds.size)
	var center:Vector2=Vector2.ZERO
	for point in screen:center+=point
	center/=screen.size()
	var extent:float=0
	for point in screen:extent=maxf(extent,point.distance_to(center))
	# Soft turquoise bathymetry is water only, outside the unchanged solid polygon.
	for band in range(3,0,-1):
		for outline in Geometry2D.offset_polygon(screen,band*clampf(extent*.018,.8,4.0)):
			target.draw_colored_polygon(outline,Color(.20,.80,.72,.045))
	target.draw_polygon(screen,PackedColorArray([Color.WHITE]),uv,data.texture)
	if not terrain.is_empty():_elevation(target,terrain,projector,flat_projector,detail,data)
	if detail>=2:_paint_micro_ground(target,data,projector,flat_projector if str(terrain.get("version",""))=="tactical-terrain-v4" else Callable())
	BiomeArt.paint(target,terrain,projector,seed,detail,town,flat_projector)
	if not town.is_empty():Town.paint_ground(target,town,polygon,projector,detail,flat_projector if str(terrain.get("version",""))=="tactical-terrain-v4" else Callable())
	BiomeArt.paint_crossings(target,terrain,projector,detail)
	var closed:PackedVector2Array=screen.duplicate();closed.append(screen[0])
	target.draw_polyline(closed,Color("dce1b8"),1.4,true)
	if detail<=0:
		Town.paint_structures(target,town,projector,detail,flat_projector);return
	if include_coast_motion:paint_coast_motion(target,raw,projector,tick)
	if detail<2:
		Town.paint_structures(target,town,projector,detail,flat_projector);return
	for item in data.get("beach_details",[]):
		var at:Vector2=projector.call(item.at)
		var radius:float=at.distance_to(projector.call((item.at as Vector2)+Vector2(float(item.size),0)))
		if radius<.45:continue
		var direction:=Vector2.from_angle(float(item.angle))
		if int(item.kind)==0:
			target.draw_line(at-direction*radius*1.8,at+direction*radius*1.8,Color(.45,.38,.24,.42),maxf(.8,radius*.45),true)
		else:
			target.draw_circle(at+Vector2(.5,.7),radius,Color(.38,.37,.27,.25))
			target.draw_circle(at,radius*.82,Color("c7b992") if int(item.kind)==1 else Color("dce0bb"))
	for decoration in data.decor:
		if str(terrain.get("version","")) in ["tactical-terrain-v2","tactical-terrain-v4"] and decoration.kind=="tree_cluster":continue
		var world:Vector2=decoration.at;var at:Vector2=projector.call(world);var clear:bool=true
		var world_size:float=26.0 if decoration.kind=="tree_cluster" else 10.0
		for building in town.get("buildings",[]):
			if Geometry2D.is_point_in_polygon(world,points(building.get("footprint",[]))):clear=false;break
		for road in town.get("roads",[]):
			var line:PackedVector2Array=points(road.get("points",[]))
			for segment in range(line.size()-1):
				if world.distance_to(Geometry2D.get_closest_point_to_segment(world,line[segment],line[segment+1]))<float(road.get("width",110))*.8:clear=false;break
		for safe in protected:
			var safe_point:Vector2=Vector2(float(safe.get("x",0)),float(safe.get("y",0))) if safe is Dictionary else safe if safe is Vector2 else world
			if world.distance_to(safe_point)<world_size:clear=false;break
		if not clear:continue
		var texture:Texture2D=_texture(decoration.kind)
		if texture==null:continue
		var measure:Callable=flat_projector if flat_projector.is_valid() else projector
		var pixels:float=(measure.call(world) as Vector2).distance_to(measure.call(world+Vector2(world_size,0)))*float(decoration.scale)
		if pixels<.65:continue
		var dimensions:Vector2=Vector2(pixels,pixels*texture.get_height()/maxf(1,texture.get_width()))
		# Entire object must stay on land; scenery never creates new collision.
		if not Geometry2D.is_point_in_polygon(at+Vector2(-pixels*.42,-dimensions.y*.60),screen) or not Geometry2D.is_point_in_polygon(at+Vector2(pixels*.42,dimensions.y*.20),screen):continue
		target.draw_texture_rect(texture,Rect2(at-dimensions*Vector2(.5,.72),dimensions),false)
	Town.paint_structures(target,town,projector,detail,flat_projector)

static func _paint_micro_ground(target:CanvasItem,data:Dictionary,projector:Callable,flat_projector:Callable=Callable())->void:
	if micro_texture==null:
		var image:=Image.create(128,128,false,Image.FORMAT_RGBA8)
		var noise:=FastNoiseLite.new();noise.seed=915027;noise.frequency=.11;noise.fractal_octaves=3
		for y in range(128):
			for x in range(128):
				var n:float=noise.get_noise_2d(x,y);var dark:bool=n<0
				image.set_pixel(x,y,Color(.15,.23,.13,absf(n)*.15) if dark else Color(.97,.94,.75,n*.16))
		image.generate_mipmaps();micro_texture=ImageTexture.create_from_image(image)
	for cell in data.get("micro_cells",[]):
		var vertices:PackedVector2Array=[];var coords:PackedVector2Array=[]
		for point in cell.points:vertices.append(projector.call(point));coords.append((point-(cell.origin as Vector2))/256.0)
		if target is Control:
			var bounds:Rect2=Rect2(vertices[0],Vector2.ZERO)
			for point in vertices:bounds=bounds.expand(point)
			if not bounds.intersects(Rect2(Vector2.ZERO,target.size).grow(2),true):continue
		GroundMesh.paint(target,cell.points,projector,Color.WHITE,micro_texture,coords,flat_projector,8)

static func paint_coast_motion(target:CanvasItem,raw:Variant,projector:Callable,tick:float)->void:
	var polygon:PackedVector2Array=points(raw)
	if polygon.size()<3:return
	var screen:PackedVector2Array=[];var center:Vector2=Vector2.ZERO
	for point in polygon:
		var projected:Vector2=projector.call(point);screen.append(projected);center+=projected
	center/=screen.size()
	var extent:float=0
	for point in screen:extent=maxf(extent,point.distance_to(center))
	for index in range(screen.size()):
		var a:Vector2=screen[index];var b:Vector2=screen[(index+1)%screen.size()]
		var outward:Vector2=((a+b)*.5-center).normalized()
		for wave in range(2):
			var phase:float=fposmod(tick*.21+wave*.49+index*.041,1)
			var width:float=clampf(extent*.07,3,16)*(1-phase)
			var curve:PackedVector2Array=[]
			for segment in range(7):
				var blend:float=.12+segment*.115
				curve.append(a.lerp(b,blend)+outward*(width+sin(blend*PI)*1.4))
			target.draw_polyline(curve,Color(.87,1,.94,sin(phase*PI)*.30),1.0,true)

static func _elevation(target:CanvasItem,terrain:Dictionary,projector:Callable,flat_projector:Callable,detail:int,data:Dictionary)->void:
	if rock_face_texture==null:
		var image:=Image.create(128,64,false,Image.FORMAT_RGBA8)
		var noise:=FastNoiseLite.new();noise.seed=612015;noise.frequency=.075;noise.fractal_octaves=3
		for y in range(64):
			for x in range(128):
				var n:float=noise.get_noise_2d(x,y);var seam:float=absf(sin(x*.043+y*.071+n*1.6))
				var shade:float=.92+n*.10-(.06 if seam<.05 else 0)
				image.set_pixel(x,y,Color(shade,shade,shade,1))
		image.generate_mipmaps();rock_face_texture=ImageTexture.create_from_image(image)
	var zones:Array=terrain.get("elevation_zones",[]).duplicate()
	zones.sort_custom(func(a,b):return float(a.get("height_m",0))<float(b.get("height_m",0)))
	for zone in zones:
		var polygon:PackedVector2Array=points(zone.get("polygon",[]))
		if polygon.size()<3 or float(zone.get("height_m",0))<=0:continue
		if str(terrain.get("height_model",""))=="inset_edge_blend_v1":
			_blended_hill(target,zone,polygon,projector,detail,data)
			continue
		var top:PackedVector2Array=[];var foot:PackedVector2Array=[]
		var zone_projector:Callable=projector
		if str(terrain.get("version",""))=="tactical-terrain-v4" and flat_projector.is_valid():
			var scale:float=(flat_projector.call(polygon[0]+Vector2.RIGHT) as Vector2).distance_to(flat_projector.call(polygon[0]))
			var rise:float=float(zone.get("height_m",0))*scale
			# Sample the plateau's own top, including its boundary vertices.
			# A point-in-polygon test exactly on the rim may return the low side.
			zone_projector=func(point:Vector2)->Vector2:return flat_projector.call(point)-Vector2(0,rise)
		for point in polygon:
			top.append(zone_projector.call(point))
			foot.append(flat_projector.call(point) if flat_projector.is_valid() else projector.call(point))
		# A short contact shadow makes the raised terrain sit on the same ground
		# as the roads; this is lighting, never an additional terrain footprint.
		var height_px:float=0
		for index in range(top.size()):height_px=maxf(height_px,top[index].distance_to(foot[index]))
		if height_px>.4:
			var shadow:PackedVector2Array=[]
			for point in foot:shadow.append(point+Vector2(height_px*.21,height_px*.11))
			target.draw_colored_polygon(shadow,Color(.16,.29,.20,.13))
		# Native zones are the sole source for height. The side wall is a visual
		# exaggeration of that same elevation, never an extra collision polygon.
		for index in range(top.size()):
			var next:int=(index+1)%top.size()
			if top[index].distance_to(foot[index])<.25:continue
			var rock:Color=Color("b8ab83") if (foot[next]-foot[index]).x>0 else Color("748b71")
			var wall_texture:Texture2D=rock_face_texture
			if str(terrain.get("version",""))=="tactical-terrain-v4":
				wall_texture=BiomeArt.rock_face_material(int(data.get("seed",0))+index,polygon[index].distance_to(polygon[next]),float(zone.get("height_m",0)))
				rock=Color(1,.99,.93) if (foot[next]-foot[index]).x>0 else Color(.82,.90,.85)
			# Sloped polygon edges may project into a concave/degenerate quad.
			# These two authored triangles need no screen-space retriangulation.
			var wall_uv:Array[PackedVector2Array]=[PackedVector2Array([Vector2(0,1),Vector2(1,1),Vector2(1,0)]),PackedVector2Array([Vector2(0,1),Vector2(1,0),Vector2(0,0)])]
			var faces:Array[PackedVector2Array]=[PackedVector2Array([foot[index],foot[next],top[next]]),PackedVector2Array([foot[index],top[next],top[index]])]
			for face_index in range(2):
				var face:PackedVector2Array=faces[face_index]
				if absf((face[1]-face[0]).cross(face[2]-face[0]))>.001:target.draw_primitive(face,PackedColorArray([rock]),wall_uv[face_index],wall_texture)
			if detail>=2 and (foot[next]-foot[index]).x>0:
				target.draw_line(foot[index],foot[next],Color(.15,.28,.18,.28),1.2,true)
		var level:int=int(zone.get("level",1));var tint:Color=Color(1.03,1.02,.88) if level<=1 else Color(.95,1.03,.92)
		var uv:PackedVector2Array=[]
		for point in polygon:uv.append((point-data.bounds.position)/data.bounds.size)
		GroundMesh.paint(target,polygon,zone_projector,tint,data.texture,uv)
		# Keep only the sunlit lip. Drawing several closed contour strokes made
		# a plateau look like a flat UI badge rather than a mass of earth.
		if detail>=1:
			for index in range(top.size()):
				var next:int=(index+1)%top.size()
				if (foot[next]-foot[index]).x<0:target.draw_line(top[index],top[next],Color(.85,.90,.67,.45),.9,true)
	for ramp in terrain.get("ramps",[]):
		if str(terrain.get("version",""))=="tactical-terrain-v4":
			# V4 publishes a traversable polygon, not an old path centreline.
			# Its elevation zone above already paints the same authoritative land.
			continue
		var route:PackedVector2Array=points(ramp.get("points",[]))
		if route.size()<2:continue
		for segment in range(route.size()-1):
			var a:Vector2=route[segment];var b:Vector2=route[segment+1];var normal:Vector2=(b-a).normalized().orthogonal()*float(ramp.get("width",300))*.5
			if str(terrain.get("height_model",""))=="inset_edge_blend_v1":
				# Recommended walking trail on a continuous slope, not a solid
				# raised road or a fabricated collision wall.
				var previous:Vector2=projector.call(a)
				for step in range(1,13):
					var next:Vector2=projector.call(a.lerp(b,step/12.0))
					target.draw_line(previous,next,Color(.89,.81,.57,.60),2.4,true);previous=next
				continue
			var footprint:PackedVector2Array=[a-normal,b-normal,b+normal,a+normal];var visual:PackedVector2Array=[]
			for point in footprint:visual.append(projector.call(point))
			GroundMesh.paint(target,footprint,projector,Color("d8c59a"))
			target.draw_line(projector.call(a-normal),projector.call(b-normal),Color("ece0b7"),1.2,true)
			target.draw_line(projector.call(a+normal),projector.call(b+normal),Color("ece0b7"),1.2,true)

static func _blended_hill(target:CanvasItem,zone:Dictionary,polygon:PackedVector2Array,projector:Callable,detail:int,data:Dictionary)->void:
	var key:String=str(hash(polygon))
	if not slope_mesh_cache.has(key):
		var bounds:Rect2=Rect2(polygon[0],Vector2.ZERO)
		for point in polygon:bounds=bounds.expand(point)
		var shortest:float=maxf(1,minf(bounds.size.x,bounds.size.y))
		var columns:int=clampi(ceili(bounds.size.x/shortest*8),4,16);var rows:int=clampi(ceili(bounds.size.y/shortest*8),4,16)
		var cells:Array[PackedVector2Array]=[]
		for row in range(rows):
			for column in range(columns):
				var from:Vector2=bounds.position+bounds.size*Vector2(float(column)/columns,float(row)/rows)
				var to:Vector2=bounds.position+bounds.size*Vector2(float(column+1)/columns,float(row+1)/rows)
				var cell:PackedVector2Array=[from,Vector2(to.x,from.y),to,Vector2(from.x,to.y)]
				for clipped in Geometry2D.intersect_polygons(cell,polygon):
					if clipped.size()>=3:cells.append(clipped)
		if slope_mesh_cache.size()>=CACHE_LIMIT:slope_mesh_cache.erase(slope_mesh_cache.keys()[0])
		slope_mesh_cache[key]=cells
	var projected:Dictionary={};var tint:Color=Color(1.03,1.06,.92) if int(zone.get("level",1))==1 else Color(1.12,1.10,.94)
	for cell in slope_mesh_cache[key]:
		var vertices:PackedVector2Array=[];var uv:PackedVector2Array=[]
		for point in cell:
			if not projected.has(point):projected[point]=projector.call(point)
			vertices.append(projected[point]);uv.append((point-data.bounds.position)/data.bounds.size)
		GroundMesh.paint(target,cell,projector,tint,data.texture,uv)
	if detail<1:return
	for contour in Geometry2D.offset_polygon(polygon,-float(zone.get("blend_width_m",120))):
		if contour.size()<3:continue
		var top:PackedVector2Array=[]
		for point in contour:top.append(projector.call(point))
		top.append(top[0]);target.draw_polyline(top,Color(.46,.51,.29,.34),1,true)
