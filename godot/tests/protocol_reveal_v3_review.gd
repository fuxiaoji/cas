extends SceneTree
const Economy = preload("res://scripts/economy.gd")
const Output: String = "res://../artifacts/protocol-reveal-v3/"
var checks: int = 0
var failures: Array[String] = []
var input_events: int = 0
var app
var profile: String
var main_sha: String
var backup_sha: String
var shots: Array[String] = []
func _initialize() -> void: call_deferred("run")
func check(value: bool, title: String) -> void:
	checks += 1
	if not value: failures.append(title);push_error(title)
func frame() -> void:
	await process_frame;await process_frame;await process_frame
func click(node: Control) -> void:
	var point: Vector2 = root.get_screen_transform()*node.get_global_transform()*(node.size*.5)
	for pressed: bool in [true, false]:
		var event := InputEventMouseButton.new();event.button_index=MOUSE_BUTTON_LEFT;event.position=point;event.pressed=pressed;Input.parse_input_event(event);input_events+=1;await process_frame
	await frame()
func shot(title: String) -> void:
	if DisplayServer.get_name()=="headless":return
	await process_frame;await RenderingServer.frame_post_draw
	var path: String=Output+title+".png"
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path(path));shots.append(ProjectSettings.globalize_path(path))
func run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(Output))
	main_sha=FileAccess.get_sha256("user://cas_port_v1.json");backup_sha=FileAccess.get_sha256("user://cas_port_v1.json.bak")
	profile=Output+"ordinary-%d.json"%OS.get_process_id()
	var source: String="res://../artifacts/littoral-drag/guide-player-realtime/isolated-guide-56436.json"
	check(FileAccess.file_exists(source),"legitimate prior normal tutorial completion baseline exists")
	if not FileAccess.file_exists(source):return finish()
	FileAccess.open(profile,FileAccess.WRITE).store_string(FileAccess.get_file_as_string(source))
	var account=Economy.new(profile);check(account.load_state().get("ok",false),"ordinary isolated winner loads")
	app=load("res://scenes/main.tscn").instantiate();app.economy=account;app.boot_to_title=false;root.add_child(app);app.set_process(false);await frame()
	app.page_motion=false;app.set_meta("reduced_motion",false)
	root.content_scale_size=Vector2i(1600,900);root.content_scale_mode=Window.CONTENT_SCALE_MODE_CANVAS_ITEMS;root.size=Vector2i(1280,720)
	app.show_page("home_recruit");await frame()
	var recruit=app.page.get_node("TacticalRecruit")
	var sequence: int=int(app.home.state().draw_sequence);var tickets: int=int(app.home.state().tickets)
	check(tickets>=10,"ordinary first tutorial awards enough tickets for real ten draw")
	await click(recruit.get_node("Layout/Actions/DrawTen"))
	check(int(app.home.state().draw_sequence)==sequence+10,"real draw consumes one committed ten-result transaction")
	check(int(app.home.state().tickets)==tickets-10,"ten tickets charged exactly once")
	check(is_instance_valid(recruit.reveal),"actual DrawTen input opens full-screen protocol animation")
	if not is_instance_valid(recruit.reveal):return finish()
	var reveal=recruit.reveal
	await create_timer(.45).timeout
	check(reveal.phase_time>=.35,"real render frames advance signal animation without economy callbacks")
	reveal.set_process(false);reveal.phase_time=.5;reveal._refresh();await shot("01-finding-signal")
	check(reveal.phase=="signal" and not reveal.get_node("IdentityPortrait").visible,"signal phase precedes identity reveal")
	reveal.phase_time=1.9;reveal._refresh();await shot("02-identity-closeup")
	check(reveal.get_node("IdentityCloseup").visible,"own portrait closeup enters during handshake")
	reveal.phase_time=3.6;reveal._refresh();await shot("03-personality-revealed")
	check(reveal.get_node("ConfirmReveal").visible and reveal.phase=="revealed","full portrait reveal reaches confirm stage")
	check(reveal.get_node("IdentityPortrait").texture.resource_path==str(reveal.results[0].portrait),"committed identity uses its own portrait")
	check(reveal.get_node("IdentityType").visible,"revealed identity includes its actual military type")
	await click(reveal.get_node("RevealBack"));check(not is_instance_valid(recruit.reveal),"return closes reveal immediately without trapping input")
	check(int(app.home.state().draw_sequence)==sequence+10 and int(app.home.state().tickets)==tickets-10,"closing animation never charges again")
	check(recruit.get_node("Layout/ReplayCommittedDraw").visible,"committed results remain available after interrupted animation")
	await click(recruit.get_node("Layout/ReplayCommittedDraw"));reveal=recruit.reveal;await frame()
	check(reveal.results==app.home.state().last_draw,"replay uses exact durable committed results")
	await click(reveal.get_node("SkipReveal"));await shot("04-ten-results")
	check(reveal.phase=="all" and reveal.get_node("CommittedResults").get_child_count()==10,"skip shows all ten committed portraits")
	for window_size: Vector2i in [Vector2i(960,540),Vector2i(1280,720),Vector2i(1920,1080)]:
		root.size=window_size;await frame()
		for node_name: String in ["RevealBack","RevealHome","ConfirmReveal"]:
			var node: Control=reveal.get_node(node_name);check(Rect2(Vector2.ZERO,reveal.size).encloses(node.get_global_rect()),"navigation and confirmation visible at %s/%s"%[window_size,node_name])
		await shot("ten-results-%d"%window_size.x)
	await click(reveal.get_node("RevealHome"));check(app.screen=="harbor","direct home works from active reveal")
	check(int(app.home.state().draw_sequence)==sequence+10,"skip replay and home preserve committed sequence")
	app.show_page("home_recruit");await frame();recruit=app.page.get_node("TacticalRecruit")
	app.set_meta("reduced_motion",true)
	await click(recruit.get_node("Layout/ReplayCommittedDraw"));reveal=recruit.reveal
	check(reveal.phase=="revealed" and not reveal.get_node("IdentityCloseup").visible,"reduced motion reveals identity immediately without sweeping closeup")
	await click(reveal.get_node("ConfirmReveal"));check(reveal.result_index==1,"next actual button shows second committed identity")
	await click(reveal.get_node("RevealBack"))
	check(int(app.home.state().draw_sequence)==sequence+10 and int(app.home.state().tickets)==tickets-10,"reduced-motion replay and next identity never repeat payment")
	app.core.close();app.queue_free();await frame()
	var restored=Economy.new(profile);check(restored.load_state().get("ok",false),"committed draw survives full reload")
	check(int(restored.state.home_v1.draw_sequence)==sequence+10 and restored.state.home_v1.last_draw.size()==10,"durable outcome survives leaving during animation")
	finish()
func finish() -> void:
	if is_instance_valid(app):app.core.close();app.queue_free()
	check(main_sha==FileAccess.get_sha256("user://cas_port_v1.json"),"user profile unchanged")
	check(backup_sha==FileAccess.get_sha256("user://cas_port_v1.json.bak"),"user backup unchanged")
	var report: Dictionary={"passed":failures.is_empty(),"checks":checks,"failures":failures,"input_events":input_events,"profile":ProjectSettings.globalize_path(profile),"source_sha256":main_sha,"backup_sha256":backup_sha,"images":shots}
	FileAccess.open(Output+"receipt.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "));print("PROTOCOL_REVEAL "+JSON.stringify(report));quit(0 if failures.is_empty() else 1)
