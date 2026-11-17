extends SceneTree
const TransitionSettle=preload("res://tests/transition_settle.gd")
const Main=preload("res://scenes/main.tscn")
const Economy=preload("res://scripts/economy.gd")
const Recruit=preload("res://scripts/recruit_presentation.gd")
var app
var checks:=0
var failures:Array[String]=[]
var screenshots:Array[String]=[]
var output:="res://../artifacts/godot/full-modes/"

func _initialize() -> void:call_deferred("_run")
func check(value:bool,text:String) -> void:
	checks+=1
	if not value:failures.append(text);push_error(text)
func button(text:String) -> Button:
	for node in app.find_children("*","Button",true,false):
		if is_instance_valid(node) and str(node.text)==text:return node
	return null
func click(text:String) -> void:
	await TransitionSettle.wait_for_route(self,app)
	var control:=button(text)
	check(control!=null,"button reachable: "+text)
	if control:control.pressed.emit()
	await process_frame
func shot(name:String) -> void:
	await TransitionSettle.wait_for_route(self,app)
	await process_frame
	if DisplayServer.get_name()=="headless":return
	await RenderingServer.frame_post_draw
	var image:Image=app.get_viewport().get_texture().get_image()
	if image and image.save_png(ProjectSettings.globalize_path(output+name+".png"))==OK:screenshots.append(name+".png")
	else:check(false,"capture "+name)
func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	var path:="user://tests/full-mode-ui-%d.json"%OS.get_process_id()
	app=Main.instantiate();app.boot_to_title=false;app.economy=Economy.new(path);root.add_child(app)
	await process_frame
	for route in ["harbor","modes","academy","story","challenge","activity","archives","shop","roster","recruit"]:
		app.show_page(route)
		await process_frame
		check(app.screen==route and app.page.get_child_count()>0,"native page renders: "+route)
		await shot(route)
	# Explicit preview fixture: use a guaranteed featured tier only in this
	# disposable test account, so every artistic reveal state can be inspected.
	app.economy.config.gacha.weights={"ur":100,"elite":0,"rare":0,"common":0}
	app.economy.config.gacha.featured_ur_share=1.0
	var tickets:=int(app.economy.wallet().up_tickets)
	await click("征募十次　◇ 10")
	check(int(app.economy.wallet().up_tickets)==tickets-10 and app.economy.state.pending_recruit.draws.size()==10,"UP UI commits ten before animation")
	await shot("recruit-signal")
	await click("跳过演出")
	check(button("确认入列")!=null,"skip reaches committed manifest")
	await create_timer(0.7).timeout
	await shot("recruit-manifest")
	await click("确认入列")
	check(app.economy.state.pending_recruit.is_empty(),"confirm marks animation viewed")
	var sequence:=int(app.economy.state.draw_sequence)
	app.show_page("recruit")
	await click("上次到港")
	await create_timer(0.3).timeout
	await shot("recruit-missouri-face")
	check(int(app.economy.state.draw_sequence)==sequence and int(app.economy.wallet().up_tickets)==tickets-10,"face replay neither rerolls nor charges")
	app.close_modal()
	# Play the entire timeline on the already committed batch, never a new draw.
	var replay:Dictionary=app.economy.state.last_recruit.duplicate(true);replay.phase="signal"
	Recruit.reveal(app,replay)
	await create_timer(2.5).timeout
	check(button("查看总览")!=null,"full signal and approach timeline reaches character reveal")
	app.close_modal()
	app.show_page("academy")
	var ammo:=int(app.economy.wallet().ammo_stock)
	await click("白昼5对5演习")
	check(app.screen=="battle" and str(app.run.get("mode",""))=="exercise","exercise entry starts real borrowed mode")
	check(int(app.economy.wallet().ammo_stock)==ammo,"exercise UI does not consume personal ammo")
	app.save_leave()
	await process_frame
	check(app.screen=="harbor" and not app.economy.state.active_run.is_empty(),"save leave preserves borrowed mode")
	app.resume_run()
	await process_frame
	check(app.screen=="battle" and str(app.run.mode)=="exercise","borrowed mode resumes exact active snapshot")
	check(app.campaign_mode,"resumed borrowed mode keeps battle audio and mode classification")
	app.abandon()
	await process_frame
	check(app.economy.state.active_run.is_empty() and app.economy.latest_receipt().status=="abandoned","explicit abandon unlocks port without fake victory")
	app.audio.shutdown();app.core.close();app.queue_free();await process_frame
	for suffix in ["",".bak",".tmp"]:
		if FileAccess.file_exists(path+suffix):DirAccess.remove_absolute(ProjectSettings.globalize_path(path+suffix))
	var report:={"checks":checks,"passed":checks-failures.size(),"failures":failures,"screenshots":screenshots,"scope":"real native menu callbacks; featured-tier fixture isolated in temporary test account"}
	var file:=FileAccess.open(output+"ui-receipt.json",FileAccess.WRITE)
	if file:file.store_string(JSON.stringify(report,"\t"));file.close()
	print(JSON.stringify(report));quit(0 if failures.is_empty() else 1)
