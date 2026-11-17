extends SceneTree
const Main=preload("res://scenes/main.tscn")
const Economy=preload("res://scripts/economy.gd")
const Chapter=preload("res://scripts/chapter_presentation.gd")
const Content=preload("res://scripts/chapter_story_data.gd")
const Settle=preload("res://tests/transition_settle.gd")
var app
var checks:=0
var failures:Array[String]=[]
var shots:Array[String]=[]
var output:="res://../artifacts/godot/chapter-navigation/"
func _initialize()->void:call_deferred("run")
func check(value:bool,title:String)->void:
	checks+=1
	if not value:failures.append(title);push_error(title)
func click(text:String)->void:
	await Settle.wait_for_route(self,app)
	var target:Button
	for node in app.find_children("*","Button",true,false):
		if node.is_visible_in_tree() and node.text==text and not node.disabled:target=node;break
	check(target!=null,"visible action "+text)
	if target==null:return
	var point:Vector2=target.get_viewport().get_screen_transform()*target.get_global_transform_with_canvas()*(target.size*.5)
	var motion:=InputEventMouseMotion.new();motion.position=point;Input.parse_input_event(motion)
	var down:=InputEventMouseButton.new();down.button_index=MOUSE_BUTTON_LEFT;down.pressed=true;down.position=point;Input.parse_input_event(down);await process_frame
	var up:=InputEventMouseButton.new();up.button_index=MOUSE_BUTTON_LEFT;up.position=point;Input.parse_input_event(up);await process_frame;await process_frame
func shot(name:String)->void:
	if DisplayServer.get_name()=="headless":return
	await Settle.wait_for_route(self,app);await RenderingServer.frame_post_draw
	if app.screen=="chapter":await create_timer(.55).timeout
	var path:=ProjectSettings.globalize_path(output+name+".png")
	check(root.get_texture().get_image().save_png(path)==OK,"captured "+name);shots.append(path)
func run()->void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	var path:="user://tests/chapter-routes-%d.json"%OS.get_process_id()
	app=Main.instantiate();app.boot_to_title=false;app.economy=Economy.new(path);root.add_child(app);app.set_process(false);await process_frame
	var wallet:Dictionary=app.economy.wallet().duplicate(true)
	await click("剧情章节")
	check(app.screen=="story_catalog" and app.page.has_node("StoryCatalog"),"harbor enters actual chapter catalog")
	await shot("01-catalog")
	await click("查看章节路线")
	check(app.screen=="story_route" and app.page.has_node("StoryRoute"),"cover enters actual chapter route")
	var route:Control=app.page.get_node("StoryRoute")
	check(route.get_node("Graph").nodes.size()==16,"all sixteen original nodes represented")
	check(route.get_node("Graph/Route_rescue").disabled==false and route.get_node("Graph/Route_boss").disabled,"future real mission locked without false clears")
	await shot("02-route-new")
	await click("继续故事")
	check(app.screen=="chapter","route opens actual first scene")
	var stage:int=app.page.get_node("ChapterStage").get_instance_id()
	var backdrop:int=app.page.get_node("ChapterStage/Backdrop").get_instance_id()
	var texture:int=app.page.get_node("ChapterStage/Backdrop").texture.get_instance_id()
	var page_id:int=app.page.get_instance_id()
	var player=app.page.get_node("ChapterDialogueReader")
	player.continue_reading();player.continue_reading();await process_frame
	check(int(app.progression.chapter_status().line)==1 and app.page.get_instance_id()==page_id,"next line keeps same actual page")
	check(app.page.get_node("ChapterStage").get_instance_id()==stage and app.page.get_node("ChapterStage/Backdrop").get_instance_id()==backdrop,"next line keeps stage and backdrop nodes")
	check(app.page.get_node("ChapterStage/Backdrop").texture.get_instance_id()==texture and not app.page.get_node("ChapterStage").has_node("BackgroundBlend"),"same background is not reloaded or cross faded")
	await click("跳过本段");await click("你们有谁受伤了吗？")
	check(app.progression.chapter_status().node=="waking" and app.progression.chapter_status().choices.rescue=="crew","real choice advances to waking")
	await process_frame
	var actor:int=app.page.get_node("ChapterStage/Cast/Actor_fletcher").get_instance_id()
	player=app.page.get_node("ChapterDialogueReader");player.continue_reading();player.continue_reading();await process_frame
	check(app.page.get_node("ChapterStage/Cast/Actor_fletcher").get_instance_id()==actor,"speaker change preserves the same actor instance")
	check(app.page.get_node("ChapterStage/Cast/Actor_fletcher").modulate.a>.9,"speaker is not faded from zero again")
	var reader_id:int=app.page.get_node("ChapterDialogueReader").get_instance_id()
	app.set_meta("chapter_auto",true);app.show_page("chapter");await process_frame
	check(app.page.get_node("ChapterDialogueReader").get_instance_id()==reader_id,"auto switch keeps current reader and reveal progress")
	app.set_meta("chapter_auto",false);app.set_meta("reduced_motion",true);app.show_page("chapter");await process_frame
	check(app.page.get_node("ChapterStage/Cast/Actor_fletcher").scale==Vector2.ONE and "[wave" not in app.page.get_node("ChapterStage/Body").text,"reduced motion stops effects in the same scene")
	await shot("03-stable-cast")
	await click("‹ 路线")
	check(app.screen=="story_route" and app.progression.chapter_status().node=="waking","story back returns to its route without rewinding progress")
	check(app.page.get_node("StoryRoute/Graph").current=="waking","route highlights newly reached scene")
	app.go_back("story_catalog");await process_frame
	check(app.screen=="story_catalog","route back returns to chapter catalog")
	check(app.economy.wallet()==wallet and app.progression.chapter_status().cleared.is_empty(),"navigation and rereading grant no fake resources or mission clear")
	app.audio.shutdown();app.core.close();app.queue_free();await process_frame
	for suffix in ["",".bak",".tmp"]:
		if FileAccess.file_exists(path+suffix):DirAccess.remove_absolute(ProjectSettings.globalize_path(path+suffix))
	var receipt:={"checks":checks,"failures":failures,"screenshots":shots,"scope":"actual pointer navigation, same-node and same-background identity, no battle results fabricated"}
	var file:=FileAccess.open(output+"route-receipt.json",FileAccess.WRITE);file.store_string(JSON.stringify(receipt,"\t"));file.close();print(JSON.stringify(receipt));quit(0 if failures.is_empty() else 1)
