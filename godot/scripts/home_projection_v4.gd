extends RefCounted
## Presentation projection of the native metre map, shared by picking and painting.
const Terrain=preload("res://scripts/procedural_amphibious_terrain.gd")
var land:Dictionary={}
var grid:Dictionary={}
var legal:Dictionary={}
var cells:Array=[]
var world_frame:Rect2=Rect2(0,0,1,1)
var screen:Rect2=Rect2(0,0,1,1)
var zones:Array=[]
var ramps:Array=[]
var heights:Array[float]=[0.0]
var resident_routes:Dictionary={}
var coastal_walks:Array[PackedVector2Array]=[]
func bind(source:Dictionary)->void:
	land=source.get("land",{});grid=source.get("construction_grid",{});legal.clear();cells=[];zones=[];ramps=[];heights=[0.0];resident_routes.clear()
	coastal_walks.clear()
	for raw in grid.get("buildable_cells",[]):
		var cell:=Vector2i(int(raw.get("x",0)),int(raw.get("y",0)));legal[cell]=true;cells.append(cell)
	var points:PackedVector2Array=Terrain.points(land.get("polygon",[]))
	if points.is_empty():return
	world_frame=Rect2(iso(points[0]),Vector2.ZERO)
	for point in points:world_frame=world_frame.expand(iso(point))
	var terrain:Dictionary=land.get("terrain",{});var levels:Dictionary={0:0.0}
	if str(land.get("geography",{}).get("version",""))=="cas-coastal-geography-v1":_build_coastal_walks(terrain)
	for raw in terrain.get("elevation_zones",[]):
		var shape:PackedVector2Array=Terrain.points(raw.get("polygon",[]));var h:float=float(raw.get("height_m",0));var level:int=int(raw.get("level",0));levels[level]=h
		zones.append({"polygon":shape,"height":h,"level":level,"blend":float(raw.get("blend_width_m",120))})
		if not heights.has(h):heights.append(h)
		for point in shape:world_frame=world_frame.expand(iso(point)-Vector2(0,h))
	for raw in terrain.get("ramps",[]):
		var path:PackedVector2Array=Terrain.points(raw.get("points",[]));var segments:Array=[];var distance:float=0
		for index in range(path.size()-1):segments.append({"a":path[index],"b":path[index+1],"start":distance});distance+=path[index].distance_to(path[index+1])
		ramps.append({"segments":segments,"length":distance,"radius":float(raw.get("width",0))*.5,"from":float(levels.get(int(raw.get("from_level",0)),0)),"to":float(levels.get(int(raw.get("to_level",0)),0))})
func iso(p:Vector2)->Vector2:return Vector2(.866025403784*(p.x+p.y),.5*(p.x-p.y))
func scale()->float:return minf(screen.size.x/maxf(1,world_frame.size.x),screen.size.y/maxf(1,world_frame.size.y))
func flat(p:Vector2)->Vector2:return screen.get_center()+(iso(p)-world_frame.get_center())*scale()
func height(p:Vector2)->float:
	var result:float=0;var level:int=-1;var blended:bool=str(land.get("terrain",{}).get("height_model",""))=="inset_edge_blend_v1"
	for zone in zones:
		if not Geometry2D.is_point_in_polygon(p,zone.polygon):continue
		if blended:
			var distance:float=INF;var polygon:PackedVector2Array=zone.polygon
			for index in range(polygon.size()):distance=minf(distance,p.distance_to(Geometry2D.get_closest_point_to_segment(p,polygon[index],polygon[(index+1)%polygon.size()])))
			result=maxf(result,float(zone.height)*clampf(distance/maxf(.001,float(zone.blend)),0,1))
		elif int(zone.level)>=level:result=float(zone.height);level=int(zone.level)
	if not blended:
		for ramp in ramps:
			for segment in ramp.segments:
				var delta:Vector2=segment.b-segment.a;var fraction:float=(p-segment.a).dot(delta)/maxf(.001,delta.length_squared())
				if fraction>=0 and fraction<=1 and p.distance_to(segment.a+delta*fraction)<=float(ramp.radius):return lerpf(float(ramp.from),float(ramp.to),(float(segment.start)+delta.length()*fraction)/maxf(.001,float(ramp.length)))
	return result
