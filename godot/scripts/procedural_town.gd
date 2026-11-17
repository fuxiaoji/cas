@tool
extends RefCounted
const GroundMesh=preload("res://scripts/littoral_ground_mesh.gd")
## Streets and buildings come from the native town record. This creates no walls.
const MANIFEST:String="res://data/coastal-town-art-v4.json"
static var manifest:Dictionary={}
static var art:Dictionary={}

static func _points(raw:Variant)->PackedVector2Array:
	var result:PackedVector2Array=[]
	if raw is PackedVector2Array:return raw
	if raw is Array:
		for point in raw:
			if point is Vector2:result.append(point)
			elif point is Dictionary:result.append(Vector2(float(point.get("x",0)),float(point.get("y",0))))
	return result

static func _project(points:PackedVector2Array,projector:Callable)->PackedVector2Array:
	var output:PackedVector2Array=[]
	for point in points:output.append(projector.call(point))
	return output

static func _corridor(a:Vector2,b:Vector2,width:float)->PackedVector2Array:
	var normal:Vector2=(b-a).normalized().orthogonal()*width*.5
	return PackedVector2Array([a-normal,b-normal,b+normal,a+normal])

static func _clipped(target:CanvasItem,polygon:PackedVector2Array,shore:PackedVector2Array,projector:Callable,color:Color,flat_projector:Callable=Callable(),edge_m:float=128)->void:
	for piece in Geometry2D.intersect_polygons(polygon,shore):
		if piece.size()>=3:GroundMesh.paint(target,piece,projector,color,null,PackedVector2Array(),flat_projector,8,edge_m)

static func _art(group:String,index:int)->Texture2D:
	if manifest.is_empty() and FileAccess.file_exists(MANIFEST):
		var raw:Variant=JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
		if raw is Dictionary:manifest=raw
	var rows:Array=manifest.get(group,[])
	if rows.is_empty():return null
	var key:String=group+":"+str(posmod(index,rows.size()))
	if not art.has(key):
		var row:Dictionary=rows[posmod(index,rows.size())];var path:String=str(row.get("atlas",""))
		if not ResourceLoader.exists(path):return null
		var texture:Texture2D=load(path);var region:Array=row.get("region",[])
		if region.size()!=4:return null
		var cutout:=AtlasTexture.new();cutout.atlas=texture;cutout.region=Rect2(region[0],region[1],region[2],region[3]);cutout.filter_clip=true;art[key]=cutout
	return art[key]

static func paint_ground(target:CanvasItem,town:Dictionary,shore:PackedVector2Array,projector:Callable,detail:int,flat_projector:Callable=Callable())->void:
	if not flat_projector.is_valid():_paved_district(target,town,shore,projector,detail)
	for road in town.get("roads",[]):
		var points:PackedVector2Array=_points(road.get("points",[]));var width:float=float(road.get("width",110))
		for segment in range(points.size()-1):
			var a:Vector2=points[segment];var b:Vector2=points[segment+1]
			_clipped(target,_corridor(a,b,width*1.27),shore,projector,Color("c9d8c7"),flat_projector,24 if flat_projector.is_valid() else 128)
			_clipped(target,_corridor(a,b,width),shore,projector,Color("607c86"),flat_projector,24 if flat_projector.is_valid() else 128)
			if detail<1 or projector.call(a).distance_to(projector.call(a+Vector2(width,0)))<5:continue
			var direction:Vector2=(b-a).normalized();var length:float=a.distance_to(b);var spacing:float=maxf(25,width*.65)
			for dash in range(int(length/spacing)):
				var from:Vector2=a+direction*(dash*spacing+spacing*.15);var to:Vector2=from+direction*(spacing*.38)
				if Geometry2D.is_point_in_polygon(from,shore) and Geometry2D.is_point_in_polygon(to,shore):
					if flat_projector.is_valid():
						var h0:float=(flat_projector.call(from) as Vector2).y-(projector.call(from) as Vector2).y
						var h1:float=(flat_projector.call(to) as Vector2).y-(projector.call(to) as Vector2).y
						if absf(h0-h1)>1:continue
					target.draw_line(projector.call(from),projector.call(to),Color("e8d59b"),1.2,true)
	for building in town.get("buildings",[]):
		var footprint:PackedVector2Array=_points(building.get("footprint",[]))
		if footprint.size()<3:continue
		var frontage:float=footprint[0].distance_to(footprint[1])
		for yard in Geometry2D.offset_polygon(footprint,minf(12,frontage*.18)):_clipped(target,yard,shore,projector,Color("dbd9ba"),flat_projector,24 if flat_projector.is_valid() else 128)
		_clipped(target,footprint,shore,projector,Color("d5d8bb"),flat_projector,24 if flat_projector.is_valid() else 128)

