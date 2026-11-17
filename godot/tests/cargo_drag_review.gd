extends SceneTree
const MainScene=preload("res://scenes/main.tscn")
const Economy=preload("res://scripts/economy.gd")
const Cargo=preload("res://scripts/cargo_presentation.gd")
const Service=preload("res://scripts/cargo_service.gd")
const Transition=preload("res://tests/transition_settle.gd")
class FrozenCargoEconomy extends Economy:
	func preview_sortie(seed:int,basic:bool=false,mission:Dictionary={})->Dictionary:
		var prepared:Dictionary=super.preview_sortie(seed,basic,mission)
		if not OS.get_cmdline_user_args().has("--adventure"):prepared.erase("gameplay_profile")
		return prepared
var app
var path:String
var failures:Array=[]
var checks:=0
var clicks:=0
var shots:Array=[]
var notices:Array=[]
var folder:String
var drags:=0
func _initialize()->void:call_deferred("run_test")
func check(ok:bool,title:String)->bool:
	checks+=1
	if not ok:failures.append(title);push_error(title)
	return ok
func issue(q:Dictionary,ok:bool=true)->Dictionary:
	var r:Dictionary=app.issue(q);check(bool(r.get("ok",false))==ok,str(q.op)+" "+str(r.get("error","ok")));return r
func client()->void:
	app=MainScene.instantiate();app.boot_to_title=false;app.economy=FrozenCargoEconomy.new(path);root.add_child(app);app.set_process(false)
	await process_frame;await Transition.wait_for_route(self,app)
func release()->void:
	app.core.close();app.queue_free();await process_frame;await process_frame
func shot(name:String)->void:
	await Transition.wait_for_route(self,app);await process_frame
	if DisplayServer.get_name()=="headless":return
	await RenderingServer.frame_post_draw
	var filename:=folder.path_join(name+".png");root.get_texture().get_image().save_png(filename);shots.append(filename)
func pointer(node:Control,local:Vector2)->void:
	await Transition.wait_for_route(self,app)
	# Wait for container minimum sizes and the asynchronous fullscreen/window resize.
	await process_frame;await process_frame;await create_timer(.06).timeout
	if DisplayServer.get_name()!="headless":await RenderingServer.frame_post_draw
	var point:Vector2=node.get_viewport().get_screen_transform()*node.get_global_transform_with_canvas()*local
	var motion:=InputEventMouseMotion.new();motion.position=point;Input.parse_input_event(motion);await process_frame
	for pressed in [true,false]:
		var event:=InputEventMouseButton.new();event.position=point;event.button_index=MOUSE_BUTTON_LEFT;event.pressed=pressed;Input.parse_input_event(event);await process_frame
	clicks+=1;await process_frame
func cargo_panel()->Control:return app.modal.get_node("CargoHold")
func find_button(node:Node,text:String)->Button:
	if node is Button and node.text==text and node.is_visible_in_tree():return node
	for child in node.get_children():
		var found:Button=find_button(child,text)
		if found!=null:return found
	return null
func screen_point(node:Control,local:Vector2)->Vector2:
	return node.get_viewport().get_screen_transform()*node.get_global_transform_with_canvas()*local
func motion_at(point:Vector2,held:bool=false)->void:
	var motion:=InputEventMouseMotion.new();motion.position=point;motion.button_mask=MOUSE_BUTTON_MASK_LEFT if held else 0;Input.parse_input_event(motion);await process_frame;await process_frame
func press_at(point:Vector2,pressed:bool=true,double:bool=false)->void:
	var event:=InputEventMouseButton.new();event.position=point;event.button_index=MOUSE_BUTTON_LEFT;event.pressed=pressed;event.double_click=double;Input.parse_input_event(event);await process_frame
func start_drag(node:Control,local:Vector2,target:Vector2)->void:
	await process_frame;await process_frame;await create_timer(.06).timeout
	var start:=screen_point(node,local);await motion_at(start);await press_at(start)
	for i in range(1,7):await motion_at(start.lerp(target,float(i)/6.0),true)
	drags+=1
func key(code:Key)->void:
	var event:=InputEventKey.new();event.keycode=code;event.pressed=true;Input.parse_input_event(event);await process_frame
	event=InputEventKey.new();event.keycode=code;Input.parse_input_event(event);await process_frame
