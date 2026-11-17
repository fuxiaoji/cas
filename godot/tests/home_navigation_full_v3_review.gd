extends SceneTree
const Economy=preload("res://scripts/economy.gd")
const Service=preload("res://scripts/home_service.gd")
const Transition=preload("res://tests/transition_settle.gd")
const OUTPUT:String="res://../artifacts/home-v3-20261114/"
var app
var home
var checks:int=0
var failures:Array[String]=[]
var inputs:int=0
var shots:Array=[]
var paths:Array=[]
func _initialize()->void:call_deferred("run")
func check(ok:bool,message:String)->bool:
	checks+=1
	if not ok:failures.append(message);push_error(message)
	return ok
func settle()->void:
	await process_frame;await process_frame;await Transition.wait_for_route(self,app)
func point(node:Control,local:Vector2)->Vector2:return node.get_viewport().get_screen_transform()*node.get_global_transform_with_canvas()*local
func click(node:Control)->void:
	if not check(is_instance_valid(node),"actual input target exists"):return
	var target:Vector2=point(node,node.size*.5);var motion:=InputEventMouseMotion.new();motion.position=target;Input.parse_input_event(motion);inputs+=1;await process_frame
	for pressed in [true,false]:
		var event:=InputEventMouseButton.new();event.position=target;event.global_position=target;event.button_index=MOUSE_BUTTON_LEFT;event.pressed=pressed;Input.parse_input_event(event);inputs+=1;await process_frame
	await settle()
func by_text(parent:Node,text:String)->Button:
	for node in parent.find_children("*","Button",true,false):
		if node.text==text:return node
	return null
func shot(name:String)->void:
	if DisplayServer.get_name()=="headless":return
	await process_frame;await process_frame
	await RenderingServer.frame_post_draw;var path:String=OUTPUT+name+".png";check(root.get_texture().get_image().save_png(path)==OK,"GPU "+name);shots.append({"path":path,"sha256":FileAccess.get_sha256(path)})
func enter_home()->void:
	await click(app.page.get_node("HomeIslandEntry"));home=app.page.get_node_or_null("HomeIsland")
	if home==null:print("ROUTE DEBUG ",app.screen," modal=",is_instance_valid(app.modal));await shot("unexpected-route");finish_abort(app);return
	check(app.screen=="home","Home entry completes without stale modal")
