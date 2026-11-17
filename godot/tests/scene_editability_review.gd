extends SceneTree
## Copies the real scenes to artifacts, mutates only copies, and reloads those copies.
## Read-only layout audit uses an isolated account. No original scene or player profile is written.
const Economy=preload("res://scripts/economy.gd")
const Settle=preload("res://tests/transition_settle.gd")
var checks:=0
var failures:Array[String]=[]
var output:="res://../artifacts/godot/scene-editability/"
var layouts:Array[Dictionary]=[]
func _initialize() -> void:call_deferred("run")
func check(ok:bool,title:String) -> void:
	checks+=1
	if not ok:failures.append(title);push_error(title)
func scrolling_parent(node:Node) -> ScrollContainer:
	var ancestor:Node=node.get_parent()
	while ancestor!=null:
		if ancestor is ScrollContainer:return ancestor
		ancestor=ancestor.get_parent()
	return null
func custom_scene_copy(name:String) -> void:
	var original:String="res://scenes/ui/%s.tscn"%name
	var original_hash:=FileAccess.get_sha256(original)
	var view:Control=load(original).instantiate()
	var custom_color:=Color("b74897")
	var custom_panel:=StyleBoxFlat.new();custom_panel.bg_color=Color("263b52")
	var target:Button
	if name=="harbor":
		view.use_default_styles=false;target=view.get_node("Sail")
	else:
		view.use_default_style=false;view.use_catalog_content=false
		target=view.get_node("Body/Buy")
		view.get_node("Body/Title").text="自定义补给标题"
		view.get_node("Body/Amount").text="自定义资源展示"
		view.get_node("Body/Price").text="自定义价格标签"
		view.get_node("Body/Art").texture=load("res://assets/story/chapter1/gate.png")
		view.add_theme_stylebox_override("panel",custom_panel)
	target.add_theme_font_size_override("font_size",39)
	target.add_theme_color_override("font_color",custom_color)
	target.add_theme_stylebox_override("normal",custom_panel)
	root.add_child(view);await process_frame;await process_frame
	if name=="harbor":
		var icons_ok:=true
		for icon in ["SailIcon","StoryIcon","CampaignIcon","CrewIcon","FleetIcon","WarehouseIcon","ShopIcon","RecruitIcon"]:
			var texture:Texture2D=view.get_node(icon).texture
			icons_ok=icons_ok and texture!=null and texture.resource_path.ends_with(".svg")
		check(icons_ok,"harbor keeps eight real SVG resources with default style disabled")
	var packed:=PackedScene.new();check(packed.pack(view)==OK,"pack custom styles: "+name)
	var path:=ProjectSettings.globalize_path(output+name+"-custom-copy.tscn")
	check(ResourceSaver.save(packed,path)==OK,"save custom styles: "+name)
	view.queue_free();await process_frame
	var reloaded:Control=ResourceLoader.load(path,"PackedScene",ResourceLoader.CACHE_MODE_IGNORE).instantiate()
	root.add_child(reloaded);await process_frame;await process_frame
	var button:Button=reloaded.get_node("Sail" if name=="harbor" else "Body/Buy")
	check(button.get_theme_font_size("font_size")==39,"custom button font survives ready and reload: "+name)
	check(button.get_theme_color("font_color").is_equal_approx(custom_color),"custom button color survives ready and reload: "+name)
	check(button.get_theme_stylebox("normal").bg_color.is_equal_approx(custom_panel.bg_color),"custom stylebox survives ready and reload: "+name)
	if name!="harbor":
		check(reloaded.get_node("Body/Title").text=="自定义补给标题" and reloaded.get_node("Body/Amount").text=="自定义资源展示" and reloaded.get_node("Body/Price").text=="自定义价格标签","manual catalog text survives reload")
		check(reloaded.get_node("Body/Art").texture.resource_path=="res://assets/story/chapter1/gate.png","manual catalog illustration survives reload")
		reloaded.pack_id="demo-300"
		check(reloaded.get_node("Body/Title").text=="自定义补给标题","disabled catalog preserves content when id changes")
	check(FileAccess.get_sha256(original)==original_hash,"custom style test leaves source unchanged: "+name)
	reloaded.queue_free();await process_frame