func run_test()->void:
	path="user://tests/cargo-drag-review-%d.json"%OS.get_process_id()
	folder=ProjectSettings.globalize_path("res://../artifacts/godot/cargo-drag"+("-adventure" if OS.get_cmdline_user_args().has("--adventure") else ""));DirAccess.make_dir_recursive_absolute(folder)
	if OS.get_environment("CAS_SIM_PATH").is_empty():OS.set_environment("CAS_SIM_PATH",ProjectSettings.globalize_path("res://../target/release/cas-sim.exe"))
	await client()
	var id:String=str(app.economy.formation[0]);check(app.fleets.set_members([id]).ok,"real single owned fleet")
	check(app.economy.set_salvage_options({"difficulty":"calm","environment":"atoll","weather":"clear"}).ok,"persistent independent v4 options")
	var heavy:Dictionary=app.economy.cargo_budget();check(app.economy.set_cargo_loadout(id,50,false).ok,"less ammunition and actual torpedo omission")
	var light:Dictionary=app.economy.cargo_budget();check(int(light.max_kg)>int(heavy.max_kg),"capacity increases from real light loadout")
	Cargo.open_loadout(app);await shot("01-loadout");app.close_modal()
	app.set_meta("next_sortie_seed",40);app.launch(false,{"kind":"salvage","id":"calm"});await Transition.wait_for_route(self,app);app.running=false
	if not check(app.screen=="battle" and app.run.content=="salvage-v4","launch genuine v4 voyage"):await done();return
	check(int(app.core.view.salvage.ships[0].ammo)==50 and int(app.core.view.ships[0].ammo)==0,"native loadout budget and weapon supply agree")
	var x:float=app.core.view.ships[0].x;var y:float=app.core.view.ships[0].y
	var travel_seconds:=20 if OS.get_cmdline_user_args().has("--adventure") else 60
	issue({"op":"route","fleet":1,"mode":"follow","speed":6,"points":[{"x":x+400,"y":y}]});issue({"op":"step","seconds":travel_seconds})
	check(float(app.core.view.ships[0].x)>x+10,"actual low speed navigation to wreck")
	issue({"op":"salvage_collect","ruin":1});issue({"op":"step","seconds":2});await process_frame
	check(app.core.view.salvage.cargo_grid.items.size()==1,"one physical item revealed after two seconds")
	await shot("02-search-one-item");check(app.checkpoint(),"checkpoint partial search")
	var snapshot:Dictionary=app.core.view.salvage.duplicate(true);await release();await client();app.resume_run();await Transition.wait_for_route(self,app);app.running=false
	check(app.core.view.salvage==snapshot,"restart restores exact search and revealed item")
	issue({"op":"step","seconds":6});await process_frame
	if OS.get_cmdline_user_args().has("--adventure"):
		# New hostile telegraphs can interrupt a search. Resume the real action;
		# retained discoveries remain unique across interrupted searches.
		for attempt in range(3):
			if app.core.view.salvage.cargo_grid.items.size()>=4:break
			issue({"op":"search_salvage","ruin":1});issue({"op":"step","seconds":8})
	check(app.core.view.salvage.cargo_grid.items.size()==4 and app.core.view.salvage.cargo.size()==0,"search discovers four; UI never auto-loots")
	app.running=true;Cargo.open(app);await process_frame;check(not app.running,"organizing pauses simulation")
	var escape:=InputEventKey.new();escape.keycode=KEY_ESCAPE;escape.pressed=true;Input.parse_input_event(escape);await process_frame;await process_frame
	check(app.running and not is_instance_valid(app.modal),"Escape restores prior simulation state")
	app.running=false;Cargo.open(app);await process_frame;await process_frame;await create_timer(.1).timeout
	var panel:Control=cargo_panel();var first:Button=panel.list.get_child(0).get_child(1)
	var target:=screen_point(panel.grid,Vector2(6*44+22,22))
	await start_drag(first,first.size*.5,target)
	check(panel.dragging and panel.grid.preview_valid,"real held mouse list drag previews full fitting shape")
	check(app.core.view.salvage.cargo.size()==0,"drag preview never awards or moves native cargo")
	await shot("drag-valid-1280");await press_at(target,false)
	check(app.core.view.salvage.cargo_grid.items[0].placement==[6.0,0.0,0.0],"release list drag sends real native placement")
	panel=cargo_panel();target=screen_point(panel.grid,Vector2(4*44+22,2*44+22))
	await start_drag(panel.grid,Vector2(7*44+22,22),target)
	check(panel.grid.grab_offset==Vector2i(1,0),"grabbing second occupied cell preserves exact anchor")
	await press_at(target,false)
	check(app.core.view.salvage.cargo_grid.items[0].placement==[3.0,2.0,0.0],"grid drag moves without origin snapping")
	target=screen_point(panel.grid,Vector2(7*44+22,2*44+22))
	await start_drag(panel.grid,Vector2(4*44+22,2*44+22),target);await key(KEY_R)
	check(panel.grid.grab_offset==Vector2i(0,1) and panel.grid.preview_valid,"R rotates grabbed cell anchor inside edge")
	await press_at(target,false)
	check(app.core.view.salvage.cargo_grid.items[0].placement==[7.0,1.0,1.0],"release rotated grid drag commits native rotation")
	var second:Button=panel.list.get_child(1).get_child(1)
	target=screen_point(panel.grid,Vector2(22,22));await start_drag(second,second.size*.5,target);await press_at(target,false)
	check(app.core.view.salvage.cargo.size()==2,"second list drag carries second physical item")
	var untouched:Dictionary=app.core.view.salvage.cargo_grid.duplicate(true)
	target=screen_point(panel.grid,Vector2(44+22,2*44+22))
	await start_drag(panel.grid,Vector2(7*44+22,2*44+22),target)
	check(not panel.grid.preview_valid and panel.drag_hint.text.begins_with("×"),"overlap shows rejection by symbol and whole shape")
	await shot("drag-invalid-overlap");await press_at(target,false)
	check(app.core.view.salvage.cargo_grid==untouched,"overlap release keeps original authoritative placement")
	target=screen_point(panel,Vector2(-80,320));await start_drag(panel.grid,Vector2(7*44+22,2*44+22),target);await press_at(target,false)
	check(app.core.view.salvage.cargo_grid==untouched and not panel.dragging,"outside release cancels without destroying or dropping cargo")
	target=screen_point(panel.grid,Vector2(4*44+22,3*44+22));await start_drag(panel.grid,Vector2(7*44+22,2*44+22),target);await key(KEY_ESCAPE);await press_at(target,false)
	check(is_instance_valid(app.modal) and not panel.dragging and app.core.view.salvage.cargo_grid==untouched,"Escape cancels gesture before closing organizer")
	await start_drag(panel.grid,Vector2(7*44+22,2*44+22),target)
	var right:=InputEventMouseButton.new();right.position=target;right.button_index=MOUSE_BUTTON_RIGHT;right.pressed=true;Input.parse_input_event(right);await process_frame;right=InputEventMouseButton.new();right.position=target;right.button_index=MOUSE_BUTTON_RIGHT;Input.parse_input_event(right);await process_frame;await press_at(target,false)
	check(is_instance_valid(app.modal) and not panel.dragging and app.core.view.salvage.cargo_grid==untouched,"right click cancels gesture without abandoning cargo")
	# A double-click chooses a fit but never sorts existing items or invents a reward.
	var third:Button=panel.list.get_child(2).get_child(1);var point:=screen_point(third,third.size*.5)
	await motion_at(point);await press_at(point,true,true);await press_at(point,false)
	check(app.core.view.salvage.cargo.size()==3,"double click quickly stows one discovered item")
	check(app.core.view.salvage.cargo_grid.items[0].placement==untouched.items[0].placement and app.core.view.salvage.cargo_grid.items[1].placement==untouched.items[1].placement,"quick stow leaves hand arranged items unchanged")
	issue({"op":"cargo_drop","item":"v4-1-2"})
	issue({"op":"cargo_place","item":"v4-1-0","x":5,"y":2,"rotation":0});issue({"op":"cargo_place","item":"v4-1-1","x":3,"y":0,"rotation":0});panel.refresh()
	first=panel.list.get_child(0).get_child(1)
	await pointer(first,first.size*0.5);check(panel.selected=="v4-1-0","pointer selects native item")
	await pointer(panel.get_node("Rotate"),panel.get_node("Rotate").size*0.5)
	await pointer(panel.grid,Vector2(7*44+22,22));check(app.core.view.salvage.cargo_grid.items[0].placement==[7.0,0.0,1.0],"pointer rotates and packs shape at grid edge")
	var prior:Dictionary=app.core.view.salvage.cargo_grid.duplicate(true)
	issue({"op":"cargo_place","item":"v4-1-1","x":7,"y":0,"rotation":0},false);check(prior==app.core.view.salvage.cargo_grid,"invalid overlap leaves authoritative cargo unchanged")
	panel._pick("v4-1-1");await pointer(panel.grid,Vector2(22,22))
	check(app.core.view.salvage.cargo.size()==2,"only two chosen items carried")
	if DisplayServer.get_name()!="headless":
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED);DisplayServer.window_set_size(Vector2i(1280,720));await create_timer(.2).timeout
		check(DisplayServer.window_get_size()==Vector2i(1280,720),"cargo viewport at 1280 by 720")
	await shot("03-shaped-cargo-1280")
	if DisplayServer.get_name()!="headless":
		DisplayServer.window_set_size(Vector2i(960,540));await create_timer(.2).timeout;check(DisplayServer.window_get_size()==Vector2i(960,540),"cargo viewport at 960 by 540");await shot("04-shaped-cargo-960")
	for dimensions in [Vector2i(960,540),Vector2i(1280,720),Vector2i(1600,720)]:
		if DisplayServer.get_name()!="headless":DisplayServer.window_set_size(dimensions);await create_timer(.2).timeout
		target=screen_point(panel.grid,Vector2(6*44+22,44+22));await start_drag(panel.grid,Vector2(7*44+22,22),target)
		check(panel.dragging and panel.grid.preview_valid,"scaled pointer drag previews valid at "+str(dimensions))
		await shot("drag-valid-"+str(dimensions.x)+"x"+str(dimensions.y));await press_at(target,false)
		check(app.core.view.salvage.cargo_grid.items[0].placement==[6.0,1.0,1.0],"scaled pointer release native position at "+str(dimensions))
		target=screen_point(panel.grid,Vector2(7*44+22,22));await start_drag(panel.grid,Vector2(6*44+22,44+22),target);await press_at(target,false)
		check(app.core.view.salvage.cargo_grid.items[0].placement==[7.0,0.0,1.0],"scaled drag back restores layout at "+str(dimensions))
	app.close_modal();await process_frame
	issue({"op":"cargo_sort"})
	app.running=true;Cargo.open(app);await process_frame;panel=cargo_panel();panel._pick("v4-1-0")
	await pointer(panel.action,panel.action.size*.5)
	var held_tick:int=int(app.core.view.tick);check(not app.running,"discard confirmation stays paused")
	var cancel:Button=find_button(app,"取消");await pointer(cancel,cancel.size*.5)
	check(app.running and int(app.core.view.tick)==held_tick and app.core.view.salvage.cargo.size()==2,"cancel discard restores running state without dropping")
	Cargo.open(app);await process_frame;panel=cargo_panel();panel._pick("v4-1-0");await pointer(panel.action,panel.action.size*.5)
	check(not app.running,"second discard confirmation paused")
	var confirm:Button=find_button(app,"确认");await pointer(confirm,confirm.size*.5)
	check(not app.running and is_instance_valid(app.modal) and int(app.core.view.tick)==held_tick,"confirm keeps reopened organizer paused")
	check(app.core.view.salvage.cargo.size()==1,"real confirm permanently discards item")
	app.close_modal();await process_frame;check(app.running,"closing organizer after confirm restores original running state");app.running=false
	issue({"op":"cargo_place","item":"v4-1-0","x":0,"y":0,"rotation":0},false)
	notices=app.battle_controller.feedback.notice_history.duplicate(true)
	var adventure:bool=OS.get_cmdline_user_args().has("--adventure")
	check(notices.any(func(n):return str(n.kind)=="search_complete" or (adventure and str(n.kind)=="warning")),"real search or higher priority hostile feedback shown")
	check(notices.any(func(n):return str(n.kind)=="pickup" or (adventure and str(n.kind)=="warning")),"real stow or higher priority hostile feedback shown")
	if adventure:
		check(app.core.view.events.any(func(e):return str(e.kind)=="cargo_search_complete") and app.core.view.events.any(func(e):return str(e.kind)=="cargo_stowed"),"actual adventure search and carry events exist beneath danger priority")
	issue({"op":"salvage_extract","exit":0});issue({"op":"step","seconds":12})
	check(bool(app.core.view.salvage.extracted),"genuine timed frontier extraction")
	var save:Dictionary=app.core.request({"op":"save"});var replay:Dictionary=app.core.request({"op":"replay","save":save.data});check(replay.data==app.core.view,"actual cargo replay matches")
	var before_items:int=Service.new(app.economy).stash().items.size();app.finish_battle();await Transition.wait_for_route(self,app)
	check(bool(app.last_receipt.get("success",false)) and Service.new(app.economy).stash().items.size()==before_items+1,"atomic success deposits only carried shape")
	var receipt:Dictionary=app.last_receipt.duplicate(true);check(app.economy.settle_sortie(receipt).duplicate,"duplicate settlement cannot award twice")
	var result_button:Button=find_button(app,"整理带回物资")
	if not check(result_button!=null,"actual result exposes v4 cargo destination"):await done();return
	await pointer(result_button,result_button.size*.5);check(app.screen=="warehouse" and is_instance_valid(app.modal),"result button reaches physical port stash")
	await shot("05-port-grid-stash")
	var data:Dictionary=Service.new(app.economy).stash();var carried:String=str(data.items[-1].id);var currency:int=app.economy.wallet().credits
	var stash:Control=cargo_panel();await process_frame;await process_frame
	var item_button:Button=stash.list.get_child(stash.list.get_child_count()-1).get_child(1)
	target=screen_point(stash.grid,Vector2(8*44+22,44+22));await start_drag(item_button,item_button.size*.5,target);await press_at(target,false)
	check(Service.new(app.economy).stash().items[-1].placement==[8,1,0],"mother port drag reaches previously clipped rightmost grid columns")
	var old:Dictionary=Service.new(app.economy).stash().duplicate(true)
	app.close_modal();Cargo.open_stash(app);await process_frame;await process_frame
	stash=cargo_panel();check(Service.new(app.economy).stash()==old,"port placement persists after organizer reopened")
	await shot("stash-rightmost-column");item_button=stash.list.get_child(stash.list.get_child_count()-1).get_child(1)
	await pointer(item_button,item_button.size*.5);await pointer(stash.action,stash.action.size*.5)
	check(not Service.new(app.economy).stash().items.any(func(item):return str(item.id)==carried),"pointer unpacks real port item")
	check(Service.new(app.economy).stash().items.size()==before_items,"item cannot be redeemed twice")
	check(int(app.economy.wallet().credits)>currency or app.economy.state.item_instances.size()>0,"redeem converts to actual economy goods")
	app.close_modal();check(app.economy.service_all([id],50).ok,"real repair and reload service")
	app.set_meta("next_sortie_seed",40);app.launch(false,{"kind":"salvage","id":"calm"});await Transition.wait_for_route(self,app);app.running=false
	issue({"op":"route","fleet":1,"mode":"follow","speed":6,"points":[{"x":x+400,"y":y}]});issue({"op":"step","seconds":travel_seconds});issue({"op":"salvage_collect","ruin":1});issue({"op":"step","seconds":8});issue({"op":"cargo_place","item":"v4-1-0","x":0,"y":0,"rotation":0})
	var stash_count:int=Service.new(app.economy).stash().items.size();issue({"op":"salvage_abandon"});app.finish_battle();await Transition.wait_for_route(self,app)
	check(not bool(app.last_receipt.get("success",false)) and Service.new(app.economy).stash().items.size()==stash_count,"failure awards no unextracted physical goods")
	await shot("06-actual-failure")
	await done()
func done()->void:
	await release()
	var report:Dictionary={"checks":checks,"passed":checks-failures.size(),"failures":failures,"pointer_clicks":clicks,"real_pointer_drags":drags,"renderer":DisplayServer.get_name(),"synthetic_receipts":false,"screenshots":shots,"notices":notices,"isolated_profile":ProjectSettings.globalize_path(path)}
	var f:=FileAccess.open(folder.path_join("integration.json"),FileAccess.WRITE);f.store_string(JSON.stringify(report,"\t"));f.close();print(JSON.stringify(report));quit(0 if failures.is_empty() else 1)



