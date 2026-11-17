extends SceneTree
const Economy=preload("res://scripts/economy.gd")
const Store=preload("res://scripts/simulated_store.gd")
const Settle=preload("res://tests/transition_settle.gd")
var checks:=0
var failures:Array[String]=[]
var app
var output:="res://../artifacts/godot/liveops-growth/"
func _initialize() -> void:call_deferred("run")
func check(value:bool,title:String) -> void:
	checks+=1
	if not value:failures.append(title);push_error(title)
func click(text:String) -> void:
	await Settle.wait_for_route(self,app)
	var target:Button
	for node in app.find_children("*","Button",true,false):
		if node.text==text and node.is_visible_in_tree():target=node;break
	check(target!=null,"visible button: "+text)
	if target==null:return
	var point:Vector2=target.get_viewport().get_screen_transform()*target.get_global_transform_with_canvas()*(target.size*.5)
	var motion:=InputEventMouseMotion.new();motion.position=point;Input.parse_input_event(motion)
	var down:=InputEventMouseButton.new();down.button_index=MOUSE_BUTTON_LEFT;down.position=point;down.pressed=true;Input.parse_input_event(down);await process_frame
	var up:=InputEventMouseButton.new();up.button_index=MOUSE_BUTTON_LEFT;up.position=point;Input.parse_input_event(up);await process_frame;await process_frame
