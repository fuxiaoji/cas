extends SceneTree
const Settle=preload("res://tests/transition_settle.gd")
const Art=preload("res://scripts/character_art.gd")
var app
var checks:=0
var failures:Array[String]=[]
var shots:Array[String]=[]
var output:="res://../artifacts/godot/home-identity/"
func _initialize()->void:call_deferred("run")
func check(ok:bool,title:String)->void:
	checks+=1
	if not ok:failures.append(title);push_error(title)
func click(button:Control)->void:
	var at:Vector2=button.get_viewport().get_screen_transform()*(button.get_global_rect().get_center())
	for down in [true,false]:
		var event:=InputEventMouseButton.new();event.button_index=MOUSE_BUTTON_LEFT;event.pressed=down;event.position=at
		Input.parse_input_event(event);await process_frame
	await Settle.wait_for_route(self,app)
func shot(name:String)->void:
	await process_frame;await process_frame;await RenderingServer.frame_post_draw
	var path:=ProjectSettings.globalize_path(output+name+".png")
	check(root.get_texture().get_image().save_png(path)==OK,"actual GPU capture "+name);shots.append(path)
func run()->void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	root.content_scale_size=Vector2i(1600,900);root.size=Vector2i(1280,720)
	app=load("res://scenes/main.tscn").instantiate();app.boot_to_title=false
	app.economy=load("res://scripts/economy.gd").new("user://tests/home-identity-%d.json"%OS.get_process_id())
	root.add_child(app);await process_frame;app.page_motion=false
	for route in ["formation","roster","warehouse","shop","player","settings","modes","arena","recruit"]:
		app.show_page("harbor");app.show_page(route);await Settle.wait_for_route(self,app)
		var home:Button=app.page.find_child("NavigateHome",true,false)
		check(home!=null and home.visible,"distinct home action in "+route)
		var back:Control=app.page.find_child("NavigateBack",true,false)
		if back!=null:check(not back.get_global_rect().intersects(home.get_global_rect()),"home and back never overlap "+route)
		await click(home);check(app.screen=="harbor","real pointer goes directly home from "+route)
	var card:Dictionary=app.cards["IBS-U-USN-HELENA"]
	var projection:Dictionary=Art.projection(card)
	check(str(projection.kind)=="generated_chibi" and str(projection.path).contains("chibis-generated-2026-11-12-v4"),"Helena resolves to own corrected generated SD")
	check(str(card.get("chibi_reference","" )).is_empty(),"Helena no longer falls back to different blue-haired identity")
	# Show unmodified own portrait and actual SD pixels at game reading sizes.
	app.show_page("roster");await process_frame
	var panel:Control=app.open_modal("海伦娜 · 本人立绘与小人")
	app.picture(panel,str(card.portrait),380,230,300,420)
	for entry in [[760,300,80],[910,280,160],[1110,250,240]]:
		app.picture(panel,str(projection.path),entry[0],entry[1],entry[2],entry[2])
	await shot("helena-own-portrait-and-sd")
	app.close_modal();app.start_campaign();await Settle.wait_for_route(self,app)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED);app.fullscreen_battle=false;root.size=Vector2i(1280,720)
	var helena:Dictionary={}
	for ship in app.core.view.ships:
		if Art.resolve(app.cards,ship,false).get("identity","")=="IBS-U-USN-HELENA":helena=ship;break
	check(not helena.is_empty(),"real historical voyage contains correctly resolved Helena")
	if not helena.is_empty():
		app.sea.zoom=3.0;app.sea.pan=Vector2.ZERO
		app.sea.pan=app.sea.size*.5-app.sea.project(app.sea.pos(helena));app.sea.selected_ship=int(helena.id);app.sea.queue_redraw()
		await shot("helena-on-original-satellite")
	var active_id:String=str(app.economy.state.active_run.run_id)
	var snapshot:String=str(app.core.request({"op":"save","serialized":true}).serialized)
	app.battle_controller.open_pause_menu();await process_frame
	var home:Button=app.modal.find_child("NavigateHome",true,false)
	check(home!=null,"pause menu offers direct save and home")
	await click(home)
	check(app.screen=="harbor" and str(app.economy.state.active_run.run_id)==active_id,"return home preserves ongoing battle identity")
	check(str(app.economy.state.active_run.snapshot)==snapshot,"return home saves exact native battle snapshot")
	app.resume_run();await Settle.wait_for_route(self,app)
	check(app.screen=="battle" and str(app.core.request({"op":"save","serialized":true}).serialized)==snapshot,"resume continues exact paused battle")
	app.core.close()
	var receipt:Dictionary={"checks":checks,"failures":failures,"screenshots":shots,"projection":projection}
	FileAccess.open(output+"receipt.json",FileAccess.WRITE).store_string(JSON.stringify(receipt,"  "))
	print("HOME_IDENTITY ",JSON.stringify({"checks":checks,"failures":failures}));quit(0 if failures.is_empty() else 1)
