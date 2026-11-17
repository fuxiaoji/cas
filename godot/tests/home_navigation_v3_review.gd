extends SceneTree
const Economy=preload("res://scripts/economy.gd")
const Transition=preload("res://tests/transition_settle.gd")
var app
var checks:int=0
var failures:Array[String]=[]
var inputs:int=0
var baseline:bool=false
func _initialize()->void:call_deferred("run")
func check(ok:bool,message:String)->void:
	checks+=1
	if not ok:failures.append(message);push_error(message)
func settle()->void:
	await process_frame;await process_frame
	await Transition.wait_for_route(self,app)
func click(node:Control)->void:
	var point:Vector2=node.get_viewport().get_screen_transform()*node.get_global_transform_with_canvas()*(node.size*.5)
	var motion:=InputEventMouseMotion.new();motion.position=point;Input.parse_input_event(motion);inputs+=1;await process_frame
	for pressed:bool in [true,false]:
		var event:=InputEventMouseButton.new();event.position=point;event.global_position=point;event.button_index=MOUSE_BUTTON_LEFT;event.pressed=pressed;Input.parse_input_event(event);inputs+=1;await process_frame
	await settle()
func run()->void:
	baseline=OS.get_cmdline_user_args().has("--baseline")
	var path:String="C:/Users/fwj/AppData/Local/Temp/CAS-home-navigation-v3-%d.json"%OS.get_process_id()
	var source_sha:String=FileAccess.get_sha256("user://cas_port_v1.json")
	var source_backup:String=FileAccess.get_sha256("user://cas_port_v1.json.bak")
	var account=Economy.new(path);check(account.load_state().get("ok",false),"ordinary isolated account")
	app=load("res://scenes/main.tscn").instantiate();app.economy=account;app.boot_to_title=false
	root.add_child(app);app.set_process(false);await settle();app.page_motion=false
	await click(app.page.get_node("HomeIslandEntry"))
	check(app.screen=="home","ordinary account enters actual home screen")
	var home=app.page.get_node("HomeIsland")
	await click(home.get_node("Layout/Bottom/Garrison"))
	check(is_instance_valid(app.modal),"actual garrison button opens modal")
	if baseline:
		await click(app.page.get_node("NavigateBack"))
		check(not is_instance_valid(app.modal),"original top back must remain reachable with home modal")
	else:
		await click(app.modal.get_node("ModalNavigateBack"))
		check(not is_instance_valid(app.modal) and app.screen=="home","modal back closes one layer")
		await click(home.get_node("Layout/Bottom/Units"))
		await click(app.modal.get_node("ModalNavigateHome"))
		check(app.screen=="harbor" and not is_instance_valid(app.modal),"modal harbor exits directly")
	check(FileAccess.get_sha256("user://cas_port_v1.json")==source_sha and FileAccess.get_sha256("user://cas_port_v1.json.bak")==source_backup,"main account and backup remain untouched")
	var receipt:Dictionary={"checks":checks,"failures":failures,"passed":failures.is_empty(),"input_events":inputs,"baseline":baseline,"isolated_path":path}
	var output:=FileAccess.open("C:/Users/fwj/AppData/Local/Temp/CAS-home-navigation-v3-"+("baseline" if baseline else "receipt")+".json",FileAccess.WRITE)
	output.store_string(JSON.stringify(receipt,"\t"));print(JSON.stringify(receipt));app.core.close();app.queue_free();await process_frame;quit(0 if failures.is_empty() else 1)
