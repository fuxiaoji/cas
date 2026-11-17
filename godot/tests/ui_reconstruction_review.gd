extends SceneTree
const TransitionSettle=preload("res://tests/transition_settle.gd")
var app
var checks := 0
var failures: Array[String] = []
var output := "res://../artifacts/godot/ui-reconstruction/"
func _initialize() -> void: call_deferred("review")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message); push_error(message)
func shot(name: String) -> void:
	await TransitionSettle.wait_for_route(self,app)
	await process_frame
	await process_frame
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path(output+name+".png"))
func review() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	app=load("res://scenes/main.tscn").instantiate()
	app.economy=load("res://scripts/economy.gd").new("user://tests/ui-reconstruction-%d.json" % OS.get_process_id())
	root.add_child(app)
	await process_frame
	for route in ["harbor","roster","formation","warehouse","campaign","shop","modes","activity","mail","resources","ladder","settings"]:
		app.show_page(route)
		await process_frame
		check(app.screen==route,"route reachable: "+route)
		var scene_name:String={"harbor":"Harbor","activity":"ActivityHub"}.get(route,"")
		if not scene_name.is_empty():
			check(app.page.find_child(scene_name,true,false)!=null,"runtime named scene exists: "+scene_name)
		else:
			check(app.page.find_children("*","Control",true,false).size()>5,"content exists: "+route)
		await shot(route)
	app.show_page("formation")
	await process_frame
	var slot=app.page.find_child("AddFleetMember",true,false)
	check(slot!=null,"visible slot picker available")
	if slot:
		slot.pressed.emit()
		await process_frame
		check(is_instance_valid(app.modal),"slot opens roster overlay")
		await shot("formation-picker")
		app.close_modal()
	var before: Array=app.economy.formation.duplicate()
	var image_keys: Array=app.Design.PATHS.keys()
	check(image_keys.size()>=20,"coherent functional icon family")
	check(app.Design.icon_texture("fleet").get_width()>=192,"icons retain resolution")
	for size in [Vector2i(960,540),Vector2i(1600,720)]:
		root.size=size
		app.show_page("harbor")
		await process_frame
		await shot("harbor-%dx%d"%[size.x,size.y])
		app.show_page("formation")
		await process_frame
		await shot("formation-%dx%d"%[size.x,size.y])
	check(before==app.economy.formation,"navigation and resizing preserve formation")
	var file=FileAccess.open(ProjectSettings.globalize_path(output+"receipt.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"failures":failures,"note":"Screenshots are rendered Godot UI; profile is disposable, slot picker uses button signal."},"  "))
	file.close()
	app.queue_free()
	await process_frame
	print("UI_RECONSTRUCTION: %d checks, %d failures"%[checks,failures.size()])
	quit(0 if failures.is_empty() else 1)
