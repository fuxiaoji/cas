extends "res://tests/littoral_v4_world_review.gd"
func run()->void:
	output_dir="res://../artifacts/carrier-20261115/ui/";DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_dir))
	main_hash=FileAccess.get_sha256("user://cas_port_v1.json");backup_hash=FileAccess.get_sha256("user://cas_port_v1.json.bak")
	profile=output_dir+"isolated-%d.json"%OS.get_process_id();var account=load("res://scripts/economy.gd").new(profile)
	account.load_state();app=load("res://scenes/main.tscn").instantiate();app.economy=account;app.boot_to_title=false;app.fullscreen_battle=true
	root.content_scale_size=Vector2i(1600,900);root.size=Vector2i(1280,720);root.add_child(app);await frames();app.set_process(false);app.page_motion=false
	var config:Dictionary={"op":"new_littoral","version":"cas-littoral-v4","mode":"tutorial","lesson":"landing","seed":42,"ships":[{"id":"CAS-H-USN-ENTERPRISE-1942","hp":100,"ammo":100},{"id":"CAS-H-IJN-SHOKAKU-1942","hp":100,"ammo":100}],"roster":["MCP-034","MCP-001"],"unit_condition":[],"transport_preset":"combat","defense":[]}
	if not check(app.core.request(config).get("ok",false),"isolated two-carrier battle starts"):return finish()
	app.show_page("battle");await frames(6);controller().tutorial_dismissed=true;controller().tutorial.active=false;controller().tutorial.hide();app.sea.focus_fleet();await frames()
	check(controller().ui.has_node("CarrierCommandDesk"),"naval command desk exists")
	await click(controller().ui.get_node("CarrierCommandDesk"));await frames()
	var found:Array=[]
	for node in app.find_children("*","Button",true,false):
		if node.text=="开启新版手动指挥 / 待命队列":found.append(node)
	if check(not found.is_empty(),"actual carrier menu enable action"):
		await click(found[0]);await frames()
	check(app.core.view.littoral.has("carrier_ops"),"UI opt-in enables real core queue")
	var squads:Array=app.core.view.littoral.aviation.squadrons
	var patrol:Dictionary=squads[0];var bomber:Dictionary=squads[1];var other:Dictionary=squads[4]
	var sea_point:Vector2=Vector2(8500,15000)
	await drag(card("Squadron_"+str(patrol.id)),world(sea_point));await advance(1)
	check(app.core.view.littoral.aviation.aircraft.any(func(a):return int(a.carrier)==1),"pointer drag launches real patrol")
	var ruin:Dictionary=app.core.view.littoral.land.ruins[0];var goal:Vector2=Vector2(float(ruin.x),float(ruin.y))
	# Use the same production gesture classifier as pointer release for a precise
	# land point, independent of which map is in front during this review.
	var q:Dictionary=controller()._air_order({"squadron_id":str(bomber.id)},{"world":goal,"hit":{}},false)
	check(q.get("queue",false),"new drag sends a queued mission")
	check(app.issue(q).get("ok",false),"busy deck accepts actual queued bomber")
	check(app.core.view.littoral.carrier_ops.queue.size()==1,"queue appears in public observation")
	q=controller()._air_order({"squadron_id":str(other.id)},{"world":goal,"hit":{}},false);app.issue(q);await advance(8)
	check(app.core.view.littoral.aviation.aircraft.any(func(a):return int(a.carrier)==2),"second deck actually operates concurrently")
	await shot("two-carrier-decks-and-queue")
	var mother:Dictionary=app.core.view.ships[0];q=controller()._air_order({"squadron_id":str(patrol.id)},{"world":Vector2(float(mother.x),float(mother.y)),"hit":{}},false)
	check(str(q.action)=="return","drag onto actual mother produces recall")
	check(app.issue(q).get("ok",false),"real recall command accepted")
	load("res://scripts/carrier_command_desk.gd").lesson(controller(),3);await frames();await shot("detailed-carrier-lesson")
	app.close_modal();load("res://scripts/carrier_command_desk.gd").catalogue(controller());await frames();await shot("pacific-source-catalogue")
	load("res://scripts/carrier_command_desk.gd").character(controller(),"CAS-H-IJN-JUNYO-1942");await frames(6)
	var textures:Array=app.find_children("*","TextureRect",true,false).filter(func(n):return n.texture!=null and str(n.texture.resource_path).contains("carrier-20261115"))
	check(textures.size()==2,"own portrait and SD load from new art ledger")
	await shot("junyo-portrait-and-sd")
	app.close_modal();await advance(70)
	check(app.core.view.littoral.aviation.squadrons.all(func(s):return int(s.available)+int(s.airborne)+int(s.lost)==int(s.total)),"physical aircraft conservation")
	finish()
