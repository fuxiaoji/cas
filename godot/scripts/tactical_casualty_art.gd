@tool
extends RefCounted
## Static, identity-specific loss poses, selected by the saved public pose seed.
static var catalogue:Dictionary={}
static var textures:Dictionary={}
static func _load()->void:
	if catalogue.is_empty() and FileAccess.file_exists("res://data/combined-arms-art-v4.json"):
		var raw:Variant=JSON.parse_string(FileAccess.get_file_as_string("res://data/combined-arms-art-v4.json"))
		if raw is Dictionary:catalogue=raw
static func lookup(row:Dictionary)->Dictionary:
	_load()
	var identity:String=str(row.get("unit_id",""))
	var entry:Dictionary=catalogue.get("casualties",{}).get(identity,{}) if str(row.get("side","axis"))=="allies" else catalogue.get("enemy_casualty",{})
	if entry.is_empty():return {}
	var frames:Array=entry.get("frames",[])
	if frames.is_empty():return {}
	var index:int=posmod(int(row.get("pose_seed",row.get("id",0))),frames.size())
	return {"atlas":str(entry.get("atlas","")),"region":frames[index].get("region",[]),"index":index,"identity":identity}
static func paint(canvas:CanvasItem,row:Dictionary,height:float,mirrored:bool=false)->bool:
	var frame:Dictionary=lookup(row)
	if frame.is_empty() or frame.region.size()!=4 or not ResourceLoader.exists(str(frame.atlas)):return false
	if not textures.has(frame.atlas):textures[frame.atlas]=load(str(frame.atlas))
	var texture:Texture2D=textures[frame.atlas];var raw:Array=frame.region
	var source:=Rect2(float(raw[0]),float(raw[1]),float(raw[2]),float(raw[3]))
	var dimensions:Vector2=source.size/maxf(1,maxf(source.size.x,source.size.y))*height*1.45
	var dest:=Rect2(-dimensions*.5,dimensions)
	if mirrored:dest.size.x=-dest.size.x
	canvas.draw_texture_rect_region(texture,dest,source)
	return true
static func paint_land_enemy(canvas:CanvasItem,row:Dictionary,column:int,height:float,mirrored:bool=false)->bool:
	_load()
	var entry:Dictionary=catalogue.get("land_enemies",{}).get(str(row.get("kind","")),{})
	if entry.is_empty() or not ResourceLoader.exists(str(entry.get("atlas",""))):return false
	var path:String=str(entry.atlas)
	if not textures.has(path):textures[path]=load(path)
	var texture:Texture2D=textures[path]
	var cell:Vector2=texture.get_size()/Vector2(float(entry.get("columns",4)),float(entry.get("rows",4)))
	var source:=Rect2(Vector2(clampi(column,0,3),int(entry.get("row",0)))*cell,cell)
	var dest:=Rect2(Vector2(-height*.55,-height*.9),Vector2(height*1.1,height*1.1))
	if mirrored:dest.size.x=-dest.size.x
	canvas.draw_texture_rect_region(texture,dest,source);return true
