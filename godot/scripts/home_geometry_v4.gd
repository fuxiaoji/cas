extends RefCounted
## One immutable native home preview. This adapter never persists or invents terrain.
const Core=preload("res://scripts/core_bridge.gd")
const VERSION:String="cas-island-war-v4"
var _home_ref:WeakRef
var home:
	get:return _home_ref.get_ref() if _home_ref!=null else null
var signature:String=""
var cached:Dictionary={}
var buildable_cells:Dictionary={}
var retry_at:int=0
func _init(owner)->void:_home_ref=weakref(owner)
func observe()->Dictionary:
	var source:Dictionary=home.state()
	var request:Dictionary={"op":"island_home_preview","version":VERSION,"seed":int(source.seed),"hq_level":home.development(true).level(),"buildings":source.buildings.duplicate(true)}
	var key:String=JSON.stringify(request)
	if key==signature and (cached.get("ok",false) or Time.get_ticks_msec()<retry_at):return cached
	var bridge=Core.new();var response:Dictionary=bridge.request(request);bridge.close()
	if not response.get("ok",false):
		signature=key;retry_at=Time.get_ticks_msec()+3000;cached={"ok":false,"message":str(response.get("error","岛屿地形准备中"))};return cached
	var view:Dictionary=response.get("data",response)
	var land:Dictionary=view.get("littoral",{}).get("land",{})
	var grid:Dictionary=view.get("construction_grid",{})
	if land.get("polygon",[]).size()<3 or grid.is_empty():return {"ok":false,"message":"原核尚未提供完整家园地形"}
	signature=key;cached={"ok":true,"version":VERSION,"width_m":float(view.get("island_war",{}).get("width_m",0)),"height_m":float(view.get("island_war",{}).get("height_m",0)),"land":land.duplicate(true),"placement":view.get("island_war",{}).get("placement",{}).duplicate(true),"construction_grid":grid.duplicate(true),"source_request":request}
	buildable_cells.clear()
	for cell in grid.get("buildable_cells",[]):
		if cell is Dictionary:buildable_cells[Vector2i(int(cell.get("x",0)),int(cell.get("y",0)))]=true
	return cached
func buildable(cell:Vector2i)->bool:
	var view:Dictionary=observe()
	return bool(view.get("ok",false)) and buildable_cells.has(cell)
func candidate(kind:String,cell:Vector2i)->Dictionary:
	var source:Dictionary=home.state();var bridge=Core.new()
	var response:Dictionary=bridge.request({"op":"island_home_preview","version":VERSION,"seed":int(source.seed),"hq_level":home.development(true).level(),"buildings":source.buildings.duplicate(true),"candidate":{"kind":kind,"cell":{"x":cell.x,"y":cell.y}}});bridge.close()
	if not response.get("ok",false):return home._fail(str(response.get("error","此处不能建设")))
	var view:Dictionary=response.get("data",response);var preview:Variant=view.get("candidate",view.get("placement_preview",{}))
	if not preview is Dictionary or not bool(preview.get("valid",false)):return home._fail(str(preview.get("reason","此处不能建设")) if preview is Dictionary else "此处不能建设")
	return {"ok":true,"preview":preview.duplicate(true)}
