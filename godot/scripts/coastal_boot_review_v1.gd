extends SceneTree
const ROOT:String="res://../artifacts/coastal-rebuild-20261116/"
var failures:Array[String]=[]
var checks:int=0
var results:Array=[]
func _initialize()->void:call_deferred("run")
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures.append(label);push_error(label)
func run()->void:
	var hashes:Dictionary={}
	for name:String in ["cas_port_v1.json","cas_port_v1.json.bak"]:hashes[name]=FileAccess.get_sha256("user://"+name)
	var path:String=ProjectSettings.globalize_path(ROOT+"boot-player-%d.json"%OS.get_process_id())
	DirAccess.copy_absolute(ProjectSettings.globalize_path(ROOT+"player.json"),path)
	var boot=load("res://scenes/coastal_play_v1.tscn").instantiate()
	boot.profile_override=path
	boot.boot_completed.connect(func(result:Dictionary):results.append(result))
	root.size=Vector2i(1600,900);root.add_child(boot)
	check(boot.loading!=null and boot.loading.visible,"new entry presents loading layer immediately")
	var began:int=Time.get_ticks_msec()
	while results.is_empty() and Time.get_ticks_msec()-began<60000:await process_frame
	check(not results.is_empty() and results[0].get("ok",false),"new coastal boot completes successfully")
	while is_instance_valid(boot.app) and (boot.app.screen!="home" or boot.app._route_worker or boot.app.page_transition.is_busy()) and Time.get_ticks_msec()-began<60000:await process_frame
	check(boot.completed and not boot.failed,"new entry reaches completed state")
	check(not boot.loading.visible,"loading cover releases input")
	check(is_instance_valid(boot.app) and boot.app.screen=="home","new launcher opens real home island")
	if is_instance_valid(boot.app):
		var island=boot.app.page.get_node_or_null("HomeIsland")
		check(island!=null and is_instance_valid(island.canvas.world3d),"boot mounts new real 3D scene")
		if island!=null:check(str(island.canvas.native_projection.land.geography.version)=="cas-coastal-geography-v1","boot uses new native geography")
		if DisplayServer.get_name()!="headless":
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(ROOT+"boot-home.png")
		boot.app.core.close()
	for name:String in hashes:check(FileAccess.get_sha256("user://"+name)==hashes[name],"normal profile unchanged "+name)
	var report:Dictionary={"passed":failures.is_empty(),"checks":checks,"failures":failures,"elapsed_ms":Time.get_ticks_msec()-began,"headless":DisplayServer.get_name()=="headless","normal_profile_written":false}
	FileAccess.open(ROOT+"boot-review.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	print("COASTAL_BOOT_REVIEW ",JSON.stringify(report))
	boot.queue_free()
	for i in range(5):await process_frame
	quit(0 if failures.is_empty() else 1)