func shot(name:String) -> void:
	if DisplayServer.get_name()=="headless":return
	await Settle.wait_for_route(self,app)
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(ProjectSettings.globalize_path(output+name+".png"))==OK,"real viewport saved: "+name)
func run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	var path:="user://tests/liveops-store-%d.json"%OS.get_process_id()
	var account=Economy.new(path);account.load_state()
	var store=Store.new(account)
	var origins:int=account.wallet().origins
	var commander:Dictionary=account.player_profile().duplicate(true)
	check(store.catalog().size()==6,"six simulated packs")
	check(not store.create_order("missing","bad").ok,"reject nonexistent pack")
	var order:Dictionary=store.create_order("demo-300","order-one").order
	check(int(account.wallet().origins)==origins and order.status=="pending","creating order grants nothing")
	check(store.create_order("demo-300","order-one").get("duplicate",false) and store.orders().size()==1,"creation request replay keeps same order")
	check(not store.create_order("demo-60","order-one").ok,"request id cannot change pack")
	account=Economy.new(path);account.load_state();store=Store.new(account)
	check(store.orders()[0].status=="pending","pending order survives restart")
	check(store.complete_order(str(order.id),"fulfill-one").ok,"fulfill local simulation")
	check(int(account.wallet().origins)==origins+300,"single exact grant")
	check(store.complete_order(str(order.id),"fulfill-one").get("duplicate",false),"same request completion replay")
	check(store.complete_order(str(order.id),"different-fulfill").get("duplicate",false) and int(account.wallet().origins)==origins+300,"new request cannot double credit fulfilled order")
	check(account.player_profile()==commander,"simulated money grants no commander xp")
	var cancelled:Dictionary=store.create_order("demo-60").order
	check(store.cancel_order(str(cancelled.id)).ok and not store.complete_order(str(cancelled.id)).ok,"cancelled order cannot fulfill")
	account.state.active_run={"id":"test-lock"}
	check(not store.create_order("demo-60").ok,"active sortie blocks simulated store")
	account.state.active_run={}
	var pending:Dictionary=store.create_order("demo-60").order
	var saved_path:String=account.save_path
	var before:Dictionary=account.state.duplicate(true)
	account.save_path="user://tests/blocked-store-%d/slot.json"%OS.get_process_id()
	var block:=FileAccess.open(account.save_path.get_base_dir(),FileAccess.WRITE);block.store_string("read-only path fixture");block.close()
	check(not store.complete_order(str(pending.id),"write-failure").ok and account.state==before,"failed save rolls back balance and pending status")
	account.save_path=saved_path
	check(store.complete_order(str(pending.id),"write-failure").ok and int(account.wallet().origins)==origins+360,"retry after failed save grants once")
	check(account.purchase("origins-up").ok,"simulated resource uses same ordinary currency exchange")
	app=load("res://scenes/main.tscn").instantiate();app.boot_to_title=false;app.economy=account;root.add_child(app);await process_frame;await process_frame
	check(app.page.find_child("Harbor",true,false)!=null,"runtime harbor uses editable scene")
	await shot("01-harbor")
	await click("活动");check(app.screen=="activity","actual activity route")
	await shot("02-activity")
	await click("更新公告");check(str(app.get_meta("activity_tab"))=="updates","announcement tab")
	await shot("03-updates")
	await click("战役进度")
	var campaign:Dictionary=app.core.request({"op":"campaign"});var rows:Array=campaign.data.scenarios
	var playable:=0;var verified:=0
	for row in rows:
		if row.get("playable",false):playable+=1
		if row.get("runtime",{}).get("historicalReady",false):verified+=1
	var actual_label:=false
	for node in app.find_children("*","Label",true,false):
		if node.text=="可试玩 %d 份  /  历史核验完成 %d 份"%[playable,verified]:actual_label=true
	check(actual_label,"campaign development label reflects core catalog, not invented progress")
	await shot("04-campaign-progress")
	await click("本期UP");await shot("05-featured")
	await click("前往UP征募");check(app.screen=="recruit" and app.get_meta("recruit_pool")=="up","UP action opens actual featured pool")
	app.show_page("activity");await click("回港补给")
	var first_reward:=false
	for node in app.find_children("*","Label",true,false):
		if node.text.contains("银币 ×500") and node.text.contains("常驻券 ×2"):first_reward=true
	check(first_reward,"attendance presentation includes every simultaneous reward")
	await click("领取今日签到")
	var tomorrow:=false;var disabled:=false
	for node in app.find_children("*","Label",true,false):
		if node.text=="明日可领":tomorrow=true
	for node in app.find_children("*","Button",true,false):
		if node.text=="领取今日签到":disabled=node.disabled
	check(tomorrow and disabled,"today claimed does not advertise next-day claim")
	await shot("05b-attendance")
	app.show_page("harbor");await click("军需");await click("模拟充值")
	check(app.page.find_child("SimulatedRecharge",true,false)!=null,"runtime recharge uses editable scene")
	var art_paths:Dictionary={}
	for node in app.find_child("Packs",true,false).get_children():
		var texture:Texture2D=node.get_node("Body/Art").texture
		if texture!=null:art_paths[texture.resource_path]=true
	check(art_paths.size()==6,"six distinct original pack artworks, no breakthrough core reuse")
	await shot("06-simulated-store")
	await click("生成模拟订单");check(is_instance_valid(app.modal),"actual pointer creates order and opens review")
	var balance:int=account.wallet().origins
	await shot("07-simulation-confirmation")
	await click("模拟到账");check(int(account.wallet().origins)==balance+60,"actual confirmation pointer credits exactly one pack")
	await click("模拟订单记录");await shot("08-simulation-history")
	app.close_modal();app.show_page("harbor");await click("指挥官 Lv.%d"%int(account.player_profile().level))
	check(app.screen=="player","commander profile entry accessible")
	await shot("09-commander")
	var report:Dictionary={"checks":checks,"failures":failures,"display":DisplayServer.get_name(),"campaigns":{"playable":playable,"historically_verified":verified},"profile":path}
	var file:=FileAccess.open(output+"report.json",FileAccess.WRITE);file.store_string(JSON.stringify(report,"  "));file.close()
	app.core.close();app.queue_free();await process_frame
	print("LIVEOPS_STORE_REVIEW ",JSON.stringify(report));quit(0 if failures.is_empty() else 1)

