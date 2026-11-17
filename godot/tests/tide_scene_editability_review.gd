extends SceneTree
## Source scenes are read-only here. Only isolated copies and a PID-specific account are saved.
const Design=preload("res://scripts/ui_design.gd")
const Settle=preload("res://tests/transition_settle.gd")
const NAMES=["tide_event_hub","tide_story","tide_battle_hud"]
var app
var checks:=0
var failures:Array[String]=[]
var shots:Array[String]=[]
var layouts:Array[Dictionary]=[]
var output:="res://../artifacts/godot/tide-scene-editability/"
func _initialize()->void:call_deferred("run")
func check(ok:bool,title:String)->void:
	checks+=1
	if not ok:failures.append(title);push_error(title)
func shot(name:String)->void:
	await process_frame;await RenderingServer.frame_post_draw
	var path:=ProjectSettings.globalize_path(output+name+".png")
	check(root.get_texture().get_image().save_png(path)==OK,"actual GPU image "+name);shots.append(path)
func custom_copy(name:String)->void:
	var path:="res://scenes/ui/%s.tscn"%name
	var source_hash:=FileAccess.get_sha256(path)
	var scene:Control=load(path).instantiate()
	scene.use_default_styles=false
	var target_path:="Tabs/Overview" if name=="tide_event_hub" else "Next" if name=="tide_story" else "Pause"
	var title_path:="Title" if name=="tide_event_hub" else "Speaker" if name=="tide_story" else "Status/Body/Wave"
	var art_path:="Hero" if name=="tide_event_hub" else "Backdrop"
	var offset_path:="Hero" if name=="tide_event_hub" else "Back" if name=="tide_story" else "Status"
	if name=="tide_event_hub":scene.use_content_headings=false;scene.use_content_artwork=false
	elif name=="tide_story":scene.use_content_text=false;scene.use_content_artwork=false
	else:scene.show_control_hint=false
	var custom_color:=Color("b74897")
	var custom_panel:=StyleBoxFlat.new();custom_panel.bg_color=Color("26415c")
	var target:Button=scene.get_node(target_path)
	target.add_theme_font_size_override("font_size",31)
	target.add_theme_color_override("font_color",custom_color)
	target.add_theme_stylebox_override("normal",custom_panel)
	scene.get_node(title_path).text="副本自定义标题"
	if name!="tide_battle_hud":scene.get_node(art_path).texture=load("res://assets/story/chapter1/gate.png")
	var offset:float=scene.get_node(offset_path).offset_left+17.0
	scene.get_node(offset_path).offset_left=offset
	var authored_theme:Theme=Design.theme();authored_theme.default_font_size=25;scene.theme=authored_theme
	root.add_child(scene);await process_frame;await process_frame
	if name=="tide_event_hub":scene.bind(app);scene._render("shop")
	elif name=="tide_story":scene.bind(app)
	check(scene.theme==authored_theme,"authored Theme survives ready "+name)
	var packed:=PackedScene.new();check(packed.pack(scene)==OK,"pack isolated native copy "+name)
	var copy_path:=output+name+"-custom-copy.tscn"
	check(ResourceSaver.save(packed,copy_path)==OK,"save native custom scene "+name)
	scene.queue_free();await process_frame
	var restored:Control=ResourceLoader.load(copy_path,"PackedScene",ResourceLoader.CACHE_MODE_IGNORE).instantiate()
	root.add_child(restored);await process_frame;await process_frame
	if name=="tide_event_hub":restored.bind(app);restored._render("story");restored._render("shop")
	elif name=="tide_story":restored.bind(app)
	var button:Button=restored.get_node(target_path)
	check(not restored.use_default_styles,"Inspector style switch persists "+name)
	check(button.get_theme_font_size("font_size")==31,"authored font survives ready/bind/reload "+name)
	check(button.get_theme_color("font_color").is_equal_approx(custom_color),"authored color survives ready/bind/reload "+name)
	check(button.get_theme_stylebox("normal").bg_color.is_equal_approx(custom_panel.bg_color),"authored button style survives ready/bind/reload "+name)
	check(restored.theme.default_font_size==25,"authored Theme resource survives reload "+name)
	check(restored.get_node(title_path).text=="副本自定义标题","authored content survives reload "+name)
	check(is_equal_approx(restored.get_node(offset_path).offset_left,offset),"authored layout offset survives reload "+name)
	if name!="tide_battle_hud":check(restored.get_node(art_path).texture.resource_path=="res://assets/story/chapter1/gate.png","authored illustration survives bind/reload "+name)
	else:check(not restored.get_node("Hint").visible,"Inspector hint visibility persists")
	check(FileAccess.get_sha256(path)==source_hash,"original native scene unchanged "+name)
	restored.queue_free();await process_frame
