extends SceneTree
## Exercise the real entrance and nested menu routes with an isolated player profile.
const Settle=preload("res://tests/transition_settle.gd")
var app
var checks:=0
var events:=0
var failures:Array[String]=[]
var pictures:Array[String]=[]
var output:="res://../artifacts/godot/title-navigation/"
func _initialize()->void:call_deferred("run")
func check(ok:bool,title:String)->void:
	checks+=1
	if not ok:failures.append(title);push_error(title)
func find_button(text:String)->Button:
	for node in app.find_children("*","Button",true,false):
		if node.is_visible_in_tree() and node.text==text:return node
	return null
func click_node(node:Control)->void:
	await Settle.wait_for_route(self,app)
	check(is_instance_valid(node) and node.is_visible_in_tree(),"visible interactive control")
	if not is_instance_valid(node):return
	var point:Vector2=node.get_viewport().get_screen_transform()*node.get_global_transform_with_canvas()*(node.size*.5)
	var motion:=InputEventMouseMotion.new();motion.position=point;Input.parse_input_event(motion)
	var down:=InputEventMouseButton.new();down.button_index=MOUSE_BUTTON_LEFT;down.pressed=true;down.position=point;Input.parse_input_event(down)
	await process_frame
	var up:=InputEventMouseButton.new();up.button_index=MOUSE_BUTTON_LEFT;up.position=point;Input.parse_input_event(up)
	events+=3;await process_frame;await process_frame
	await Settle.wait_for_route(self,app)
func click(text:String)->void:await click_node(find_button(text))
func back()->void:await click("‹  返回")
func escape()->void:
	var key:=InputEventKey.new();key.keycode=KEY_ESCAPE;key.physical_keycode=KEY_ESCAPE;key.pressed=true;Input.parse_input_event(key)
	await process_frame
	key=InputEventKey.new();key.keycode=KEY_ESCAPE;key.physical_keycode=KEY_ESCAPE;Input.parse_input_event(key)
	events+=2;await process_frame;await Settle.wait_for_route(self,app)
func shot(name:String)->void:
	if DisplayServer.get_name()=="headless":return
	await Settle.wait_for_route(self,app);await RenderingServer.frame_post_draw
	var path:=ProjectSettings.globalize_path(output+name+".png")
	check(root.get_texture().get_image().save_png(path)==OK,"viewport captured: "+name);pictures.append(path)
func run()->void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	app=load("res://scenes/main.tscn").instantiate()
	app.economy=load("res://scripts/economy.gd").new("user://tests/title-navigation-%d.json"%OS.get_process_id())
	root.add_child(app);await process_frame;await process_frame
	check(app.screen=="title","normal game boot presents the title before harbor")
	var title:Control=app.page.get_node("TitleScreen")
	check(title.get_node("Title").text=="归航" and title.get_node("Backdrop").texture!=null,"editable title and original CG are present")
	check(title.get_node("Actions/Begin").has_focus(),"primary entrance has keyboard focus")
	await shot("01-title-1280")
	await click("设置");check(app.screen=="settings","title settings opens")
	await back();check(app.screen=="title","settings returns to the title that opened it")
	await click("开始游戏");check(app.screen=="harbor","start enters the actual loaded harbor")
	await click("剧情章节");check(app.screen=="story_catalog","harbor opens chapter covers first")
	await shot("02-chapters")
	await click("查看章节路线");check(app.screen=="story_route","cover opens a route, not dialogue immediately")
	check(app.page.has_node("StoryRoute/Graph"),"chapter route graph is an actual editable node")
	await shot("03-chapter-route")
	await click("继续故事");check(app.screen=="chapter","route opens the selected available story node")
	var stage:Control=app.page.get_node_or_null("ChapterStage")
	check(stage!=null,"story has a persistent stage")
	var old_id:int=stage.get_instance_id() if stage else 0
	await click("自动");check(app.page.get_node("ChapterStage").get_instance_id()==old_id,"reader toggle preserves the actual background and cast stage")
	await click("自动：开")
	await click("‹ 路线");check(app.screen=="story_route","story exit returns one level to chapter route")
	await back();check(app.screen=="story_catalog","route back returns chapter covers")
	await escape();check(app.screen=="harbor","Escape returns to the invoking harbor")
	await click("舰娘");check(app.screen=="roster","roster entry")
	var search:LineEdit=app.page.get_node("RosterSearch")
	search.text="弗";search.text_changed.emit(search.text)
	var card:Button=app.page.get_node("RosterScroll").find_child("RosterShip_IBS-U-USN-FLETCHER",true,false)
	await click_node(card);check(app.screen=="ship_detail","real filtered ship card opens detail")
	await back();check(app.screen=="roster" and app.page.get_node("RosterSearch").text=="弗","back preserves the roster filter")
	check(app.page.get_node("RosterScroll").find_child("RosterShip_IBS-U-USN-FLETCHER",true,false).has_focus(),"back restores the selected card focus")
	await back();await click("编队")
	await click("装载与货舱");check(is_instance_valid(app.modal),"formation opens real loadout panel")
	await escape();check(not is_instance_valid(app.modal) and app.screen=="formation","Escape closes modal before navigating")
	await back();check(app.screen=="harbor","formation returns to harbor")
	await click("出航")
	var expedition:Button
	for node in app.page.find_children("*","Button",true,false):
		if node.tooltip_text=="打捞远征":expedition=node
	await click_node(expedition);check(app.screen=="expedition","salvage enters difficulty and environment selection")
	await shot("04-expedition")
	await back();check(app.screen=="modes","expedition back returns modes")
	await back();check(app.screen=="harbor","modes back returns harbor")
	# Title scene customization must survive pack/reload without touching the original.
	var original:="res://scenes/ui/title_screen.tscn";var original_hash:=FileAccess.get_sha256(original)
	var editable:Control=load(original).instantiate();editable.use_default_styles=false;editable.game_title="测试标题"
	editable.get_node("Actions/Begin").add_theme_font_size_override("font_size",31)
	root.add_child(editable);await process_frame
	var packed:=PackedScene.new();check(packed.pack(editable)==OK,"title scene packs after editor-style customization")
	var copy:=ProjectSettings.globalize_path(output+"title-custom-copy.tscn")
	check(ResourceSaver.save(packed,copy)==OK,"custom title scene saves")
	editable.queue_free();await process_frame
	var reloaded:Control=load(copy).instantiate();root.add_child(reloaded);await process_frame
	check(reloaded.get_node("Title").text=="测试标题" and reloaded.get_node("Actions/Begin").get_theme_font_size("font_size")==31,"custom title and font survive scene reload")
	check(FileAccess.get_sha256(original)==original_hash,"editable scene test leaves original intact")
	reloaded.queue_free();app.queue_free();await process_frame;await process_frame
	var suffix:="-headless" if DisplayServer.get_name()=="headless" else ""
	var file:=FileAccess.open(ProjectSettings.globalize_path(output+"receipt"+suffix+".json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"failures":failures,"input_events":events,"screenshots":pictures,"scope":"Real title, chapter hierarchy, persistent stage, back history, filter/focus restoration, loadout entry, editable title; isolated profile."},"  "));file.close()
	print("TITLE_NAVIGATION: %d/%d"%[checks-failures.size(),checks]);quit(0 if failures.is_empty() else 1)
