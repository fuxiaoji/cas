@tool
extends RefCounted
## The authored 2026-11-14 canon is independent of the frozen v1 story.
const IDS:Array[String]=["chapter-01","chapter-02","chapter-03"]
static var cache:Dictionary={}
static func chapter(id:String)->Dictionary:
	if not IDS.has(id):return {}
	if not cache.has(id):
		var path:String="res://data/story-canon-v2/%s.json"%id
		if not FileAccess.file_exists(path):return {}
		var value:Variant=JSON.parse_string(FileAccess.get_file_as_string(path))
		if not value is Dictionary:return {}
		preload("res://scripts/canon_tactical_v3.gd").enrich(value)
		cache[id]=value
	return cache[id]
static func scene(chapter_id:String,node_id:String)->Dictionary:
	for node in chapter(chapter_id).get("scenes",[]):
		if str(node.get("id",""))==node_id:return node
	return {}
static func action(node:Dictionary)->String:
	return str(node.get("action_type",node.get("action",{}).get("type","native_battle" if str(node.get("kind",""))=="battle" else "")))
static func objective(node:Dictionary)->String:
	var direct:String=str(node.get("objective",""))
	if not direct.is_empty():return direct
	var goals:Array=node.get("objectives",[])
	return str(goals[0]) if not goals.is_empty() else str(node.get("title","请完成当前实际操作，再回来继续故事。"))
static func seed(node:Dictionary)->int:
	# Authored lessons use the registered, already exercised teaching seeds.
	# An explicit chapter node seed always takes precedence.
	return int(node.get("seed",42 if action(node) in ["littoral_sea","littoral_landing","littoral_combined","island_defense"] else 6109))
static func background(node:Dictionary,line:Dictionary={})->String:
	for path in [line.get("cg_asset",""),node.get("background_asset",""),node.get("cg_asset","")]:
		if not str(path).is_empty() and ResourceLoader.exists(str(path)):return str(path)
	return "res://assets/backgrounds/night-sea-v2.png" if str(node.get("background","day")) in ["night","storm","court","silence"] else "res://assets/backgrounds/harbor-day-v2.png"
