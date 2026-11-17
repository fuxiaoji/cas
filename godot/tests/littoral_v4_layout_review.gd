extends "res://tests/littoral_drag_v2_review.gd"
## Explicit layout fixture: two genuine observations composed locally, no v4 gameplay claim.
func run()->void:
	output_dir="res://../artifacts/littoral-v4-ui/layout-fixture/";DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_dir))
	main_hash=FileAccess.get_sha256("user://cas_port_v1.json");backup_hash=FileAccess.get_sha256("user://cas_port_v1.json.bak")
	profile=output_dir+"isolated-%d.json"%OS.get_process_id()
	var account=load("res://scripts/economy.gd").new(profile);account.load_state()
	app=load("res://scenes/main.tscn").instantiate();app.economy=account;app.boot_to_title=false;app.fullscreen_battle=true
	root.content_scale_size=Vector2i(1600,900);root.size=Vector2i(1280,720);root.add_child(app);await frames();app.set_process(false);app.page_motion=false
	check(app.core.request({"op":"new_littoral","version":"cas-littoral-v3","mode":"tutorial","seed":42,"ships":[{"id":"IBS-U-USN-ERMA-IOWA","hp":100,"ammo":100},{"id":"IBS-U-IJN-NISSHIN","hp":100,"ammo":100}],"roster":["MCP-034","MCP-001"],"unit_condition":[{"id":"MCP-034","hp":100},{"id":"MCP-001","hp":100}],"transport_preset":"transport","defense":[]}).get("ok",false),"real old amphibious layout observation")
	var littoral:Dictionary=app.core.view.littoral.duplicate(true);littoral.version="cas-littoral-v4";littoral["seed"]=42;littoral["aviation"]={"squadrons":[],"aircraft":[]};littoral["corpses"]=[]
	check(app.core.request({"op":"new","seed":6106,"side":"allies","enemy":"gunnery","variant":"prologue","realtime":true}).get("ok",false),"real original World layout observation")
	var world_save:String=app.core.request({"op":"save","serialized":true}).serialized
	app.core.view["littoral"]=littoral
	app.show_page("battle");await frames(5)
	var naval=controller().naval_controller
	if not check(naval!=null,"original command desk is built in composed layout"):return finish()
	controller().tutorial_dismissed=true;controller().tutorial.active=false;controller().tutorial.hide()
	for dimensions in [Vector2i(960,540),Vector2i(1280,720),Vector2i(1920,1080)]:
		root.size=dimensions;await frames(5)
		var first:int=int(app.core.view.ships[0].id)
		await click(naval.hud.fleet_cards[first].button)
		check(naval.ship_id==first,"real pointer selects original ship in layout "+str(dimensions))
		await click(naval.hud.range_button);check(not app.sea.ranges_visible,"actual range button reachable "+str(dimensions));await click(naval.hud.range_button)
		await shot("sea-%dx%d"%[dimensions.x,dimensions.y])
		naval.show_tab("ship");await frames();await shot("drawer-%dx%d"%[dimensions.x,dimensions.y]);await click(naval.hud.tactical_button)
		check(naval.collapsed,"actual original drawer close remains reachable")
		await click(controller().ui.get_node("MiniMap"));check(controller().primary_map=="land","actual linked map swap reachable")
		await shot("land-%dx%d"%[dimensions.x,dimensions.y]);await click(controller().ui.get_node("MiniMap"))
	check(str(app.core.request({"op":"save","serialized":true}).serialized)==world_save,"layout inspection never changes authoritative World save")
	FileAccess.open(output_dir+"scope.json",FileAccess.WRITE).store_string(JSON.stringify({"scope":"Composed genuine World and old amphibious observations for layout only. Not a native v4 integration, aircraft or deployment proof.","normal_account_read_only":true},"  "))
	finish()
