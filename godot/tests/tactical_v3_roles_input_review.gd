extends "res://tests/littoral_drag_v2_review.gd"
## Real native loan scenarios and real pointer skill drags. Casting at an empty
## legal point checks input/cost/equipment only; damage is proved by core courses.
func run()->void:
	output_dir="res://../artifacts/island-war-v3/presentation/"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_dir))
	main_hash=FileAccess.get_sha256("user://cas_port_v1.json");backup_hash=FileAccess.get_sha256("user://cas_port_v1.json.bak")
	var account=load("res://scripts/economy.gd").new(output_dir+"roles-input-isolated-%d.json"%OS.get_process_id());account.new_profile();account.state.progression.first_voyage_canon.active=false
	app=load("res://scenes/main.tscn").instantiate();app.economy=account;app.boot_to_title=false;app.deferred_startup=false;app.staged_navigation=false;app.immersive_fullscreen=false
	root.content_scale_size=Vector2i(1600,900);root.size=Vector2i(1600,900);root.add_child(app);await frames(6);app.page_motion=false;app.page_transition.cancel();app.set_process(false);AudioServer.set_bus_mute(0,true)
	app.home.development();app.show_page("home");await frames()
	var owned:Dictionary=account.state.duplicate(true);var disk:String=FileAccess.get_sha256(account.save_path)
	var plan:Dictionary=load("res://scripts/canon_tactical_v3.gd").request("roles")
	if not check(plan.get("ok",false),"real exported role course exists"):return finish_roles()
	for identity in ["MCP-203","MCP-184","MCP-145","MCP-128","MCP-116","MCP-009"]:
		await app.launch_home_exercise(plan.request);await frames()
		if not check(app.home_exercise_session.active,"isolated borrowed role course opens "+identity):continue
		controller().tutorial.close_help()
		check(app.core.request({"op":"island_autonomy","enabled":false}).get("ok",false),"manual role review keeps skill under player control "+identity)
		var company_to_land:Dictionary={}
		for row in app.core.view.littoral.groups:
			if str(row.get("unit_id",""))==identity:company_to_land=row;break
		if not check(not company_to_land.is_empty(),"real borrowed role company "+identity):app.close_home_exercise();await frames();continue
		controller().selected_unit=str(company_to_land.id);controller().roster_signature="";app.update_battle();await frames()
		if identity=="MCP-116":
			for friend in app.core.view.littoral.groups:
				if str(friend.get("unit_id",""))!="MCP-203":continue
				var escort:Control=card("Unit_"+str(friend.id));controller().ui.get_node("Tray/Scroll").ensure_control_visible(escort);await frames()
				var same_beach:Dictionary=app.core.view.littoral.beaches[1]
				await drag(escort,world(Vector2(float(same_beach.land.x),float(same_beach.land.y))),true);break
		var deploy:Control=card("Unit_"+str(company_to_land.id));controller().ui.get_node("Tray/Scroll").ensure_control_visible(deploy);await frames()
		var beach:Dictionary=app.core.view.littoral.beaches[1]
		await drag(deploy,world(Vector2(float(beach.land.x),float(beach.land.y))),true)
		var selected:Dictionary={}
		for i in range(200):
			var response:Dictionary=app.core.request({"op":"step","seconds":.2})
			if not response.get("ok",false):check(false,"real approach step "+identity+": "+str(response));break
			for row in app.core.view.littoral.groups:
				if str(row.get("unit_id",""))==identity and str(row.stage)=="ground" and bool(row.get("ability",{}).get("available",false)):selected=row;break
			if not selected.is_empty():break
		if not check(not selected.is_empty(),"actual live landed skill operator "+identity):app.close_home_exercise();await frames();continue
		check(app.core.request({"op":"island_autonomy","enabled":false}).get("ok",false),"manual takeover before skill "+identity);app.update_battle();await frames()
		var company:String=str(selected.id)
		var unit:Control=card("Unit_"+company)
		var scroll:ScrollContainer=controller().ui.get_node("Tray/Scroll")
		if not check(unit!=null,"actual company card "+identity):app.close_home_exercise();await frames();continue
		scroll.ensure_control_visible(unit);await frames()
		if controller().selected_unit!=company:await click(unit)
		check(controller().selected_unit==company,"pointer selects company "+identity)
		controller().set_primary_map("land");await frames()
		var land=controller().ui.get_node("LandWindow/Map");land.zoom=1;land.focus_selected();await frames()
		var skill:Control=card("Ability_"+company)
		if not check(skill!=null,"contextual actual skill card "+identity):app.close_home_exercise();await frames();continue
		scroll.ensure_control_visible(skill);await frames()
		var native_before:Dictionary=controller()._group().duplicate(true)
		var position:Dictionary=native_before.position;var point:=Vector2(float(position.x),float(position.y))
		if identity=="MCP-009":
			var legal:bool=false
			for approach in range(240):
				var targets:Array=app.core.view.littoral.land.buildings.filter(func(row):return str(row.get("side","axis"))!="allies" and float(row.get("hp",0))>0)
				var nearest:Dictionary={};var gap:float=INF
				for target in targets:
					var preview:Dictionary=app.core.request({"op":"littoral_ability_preview","unit_id":identity,"company_id":company,"x":float(target.x),"y":float(target.y)})
					if preview.get("ok",false) and preview.get("data",{}).get("valid",false):point=Vector2(float(target.x),float(target.y));legal=true;break
					var distance:float=Vector2(float(controller()._group().position.x),float(controller()._group().position.y)).distance_to(Vector2(float(target.x),float(target.y)))
					if distance<gap:gap=distance;nearest=target
				if legal:break
				if nearest.is_empty():break
				if approach%10==0:
					var origin:=Vector2(float(controller()._group().position.x),float(controller()._group().position.y));var centre:=Vector2(float(nearest.x),float(nearest.y));var goal:Vector2=centre+(origin-centre).normalized()*110
					app.issue({"op":"littoral_order","unit_id":identity,"company_id":company,"action":"move","x":goal.x,"y":goal.y})
				app.core.request({"op":"step","seconds":.2});app.update_battle();await process_frame
			if not check(legal,"engineers actually approach a real fortification in bomb range"):
				app.close_home_exercise();await frames();continue
			land.zoom=8;land.camera_center=point;land._camera_updated();await frames();native_before=controller()._group().duplicate(true)
		# Native availability changes can legitimately rebuild the contextual tray
		# while engineers approach; pick the current live widget before dragging.
		skill=card("Ability_"+company)
		if not check(is_instance_valid(skill),"current skill card after actual approach "+identity):app.close_home_exercise();await frames();continue
		scroll.ensure_control_visible(skill);await frames()
		var count:int=int(native_before.ability.charges);var ability_id:String=str(native_before.ability.id)
		var turret_capacity:int=0
		for weapon in JSON.parse_string(FileAccess.get_file_as_string("res://data/island-war-v3.json")).get("weapons",[]):
			if str(weapon.get("family_id",weapon.get("id","")))=="aa_cannon":turret_capacity=int(weapon.get("ammo_capacity",0))
		events.clear();controller().interaction_event.connect(func(kind,data):events.append({"kind":kind,"data":data.duplicate(true),"tick":app.core.view.tick}))
		await drag(skill,world(point),identity in ["MCP-184","MCP-128"])
		check(event_seen("ability_ordered"),"real pointer drop orders skill "+identity)
		check(int(controller()._group().ability.charges)==count-1,"actual finite skill charge consumed once "+identity)
		if ability_id in ["grenade","demolition"]:check(app.core.view.littoral.shots.any(func(row):return str(row.get("weapon_family_id",row.get("weapon_id","")))==("demolition_charge" if ability_id=="demolition" else "grenade")),"real grenade or engineering bomb flight exists")
		elif ability_id=="deploy_aa_turret":check(turret_capacity>0 and app.core.view.island_war.deployables.any(func(row):return str(row.kind)=="aa_turret" and str(row.get("source_company",""))==company and int(row.ammo)==turret_capacity),"real separate finite AA equipment uses native weapon capacity")
		else:check(app.core.view.littoral.land.effects.any(func(row):return str(row.kind)==ability_id and str(row.source_company)==company and float(row.remaining_s)>0),"real timed skill region exists "+identity)
		var saved:Dictionary=app.core.request({"op":"save","serialized":true})
		FileAccess.open(output_dir+"manual-skill-"+identity+".json",FileAccess.WRITE).store_string(JSON.stringify({"native":saved.get("serialized",""),"events":events,"scope":"Real pointer cast at legal empty ground; not a damage or training completion claim"}))
		await shot("manual-skill-"+identity)
		app.close_home_exercise();await frames()
	check(account.state==owned and FileAccess.get_sha256(account.save_path)==disk,"six borrowed role reviews preserve all account and disk state")
	finish_roles()
func finish_roles()->void:
	check(FileAccess.get_sha256("user://cas_port_v1.json")==main_hash and FileAccess.get_sha256("user://cas_port_v1.json.bak")==backup_hash,"formal files unchanged")
	var report:Dictionary={"ok":failures.is_empty(),"checks":checks,"failures":failures,"inputs":inputs,"scope":"Production Main and six actual role operators; mouse/touch skill-card drags, native charges/equipment/timed effects; engineer walks into native bomb range of a real fortification. Other empty-ground casts do not claim damage, victory or tutorial completion."}
	FileAccess.open(output_dir+"roles-input-receipt.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"));print(JSON.stringify(report));app.queue_free();quit(0 if failures.is_empty() else 1)
