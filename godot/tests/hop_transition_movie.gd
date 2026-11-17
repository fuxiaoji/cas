extends SceneTree
## Production Main footage through Godot MovieWriter at fixed 60fps. No frame
## synthesis, coordinate drawing, world access or normal-account mutation.
const Economy=preload("res://scripts/economy.gd")
var app
func _initialize()->void:call_deferred("run")
func frames(count:int)->void:
	for index in count:await process_frame
func run()->void:
	root.content_scale_size=Vector2i(1600,900);root.content_scale_mode=Window.CONTENT_SCALE_MODE_CANVAS_ITEMS;root.size=Vector2i(1280,720)
	var account_path:String="user://tests/hop-movie-%d.json"%OS.get_process_id()
	app=load("res://scenes/main.tscn").instantiate();app.boot_to_title=false;app.economy=Economy.new(account_path)
	root.add_child(app);app.set_process(false);await frames(4);app.page_motion=false
	# Warm page resources before filming so synchronous PNG/first-use shader costs
	# do not create gaps in this separate reference clip.
	for route in ["formation","modes","home","harbor"]:app.show_page(route);await frames(3)
	var account:String=JSON.stringify(app.economy.state)
	app.page_motion=true;app.set_meta("reduced_motion",false);app.page_transition.random.seed=20261113
	var routes:Array=[]
	for pair in [{"route":"formation","style":0},{"route":"modes","style":1},{"route":"home","style":2}]:
		app.set_meta("transition_style",int(pair.style));app.show_page(str(pair.route));var count:int=0
		while app.page_transition.is_busy() and count<110:await process_frame;count+=1
		routes.append({"route":pair.route,"frames":count,"settled":not app.page_transition.is_busy()})
		await frames(8)
	var unchanged:bool=JSON.stringify(app.economy.state)==account
	app.core.close();app.queue_free();await frames(2)
	FileAccess.open("res://../artifacts/hop-transition/movie-receipt.json",FileAccess.WRITE).store_string(JSON.stringify({"fixed_fps":60,"source":"Godot MovieWriter recording actual production Main routes","routes":routes,"normal_account_access":false,"isolated_profile_unchanged":unchanged},"  "))
	quit(0 if unchanged and routes.all(func(row):return row.settled) else 1)
