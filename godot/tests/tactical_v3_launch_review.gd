extends "res://tests/littoral_drag_v2_review.gd"
## Actual new-story departure and pointer deployment; not a chapter playthrough.
func run()->void:
	output_dir="res://../artifacts/island-war-v3/presentation/"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_dir))
	main_hash=FileAccess.get_sha256("user://cas_port_v1.json");backup_hash=FileAccess.get_sha256("user://cas_port_v1.json.bak")
	var account=load("res://scripts/economy.gd").new(output_dir+"launch-isolated-%d.json"%OS.get_process_id());account.new_profile();account.state.progression.first_voyage_canon.active=false
	var service=load("res://scripts/canon_story_service.gd").new(account);service.ensure();service.state().selected="chapter-01";service.chapter().node="v2c1-landing"
	app=load("res://scenes/main.tscn").instantiate();app.economy=account;app.boot_to_title=false;app.deferred_startup=false;app.staged_navigation=false;app.immersive_fullscreen=false
	root.content_scale_size=Vector2i(1600,900);root.size=Vector2i(1600,900);root.add_child(app);await frames(6);app.page_motion=false;app.page_transition.cancel();app.set_process(false);AudioServer.set_bus_mute(0,true)
	service.state().selected="chapter-01";service.chapter().node="v2c1-landing"
	var wallet:Dictionary=account.state.wallet.duplicate(true);var owned:Dictionary=account.state.owned.duplicate(true)
	var launch:Dictionary=await load("res://scripts/canon_story_actions.gd").launch(app)
	check(launch.get("ok",false),"authored story action starts current native lesson: "+str(launch))
	if not launch.get("ok",false):return end_review()
	if not check(str(app.core.view.get("island_war",{}).get("version",""))=="cas-island-war-v3","actual departure uses new weapon version"):return end_review()
	check(str(account.state.active_run.context.request.version)=="cas-island-war-v3" and not account.state.active_run.context.request.has("intel_profile"),"strict new island request contains no incompatible naval extras")
	check(str(service.state().pending.run_id)==str(account.state.active_run.run_id),"story binds actual departure ID")
	check(controller().tutorial.active and str(controller().tutorial.get_script().resource_path).ends_with("tactical_weapons_tutorial_v3.gd"),"new state-driven coach appears on actual departure")
	check(not controller().tutorial._finished,"reading coach does not satisfy native goals")
	controller().interaction_event.connect(func(kind,data):events.append({"kind":kind,"data":data.duplicate(true),"tick":app.core.view.tick}))
	await shot("actual-story-before-first-drag")
	var company:String=controller().selected_unit
	var deployment:Control=card("Unit_"+company)
	check(deployment!=null,"actual company card available")
	var beach:Dictionary=app.core.view.littoral.beaches[1]
	var landing:Vector2=Vector2(float(beach.land.x),float(beach.land.y))
	if deployment!=null:await drag(deployment,world(landing),true)
	check(event_seen("deploy_queued"),"real touch drag queues lawful carrier approach")
	check(not controller().tutorial._finished,"accepted deployment still cannot finish lesson")
	var grounded:bool=false
	for i in range(90):
		var response:Dictionary=app.core.request({"op":"step","seconds":.5});check(response.get("ok",false),"native approach step")
		app.update_battle();await process_frame
		for row in app.core.view.littoral.groups:
			if str(row.id)==company and str(row.stage)=="ground":grounded=true
		if grounded:break
	check(grounded,"player's dragged company really reaches land")
	await click(controller().ui.get_node("MiniMap"));check(controller().primary_map=="land","pointer swaps to land for this actual lesson")
	check(controller().ui.get_node("LandWindow/Map").zoom>1,"first land lesson focuses the real landed company")
	check(not controller().tutorial.instruction_text().begins_with("点右上小地图切到陆地"),"map swap immediately updates instruction focus")
	await shot("actual-story-first-company-landed")
	check(account.state.wallet==wallet and account.state.owned==owned,"teaching loan consumes no owned units or supplies")
	end_review()
func end_review()->void:
	check(FileAccess.get_sha256("user://cas_port_v1.json")==main_hash and FileAccess.get_sha256("user://cas_port_v1.json.bak")==backup_hash,"formal main and backup untouched")
	var report:Dictionary={"ok":failures.is_empty(),"checks":checks,"failures":failures,"inputs":inputs,"scope":"Authored action launch, production Main/Progression/CanonService, true pointer company deployment and actual landing; no claimed chapter playthrough"}
	FileAccess.open(output_dir+"launch-receipt.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"));print(JSON.stringify(report));app.queue_free();quit(0 if failures.is_empty() else 1)
