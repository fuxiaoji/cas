@tool
extends Resource
@export var version:String="tidebound-preview-2026-11-12"
@export var title:String="潮线档案"
@export_multiline var subtitle:String="沿着返航灯，读懂沉没的世界。"
@export var hero:Texture2D
@export var featured_art:Texture2D
@export var announcements:Array[Resource]=[]
func to_dictionary() -> Dictionary:
	var entries:Array=[]
	for row in announcements:
		if row!=null:entries.append({"title":str(row.title),"body":str(row.body)})
	return {"version":version,"title":title,"subtitle":subtitle,"hero":hero.resource_path if hero!=null else "","featured_art":featured_art.resource_path if featured_art!=null else "","announcements":entries}
