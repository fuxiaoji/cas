extends SceneTree
const OUTPUT:String="res://../artifacts/island-war-v3/presentation/"
var checks:int=0
var failures:Array[String]=[]
var app
func family(row:Dictionary)->String:return str(row.get("weapon_family_id",row.get("weapon",{}).get("family_id",row.get("weapon_id",""))))
func _initialize()->void:call_deferred("run")
func check(value:bool,message:String)->void:
	checks+=1
	if not value:failures.append(message);push_error(message)
func frames(count:int=4)->void:
	for i in range(count):await process_frame
func shot(name:String)->void:
	if DisplayServer.get_name()=="headless":return
	await frames();RenderingServer.force_draw(false)
	check(root.get_texture().get_image().save_png(ProjectSettings.globalize_path(OUTPUT+name+".png"))==OK,"GPU "+name)
func run()->void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	var formal:String=FileAccess.get_sha256("user://cas_port_v1.json");var backup:String=FileAccess.get_sha256("user://cas_port_v1.json.bak")
	var account=load("res://scripts/economy.gd").new(OUTPUT+"battle-isolated-%d.json"%OS.get_process_id());account.new_profile();account.state.progression.first_voyage_canon.active=false
	app=load("res://scenes/main.tscn").instantiate();app.boot_to_title=false;app.deferred_startup=false;app.staged_navigation=false;app.economy=account;app.immersive_fullscreen=false
	root.content_scale_size=Vector2i(1600,900);root.size=Vector2i(1600,900);root.add_child(app);await frames(7);app.page_motion=false;app.page_transition.cancel();app.set_process(false);AudioServer.set_bus_mute(0,true)
	app.home.development();app.show_page("home");await frames()
	var disk:String=FileAccess.get_sha256(account.save_path)
	for lesson in ["landing","weapons","airborne","artillery","role-command_network","role-grenade","role-deploy_aa_turret","role-support_designation","role-demolition_charge","role-supply_network","cadence-smg","cadence-dmr","magazine-reload"]:
		var fixture:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(OUTPUT+"actual-%s.json"%lesson))
		app.home_replay_session=load("res://scripts/home_replay_session.gd").new()
		check(app.home_replay_session.open(app,{"snapshot":str(fixture.serialized)}).get("ok",false),"independent actual replay "+lesson)
		await app.enter_battle();await frames()
		var controller=app.battle_controller;var land=controller.ui.get_node("LandWindow/Map")
		controller.seek_littoral(float(fixture.view.tick),true);await frames()
		check(controller.replay_mode,"read-only playback "+lesson)
		check(str(app.core.view.island_war.version)=="cas-island-war-v3","versioned native observation "+lesson)
		check(land.equipment_version=="tactical-vehicles-v3" if "equipment_version" in land else str(land.land.get("equipment_version",""))=="tactical-vehicles-v3","equipment profile consumed "+lesson)
		check(land.display_offsets.is_empty(),"individual real positions "+lesson)
		var actual_weapons:Array=app.core.view.littoral.land.entities.filter(func(body):return body.get("weapon") is Dictionary and not body.get("weapon",{}).is_empty())
		check(not actual_weapons.is_empty() and actual_weapons.all(func(body):return str(body.weapon.get("accuracy",{}).get("model",""))=="piecewise-linear-v1"),"actual bodies publish their native distance-accuracy profile "+lesson)
		check(actual_weapons.all(func(body):return str(body.weapon_id)!=family(body) and str(body.weapon.id)==str(body.weapon_id)),"actual bodies use distinct native model IDs and categories "+lesson)
		check(actual_weapons.all(func(body):return int(body.get("magazine_ammo",-100))+int(body.get("reserve_ammo",-100))==int(body.ammo)),"actual magazine plus reserve equals total usable rounds "+lesson)
		var weapon_shots:Array=app.core.view.littoral.get("shots",[]).filter(func(row):return row.has("weapon_id"))
		check(weapon_shots.all(func(row):return str(row.get("accuracy_application","")) in ["direct_probability","indirect_spread"] and (row.get("hit_probability")!=null if str(row.get("accuracy_application",""))=="direct_probability" else row.get("hit_probability")==null)),"actual published shots distinguish direct probability from area spread "+lesson)
		controller.set_primary_map("land");await frames()
		var target:Dictionary={}
		for row in app.core.view.littoral.land.entities:
			if fixture.get("focus")!=null and int(row.id)==int(fixture.focus):target=row
			if lesson=="weapons" and family(row)=="rocket" and str(row.get("side",""))=="allies":target=row
			if lesson=="airborne" and str(row.get("unit_id",""))=="MCP-088" and str(row.get("phase",""))=="parachuting":target=row
			if lesson=="artillery" and fixture.get("focus")==null and str(row.get("vehicle_kind",""))=="self_propelled_gun" and str(row.get("side",""))=="allies" and row.get("carried_by")==null:target=row
			if bool(row.get("seated",false)) and str(row.get("vehicle_kind","")).is_empty():
				var actor=land.actors.get(int(row.id));check(actor==null or not actor.visible,"seated body does not become an extra infantry sprite")
		if lesson=="landing":
			var kayaks:int=0
			for boat in app.core.view.littoral.get("transports",[]):
				if str(boat.get("kind",""))=="kayak":
					kayaks+=1;check(boat.get("passengers",[]).size()<=2,"actual two-seat craft capacity")
					if target.is_empty():target=boat
			check(kayaks>1,"a company uses several independent kayaks")
		if lesson=="weapons":
			var rocket_counts:Dictionary={}
			for body in app.core.view.littoral.land.entities:
				if str(body.get("unit_id",""))=="MCP-063" and family(body)=="rocket":rocket_counts[str(body.company_id)]=int(rocket_counts.get(str(body.company_id),0))+1
			check(not rocket_counts.is_empty() and rocket_counts.values().all(func(n):return int(n)==1),"one rocket operator in each observed AT company")
		if lesson=="artillery":
			check(not app.core.view.littoral.land.get("combat_vehicles",[]).is_empty(),"separate real SPG entity")
			for body in app.core.view.littoral.land.entities:
				if str(body.get("unit_id",""))=="MCP-087" and not body.has("vehicle_kind"):check(family(body)=="pistol","artillery human body has only sidearm")
		if lesson.begins_with("role-"):
			var identity:String={"role-command_network":"MCP-203","role-grenade":"MCP-184","role-deploy_aa_turret":"MCP-145","role-support_designation":"MCP-128","role-demolition_charge":"MCP-009","role-supply_network":"MCP-116"}[lesson]
			for body in app.core.view.littoral.land.entities:
				if str(body.get("unit_id",""))==identity and float(body.get("hp",0))>0:target=body;break
			if lesson=="role-grenade":check(not land.weapon_fx.records.values().filter(func(row):return str(row.weapon)=="grenade").is_empty(),"actual grenade reaches flight renderer")
			elif lesson=="role-demolition_charge":check(not land.weapon_fx.records.values().filter(func(row):return str(row.weapon)=="demolition_charge").is_empty(),"actual engineering bomb reaches flight renderer")
			elif lesson=="role-deploy_aa_turret":check(not land.land.get("deployables",[]).filter(func(row):return str(row.kind)=="aa_turret").is_empty(),"actual finite turret reaches land renderer")
			else:check(not land.land.get("effects",[]).filter(func(row):return str(row.kind)==lesson.trim_prefix("role-") and float(row.remaining_s)>0).is_empty(),"actual active role area reaches renderer")
		check(not target.is_empty(),"actual focus "+lesson)
		if not target.is_empty():
			land.zoom=18 if lesson!="landing" else 4;land.camera_center=Vector2(float(target.x),float(target.y));land.selected_unit=str(target.get("company_id",""));land._camera_updated();await frames()
			if lesson!="landing":
				var actor=land.actors.get(int(target.id));check(actor!=null and actor.visible,"actual actor rendered "+lesson)
				if actor!=null:check(actor.target_position.distance_to(land.project(Vector2(float(target.x),float(target.y))))<.001,"real body/vehicle centre "+lesson)
		if lesson.begins_with("cadence-"):
			var wanted:String=lesson.trim_prefix("cadence-")
			check(family(target)==wanted,"actual target weapon category "+lesson)
			check(str(target.get("weapon",{}).get("fire_mode",""))==("burst" if wanted=="smg" else "single"),"actual SMG burst or DMR single-shot mechanism "+lesson)
			check(land.weapon_fx.records.values().any(func(row):return str(row.weapon)==wanted and str(row.weapon_id)==str(target.get("weapon_id",""))),"actual shot model reaches its category-specific trace "+lesson)
			var firing=land.actors.get(int(target.get("id",-1)))
			check(firing!=null and firing.state_name=="fire" and firing.clock<firing.fire_until,"one actual native operator drives her own fire animation "+lesson)
		if lesson=="magazine-reload":
			check(float(target.get("reloading_in",0))>0 and int(target.get("magazine_ammo",-1))==0,"actual empty magazine enters a finite reload")
			var status:Dictionary=load("res://scripts/tactical_weapon_badge_v3.gd").reload_status(app.core.view.littoral)
			check(status.has(str(target.get("company_id",""))),"actual company publishes contextual reload status")
			var found:bool=false
			for card in controller.ui.get_node("Tray/Scroll/Cards").get_children():
				if str(card.payload.get("company_id",""))==str(target.get("company_id","")) and str(card.payload.get("kind",""))=="unit":found="换弹" in card.status.text
			check(found,"production unit card shows actual reload without a new numeric panel")
		await shot("actual-"+lesson+"-battle")
		var exact:Dictionary=app.core.view.duplicate(true);await frames(5);check(app.core.view==exact,"rendering never adjudicates "+lesson)
		app.close_home_replay();await frames()
	check(FileAccess.get_sha256(account.save_path)==disk,"replay never writes isolated account")
	check(FileAccess.get_sha256("user://cas_port_v1.json")==formal and FileAccess.get_sha256("user://cas_port_v1.json.bak")==backup,"formal files unchanged")
	var report:Dictionary={"ok":failures.is_empty(),"checks":checks,"failures":failures,"scope":"Production Main, IPC, naval controls, actual native in-flight saves and GPU view; no synthetic battle results or account rewards"}
	FileAccess.open(OUTPUT+"battle-receipt.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"));print(JSON.stringify(report));app.queue_free();await frames();quit(0 if failures.is_empty() else 1)
