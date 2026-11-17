extends RefCounted
## Repositions original-mode targets onto real, native-approved construction plots.
## Historical scenarios and already saved operations never pass through this adapter.
const Settings=preload("res://scripts/coastal_map_settings.gd")
const Core=preload("res://scripts/core_bridge.gd")
const DATA:String="res://data/island-war-v4-published.json"
static var previews:Dictionary={}

static func adapt(source:Dictionary)->Dictionary:
	var request:Dictionary=source.duplicate(true)
	request.version=Settings.VERSION;request["geography"]=Settings.geography()
	# New operations explicitly opt in; an existing operation/replay keeps its tuning.
	request["coastal_tuning"]=Settings.COMBAT_TUNING
	var island:Dictionary=request.get("island",{})
	if not island.get("forts",[]).is_empty():return {"ok":true,"request":request}
	var catalogue:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(DATA))
	var targets:Array=catalogue.get("islands",[])
	if targets.is_empty():return {"ok":false,"message":"海岸行动目标尚未就绪"}
	var target:Dictionary=targets[0]
	for row:Dictionary in targets:
		if str(row.id)==str(island.get("npc_id","")):target=row;break
	var level:int=clampi(int(island.get("island_level",1)),1,5)
	if not previews.has(level):
		var core=Core.new()
		var reply:Dictionary=core.request({"op":"island_home_preview","version":Settings.VERSION,"seed":714,"hq_level":level,"buildings":[],"geography":Settings.geography()})
		core.close()
		if not reply.get("ok",false):return {"ok":false,"message":str(reply.get("error","海岸地理尚未就绪"))}
		previews[level]=reply.data
	var preview:Dictionary=previews[level]
	var grid:Dictionary=preview.construction_grid
	var origin:=Vector2(float(grid.origin.x),float(grid.origin.y))
	var spacing:float=float(grid.cell_size_m)
	var corner:Dictionary=preview.island_war.placement.origin
	var dimensions:=Vector2(float(preview.island_war.placement.width_m),float(preview.island_war.placement.height_m))
	var cells:Array=grid.buildable_cells.duplicate()
	var world:Callable=func(c:Dictionary)->Vector2:return origin+(Vector2(float(c.x),float(c.y))+Vector2(.5,.5))*spacing
	cells.sort_custom(func(a,b):return world.call(a).distance_squared_to(Vector2(14600,13045))<world.call(b).distance_squared_to(Vector2(14600,13045)))
	var occupied:Array[Vector2]=[]
	var forts:Array=[]
	for original:Dictionary in target.forts:
		var found:bool=false
		for cell:Dictionary in cells:
			var point:Vector2=world.call(cell)
			if occupied.any(func(p:Vector2):return p.distance_to(point)<70):continue
			var fort:Dictionary=original.duplicate(true)
			var position:Vector2=(point-Vector2(float(corner.x),float(corner.y)))/dimensions
			fort.x=position.x;fort.y=position.y;forts.append(fort);occupied.append(point);found=true;break
		if not found:return {"ok":false,"message":"该岛屿的合法建设空间不足，请选择较小规模的行动"}
	island["forts"]=forts;request["island"]=island
	return {"ok":true,"request":request}