func resource_copy() -> void:
	var original:="res://data/liveops.tres"
	var original_hash:=FileAccess.get_sha256(original)
	var original_resource:Resource=load(original)
	var content:Resource=original_resource.duplicate(true)
	content.title="可编辑资源复查标题";content.subtitle="资源副本保存、重载后生效。"
	content.hero=load("res://assets/story/chapter1/gate.png")
	content.featured_art=load("res://assets/liveops/tidebound-event-v1.png")
	content.announcements[0].title="副本公告标题";content.announcements[0].body="副本公告正文：只修改副本。"
	var path:=ProjectSettings.globalize_path(output+"liveops-copy.tres")
	check(ResourceSaver.save(content,path)==OK,"save liveops resource copy")
	var reloaded:Resource=ResourceLoader.load(path,"Resource",ResourceLoader.CACHE_MODE_IGNORE)
	check(reloaded.title==content.title and reloaded.subtitle==content.subtitle,"liveops title and subtitle survive reload")
	check(reloaded.hero.resource_path==content.hero.resource_path and reloaded.featured_art.resource_path==content.featured_art.resource_path,"both editable CG resources survive reload")
	check(reloaded.announcements[0].title=="副本公告标题" and reloaded.announcements[0].body==content.announcements[0].body,"nested announcement fields survive reload")
	var hub:Control=load("res://scenes/ui/activity_hub.tscn").instantiate();hub.content=reloaded
	root.add_child(hub);await process_frame;await process_frame
	check(hub.get_node("HeroTitle").text==reloaded.title and hub.get_node("HeroSubtitle").text==reloaded.subtitle,"real activity scene consumes edited resource title and subtitle")
	check(hub.get_node("Hero").texture.resource_path==content.hero.resource_path,"real activity scene consumes edited CG")
	hub.preview_tab=1;hub._preview();await process_frame
	var found_title:=false;var found_body:=false
	for label in hub.find_children("*","Label",true,false):
		found_title=found_title or label.text=="副本公告标题"
		found_body=found_body or label.text==content.announcements[0].body
	check(found_title and found_body,"real announcement presentation consumes edited nested resource")
	check(FileAccess.get_sha256(original)==original_hash and original_resource.title!="可编辑资源复查标题" and original_resource.announcements[0].title!="副本公告标题","source resource and cached original remain unchanged")
	hub.queue_free();await process_frame
	var card:Control=load("res://scenes/ui/simulated_pack_card.tscn").instantiate();root.add_child(card);await process_frame
	card.pack_id="demo-980"
	check(card.get_node("Body/Amount").text=="980 元词","pack id setter refreshes catalog immediately")
	card.queue_free();await process_frame

