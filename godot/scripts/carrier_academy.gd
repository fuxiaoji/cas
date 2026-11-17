extends SceneTree
## Playable naval practice with an isolated profile and explicit new aviation.
func _initialize()->void:call_deferred("run")
func run()->void:
	var app=load("res://scenes/main.tscn").instantiate();app.boot_to_title=false;app.fullscreen_battle=true
	app.economy=load("res://scripts/economy.gd").new("user://carrier-academy/practice.json");app.economy.load_state()
	root.content_scale_size=Vector2i(1600,900);root.add_child(app);await process_frame;await process_frame;app.page_motion=false
	var q:Dictionary={"op":"new_littoral","version":"cas-littoral-v4","mode":"raid","seed":42,"ships":[{"id":"CAS-H-USN-ENTERPRISE-1942","hp":100,"ammo":100},{"id":"CAS-H-IJN-SHOKAKU-1942","hp":100,"ammo":100},{"id":"IBS-U-USN-ERMA-IOWA","hp":100,"ammo":100}],"roster":["MCP-034","MCP-001"],"unit_condition":[],"transport_preset":"combat","defense":[]}
	var response:Dictionary=app.core.request(q)
	if not response.get("ok",false):push_error(str(response));quit(1);return
	response=app.core.request({"op":"carrier_automation","version":"cas-carrier-ops-v3","level":"high"})
	if not response.get("ok",false):push_error(str(response));quit(1);return
	app.show_page("battle");await app.wait_for_page("battle");app.running=false
	if app.battle_controller.tutorial!=null:app.battle_controller.tutorial_dismissed=true;app.battle_controller.tutorial.active=false;app.battle_controller.tutorial.hide()
	load("res://scripts/carrier_command_desk.gd").open(app.battle_controller)
