extends RefCounted
const Art=preload("res://scripts/character_art.gd")
## Real, cancellable-by-generation resource preparation. Resources remain pinned
## until the incoming page owns them; no clock or account mutation belongs here.
const SCENES:Dictionary={
	"title":"res://scenes/ui/title_screen.tscn",
	"harbor":"res://scenes/ui/harbor.tscn",
	"home":"res://scenes/ui/home_island.tscn",
	"home_recruit":"res://scenes/ui/tactical_recruit.tscn",
	"home_story":"res://scenes/ui/home_story.tscn",
	"canon_story":"res://scenes/ui/canon_story.tscn",
	"recruit":"res://scenes/ui/recruit_banner.tscn",
	"tide_story":"res://scenes/ui/tide_story.tscn",
	"tide_event":"res://scenes/ui/tide_event_hub.tscn",
	"activity":"res://scenes/ui/activity_hub.tscn"}

static func label_for(route:String)->String:
	return str({"battle":"准备作战海域","home":"准备岛屿与街区","home_story":"翻开岛屿纪事","chapter":"准备故事与角色","story":"准备故事与角色","roster":"整理舰娘档案","home_recruit":"连接战术协议","title":"展开归航画卷","harbor":"驶向母港"}.get(route,"整理航图与素材"))

static func paths_for(route:String,app)->Array[String]:
	var paths:Array[String]=[]
	if SCENES.has(route):paths.append(str(SCENES[route]))
	paths.append("res://assets/fonts/NotoSansSC.ttf")
	if route in ["title","story","chapter","home_story","tide_story","story_catalog","story_route"]:paths.append("res://assets/fonts/NotoSerifSC.ttf")
	if route=="title":paths.append("res://assets/title/horizon-v2.png")
	if route not in ["title","battle"]:paths.append("res://assets/backgrounds/harbor-day-v2.png")
	if route=="harbor":
		var featured:Dictionary=app.PortPresentation._featured(app)
		_append_path(paths,str(featured.get("portrait","")))
	if route in ["roster","formation","ship_detail"]:
		for raw:Dictionary in app.economy.roster():
			var card:Dictionary=Art.visual_card(raw,app.cards)
			if route=="ship_detail" and str(card.id)!=str(app.get_meta("detail_ship_id","")):continue
			_append_path(paths,str(card.get("portrait","")))
	if route=="battle" and app.core.view.has("littoral"):
		_collect_paths(JSON.parse_string(FileAccess.get_file_as_string("res://data/combined-arms-art-v4.json")),paths)
		_collect_paths(JSON.parse_string(FileAccess.get_file_as_string("res://data/coastal-town-art-v4.json")),paths)
	var valid:Array[String]=[]
	for path in paths:
		if not valid.has(path) and ResourceLoader.exists(path):valid.append(path)
	return valid

static func _append_path(paths:Array[String],value:String)->void:
	if value.begins_with("res://") and not paths.has(value):paths.append(value)

static func _collect_paths(value:Variant,paths:Array[String])->void:
	if value is Dictionary:
		for child in value.values():_collect_paths(child,paths)
	elif value is Array:
		for child in value:_collect_paths(child,paths)
	elif value is String and str(value).begins_with("res://") and str(value).get_extension().to_lower() in ["png","webp","tres","tscn"]:_append_path(paths,str(value))

static func begin(route:String,app)->Dictionary:
	var resources:Array[Resource]=[]
	var job:Dictionary={"paths":paths_for(route,app),"loaded":{},"resources":resources,"error":""}
	for path in job.paths:
		if ResourceLoader.has_cached(path):
			var resource:Resource=ResourceLoader.get_cached_ref(path)
			if resource!=null:job.resources.append(resource);job.loaded[path]=true;continue
		var requested:Error=ResourceLoader.load_threaded_request(path)
		if requested!=OK:job.error="有一项画面素材未能准备，请重试。";break
	return job

static func poll(job:Dictionary)->Dictionary:
	if not str(job.get("error","")).is_empty():return {"ready":false,"progress":0.0,"error":str(job.error)}
	var amount:float=0.0
	for path in job.paths:
		if job.loaded.has(path):amount+=1.0;continue
		var progress:Array=[]
		var status:int=ResourceLoader.load_threaded_get_status(path,progress)
		if status==ResourceLoader.THREAD_LOAD_LOADED:
			var resource:Resource=ResourceLoader.load_threaded_get(path)
			if resource==null:return {"ready":false,"progress":0.0,"error":"画面素材未能读取，请重试。"}
			job.resources.append(resource);job.loaded[path]=true;amount+=1.0
		elif status in [ResourceLoader.THREAD_LOAD_FAILED,ResourceLoader.THREAD_LOAD_INVALID_RESOURCE]:
			return {"ready":false,"progress":0.0,"error":"画面素材未能读取，当前档案已保留。"}
		elif not progress.is_empty():amount+=clampf(float(progress[0]),0,1)
	var count:int=job.paths.size()
	return {"ready":job.loaded.size()==count,"progress":amount/maxi(1,count) if count>0 else 1.0,"error":""}
