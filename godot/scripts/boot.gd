extends Control
## First scene is intentionally tiny: main.gd and its transitive resources are
## requested only after this visible frame has reached the renderer.
const LoadingScene=preload("res://scenes/ui/loading_screen.tscn")
const MAIN_PATH:String="res://scenes/main.tscn"
@export var profile_override:String=""
@export var immersive_fullscreen:bool=true
var loading:Control
var app:Control
var completed:bool=false
var failed:bool=false
var boot_attempt:int=0
var resources:Array[Resource]=[]
signal boot_completed(result:Dictionary)

func _ready()->void:
	get_tree().auto_accept_quit=false
	loading=LoadingScene.instantiate();add_child(loading)
	loading.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var settings:=ConfigFile.new()
	if settings.load("user://settings.cfg")==OK:loading.set_reduced_motion(not bool(settings.get_value("display","page_motion",true)))
	loading.retry_requested.connect(_begin_boot)
	loading.quit_requested.connect(func():get_tree().quit())
	_begin_boot.call_deferred()

func _begin_boot()->void:
	boot_attempt+=1
	var token:int=boot_attempt
	completed=false;failed=false;resources.clear()
	loading.clear_failure();loading.show();loading.modulate=Color.WHITE
	loading.set_stage("正在铺开航线",-1)
	if is_instance_valid(app):
		remove_child(app);app.queue_free();app=null
	await _drawn_frame()
	if token!=boot_attempt:return
	var paths:Array[String]=[MAIN_PATH,"res://assets/fonts/NotoSansSC.ttf","res://assets/fonts/NotoSerifSC.ttf","res://assets/title/horizon-v2.png"]
	var loaded:Dictionary={}
	var began:int=Time.get_ticks_msec()
	for path in paths:
		if ResourceLoader.has_cached(path):
			var resource:Resource=ResourceLoader.get_cached_ref(path)
			if resource!=null:resources.append(resource);loaded[path]=resource;continue
		if ResourceLoader.load_threaded_request(path)!=OK:
			_fail("航线素材未能准备，请重试。",token);return
	while token==boot_attempt and is_inside_tree() and loaded.size()<paths.size():
		if Time.get_ticks_msec()-began>60000:
			_fail("准备航线超时，请重试。",token);return
		var total:float=0
		for path in paths:
			if loaded.has(path):total+=1;continue
			var progress:Array=[]
			var status:int=ResourceLoader.load_threaded_get_status(path,progress)
			if status==ResourceLoader.THREAD_LOAD_LOADED:
				var resource:Resource=ResourceLoader.load_threaded_get(path)
				if resource==null:_fail("航线素材未能读取，请重试。",token);return
				resources.append(resource);loaded[path]=resource;total+=1
			elif status in [ResourceLoader.THREAD_LOAD_FAILED,ResourceLoader.THREAD_LOAD_INVALID_RESOURCE]:
				_fail("航线素材未能读取，请重试。",token);return
			elif not progress.is_empty():total+=clampf(float(progress[0]),0,1)
		loading.set_stage("准备画卷与角色",.72*total/paths.size())
		await get_tree().process_frame
	if token!=boot_attempt or not is_inside_tree():return
	loading.set_stage("整理航海图册",.74)
	await _drawn_frame()
	var scene:PackedScene=loaded[MAIN_PATH] as PackedScene
	if scene==null or not scene.can_instantiate():_fail("航海图册未能展开，请重试。",token);return
	app=scene.instantiate()
	app.deferred_startup=true;app.staged_navigation=true
	app.immersive_fullscreen=immersive_fullscreen
	if not profile_override.is_empty():app.economy=load("res://scripts/economy.gd").new(profile_override)
	app.startup_stage.connect(func(value:float,message:String):
		if token==boot_attempt:loading.set_stage(message,value))
	app.startup_completed.connect(func(result:Dictionary):_on_app_ready(result,token))
	add_child(app);move_child(loading,get_child_count()-1)
	_watch_startup(token)

func _watch_startup(token:int)->void:
	await get_tree().create_timer(60.0).timeout
	if token==boot_attempt and not completed and not failed:
		_fail("母港尚未准备完成，请重试；当前档案已保留。",token)

func _on_app_ready(result:Dictionary,token:int)->void:
	if token!=boot_attempt:return
	if not result.get("ok",false):_fail(str(result.get("message","舰队档案未能读取，原文件已保留。")),token);return
	await _drawn_frame()
	if token!=boot_attempt:return
	loading.set_stage("航线已就绪",1.0)
	# Content has really rendered below the cover before the short reveal.
	var reveal:Tween=create_tween().bind_node(loading)
	reveal.tween_property(loading,"modulate:a",0.0,.16)
	await reveal.finished
	if token!=boot_attempt:return
	loading.hide();completed=true;boot_completed.emit(result)

func _fail(message:String,token:int)->void:
	if token!=boot_attempt:return
	failed=true;loading.show_failure(message)
	boot_completed.emit({"ok":false,"message":message})

func _drawn_frame()->void:
	await get_tree().process_frame
	if DisplayServer.get_name()!="headless":await RenderingServer.frame_post_draw

func _input(_event:InputEvent)->void:
	# The title can acquire keyboard focus while rendering beneath this cover.
	# Consume input here until reveal, while failure actions remain interactive.
	if is_instance_valid(loading) and loading.visible and not failed:
		get_viewport().set_input_as_handled()

func _notification(what:int)->void:
	if what==NOTIFICATION_WM_CLOSE_REQUEST:
		# Once mounted, Main receives this tree-wide notification itself and owns
		# checkpoint/close. Forwarding it would commit the same run twice.
		if not is_instance_valid(app) or not app.startup_ready:get_tree().quit()