func resize_window(dimensions:Vector2i)->void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	root.size=dimensions
	await process_frame;await process_frame
	check(root.size==dimensions,"actual window size "+str(dimensions))
func audit_visible(view:Control,name:String,dimensions:Vector2i)->void:
	var outside:Array[String]=[]
	var viewport:=Rect2(Vector2.ZERO,app.page.size).grow(1.0)
	for node in view.find_children("*","Button",true,false):
		if not node.is_visible_in_tree():continue
		var scroll:ScrollContainer=null
		var parent:Node=node.get_parent()
		while parent!=view and parent!=null:
			if parent is ScrollContainer:scroll=parent;break
			parent=parent.get_parent()
		if scroll!=null:continue
		if not viewport.encloses(node.get_global_rect()):outside.append(str(view.get_path_to(node)))
	check(outside.is_empty(),"no inaccessible scene buttons "+name+" "+str(dimensions)+" "+str(outside))
	layouts.append({"page":name,"window":[dimensions.x,dimensions.y],"logical_size":[app.page.size.x,app.page.size.y],"outside":outside})
func independent_canvas(dimensions:Vector2i)->void:
	root.content_scale_size=dimensions
	await resize_window(dimensions)
	app.hide()
	var background:=ColorRect.new();background.color=Design.PAPER;root.add_child(background);background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var hub:Control=load("res://scenes/ui/tide_event_hub.tscn").instantiate();root.add_child(hub);hub.bind(app);hub._render("shop")
	await process_frame;await process_frame
	check(hub.size==Vector2(dimensions),"native scene adapts to independent logical canvas "+str(dimensions))
	check(hub.get_node("ShopScroll/Products").columns==(3 if dimensions.x>=1500 else 2),"responsive product columns "+str(dimensions))
	check(hub.get_node("ShopScroll/Products").size.x<=hub.get_node("ShopScroll").size.x+1,"native product grid does not horizontally overflow "+str(dimensions))
	await shot("%dx%d-native-canvas-shop"%[dimensions.x,dimensions.y])
	hub.queue_free();background.queue_free();app.show();await process_frame