func run()->void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	var source_sha:String=FileAccess.get_sha256("user://cas_port_v1.json");var backup_sha:String=FileAccess.get_sha256("user://cas_port_v1.json.bak")
	var path:String="C:/Users/fwj/AppData/Local/Temp/CAS-home-nav-full-%d.json"%OS.get_process_id();var account=Economy.new(path);account.load_state();account.load_state();account.state.erase("test_account")
	var service=Service.new(account);service.state().unlocked=true;service.state().tutorial_complete=true;service.state()["drag_tutorial_completed"]=true
	for id in Service.RELEASED:service._own_unit(id)
	account.state.owned["IBS-U-IJN-NISSHIN"]=account._new_owned("IBS-U-IJN-NISSHIN");service.state().garrison=["IBS-U-IJN-NISSHIN"];service.state().tactical_garrison=["MCP-034","MCP-001"];account._commit(account.state.duplicate(true),"isolated progressed ordinary navigation fixture")
	app=load("res://scenes/main.tscn").instantiate();app.economy=account;app.boot_to_title=false;root.content_scale_size=Vector2i(1600,900);root.size=Vector2i(1280,720);root.add_child(app);app.set_process(false);await settle();app.page_motion=false
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	for dimensions in [Vector2i(960,540),Vector2i(1280,720),Vector2i(1920,1080)]:
		root.size=dimensions;await settle();await enter_home();await shot("home-residents-"+str(dimensions.x))
		check(home.island_actors.size()==2,"selected garrison identities appear as residents")
		var actor:Dictionary=home.island_actors["MCP-034"];var actor_before:Vector2=actor.button.position;home._process(1.2);check(actor.button.position.distance_to(actor_before)>1,"resident actually walks horizontally and hops")
		var before:Dictionary=account.state.duplicate(true);var disk:String=FileAccess.get_sha256(path);await click(actor.button)
		check(service._same(before,account.state) and FileAccess.get_sha256(path)==disk,"resident interaction is visual only, no account mutation")
		await click(home.get_node("Layout/Top/Training"));check(app.modal.name=="TrainingLessons" and app.modal.get_node("Lesson-combined")!=null,"three genuine training courses reachable")
		await shot("home-training-"+str(dimensions.x));await click(app.modal.get_node("ModalNavigateBack"));check(app.screen=="home" and not is_instance_valid(app.modal),"training Back stays at home")
		await click(home.get_node("Layout/Bottom/Build"));await click(home.find_child("Build_recycler",true,false));check(not home.building_kind.is_empty(),"real construction preview begins")
		before=account.state.duplicate(true);disk=FileAccess.get_sha256(path);await click(app.page.get_node("NavigateBack"));check(app.screen=="home" and home.building_kind.is_empty() and not home.get_node("Layout/Placement").visible,"Back cancels preview before route change")
		check(service._same(before,account.state) and FileAccess.get_sha256(path)==disk,"preview cancel charges nothing")
		await click(home.get_node("Layout/Bottom/Units"));await click(app.modal.find_child("Unit_MCP-034",true,false));await click(app.modal.get_node("ModalNavigateBack"));check(app.modal.find_child("Unit_MCP-034",true,false)!=null,"unit detail Back returns archive one layer")
		await click(app.modal.get_node("ModalNavigateBack"));check(not is_instance_valid(app.modal) and app.screen=="home","archive Back returns home")
		await click(home.get_node("Layout/Bottom/Garrison"));await click(app.modal.get_node("GarrisonTactical"));check(app.modal.find_child("TacticalGarrison_MCP-034",true,false).button_pressed,"saved tactical garrison visible")
		await shot("home-garrison-"+str(dimensions.x));await click(app.modal.get_node("ModalNavigateHome"));check(app.screen=="harbor" and not is_instance_valid(app.modal),"garrison direct Harbor clears full blocker")
		await enter_home();await click(home.get_node("Layout/Bottom/Recruit"));check(app.screen=="home_recruit","actual recruitment page opens")
		await click(app.page.get_node("NavigateBack"));check(app.screen=="home","recruit Back retains home parent")
		home=app.page.get_node("HomeIsland");await click(home.get_node("Layout/Bottom/Sortie"));check(is_instance_valid(app.modal) and not home.deployment_button.disabled,"ordinary owned two-company transport plan selectable")
		var selector:OptionButton=app.modal.find_child("CompanyTransport_MCP-034",true,false);check(selector!=null and selector.item_count==service.profile("MCP-034").transport_options.size() and selector.get_item_icon(0)!=null,"own default vehicle and all native legal family options")
		if selector==null:print("DEPLOYMENT DEBUG ",home.unit_selection," ",app.modal.find_children("CompanyTransport*","",true,false));return finish_abort(app)
		for node in [selector,app.modal.find_child("LittoralMode",true,false),app.modal.find_child("TransportPreset",true,false),app.modal.find_child("LaunchLittoral",true,false),app.modal.get_node("ModalNavigateBack"),app.modal.get_node("ModalNavigateHome")]:
			var touch_size:Vector2=point(node,node.size)-point(node,Vector2.ZERO);check(touch_size.y>=44,"44px interaction target at "+str(dimensions)+" "+str(node.name))
		await shot("home-sortie-"+str(dimensions.x));before=account.state.duplicate(true);disk=FileAccess.get_sha256(path);await click(app.modal.get_node("ModalNavigateHome"));check(app.screen=="harbor" and service._same(before,account.state) and FileAccess.get_sha256(path)==disk,"cancel sortie to Harbor has no fees")
	# Actual launch, save-to-harbor and resume must preserve the same active run.
	root.size=Vector2i(1280,720);await settle();await enter_home();await click(home.get_node("Layout/Bottom/Sortie"));await click(app.modal.find_child("LaunchLittoral",true,false));check(app.screen=="battle" and not account.state.active_run.is_empty(),"actual owned fleet launches native v3 battle")
	if app.screen=="battle":
		var run_id:String=str(account.state.active_run.run_id);await click(app.battle_controller.ui.get_node("Top/Menu"));await click(by_text(app.modal,"保存并返回母港"));check(app.screen=="harbor" and str(account.state.active_run.run_id)==run_id,"save Harbor preserves live run identity")
		await enter_home();await click(home.get_node("Layout/Bottom/Sortie"));await click(by_text(home.get_node("Layout/Notice"),"继续行动"));check(app.screen=="battle" and str(account.state.active_run.run_id)==run_id,"active run sortie resumes same native snapshot")
		await click(app.battle_controller.ui.get_node("Top/Menu"));await click(app.modal.get_node("ModalNavigateHome"));check(app.screen=="harbor" and not is_instance_valid(app.modal),"battle modal direct Harbor saves and never leaves blocker")
	check(FileAccess.get_sha256("user://cas_port_v1.json")==source_sha and FileAccess.get_sha256("user://cas_port_v1.json.bak")==backup_sha,"main account and backup untouched")
	var report:Dictionary={"checks":checks,"failures":failures,"passed":failures.is_empty(),"input_events":inputs,"isolated_path":path,"screenshots":shots,"runtime":OS.get_environment("CAS_SIM_PATH"),"display":DisplayServer.get_name(),"main_account_written":false,"sizes":[[960,540],[1280,720],[1920,1080]]}
	FileAccess.open(OUTPUT+("nav-headless.json" if DisplayServer.get_name()=="headless" else "nav-gpu.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"\t"));print(JSON.stringify(report));app.core.close();app.queue_free();await process_frame;quit(0 if failures.is_empty() else 1)
func finish_abort(owner:Node)->void:
	owner.core.close();quit(1)
