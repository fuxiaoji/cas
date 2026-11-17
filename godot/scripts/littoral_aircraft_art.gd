@tool
extends RefCounted
## Actual public aircraft positions use their registered aircraft type, never a shipgirl SD.
static var catalogue:Dictionary={}
static var textures:Dictionary={}
static func display_name(type:String)->String:
	return str({"F4F":"野猫战斗机","SBD":"无畏俯冲机","TBD":"蹂躏者雷击机","A6M2":"零式战斗机","D3A2":"九九舰爆","B5N2":"九七舰攻","support_helicopter":"支援直升机","attack_helicopter":"武装直升机"}.get(type,type))
static func artwork(type:String)->Dictionary:
	if catalogue.is_empty() and FileAccess.file_exists("res://data/combined-arms-art-v4.json"):
		var raw:Variant=JSON.parse_string(FileAccess.get_file_as_string("res://data/combined-arms-art-v4.json"))
		if raw is Dictionary:catalogue=raw.get("aircraft",{})
	return catalogue.get(type,{})
static func paint(canvas:CanvasItem,row:Dictionary,at:Vector2,length:float,tick:float=0)->bool:
	var type:String=str(row.get("visual_type",row.get("kind","")));var entry:Dictionary=artwork(type)
	var path:String=str(entry.get("atlas",""))
	if path.is_empty() or not ResourceLoader.exists(path):return false
	if not textures.has(path):textures[path]=load(path)
	var texture:Texture2D=textures[path]
	var cell:Vector2=texture.get_size()/Vector2(float(entry.get("columns",4)),float(entry.get("rows",2)))
	var source:=Rect2(Vector2(float(entry.get("column",0)),float(entry.get("row",0)))*cell,cell)
	var dimensions:Vector2=cell/maxf(1,maxf(cell.x,cell.y))*length
	var tint:Color=Color.WHITE if str(row.get("side","allies"))=="allies" else Color("f1b39f")
	canvas.draw_set_transform(at,deg_to_rad(float(row.get("heading",0))))
	canvas.draw_texture_rect_region(texture,Rect2(-dimensions*.5,dimensions),source,tint)
	if type.contains("helicopter"):
		var blade:Vector2=Vector2.from_angle(tick*28+int(row.get("id",0)))*length*.23
		canvas.draw_line(-blade,blade,Color(.85,.94,.9,.46),1.7,true)
	canvas.draw_set_transform(Vector2.ZERO)
	return true
