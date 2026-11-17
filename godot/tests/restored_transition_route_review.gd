extends SceneTree
## Actual game menu and input barrier, using a PID-isolated new account.
var checks:=0
var failures:Array[String]=[]
var output:="res://../artifacts/godot/restored-transition/"
func _initialize()->void:call_deferred("run")
func check(ok:bool,title:String)->void:
	checks+=1
	if not ok:failures.append(title);push_error(title)
func run()->void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	root.size=Vector2i(1280,720)
	var app=load("res://scenes/main.tscn").instantiate();app.boot_to_title=false
	app.economy=load("res://scripts/economy.gd").new("user://tests/restored-transition-%d.json"%OS.get_process_id())
	root.add_child(app);app.set_process(false);await process_frame;await process_frame
	app.page_transition.full_screen_wipe=false;app.page_transition.duration=.42;app.page_transition.use_registered_cast=false
	app.page_motion=false;app.show_page("harbor");await process_frame;await process_frame
	var account_before:String=JSON.stringify(app.economy.state)
	app.page_motion=true;app.show_page("modes")
	var transition=app.page_transition
	check(app.screen=="modes" and is_instance_valid(app.page),"new page is built synchronously")
	check(transition.is_busy() and not transition.full_screen_wipe,"actual route supports the optional lightweight transition")
	check(transition.actor_states.size()==3,"actual new-account roster presents three authentic SD actors")
	transition.player.pause();transition.player.seek(.42*transition._clip_length(),true);transition._process(0)
	await process_frame;await RenderingServer.frame_post_draw
	check(not transition.mask.visible and not transition.old_frame.visible,"actual incoming menu remains unobstructed by full-screen art")
	check(root.get_texture().get_image().save_png(ProjectSettings.globalize_path(output+"actual-modes-three-large-chibis.png"))==OK,"saved real production menu transition")
	# The real back button lives under this point. The short input gate must intercept it.
	var point:Vector2=app.get_viewport().get_screen_transform()*app.page.get_global_transform_with_canvas()*Vector2(100,45)
	for pressed in [true,false]:
		var event:=InputEventMouseButton.new();event.button_index=MOUSE_BUTTON_LEFT;event.pressed=pressed;event.position=point;Input.parse_input_event(event);await process_frame
	check(app.screen=="modes","actual pointer cannot trigger an underlying back button during the hop")
	transition.player.play()
	await create_timer(.6).timeout
	check(not transition.is_busy() and not transition.overlay.visible and is_equal_approx(app.page.modulate.a,1.0),"actual route settles without a loading hold or dim page")
	check(JSON.stringify(app.economy.state)==account_before,"decorative transition and blocked input do not modify account progression or currency")
	app.show_page("warehouse");app.show_page("harbor");await create_timer(.6).timeout
	check(app.screen=="harbor" and not transition.is_busy() and is_equal_approx(app.page.modulate.a,1.0),"actual rapid consecutive routes finish on the requested page")
	app.core.close();app.queue_free();await process_frame
	var report:Dictionary={"checks":checks,"failures":failures,"passed":failures.is_empty(),"account":"PID-isolated new profile; no rewards, transactions or combat were invoked"}
	FileAccess.open(output+"actual-route-receipt.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	print("RESTORED_TRANSITION_ROUTE ",JSON.stringify(report));quit(0 if failures.is_empty() else 1)