static func _paved_district(target:CanvasItem,town:Dictionary,shore:PackedVector2Array,projector:Callable,detail:int)->void:
	var vertical:Array[float]=[];var horizontal:Array[float]=[];var bounds:Rect2;var initialized:bool=false;var street_width:float=600
	for road in town.get("roads",[]):
		var points:PackedVector2Array=_points(road.get("points",[]))
		street_width=float(road.get("width",600))
		for point in points:
			if not initialized:bounds=Rect2(point,Vector2.ZERO);initialized=true
			else:bounds=bounds.expand(point)
		if points.size()<2:continue
		if absf(points[0].x-points[-1].x)<1:vertical.append(points[0].x)
		if absf(points[0].y-points[-1].y)<1:horizontal.append(points[0].y)
	if not initialized:return
	# The district follows the native street extent. These traversable paving
	# materials add no structure, target or collision to the native simulation.
	bounds=bounds.grow(street_width*.6)
	var district:PackedVector2Array=[bounds.position,Vector2(bounds.end.x,bounds.position.y),bounds.end,Vector2(bounds.position.x,bounds.end.y)]
	# A kilometre-wide street extent is not a kilometre-wide concrete slab.
	# Keep the seeded terrain visible between actual building plots.
	_clipped(target,district,shore,projector,Color(.70,.79,.64,.10))
	vertical.sort();horizontal.sort()
	for column in range(vertical.size()-1):
		for row in range(horizontal.size()-1):
			var inset:float=street_width*.68
			var from:Vector2=Vector2(vertical[column]+inset,horizontal[row]+inset)
			var to:Vector2=Vector2(vertical[column+1]-inset,horizontal[row+1]-inset)
			if to.x<=from.x or to.y<=from.y:continue
			var block:PackedVector2Array=[from,Vector2(to.x,from.y),to,Vector2(from.x,to.y)]
			var colors:Array[Color]=[Color("d7d6b5"),Color("cad2ab"),Color("e1d5b2"),Color("bcc99b")]
			var occupied:bool=false
			for building in town.get("buildings",[]):
				var footprint:PackedVector2Array=_points(building.get("footprint",[]))
				if footprint.size()>0 and Geometry2D.is_point_in_polygon(footprint[0],block):occupied=true;break
			if not occupied:continue
			var tint:Color=colors[posmod(column+row*3,4)];tint.a=.16
			_clipped(target,block,shore,projector,tint)
			if detail<2:continue
			# Fine paving seams follow the same world basis as the street grid.
			for seam in range(1,4):
				var y:float=lerpf(from.y,to.y,seam*.25)
				if (to-from).length()<300:target.draw_line(projector.call(Vector2(from.x,y)),projector.call(Vector2(to.x,y)),Color(.43,.49,.39,.15),.65,true)

static func paint_structures(target:CanvasItem,town:Dictionary,projector:Callable,detail:int,flat_projector:Callable=Callable())->void:
	var rows:Array=[]
	for building in town.get("buildings",[]):
		var points:PackedVector2Array=_points(building.get("footprint",[]))
		if points.size()<3:continue
		var screen:PackedVector2Array=_project(points,projector);var bounds:Rect2=Rect2(screen[0],Vector2.ZERO)
		for point in screen:bounds=bounds.expand(point)
		rows.append({"record":building,"footprint":points,"screen":screen,"bounds":bounds,"depth":bounds.end.y})
	rows.sort_custom(func(a,b):return float(a.depth)<float(b.depth))
	for row in rows:
		var building:Dictionary=row.record;var screen:PackedVector2Array=row.screen;var bounds:Rect2=row.bounds
		if detail<=0:target.draw_colored_polygon(screen,Color("f2cd9d"));continue
		if bounds.size.x<2:target.draw_colored_polygon(screen,Color("e4b17d"));continue
		var shift:Vector2=Vector2(bounds.size.x*.12,bounds.size.x*.11)
		var shadow:PackedVector2Array=[]
		for point in screen:shadow.append(point+shift)
		target.draw_colored_polygon(shadow,Color(.12,.30,.33,.25))
		var index:int=int(building.get("art_variant",abs(hash(str(building.get("id",""))))))
		var texture:Texture2D=_art("buildings",index)
		if texture!=null:
			var width:float=bounds.size.x*1.08;var dimensions:Vector2=Vector2(width,width*texture.get_height()/maxf(1,texture.get_width()))
			target.draw_texture_rect(texture,Rect2(Vector2(bounds.get_center().x,bounds.end.y)-dimensions*Vector2(.5,1),dimensions),false)
		else:_building_volume(target,screen,int(building.get("floors",2)),index)
	# Native placement records may include street props; purely decorative props
	# are never manufactured by the renderer on top of walkable combat targets.
	for prop in town.get("props",[]):
		var world:Vector2=Vector2(float(prop.get("x",0)),float(prop.get("y",0)));var at:Vector2=projector.call(world)
		var texture:Texture2D=_art("props",int(prop.get("variant",0)))
		if texture!=null:
			var measure:Callable=flat_projector if flat_projector.is_valid() else projector
			var width:float=(measure.call(world) as Vector2).distance_to(measure.call(world+Vector2(float(prop.get("width_m",4)),0)))
			if width<.6:continue
			var dimensions:Vector2=Vector2(width,width*texture.get_height()/maxf(1,texture.get_width()))
			target.draw_texture_rect(texture,Rect2(at-dimensions*Vector2(.5,.9),dimensions),false)
	if detail>=2:_roadside_props(target,town,projector,flat_projector)

