extends SceneTree
## Explicit candidate entry; formal account and installed 27-person release stay separate.
func _initialize()->void:call_deferred("run")
func run()->void:
	OS.set_environment("CAS_SIXTH_INFANTRY_PREVIEW","1")
	OS.set_environment("CAS_SIM_PATH",ProjectSettings.globalize_path("res://../target-sixth/release/cas-sim.exe"))
	var account=load("res://scripts/economy.gd").new("res://../artifacts/sixth-infantry/demo-account.json")
	if FileAccess.file_exists(account.save_path):
		if not account.load_state().ok:quit(1);return
	else:
		if not account.new_profile().ok:quit(1);return
	account.state.active_run={};account.state.progression.first_voyage_canon.active=false
	var home=load("res://scripts/home_service.gd").new(account)
	home.state().unlocked=true;home.state().tutorial_complete=true;home.state().drag_tutorial_completed=true
	home._own_unit("MCP-306");home.state().tactical_garrison=["MCP-306"]
	for id in ["CAS-O-APV-TIDEBRIDGE","CAS-H-USN-ENTERPRISE-1942"]:account.state.owned[id]=account._new_owned(id)
	home.state().garrison=["CAS-O-APV-TIDEBRIDGE","CAS-H-USN-ENTERPRISE-1942"]
	account.save_state()
	var app=load("res://scenes/main.tscn").instantiate()
	app.economy=account;app.boot_to_title=false;app.immersive_fullscreen=false;app.staged_navigation=false
	root.add_child(app)
	for i in range(8):await process_frame
	app.page_motion=false;app.page_transition.cancel();app.show_page("home")
	if "--audit" in OS.get_cmdline_user_args():
		for i in range(12):await process_frame
		RenderingServer.force_draw(false)
		root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../artifacts/sixth-infantry/demo-home.png"))
		print("SIXTH_DEMO_READY ",app.home.latest_unit("MCP-306").get("designation","missing"))
		app.core.close();quit()
