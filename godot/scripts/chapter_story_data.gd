extends RefCounted
## Authored fiction only. Chapters retain separate content versions and account progress.
static var cached:Dictionary={}
static var selected_chapter:String="chapter-01"
const FILES={"chapter-01":"chapter-one","chapter-02":"chapter-two","chapter-03":"chapter-three"}
static func data(chapter_id:String="")->Dictionary:
	var id:=selected_chapter if chapter_id.is_empty() else chapter_id
	if not FILES.has(id):return {}
	if not cached.has(id):
		var parsed:Variant=JSON.parse_string(FileAccess.get_file_as_string("res://data/%s.json"%FILES[id]))
		if not parsed is Dictionary:return {}
		cached[id]=parsed
		for node in parsed.get("scenes",[]):
			node["chapter_id"]=id
			var path:="res://data/chapter-scenes/%s.tres"%str(node.id)
			if ResourceLoader.exists(path):
				var visual:Resource=ResourceLoader.load(path)
				if visual!=null and visual.has_method("presentation") and str(visual.get("scene_id"))==str(node.id):node.merge(visual.presentation(),true)
	return cached[id]
static func chapter_for_stage(id:String)->String:
	for chapter_id in FILES:
		for node in data(chapter_id).get("scenes",[]):
			if str(node.get("stage",""))==id:return chapter_id
	return ""
static func chapter_for_node(id:String)->String:
	for chapter_id in FILES:
		for node in data(chapter_id).get("scenes",[]):
			if str(node.id)==id:return chapter_id
	return ""
static func background_path(node:Dictionary)->String:
	var direct:=str(node.get("background_asset",""))
	if ResourceLoader.exists(direct):return direct
	var setting:=str(node.get("background","day"))
	var path:="res://assets/story/chapter1/%s.png"%setting
	if setting=="sea_day":path="res://assets/backgrounds/recruit-sky.png"
	if ResourceLoader.exists(path):return path
	return "res://assets/backgrounds/night-sea-v2.png" if setting in ["night","silence","gate"] else "res://assets/backgrounds/harbor-day-v2.png"
static func speaker_name(line:Dictionary)->String:
	if line.has("name"):return str(line.name)
	var key:=str(line.get("speaker",""))
	return str(data("chapter-01").get("cast",{}).get(key,{}).get("name","旁白" if key.is_empty() else key))
static func scene(id:String)->Dictionary:
	for chapter_id in FILES:
		for node in data(chapter_id).get("scenes",[]):
			if str(node.id)==id:return node
	return {}
static func stage(id:String)->Dictionary:
	for chapter_id in FILES:
		for node in data(chapter_id).get("scenes",[]):
			if str(node.get("stage",""))==id:return node
	return {}