static func _roadside_props(target:CanvasItem,town:Dictionary,projector:Callable,flat_projector:Callable=Callable())->void:
	# Dressing follows the native street grid. It is non-solid scenery; buildings
	# alone use the public solid footprints. Body/command nodes render above it.
	var index:int=0
	for road in town.get("roads",[]):
		var points:PackedVector2Array=_points(road.get("points",[]));var width:float=float(road.get("width",110))
		for segment in range(points.size()-1):
			var a:Vector2=points[segment];var b:Vector2=points[segment+1];var direction:Vector2=(b-a).normalized();var distance:float=a.distance_to(b);var spacing:float=width*2.5
			for step in range(1,int(distance/spacing)):
				var side:float=-1.0 if step%2==0 else 1.0
				var world:Vector2=a+direction*(step*spacing)+direction.orthogonal()*width*.70*side
				var overlaps:bool=false
				for building in town.get("buildings",[]):
					if Geometry2D.is_point_in_polygon(world,_points(building.get("footprint",[]))):overlaps=true;break
				if overlaps:continue
				var variant:int=[0,2,1,3,4,2,0,5][posmod(index,8)];index+=1
				var texture:Texture2D=_art("props",variant)
				if texture==null:continue
				var meters:float={0:10.0,1:8.0,2:2.2,3:3.0,4:3.8,5:6.0}.get(variant,4.0)
				var at:Vector2=projector.call(world);var measure:Callable=flat_projector if flat_projector.is_valid() else projector
				var visual_width:float=(measure.call(world) as Vector2).distance_to(measure.call(world+Vector2(meters,0)))
				if visual_width<.6:continue
				var dimensions:Vector2=Vector2(visual_width,visual_width*texture.get_height()/maxf(1,texture.get_width()))
				target.draw_texture_rect(texture,Rect2(at-dimensions*Vector2(.5,.95),dimensions),false)

static func _building_volume(target:CanvasItem,screen:PackedVector2Array,floors:int,variant:int)->void:
	if screen.size()!=4:return
	var bounds:Rect2=Rect2(screen[0],Vector2.ZERO)
	for point in screen:bounds=bounds.expand(point)
	var rise:Vector2=Vector2(0,-maxf(8,bounds.size.x*(.16+.10*floors)))
	var roof:PackedVector2Array=[]
	for point in screen:roof.append(point+rise)
	var walls:Array[Color]=[Color("fff0c9"),Color("e1c891"),Color("c5d8c2"),Color("c9b897")]
	var order:Array=[0,1,2,3];order.sort_custom(func(a,b):return (screen[a].y+screen[(a+1)%4].y)<(screen[b].y+screen[(b+1)%4].y))
	for face in order:
		var next:int=(face+1)%4;var wall:PackedVector2Array=[screen[face],screen[next],roof[next],roof[face]]
		target.draw_colored_polygon(wall,walls[posmod(face+variant,4)])
		var across:int=clampi(int(screen[face].distance_to(screen[next])/12),2,7)
		for floor_index in range(maxi(1,floors)):
			for window in range(1,across):
				var center:Vector2=screen[face].lerp(screen[next],float(window)/across)+rise*(.20+.65*float(floor_index+1)/maxi(1,floors))
				target.draw_rect(Rect2(center-Vector2(1.7,2.1),Vector2(3.4,4.2)),Color("426d7b"))
	var color:Color=[Color("e6854c"),Color("e9ba6d"),Color("69a9a9"),Color("de7352")][posmod(variant,4)]
	target.draw_colored_polygon(roof,color)
	var closed:PackedVector2Array=roof.duplicate();closed.append(roof[0]);target.draw_polyline(closed,Color("f5dfb7"),1.2,true)
