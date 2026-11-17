extends SceneTree
const Settle=preload("res://tests/transition_settle.gd")
var app
var checks:int=0
var failures:Array[String]=[]
var output:String="res://../artifacts/godot/adventure-title-ai/"
func _initialize()->void:call_deferred("run")
func check(ok:bool,title:String)->void:
	checks+=1
	if not ok:failures.append(title);push_error(title)
func click(node:Control)->void:
	await Settle.wait_for_route(self,app)
	check(is_instance_valid(node) and node.is_visible_in_tree(),"visible clickable control")
	if not is_instance_valid(node):return
	var point:Vector2=node.get_viewport().get_screen_transform()*node.get_global_transform_with_canvas()*(node.size*.5)
	var motion:=InputEventMouseMotion.new();motion.position=point;Input.parse_input_event(motion)
	var down:=InputEventMouseButton.new();down.button_index=MOUSE_BUTTON_LEFT;down.pressed=true;down.position=point;Input.parse_input_event(down)
	await process_frame
	var up:=InputEventMouseButton.new();up.button_index=MOUSE_BUTTON_LEFT;up.position=point;Input.parse_input_event(up)
	await process_frame;await process_frame;await Settle.wait_for_route(self,app)
func shot(name:String)->void:
	if DisplayServer.get_name()=="headless":return
	await process_frame;await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(ProjectSettings.globalize_path(output+name+".png"))==OK,"captured "+name)
func fit(node:Control,ancestor:Control)->bool:
	return ancestor.get_global_rect().encloses(node.get_global_rect())
func run()->void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	app=load("res://scenes/main.tscn").instantiate()
	app.economy=load("res://scripts/economy.gd").new("user://tests/title-ai-%d.json"%OS.get_process_id())
	root.add_child(app);await process_frame;await process_frame
	check(app.screen=="title","game opens new title")
	var title:Control=app.page.get_node("TitleScreen")
	check(title.get_node("Backdrop").texture.resource_path.ends_with("horizon-v2.png"),"new independent game title art is installed")
	check(title.get_node("Title").get_theme_font("font").base_font.resource_path.ends_with("NotoSerifSC.ttf"),"title uses editable serif typography")
	check(title.get_node("Actions/Begin").has_focus(),"keyboard entrance focused")
	for dimensions in [Vector2i(1280,720),Vector2i(960,540),Vector2i(1600,720)]:
		root.size=dimensions;await process_frame;await process_frame
		for path in ["Title","Subtitle","Actions/Begin","Settings","Quit"]:check(fit(title.get_node(path),title),"title controls fit "+path+str(dimensions))
		await shot("title-%dx%d"%[dimensions.x,dimensions.y])
	root.size=Vector2i(1280,720);await process_frame
	await click(title.get_node("Settings"));check(app.screen=="settings","title settings works")
	app.go_back();await Settle.wait_for_route(self,app);check(app.screen=="title","settings returns to title")
	await click(app.page.get_node("TitleScreen/Actions/Begin"));check(app.screen=="harbor","start enters real harbor")
	app.set_meta("supply_category","tactics");app.show_page("shop");await Settle.wait_for_route(self,app)
	var scroll:ScrollContainer=app.page.get_node("TacticalAIInventory")
	var grid:GridContainer=scroll.get_child(0)
	check(grid.get_child_count()==9,"all current tactical policies have character cards")
	var ids:Dictionary={}
	var active_portraits:Array=[]
	for card in grid.get_children():
		var id:=str(card.get_meta("profile_id"));ids[id]=true
		var art:Dictionary=load("res://scripts/ai_character_art.gd").lookup(id)
		check(not art.is_empty(),"explicit AI character identity "+id)
		check(not active_portraits.has(str(art.get("portrait",""))),"each active policy has its own portrait "+id)
		active_portraits.append(str(art.get("portrait","")))
		check(FileAccess.get_sha256(str(art.get("portrait","")))==str(art.get("sha256","")),"approved original bytes "+id)
		check(card.get_node("Body/Portrait").texture!=null,"portrait actually shown "+id)
		check(card.get_node("Body/Name").text==str(art.get("name","")),"portrait name identity "+id)
		if id.begins_with("evo-"):check(card.get_node("Body/Action").disabled,"campaign locked policy cannot be bought "+id)
	check(ids.has("coord") and ids.has("evo-denial"),"owned and advanced policies listed")
	await shot("ai-original-portraits")
	scroll.scroll_vertical=scroll.get_v_scroll_bar().max_value
	await process_frame;await shot("ai-new-original-policies")
	app.economy.state.wallet.medals=6
	app.show_page("shop");await Settle.wait_for_route(self,app)
	var buy:Button=app.page.get_node("TacticalAIInventory").get_child(0).get_node("AI_gunnery/Body/Action")
	check(not buy.disabled,"actual old gunnery purchase is affordable")
	await click(buy)
	check(app.progression.available_ai_profiles().has("gunnery") and int(app.economy.wallet().medals)==0,"purchase still uses original six medals transaction")
	app.close_modal();await process_frame
	var choose:Button=app.page.get_node("TacticalAIInventory").get_child(0).get_node("AI_gunnery/Body/Action")
	await click(choose);check(app.progression.selected_profile()=="gunnery","portrait card selects actual policy")
	app.close_modal();await process_frame
	var registry:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/ai-art.json"))
	check(registry.profiles.size()==12,"six legacy portraits retained and six unique policies added")
	for original in ["balanced","adaptive","fleet","rc_torpedo_wings","rc_pincer","rc_coordinated"]:
		check(registry.profiles.any(func(row):return str(row.id)==original and str(row.get("portrait",""))=="res://assets/ai/"+original+".png"),"legacy portrait retained "+original)
	for id in ["evo-screen","evo-torpedo","evo-gunnery","evo-brawler","evo-kiter","evo-denial"]:
		var art:Dictionary=load("res://scripts/ai_character_art.gd").lookup(id)
		check(str(art.get("id",""))==id and str(art.get("portrait","")).begins_with("res://assets/ai/original-v3/"),"new policy has original identity "+id)
	var scene:PackedScene=load("res://scenes/ui/tactical_ai_card.tscn")
	var editable:Control=scene.instantiate();editable.use_default_style=false
	root.add_child(editable);await process_frame
	editable.get_node("Body/Name").text="可编辑名字"
	var copy:=PackedScene.new();check(copy.pack(editable)==OK,"AI card scene editable")
	var path:=output+"custom-ai-card.tscn";check(ResourceSaver.save(copy,path)==OK,"AI card custom copy saves")
	var reloaded=load(path).instantiate();check(reloaded.get_node("Body/Name").text=="可编辑名字","AI card custom copy reloads")
	reloaded.free();editable.queue_free()
	app.core.close()
	var report:Dictionary={"checks":checks,"failures":failures,"passed":failures.is_empty(),"registered_characters":registry.profiles.size(),"legacy_characters":6,"new_characters":6,"active_unique_portraits":active_portraits.size()}
	FileAccess.open(output+"report.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print(JSON.stringify(report));quit(0 if failures.is_empty() else 1)
