extends "res://tests/littoral_drag_v2_review.gd"
## Two newly released identities, genuine finite ability, responsive drag coordinates,
## and a complete account/core close and reload. QA ownership is explicit and isolated.
var selected_profile_source:String
var clone_sha:String
func run()->void:
	output_dir="res://../artifacts/littoral-drag/identity-responsive/"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_dir))
	main_hash=FileAccess.get_sha256("user://cas_port_v1.json");backup_hash=FileAccess.get_sha256("user://cas_port_v1.json.bak")
	var report:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://../artifacts/drag-littoral-v2/account/report.json"))
	selected_profile_source=str(report.profile);clone_sha=FileAccess.get_sha256(selected_profile_source)
	profile=output_dir+"isolated-identities-%d.json"%OS.get_process_id()
	if not check(DirAccess.copy_absolute(selected_profile_source,ProjectSettings.globalize_path(profile))==OK,"clone explicit twenty-identity QA fixture without touching source"):return finish()
	var account=load("res://scripts/economy.gd").new(profile)
	check(account.load_state().get("ok",false),"load isolated QA account")
	check(account.state.active_run.is_empty(),"fixture has no live voyage to abandon")
	check(account.rearm("IBS-U-IJN-NISSHIN").get("ok",false),"rearm owned transport with real mother-port ammunition stock")
	app=load("res://scenes/main.tscn").instantiate();app.economy=account;app.boot_to_title=false;app.fullscreen_battle=true
	root.content_scale_size=Vector2i(1600,900);root.size=Vector2i(1280,720);root.add_child(app);await frames();app.set_process(false);app.page_motion=false
	var prepared:Dictionary=app.home.prepare_littoral("tutorial",42,["MCP-011","MCP-018"],["IBS-U-IJN-NISSHIN"],"transport")
	if not check(prepared.get("ok",false),"normal service prepares two actually owned new identities and real capacity"):return finish()
	app.launch_littoral(prepared.request);await frames()
	if not check(app.screen=="battle","real two-identity voyage opens"):return finish()
	controller().interaction_event.connect(func(kind,data):events.append({"kind":kind,"data":data.duplicate(true),"tick":app.core.view.tick}))
	await click(controller().tutorial.get_node("Hint/Margin/Row/Close"))
	check(not controller().tutorial.active,"real slightly-later button dismisses guidance without awarding anything")
	var beach:Dictionary=app.core.view.littoral.beaches[1];var target:=Vector2(float(beach.land.x),float(beach.land.y))
	var dimensions:Array[Vector2i]=[Vector2i(960,540),Vector2i(1280,720),Vector2i(1920,1080)]
	for dimension in dimensions:
		root.size=dimension;await frames(5)
		var scale:Transform2D=root.get_screen_transform()
		check((scale*Vector2(0,card("Unit_MCP-011").size.y)-scale*Vector2.ZERO).length()>=44,"card physical touch target >=44px "+str(dimension))
		check(controller().ui.get_node("Tray/Scroll/Cards").get_child_count()<=8,"single card row never exceeds six units plus two contextual cards "+str(dimension))
		check(not controller().ui.get_node("Actions").visible and not controller().ui.get_node("LandWindow/Controls").visible,"legacy console stays hidden "+str(dimension))
		var native_before:String=app.core.request({"op":"save","serialized":true}).serialized
		await drag(card("Unit_MCP-011"),world(Vector2(3500,3000)),dimension.x==1920)
		check(str(app.core.request({"op":"save","serialized":true}).serialized)==native_before,"bad real drop preserves authority at "+str(dimension))
		check(not controller().ui.get_node("Hint").text.is_empty(),"invalid reason readable beyond color "+str(dimension))
		await drag(card("Unit_MCP-011"),world(target),dimension.x==960)
		await drag(card("Unit_MCP-018"),world(target),dimension.x==1920)
		check(app.core.view.littoral.groups.all(func(row):return row.pending_deploy is Dictionary),"both real carriers' unit queues accepted through scaled mouse/touch "+str(dimension))
		var map:Control=app.sea;check(map.unproject(map.project(target)).distance_to(target)<.03,"sea projection/inverse preserves real world coordinates "+str(dimension))
		await shot("sea-%dx%d"%[dimension.x,dimension.y])
		await click(controller().ui.get_node("MiniMap"));check(controller().primary_map=="land","pointer swaps primary map "+str(dimension))
		map=controller().ui.get_node("LandWindow/Map");check(map.unproject(map.project(target)).distance_to(target)<.03,"land projection/inverse preserves real world coordinates "+str(dimension))
		check(app.sea.miniature and not map.miniature,"true synchronized sea minimap and active land canvas "+str(dimension))
		await shot("land-%dx%d"%[dimension.x,dimension.y])
		await click(controller().ui.get_node("MiniMap"))
	for i in range(700):
		if app.core.view.littoral.groups.all(func(row):return str(row.stage)=="ground"):break
		await advance(.1)
	check(app.core.view.littoral.groups.all(func(row):return str(row.stage)=="ground"),"both new identities really arrive on shore")
	await click(controller().ui.get_node("MiniMap"))
	await click(card("Unit_MCP-011"));await frames()
	var land:Control=controller().ui.get_node("LandWindow/Map");var represented:Dictionary={}
	for actor in land.actors.values():
		if actor.friendly and actor.identity in ["MCP-011","MCP-018"]:
			represented[actor.identity]=true
			check(actor.sheet_path.is_empty() and actor.fallback_portrait!=null,"new identity shows her own portrait and original type token, no borrowed SD "+actor.identity)
	check(represented.size()==2,"both new identities visible in real public land scene")
	await shot("two-new-identities-real-land")
	var current:Dictionary=controller()._group();var ability:Dictionary=current.ability.duplicate(true);var at:Dictionary=current.position
	check(card("Ability_MCP-011")!=null,"selected actual finite ability appears in only one context card")
	if card("Ability_MCP-011")!=null:await drag(card("Ability_MCP-011"),world(Vector2(float(at.x),float(at.y))))
	check(event_seen("ability_ordered"),"real card drag accepts finite smoke ability")
	check(int(controller()._group().ability.charges)==int(ability.charges)-1,"actual native ability charges decrease once")
	check(float(controller()._group().ability.active_seconds)>0,"real native smoke buff activated")
	await shot("actual-finite-ability")
	check(app.checkpoint(),"checkpoint genuine active run and UI state")
	var expected:String=app.core.request({"op":"save","serialized":true}).serialized
	var ui_state:Dictionary=controller().serialize_ui_state();var expected_ability:Dictionary=controller()._group().ability.duplicate(true)
	app.core.close();app.queue_free();await frames()
	account=load("res://scripts/economy.gd").new(profile);check(account.load_state().get("ok",false),"close/reload isolated account")
	app=load("res://scenes/main.tscn").instantiate();app.economy=account;app.boot_to_title=false;app.fullscreen_battle=true;root.add_child(app);await frames();app.set_process(false);app.page_motion=false;app.resume_run();await frames()
	check(app.screen=="battle" and controller().primary_map=="land" and controller().selected_unit=="MCP-011","main resume restores selected identity and primary land map")
	check(str(app.core.request({"op":"save","serialized":true}).serialized)==expected,"full native snapshot identical after actual restart")
	check(app.home._same(controller()._group().ability,expected_ability),"restoring UI never replays or consumes old ability")
	check(not controller().tutorial.active and controller().serialize_ui_state().drag_tutorial.dismissed,"explicitly dismissed help stays dismissed after restart")
	await shot("restored-two-new-identities")
	controller().begin_replay();controller().seek_littoral(0);controller().end_replay();await frames()
	check(app.home._same(controller()._group().ability,expected_ability),"read-only replay and return do not replay finite ability consumption")
	check(FileAccess.get_sha256(selected_profile_source)==clone_sha,"source QA profile bytes unchanged")
	FileAccess.open(output_dir+"identity-proof.json",FileAccess.WRITE).store_string(JSON.stringify({"isolated_qa_grant":true,"source":selected_profile_source,"source_sha256":clone_sha,"identities":represented.keys(),"ability_before":ability,"ability_after":expected_ability,"ui_state":ui_state,"sizes":["960x540","1280x720","1920x1080"]},"  "))
	finish()