func run()->void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	root.gui_embed_subwindows=true
	app=load("res://scenes/main.tscn").instantiate();app.boot_to_title=false
	app.economy=load("res://scripts/economy.gd").new("user://tests/tide-editability-%d.json"%OS.get_process_id())
	root.add_child(app);app.set_process(false);await process_frame;await process_frame
	app.page_motion=false;app.set_meta("reduced_motion",true)
	for name in NAMES:await custom_copy(name)
	var dimensions_list=[Vector2i(1280,720),Vector2i(1600,900),Vector2i(1920,1080)]
	for dimensions in dimensions_list:await independent_canvas(dimensions)
	root.content_scale_size=Vector2i(1600,900)
	for dimensions in dimensions_list:
		for tab in ["overview","story","shop"]:
			app.set_meta("tide_tab",tab);app.show_page("tide_event");await Settle.wait_for_route(self,app)
			await resize_window(dimensions)
			var view:Control=app.page.get_node("TideEventHub")
			audit_visible(view,"event-"+tab,dimensions)
			if tab=="shop":check(view.get_node("ShopScroll/Products").size.x<=view.get_node("ShopScroll").size.x+1,"shop cards fit scroll width "+str(dimensions))
			else:check(view.body.size.x<=view.get_node("BriefScroll").size.x+1,"briefing wraps inside scroll width "+str(dimensions))
			await shot("%dx%d-event-%s"%[dimensions.x,dimensions.y,tab])
		app.set_meta("tide_story_ending",false);app.show_page("tide_story");await Settle.wait_for_route(self,app)
		await resize_window(dimensions)
		var story:Control=app.page.get_node("TideStory")
		story.reader.elapsed=1000.0;story.get_node("Body").visible_characters=-1
		audit_visible(story,"story",dimensions)
		check(story.get_node("Body").get_content_height()<=story.get_node("Body").size.y,"full narration fits dialogue area "+str(dimensions))
		await shot("%dx%d-story"%[dimensions.x,dimensions.y])
	app.show_page("tide_event");app.set_meta("next_tide_seed",42)
	app.launch_tide(str(app.economy.formation[0]),"normal",null,"cas-event-tide-v1");await Settle.wait_for_route(self,app)
	check(app.screen=="battle" and app.core.view.has("tide"),"final native event enters real dedicated HUD")
	for dimensions in dimensions_list:
		await resize_window(dimensions)
		var hud:Control=app.page.get_node("TideBattleHud")
		audit_visible(hud,"battle",dimensions)
		check(hud.get_node("Status").get_global_rect().end.x<hud.get_node("Clock").get_global_rect().position.x,"ship status and clock remain separate "+str(dimensions))
		await shot("%dx%d-battle"%[dimensions.x,dimensions.y])
	for i in range(110):
		if not app.core.view.tide.choices.is_empty():break
		var drops:Array=app.core.view.tide.drops
		var ship:Dictionary=app.core.view.ships[0]
		var position:=Vector2(float(ship.x),float(ship.y))
		var target:=Vector2(12000,7000)+Vector2.from_angle((i+12)*.105)*1800
		if not drops.is_empty():
			drops=drops.duplicate();drops.sort_custom(func(a,b):return Vector2(float(a.x),float(a.y)).distance_to(position)<Vector2(float(b.x),float(b.y)).distance_to(position))
			target=Vector2(float(drops[0].x),float(drops[0].y))
		app.battle_controller.move(target)
		var response:Dictionary=app.core.request({"op":"step","seconds":1})
		check(response.get("ok",false),"native progress toward first real upgrade "+str(i))
		app.update_battle();await process_frame
	check(not app.core.view.tide.choices.is_empty(),"actual public drops unlock a real offered upgrade")
	for dimensions in dimensions_list:
		await resize_window(dimensions)
		var hud:Control=app.page.get_node("TideBattleHud")
		audit_visible(hud,"upgrade",dimensions)
		check(hud.get_node("Upgrades").visible and hud.get_node("Upgrades/Choices").get_child_count()==3,"three actual native choices are visible "+str(dimensions))
		await shot("%dx%d-upgrade"%[dimensions.x,dimensions.y])
	var report:Dictionary={"checks":checks,"passed":checks-failures.size(),"failures":failures,"layouts":layouts,"screenshots":shots,"core_sha256":FileAccess.get_sha256(OS.get_environment("CAS_SIM_PATH")),"upgrade_tick":int(app.core.view.tick)}
	var file:=FileAccess.open(output+"receipt.json",FileAccess.WRITE);file.store_string(JSON.stringify(report,"\t"));file.close()
	app.audio.shutdown();app.core.close();app.queue_free();await process_frame
	print(JSON.stringify({"checks":checks,"passed":checks-failures.size(),"failures":failures,"screenshots":shots.size()}));quit(0 if failures.is_empty() else 1)
