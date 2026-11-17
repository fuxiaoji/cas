extends RefCounted
## New home island: the approved procedural Demo is validated by the simulation.
const Core=preload("res://scripts/core_bridge.gd")
const Settings=preload("res://scripts/coastal_map_settings.gd")
var _home_ref:WeakRef
var home:
	get:return _home_ref.get_ref() if _home_ref!=null else null
var signature:String=""
var cached:Dictionary={}
var buildable_cells:Dictionary={}
func _init(owner)->void:_home_ref=weakref(owner)
func _request()->Dictionary:
	var source:Dictionary=home.state()
	return {"op":"island_home_preview","version":Settings.VERSION,"geography":Settings.geography(),"seed":714,"hq_level":home.development(true).level(),"buildings":source.buildings.duplicate(true)}
func observe()->Dictionary:
	var request:Dictionary=_request()
	var key:String=JSON.stringify([request.hq_level,request.buildings])
	if key==signature and cached.get("ok",false):return cached
	var bridge=Core.new();var response:Dictionary=bridge.request(request);bridge.close()
	if not response.get("ok",false):return {"ok":false,"message":str(response.get("error","新海岸尚未准备好"))}
	var view:Dictionary=response.get("data",response)
	var land:Dictionary=view.get("littoral",{}).get("land",{})
	var grid:Dictionary=view.get("construction_grid",{})
	if land.get("polygon",[]).size()<3 or grid.is_empty():return {"ok":false,"message":"新海岸地理不完整"}
	signature=key;cached={"ok":true,"version":Settings.VERSION,"width_m":float(view.get("island_war",{}).get("width_m",720)),"height_m":float(view.get("island_war",{}).get("height_m",720)),"land":land.duplicate(true),"placement":view.get("island_war",{}).get("placement",{}).duplicate(true),"construction_grid":grid.duplicate(true)}
	buildable_cells.clear()
	for cell:Dictionary in grid.get("buildable_cells",[]):buildable_cells[Vector2i(int(cell.x),int(cell.y))]=true
	return cached
func buildable(cell:Vector2i)->bool:
	return observe().get("ok",false) and buildable_cells.has(cell)
func candidate(kind:String,cell:Vector2i)->Dictionary:
	var request:Dictionary=_request();request["candidate"]={"kind":kind,"cell":{"x":cell.x,"y":cell.y}}
	var bridge=Core.new();var response:Dictionary=bridge.request(request);bridge.close()
	if not response.get("ok",false):return home._fail(str(response.get("error","此处不能建设")))
	var preview:Dictionary=response.get("data",{}).get("candidate",{})
	return {"ok":true,"preview":preview} if preview.get("valid",false) else home._fail(str(preview.get("reason","此处不能建设")))
