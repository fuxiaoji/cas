extends "res://tests/littoral_drag_v2_review.gd"
## Isolated UI + native authority; no normal account or live window is used.
func shot(_name:String)->void:pass
func run()->void:
	output_dir="res://../artifacts/combined-autonomy-v1/ui/"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_dir))
	main_hash=FileAccess.get_sha256("user://cas_port_v1.json");backup_hash=FileAccess.get_sha256("user://cas_port_v1.json.bak")
	profile=output_dir+"isolated-%d.json"%OS.get_process_id()
	var account=load("res://scripts/economy.gd").new(profile)
	if not check(account.load_state().get("ok",false),"ordinary isolated account loads"):return finish()
	app=load("res://scenes/main.tscn").instantiate();app.economy=account;app.boot_to_title=false;app.page_motion=false
	root.content_scale_size=Vector2i(1600,900);root.size=Vector2i(1280,720);root.add_child(app)
	await frames(4);app.set_process(false);app.page_motion=false
	var request:Dictionary={"op":"new_littoral","version":"cas-littoral-v4","company_layout":"multi-company-v1","seed":42,"mode":"tutorial","lesson":"landing","ships":[{"id":"IBS-U-USN-ERMA-IOWA","hp":100,"ammo":100},{"id":"CAS-H-USN-ENTERPRISE-1942","hp":100,"ammo":100},{"id":"CAS-O-APV-TIDEBRIDGE","hp":100,"ammo":100}],"roster":["MCP-034","MCP-001","MCP-009"],"transport_preset":"combat","defense":[]}
	if not check(app.core.request(request).get("ok",false),"actual v4 multi-company native battle created"):return finish()
	app.show_page("battle");await app.wait_for_page("battle");await frames(4)
	var command=controller()
	if command.tutorial!=null:command.tutorial_dismissed=true;command.tutorial.active=false;command.tutorial.hide()
	if not check(command.autonomy_button!=null,"editable controller creates one clear autonomy button"):return finish()
	for dimensions in [Vector2i(960,540),Vector2i(1280,720),Vector2i(1920,1080)]:
		root.size=dimensions;await frames(3)
		var bounds:Rect2=command.autonomy_button.get_global_rect()
		check(bounds.size.y>=48 and root.get_visible_rect().encloses(bounds),"autonomy touch target stays visible at "+str(dimensions))
	root.size=Vector2i(1280,720);await frames(3)
	check(not app.core.view.littoral.has("autonomy"),"unopted-in battle has no extra native state")
	await click(command.autonomy_button)
	check(bool(app.core.view.littoral.get("autonomy",{}).get("enabled",false)) and app.running,"pointer click starts actual commander and clock")
	check(command.autonomy_button.text=="接管指挥","button clearly offers immediate takeover")
	app.core.request({"op":"step","seconds":12});app.update_battle();await frames(4)
	check(app.core.view.littoral.groups.any(func(row):return row.stage in ["transit","ground"]),"AI issued actual legal multi-company deployment")
	check(app.core.view.littoral.autonomy.decisions.any(func(row):return row.get("accepted",false) and row.get("order",{}).get("op","")=="littoral_air_order"),"commander issued a validated carrier squadron order")
	await click(command.ui.get_node("MiniMap"))
	check(command.primary_map=="land" and command.autonomy_button.is_visible_in_tree(),"autonomy remains reachable when land becomes main map")
	var saved:String=app.core.request({"op":"save","serialized":true}).serialized
	var ui_state:Dictionary=command.serialize_ui_state();app.core.close()
	check(app.core.request({"op":"load","serialized":saved}).get("ok",false),"close and reopen rebuilds real commander from save")
	command.restore_ui_state(ui_state);app.update_battle();await frames(4)
	check(app.core.request({"op":"save","serialized":true}).serialized==saved and bool(app.core.view.littoral.autonomy.enabled),"UI restore preserves exact native log and enabled commander")
	await click(command.autonomy_button)
	check(not bool(app.core.view.littoral.autonomy.enabled) and command.autonomy_button.text=="一键托管","pointer takeover stops future automatic decisions")
	await click(command.autonomy_button)
	app.issue({"op":"littoral_ship_order","ship":1,"action":"hold"})
	check(not bool(app.core.view.littoral.autonomy.enabled),"successful real manual tactical order also takes over immediately")
	finish()
