extends SceneTree
## Headless scene/layout and real committed draw checks. No user window control.
const Boot=preload("res://scenes/boot.tscn")
var checks:int=0
var failures:Array=[]
var review_scope:String="headless actual Godot menu/layout and production economy/reveal checks; not visual GPU or mobile device acceptance"
var app
var boot
var directory:String="res://../artifacts/story-canon-v2/menus-%d/"%OS.get_process_id()
func _initialize()->void:call_deferred("run")
func check(ok:bool,label:String)->bool:
	checks+=1
	if not ok:failures.append(label);push_error(label)
	return ok
func go(route:String)->bool:
	app.show_page(route);return check(await app.wait_for_page(route),"staged route "+route)
func frames(count:int=3)->void:
	for i in count:await process_frame
func run()->void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	var before:Dictionary={"main":FileAccess.get_sha256("user://cas_port_v1.json"),"backup":FileAccess.get_sha256("user://cas_port_v1.json.bak")}
	var source:String="res://../artifacts/boot-loading-20261114/max-level-test-account-64476.json"
	DirAccess.copy_absolute(ProjectSettings.globalize_path(source),ProjectSettings.globalize_path(directory+"max-clone.json"))
	root.content_scale_size=Vector2i(1600,900);root.size=Vector2i(1280,720)
	var results:Array=[];boot=Boot.instantiate();boot.profile_override=ProjectSettings.globalize_path(directory+"max-clone.json");boot.boot_completed.connect(func(result):results.append(result));root.add_child(boot)
	var deadline:int=Time.get_ticks_msec()+60000
	while results.is_empty() and Time.get_ticks_msec()<deadline:await process_frame
	if results.is_empty() or not results[0].get("ok",false):check(false,"isolated real boot");await finish(before);return
	app=boot.app;app.set_process(false);app.page_motion=false
	if not await go("recruit"):await finish(before);return
	check(app.page.has_node("RecruitBanner/Pool_UP") and app.page.has_node("RecruitBanner/Pool_Standard") and app.page.has_node("RecruitBanner/Pool_Tactical"),"image-led three pool navigation")
	check(app.page.has_node("RecruitBanner/DrawOne") and app.page.has_node("RecruitBanner/DrawTen"),"separate clear draw controls")
	var tickets:int=int(app.economy.wallet().up_tickets)
	app.page.get_node("RecruitBanner/DrawOne").pressed.emit()
	await app.wait_for_page("recruit");await frames(5)
	check(int(app.economy.wallet().up_tickets)==tickets-1,"real ship draw consumes exactly one UP ticket")
	var pending:Dictionary=app.economy.state.get("pending_recruit",{})
	check(not pending.is_empty(),"ship result committed before animation")
	check(is_instance_valid(app.modal),"committed ship arrival animation opens after staged page readiness")
	if is_instance_valid(app.modal):
		var skip:Button
		for node in app.modal.find_children("*","Button",true,false):
			if node.text=="跳过演出":skip=node
		if check(skip!=null,"ship reveal still has skip control"):skip.pressed.emit()
		await frames(3)
		load("res://scripts/recruit_presentation.gd").complete(app,pending)
	check(int(app.economy.wallet().up_tickets)==tickets-1 and app.economy.state.get("pending_recruit",{}).is_empty(),"finishing presentation cannot draw or charge again")
	if not await go("home_recruit"):await finish(before);return
	var scene:Control=app.page.get_node("TacticalRecruit")
	check(scene.get_node("Layout/FeaturedScroll/Featured") is VBoxContainer and scene.get_node("Layout/FeaturedScroll/Featured").get_child_count()==20,"twenty personal portrait tabs in vertical scroll")
	check(scene.get_node("Portrait").get_global_rect().size.x>root.content_scale_size.x*.4,"tactical portrait receives broad image area")
	var unit_tickets:int=int(app.home.state().tickets)
	scene.get_node("Layout/Actions/DrawOne").pressed.emit();await frames(3)
	check(int(app.home.state().tickets)==unit_tickets-1 and is_instance_valid(scene.reveal),"real tactical draw commits once then opens protocol animation")
	if is_instance_valid(scene.reveal):scene.reveal._leave()
	await frames(3)
	var after_draw:int=int(app.home.state().tickets);scene._replay_draw();await frames(3)
	check(int(app.home.state().tickets)==after_draw,"replaying tactical animation cannot charge tickets")
	if is_instance_valid(scene.reveal):scene.reveal._leave()
	if not await go("activity"):await finish(before);return
	var hub:Control=app.page.get_node("ActivityHub")
	if not check(hub.has_method("bind"),"activity runtime script compiles and binds"):await finish(before);return
	check(hub.app==app and hub.get_node("Editorial").visible,"activity controller binds actual app and displays editorial layout")
	check(hub.has_node("Editorial/Editorial_tide_event") and hub.has_node("Editorial/Editorial_recruit") and hub.has_node("Editorial/Editorial_canon_catalog"),"activity overview uses real gameplay, UP and new-story image cards")
	check(hub.get_node("Editorial/Editorial_recruit").app==app,"editorial component exposes actual runtime button routes")
	for key in ["updates","campaigns","featured","supply"]:
		app.set_meta("activity_tab",key)
		if not await go("activity"):break
		check(app.page.get_node("ActivityHub/Tabs").get_child_count()==5,"activity left categories intact "+key)
		if key=="supply":
			var wide:Control=app.page.get_node("ActivityHub/Wide")
			check(wide.get_global_rect().end.x<=1601,"daily reward content stays inside UI canvas")
	await finish(before)
func finish(before:Dictionary)->void:
	if is_instance_valid(app):app.running=false;app.core.close()
	if is_instance_valid(boot):boot.queue_free();await frames(4)
	check(before=={"main":FileAccess.get_sha256("user://cas_port_v1.json"),"backup":FileAccess.get_sha256("user://cas_port_v1.json.bak")},"normal active account and backup untouched")
	var report:Dictionary={"checks":checks,"passed":failures.is_empty(),"failures":failures,"scope":review_scope}
	FileAccess.open(directory+"receipt.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"));print("IMAGE_MENUS "+JSON.stringify(report));quit(0 if failures.is_empty() else 1)
