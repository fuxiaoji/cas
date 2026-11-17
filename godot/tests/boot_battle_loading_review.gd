extends SceneTree
## Uses the actual lightweight project entry and real native authority. No normal
## profile mutation: the old account snapshot and fresh lesson use isolated files.
const OUT:String="res://../artifacts/boot-loading-20261114/battle/"
var checks:int=0
var failures:Array[String]=[]
var pictures:Array[String]=[]
var boot
var app
var main_sha:String
var bak_sha:String
func _initialize()->void:run.call_deferred()
func check(value:bool,label:String)->bool:
	checks+=1
	if not value:failures.append(label);push_error(label)
	return value
func frames(count:int=3)->void:
	for i in count:await process_frame
func wait_boot()->bool:
	var start:int=Time.get_ticks_msec()
	while not boot.completed and not boot.failed and Time.get_ticks_msec()-start<60000:await process_frame
	return check(boot.completed and not boot.failed,"real Boot completed without a startup failure")
func wait_route(route:String)->bool:
	var start:int=Time.get_ticks_msec()
	while Time.get_ticks_msec()-start<60000:
		if app.screen==route and not app._route_worker and not app.page_transition.is_busy():
			await frames();return check(true,"real staged route settled: "+route)
		await process_frame
	return check(false,"real staged route timed out: "+route)
func mount(profile:String)->bool:
	boot=load("res://scenes/boot.tscn").instantiate();boot.profile_override=profile
	root.add_child(boot)
	if not await wait_boot():return false
	app=boot.app
	return check(app.staged_navigation and app.deferred_startup,"normal entry enables actual staged startup and navigation")
func shot(label:String)->void:
	if DisplayServer.get_name()=="headless":return
	await RenderingServer.frame_post_draw
	var path:String=OUT+label+".png"
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path(path));pictures.append(path)
func unmount()->void:
	if is_instance_valid(app):app.running=false;app.core.close()
	if is_instance_valid(boot):boot.queue_free()
	await frames(5)
func run()->void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	main_sha=FileAccess.get_sha256("user://cas_port_v1.json");bak_sha=FileAccess.get_sha256("user://cas_port_v1.json.bak")
	root.content_scale_size=Vector2i(1600,900);root.size=Vector2i(1280,720)
	var prior:String=OUT+"old-account-%d.json"%OS.get_process_id()
	DirAccess.copy_absolute(ProjectSettings.globalize_path("res://../artifacts/mobile-home-20261113/navigation/isolated-navigation-68676.json"),ProjectSettings.globalize_path(prior))
	if await mount(prior):
		check(app.economy.state.owned.size()==43,"real prior account clone loads its actual 43 ships")
		var run_id:String=str(app.economy.state.active_run.run_id)
		var wallet:String=JSON.stringify(app.economy.state.wallet)
		# Same signal as the title's Continue button, then the exact public handler.
		app.resume_run()
		if await wait_route("battle"):
			check(app.battle_controller!=null and is_instance_valid(app.sea),"battle controller and map exist before resume post-actions")
			check(str(app.core.view.littoral.version)=="cas-littoral-v1","real old run keeps its v1 ruleset")
			check(is_equal_approx(float(app.core.view.tick),40.2),"loading and reveal never advance the saved simulation clock")
			check(not app.running,"old paused run stays paused after asynchronous resume")
			check(str(app.economy.state.active_run.run_id)==run_id and JSON.stringify(app.economy.state.wallet)==wallet,"loading neither duplicates a run nor spends currency")
			await shot("resumed-real-v1-battle")
			app.go_home()
			if await wait_route("harbor"):
				check(not app.fullscreen_battle,"return from loaded battle restores window mode")
				check(str(app.economy.state.active_run.run_id)==run_id,"return retains the actual unfinished run")
	await unmount()
	var fresh:String=OUT+"fresh-lesson-%d.json"%OS.get_process_id()
	if await mount(fresh):
		app.show_page("harbor");await wait_route("harbor")
		var plan:Dictionary=app.home.prepare_littoral("tutorial",42,[],[],"balanced","cas-littoral-v4","combined")
		if check(plan.get("ok",false),"ordinary new account prepares an actual borrowed v4 combined lesson"):
			app.launch_littoral(plan.request)
			if await wait_route("battle"):
				check(app.battle_controller.naval_controller!=null,"new v4 keeps the real naval controller under the loading route")
				check(app.core.view.littoral.version=="cas-littoral-v4","the launched lesson uses installed explicit v4")
				check(float(app.core.view.tick)==0 and not app.running,"launch waits for actual loading while simulation remains paused")
				check(app.economy.state.active_run.request.lesson=="combined","one actual combined lesson is durably committed")
				await shot("new-v4-combined-battle")
				check(app.checkpoint(),"new controller can checkpoint after staged loading")
				var saved:String=str(app.core.request({"op":"save","serialized":true}).get("serialized",""))
				app.go_home();await wait_route("harbor")
				app.resume_run();await wait_route("battle")
				check(str(app.core.request({"op":"save","serialized":true}).get("serialized",""))==saved,"reload through staged cover preserves exact native snapshot")
				app.running=false
	await unmount()
	var full:String=OUT+"max-account-%d.json"%OS.get_process_id()
	DirAccess.copy_absolute(ProjectSettings.globalize_path("res://../artifacts/boot-loading-20261114/max-level-test-account-64476.json"),ProjectSettings.globalize_path(full))
	if await mount(full):
		check(app.economy.state.owned.size()==206 and app.home.state().units.size()==20,"requested actual full account boots with all 206 ships and 20 tactical personalities")
		await shot("full-account-title")
		app.page.get_node("TitleScreen/Actions/Begin").pressed.emit()
		if await wait_route("harbor"):
			await shot("full-account-harbor")
			app.show_page("roster");await wait_route("roster")
			check(app.economy.roster().size()==206,"actual roster prepares and displays the full catalogue")
			await shot("full-account-roster")
			app.go_home();await wait_route("harbor")
			app.show_page("home");await wait_route("home")
			await shot("full-account-home")
			app.go_home();await wait_route("harbor")
			var wallet_before:Dictionary=app.economy.state.wallet.duplicate(true)
			app.launch(false)
			if await wait_route("battle"):
				check(app.battle_controller!=null and is_instance_valid(app.sea),"full-account salvage controller exists before automatic pilot is resumed")
				check(not app.economy.state.active_run.is_empty(),"one real salvage departure was committed")
				check(int(app.economy.state.wallet.credits)<=int(wallet_before.credits),"loading cannot mint departure currency")
				app.running=false
				await shot("full-account-salvage")
	await unmount()
	check(FileAccess.get_sha256("user://cas_port_v1.json")==main_sha and FileAccess.get_sha256("user://cas_port_v1.json.bak")==bak_sha,"normal main and backup remain byte-identical")
	var result:Dictionary={"ok":failures.is_empty(),"checks":checks,"failures":failures,"pictures":pictures,"renderer":DisplayServer.get_name(),"normal_main_sha":main_sha,"normal_backup_sha":bak_sha}
	var file=FileAccess.open(OUT+("headless" if DisplayServer.get_name()=="headless" else "gpu")+"-receipt.json",FileAccess.WRITE);file.store_string(JSON.stringify(result,"\t"));file.close()
	print(JSON.stringify(result));quit(0 if failures.is_empty() else 1)
