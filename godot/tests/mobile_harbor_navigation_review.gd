extends SceneTree
## Real pointer navigation and physical touch-target geometry at three window sizes.
const Settle=preload("res://tests/transition_settle.gd")
const Output:String="res://../artifacts/mobile-home-20261113/navigation/"
var app
var checks:int=0
var failures:Array[String]=[]
var pictures:Array[String]=[]
var input_events:int=0
func _initialize()->void:call_deferred("run")
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures.append(label);push_error(label)
func frames(count:int=3)->void:
	for index in range(count):await process_frame
func click(control:Control)->void:
	await Settle.wait_for_route(self,app)
	check(is_instance_valid(control) and control.is_visible_in_tree(),"control visibly available to real pointer input")
	if not is_instance_valid(control):return
	var at:Vector2=control.get_viewport().get_screen_transform()*control.get_global_transform_with_canvas()*(control.size*.5)
	var motion:=InputEventMouseMotion.new();motion.position=at;Input.parse_input_event(motion)
	var down:=InputEventMouseButton.new();down.position=at;down.button_index=MOUSE_BUTTON_LEFT;down.pressed=true;Input.parse_input_event(down)
	await process_frame
	var up:=InputEventMouseButton.new();up.position=at;up.button_index=MOUSE_BUTTON_LEFT;Input.parse_input_event(up)
	input_events+=3;await frames();await Settle.wait_for_route(self,app)
func shot(label:String)->void:
	if DisplayServer.get_name()=="headless":return
	await frames();await RenderingServer.frame_post_draw
	var path:String=ProjectSettings.globalize_path(Output+label+".png")
	check(root.get_texture().get_image().save_png(path)==OK,"actual viewport capture "+label);pictures.append(path)
func run()->void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(Output))
	var source:String="user://cas_port_v1.json"
	var before:String=FileAccess.get_sha256(source);var backup:String=FileAccess.get_sha256(source+".bak")
	var profile:String=Output+"isolated-navigation-%d.json"%OS.get_process_id()
	var prior:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://../artifacts/home-review/receipt.json"))
	var fixture:String=str(prior.get("profile",""))
	check(DirAccess.copy_absolute(fixture,ProjectSettings.globalize_path(profile))==OK,"clone previously verified completed home profile without writing current account")
	var economy=load("res://scripts/economy.gd").new(profile);check(economy.load_state().get("ok",false),"load cloned profile")
	check(economy.state.active_run.is_empty(),"navigation fixture has no active voyage")
	app=load("res://scenes/main.tscn").instantiate();app.boot_to_title=false;app.economy=economy
	root.content_scale_size=Vector2i(1600,900);root.size=Vector2i(1280,720);root.add_child(app);app.set_process(false);await frames()
	var dimensions:Array[Vector2i]=[Vector2i(960,540),Vector2i(1280,720),Vector2i(1920,1080)]
	for dimension in dimensions:
		root.size=dimension;await frames();app.show_page("harbor");await Settle.wait_for_route(self,app)
		var harbor:Control=app.page.get_node("Harbor")
		var sail:Button=harbor.get_node("Sail");var arena:Button=harbor.get_node("ArenaEntry")
		var story:Button=harbor.get_node("Story");var campaign:Button=harbor.get_node("Campaign")
		check(app.page.get_node_or_null("ArenaEntry")==null,"old header arena entry removed at "+str(dimension))
		check(arena.text=="竞技" and arena.get_global_rect().position.y>sail.get_global_rect().end.y,"arena directly below sortie at "+str(dimension))
		check(arena.get_global_rect().end.y<story.get_global_rect().position.y and story.get_global_rect().end.y<campaign.get_global_rect().position.y,"sortie, arena, story and campaign have separated targets "+str(dimension))
		var transform:Transform2D=arena.get_viewport().get_screen_transform()*arena.get_global_transform_with_canvas()
		var height:float=(transform*Vector2(0,arena.size.y)-transform*Vector2.ZERO).length()
		check(height>=44.0,"arena physical touch target at least 44px at "+str(dimension))
		check(campaign.get_global_rect().end.y<harbor.get_node("Crew").get_global_rect().position.y,"campaign stays clear of bottom navigation "+str(dimension))
		await shot("harbor-%dx%d"%[dimension.x,dimension.y])
		await click(arena);check(app.screen=="arena" and app.page.has_node("ArenaHub"),"new arena button opens actual ranked/3v3 selection "+str(dimension))
		await click(app.page.get_node("NavigateBack"));check(app.screen=="harbor","arena returns to harbor that opened it "+str(dimension))
		await click(app.page.get_node("Harbor/Sail"));check(app.screen=="modes","sortie remains actual mode-selection route "+str(dimension))
		await click(app.page.get_node("NavigateBack"));check(app.screen=="harbor","sortie returns to actual previous harbor "+str(dimension))
	await click(app.page.get_node("HomeIslandEntry"));check(app.screen=="home" and app.page.has_node("HomeIsland"),"home entry still opens real native island")
	check(not app.page_transition.is_busy(),"actual transition barrier releases after new route")
	var home:Control=app.page.get_node("HomeIsland")
	await click(home.get_node("Layout/Bottom/Build"));check(home.get_node("Layout/Tray").visible,"actual pointer opens construction tray")
	await click(app.page.get_node("NavigateBack"));check(app.screen=="home" and not home.get_node("Layout/Tray").visible,"global back closes local construction layer before leaving island")
	await click(home.get_node("Layout/Bottom/Build"))
	var prior_resources:String=JSON.stringify(app.home.state().resources)
	await click(app.page.get_node("NavigateHome"));check(app.screen=="harbor","direct home returns to harbor even while construction tray is open")
	check(JSON.stringify(app.home.state().resources)==prior_resources,"leaving an unconfirmed building layer does not spend materials")
	app.core.close();app.queue_free();await frames()
	check(FileAccess.get_sha256(source)==before,"normal main profile bytes unchanged")
	check(FileAccess.get_sha256(source+".bak")==backup,"normal backup bytes unchanged")
	var receipt:Dictionary={"passed":failures.is_empty(),"checks":checks,"failures":failures,"real_pointer_events":input_events,"screenshots":pictures,"window_sizes":["960x540","1280x720","1920x1080"],"main_sha256":before,"backup_sha256":backup,"core_override":OS.get_environment("CAS_SIM_PATH"),"main_account_written":false}
	FileAccess.open(Output+"receipt.json",FileAccess.WRITE).store_string(JSON.stringify(receipt,"  "))
	print("MOBILE_HARBOR "+JSON.stringify({"checks":checks,"failures":failures,"input_events":input_events}));quit(0 if failures.is_empty() else 1)