func run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	for row in [
		["harbor","Sail"],["activity_hub","Tabs"],
		["simulated_recharge","Orders"],["simulated_pack_card","Body/Buy"]
		,["title_screen","Mark"],["story_catalog","Cover"],["story_route","Hero"]
		,["expedition_select","Heading"],["cargo_hold","GridScroll"],["cargo_loadout","Capacity"],["battle_feedback","Notice"]
		,["cargo_search","Progress"],["chapter_battle_guide","Card"]
		,["tactical_ai_card","Body/Portrait"],["monster_intel","Card"]
		,["munition_setup","Caption"],["munition_row","."]
		,["expedition_operations","Status"],["expedition_board","Situation"],["expedition_task_card","."]
	]:
		var original:String="res://scenes/ui/%s.tscn"%row[0]
		var original_hash:String=FileAccess.get_sha256(original)
		var scene:PackedScene=load(original)
		var view:Control=scene.instantiate()
		root.add_child(view)
		await process_frame;await process_frame
		var target:Control=view.get_node(str(row[1]))
		var changed_offset:float=target.offset_left+17.0
		target.offset_left=changed_offset
		var copy:=PackedScene.new()
		check(copy.pack(view)==OK,"pack actual scene: "+str(row[0]))
		var saved:String=ProjectSettings.globalize_path(output+str(row[0])+"-copy.tscn")
		check(ResourceSaver.save(copy,saved)==OK,"save copy outside project source: "+str(row[0]))
		view.queue_free();await process_frame
		var saved_scene:PackedScene=ResourceLoader.load(saved,"PackedScene",ResourceLoader.CACHE_MODE_IGNORE)
		var restored:Control=saved_scene.instantiate()
		root.add_child(restored);await process_frame;await process_frame
		check(restored.get_node_or_null(str(row[1]))!=null,"named editable node survives reload: "+str(row[0]))
		check(is_equal_approx(restored.get_node(str(row[1])).offset_left,changed_offset),"layout edit survives reload: "+str(row[0]))
		if row[0]=="simulated_recharge":check(restored.get_node("Packs").get_child_count()==6,"six nested pack instances survive reload")
		check(FileAccess.get_sha256(original)==original_hash,"original scene unchanged: "+str(row[0]))
		restored.queue_free();await process_frame
	await custom_scene_copy("harbor")
	await custom_scene_copy("simulated_pack_card")
	await resource_copy()
	var profile:="user://tests/scene-editability-%d.json"%OS.get_process_id()
	var app=load("res://scenes/main.tscn").instantiate()
	app.boot_to_title=false
	app.economy=Economy.new(profile)
	root.add_child(app);app.set_process(false);await process_frame;await process_frame
	app.page_motion=false
	for dimensions in [Vector2i(960,540),Vector2i(1600,900),Vector2i(1600,720)]:
		root.size=dimensions
		for target in [["title",""],["story_catalog",""],["story_route",""],["expedition",""],["formation",""],["harbor",""],["activity","overview"],["activity","updates"],["activity","campaigns"],["activity","featured"],["activity","supply"],["shop","simulation"],["shop","tactics"]]:
			var route:String=target[0]
			if route=="shop":app.set_meta("supply_category",target[1])
			if route=="activity":app.set_meta("activity_tab",target[1])
			app.show_page(route);await process_frame;await process_frame
			await Settle.wait_for_route(self,app)
			if route=="shop" and target[1]=="simulation":check(app.page.find_child("SimulatedRecharge",true,false)!=null,"audit actual editable recharge scene")
			var actual:Vector2=app.page.size
			var outside:Array[String]=[]
			var scroll_rows:=0
			var last_scroll_button:Button
			for button in app.page.find_children("*","Button",true,false):
				if not button.is_visible_in_tree():continue
				if scrolling_parent(button)!=null:
					scroll_rows+=1;last_scroll_button=button
					continue
				var box:Rect2=button.get_global_rect()
				if not Rect2(Vector2.ZERO,actual).grow(1).encloses(box):outside.append(button.name+":"+button.text)
			if is_instance_valid(last_scroll_button):
				var scroll:ScrollContainer=scrolling_parent(last_scroll_button)
				scroll.ensure_control_visible(last_scroll_button);await process_frame;await process_frame
				check(scroll.get_global_rect().grow(1).encloses(last_scroll_button.get_global_rect()),"final scrolling action can be revealed: "+str(target[1]))
			layouts.append({"window":str(dimensions),"viewport":str(actual),"route":route,"tab":target[1],"outside_buttons":outside,"scrolling_buttons":scroll_rows})
			check(outside.is_empty(),"visible buttons in viewport: %s %s %s"%[dimensions,route,target[1]])
	app.core.close();app.queue_free();await process_frame
	var report:={"checks":checks,"failures":failures,"layouts":layouts,"account":profile,"copies":"artifacts only; original SHA256 verified"}
	var file:=FileAccess.open(output+"report.json",FileAccess.WRITE);file.store_string(JSON.stringify(report,"  "));file.close()
	print("SCENE_EDITABILITY ",JSON.stringify(report));quit(0 if failures.is_empty() else 1)