func project(p:Vector2)->Vector2:return flat(p)-Vector2(0,height(p)*scale())
func unproject_flat(p:Vector2)->Vector2:
	var raw:Vector2=world_frame.get_center()+(p-screen.get_center())/maxf(.0001,scale())
	return Vector2(raw.x/(2*.866025403784)+raw.y,raw.x/(2*.866025403784)-raw.y)
func unproject(p:Vector2)->Vector2:
	var ordered:Array[float]=heights.duplicate();ordered.sort();ordered.reverse()
	for initial in ordered:
		var candidate:Vector2=unproject_flat(p+Vector2(0,initial*scale()))
		for iteration in range(12):candidate=unproject_flat(p+Vector2(0,height(candidate)*scale()))
		if project(candidate).distance_to(p)<.1:return candidate
	return unproject_flat(p)
func world(cell:Vector2)->Vector2:
	var origin:Dictionary=grid.get("origin",{})
	return Vector2(float(origin.get("x",0)),float(origin.get("y",0)))+(cell+Vector2(.5,.5))*float(grid.get("cell_size_m",1))
func cell_at(p:Vector2)->Vector2i:
	var origin:Dictionary=grid.get("origin",{});var raw:Vector2=(unproject(p)-Vector2(float(origin.get("x",0)),float(origin.get("y",0))))/maxf(1,float(grid.get("cell_size_m",1)))
	return Vector2i(int(floor(raw.x)),int(floor(raw.y)))
func tile(cell:Vector2i)->PackedVector2Array:
	var center:Vector2=world(Vector2(cell));var half:float=float(grid.get("cell_size_m",1))*.48
	return PackedVector2Array([project(center+Vector2(-half,-half)),project(center+Vector2(half,-half)),project(center+Vector2(half,half)),project(center+Vector2(-half,half)),project(center+Vector2(-half,-half))])
func resident(index:int,naval:bool,progress:float)->Vector2:
	if cells.is_empty():return screen.get_center()
	return project(resident_world(index,naval,progress))
func resident_world(index:int,naval:bool,progress:float)->Vector2:
	if cells.is_empty():return Vector2.ZERO
	if not coastal_walks.is_empty():
		var path:PackedVector2Array=coastal_walks[posmod(index*7+(3 if naval else 0),coastal_walks.size())]
		var along:float=clampf(progress,0,1)*(path.size()-1)
		var step:int=mini(floori(along),path.size()-2)
		return path[step].lerp(path[step+1],along-step)
	var key:String=str(index)+":"+str(naval)
	if resident_routes.has(key):
		var route:Array=resident_routes[key];return world(Vector2(route[0]).lerp(Vector2(route[1]),progress))
	var desired:Vector2i=Vector2i(6,4)+Vector2i(index%3-1,(int(index/3)+1)*(1 if naval else -1))
	var start:Vector2i=desired
	if not legal.has(start):
		var nearest:float=INF
		for candidate in cells:
			var distance:float=Vector2(candidate-desired).length_squared()
			if distance<nearest:start=candidate;nearest=distance
	var finish:Vector2i=start
	for step in [Vector2i.RIGHT,Vector2i.DOWN,Vector2i.LEFT,Vector2i.UP]:
		if legal.has(start+step):finish=start+step;break
	resident_routes[key]=[start,finish]
	return world(Vector2(start).lerp(Vector2(finish),progress))

func _build_coastal_walks(terrain:Dictionary)->void:
	# Cosmetic residents walk along authoritative roads, never through the centres
	# of occupied construction plots. These paths do not issue combat commands.
	for road:Dictionary in terrain.get("roads",[]):
		var run:PackedVector2Array=[]
		for raw:Dictionary in road.get("points",[]):
			var at:=Vector2(float(raw.x),float(raw.y));var safe:bool=at.distance_to(Vector2(14600,13065))<180.0
			for building:Dictionary in land.get("buildings",[]):
				if at.distance_to(Vector2(float(building.x),float(building.y)))<17.0:safe=false;break
			if not safe:
				if run.size()>=6:coastal_walks.append(run)
				run=[];continue
			run.append(at)
			if run.size()>=15:coastal_walks.append(run);run=PackedVector2Array([at])
		if run.size()>=6:coastal_walks.append(run)
