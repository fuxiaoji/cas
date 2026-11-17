extends "res://tests/littoral_drag_v2_review.gd"
const TransportArt=preload("res://scripts/tactical_transport_art.gd")
var observed_types:Dictionary={}
var gunship_shots:Dictionary={}
var snapshots:Array=[]
func shot(name:String)->void:
	if DisplayServer.get_name()!="headless":await super.shot(name)
func request_for(roster:Array,mode:String="tutorial",seed:int=42)->Dictionary:
	var request:Dictionary={"op":"new_littoral","version":"cas-littoral-v3","seed":seed,"mode":mode,"ships":[{"id":"IBS-U-IJN-NISSHIN","hp":100,"ammo":100},{"id":"IBS-U-USN-ERMA-IOWA","hp":100,"ammo":100}],"roster":roster,"unit_condition":roster.map(func(id):return {"id":id,"hp":100}),"transport_preset":"transport","defense":[]}
	if mode=="tutorial":request["lesson"]="landing"
	return request
func open_native(roster:Array,mode:String="tutorial",seed:int=42)->void:
	check(app.core.request(request_for(roster,mode,seed)).get("ok",false),"real native formation opens "+str(roster))
	app.show_page("battle");await frames();app.set_process(false);app.running=true
	if controller().tutorial!=null:controller().tutorial.close_help()
	for id in roster:check(app.core.request({"op":"littoral_deploy","unit_id":id,"beach":2,"insertion":"landing","queue":true}).get("ok",false),"real queued deployment "+str(id))
	app.update_battle()
func run()->void:
	output_dir="res://../artifacts/littoral-motion-v3/transport/"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_dir))
	main_hash=FileAccess.get_sha256("user://cas_port_v1.json");backup_hash=FileAccess.get_sha256("user://cas_port_v1.json.bak")
	profile=output_dir+"isolated-%d.json"%OS.get_process_id()
	var account=load("res://scripts/economy.gd").new(profile);account.load_state()
	app=load("res://scenes/main.tscn").instantiate();app.economy=account;app.boot_to_title=false;app.fullscreen_battle=true
	root.content_scale_size=Vector2i(1600,900);root.size=Vector2i(1280,720);root.add_child(app);await frames();app.set_process(false);app.page_motion=false
	TransportArt._load();check(TransportArt.catalogue.size()==20,"twenty original per-identity vehicle registrations")
	var atlas_sources:Dictionary={}
	for id in TransportArt.catalogue:
		var entry:Dictionary=TransportArt.catalogue[id];var texture:Texture2D=load(entry.atlas)
		check(texture!=null and texture.get_image().has_mipmaps(),"actual imported smooth MIP vehicle "+str(id))
		var intact:Dictionary=TransportArt.specification({"unit_id":id,"kind":entry.default_kind})
		var deploying:Dictionary=TransportArt.specification({"unit_id":id,"kind":entry.default_kind,"stage":"deploying"})
		check(bool(intact.exclusive) and str(intact.identity)==id,"own exclusive vehicle never borrowed "+str(id))
		check(float(intact.scale_reference)==float(deploying.scale_reference),"deploying body preserves fixed physical drawing scale "+str(id))
		if str(entry.default_kind)=="helicopter":check(intact.frame.region==deploying.frame.region,"air deployment retains clean intact body plus procedural rotor "+str(id))
		atlas_sources[str(entry.atlas)]=FileAccess.get_sha256(str(entry.atlas))
	var alternate:Dictionary=TransportArt.specification({"unit_id":"MCP-001","kind":"landing_craft"})
	check(not bool(alternate.exclusive) and str(alternate.identity)=="MCP-001","alternate family uses generic equipment with original identity token")
	await open_native(["MCP-034","MCP-001","MCP-022"])
	var captured:bool=false
	for i in range(650):
		app.core.request({"op":"step","seconds":.1});app.update_battle()
		for transport in app.core.view.littoral.transports:
			observed_types[str(transport.kind)]=str(transport.unit_id)
			var spec:Dictionary=TransportArt.specification(transport)
			check(not spec.is_empty() and str(spec.identity)==str(transport.unit_id),"actual transport retains public person "+str(transport.unit_id)) if not observed_types.has("checked:"+str(transport.unit_id)) else false
			observed_types["checked:"+str(transport.unit_id)]=true
		if not captured and app.core.view.littoral.transports.size()>=3:
			captured=true;snapshots.append(app.core.view.duplicate(true));await shot("three-real-transport-families-sea")
		if app.core.view.littoral.groups.all(func(row):return str(row.stage) in ["ground","lost"]):break
		if i%10==0:await process_frame
	check(observed_types.has("landing_craft") and observed_types.has("amphibious_vehicle") and observed_types.has("helicopter"),"all three actual equipment families were physically in flight or sailing")
	check(app.core.view.littoral.groups.filter(func(row):return str(row.stage)=="ground").size()>=2,"actual surviving companies really arrive ashore")
	controller().set_primary_map("land");await shot("actual-multi-company-landfall")
	var land:Control=controller().ui.get_node("LandWindow/Map")
	check(land.actors.values().filter(func(actor):return actor.friendly).size()>=12,"multiple real companies remain original living body actors")
	# The real raid fixture puts the gunship within a live threat, unlike the
	# quiet tutorial beach where she legally lands without firing a round.
	await open_native(["MCP-022","MCP-027","MCP-034","MCP-009","MCP-145"],"raid",44)
	var initial_ammo:int=int(app.core.view.littoral.groups.filter(func(row):return row.id=="MCP-027")[0].vehicle_ammo)
	var captured_fire:bool=false
	for i in range(800):
		app.core.request({"op":"step","seconds":.1});app.update_battle()
		for record in app.core.view.littoral.get("shots",[]):
			if str(record.get("kind",""))=="transport_gunship" and str(record.get("source",""))=="MCP-027":
				gunship_shots[str(record.id)]=record.duplicate(true)
				if not captured_fire:
					captured_fire=true;snapshots.append(app.core.view.duplicate(true));await shot("027-actual-finite-gunship-fire")
		if str(app.core.view.littoral.groups.filter(func(row):return row.id=="MCP-027")[0].stage) in ["lost","ground"]:break
		if i%10==0:await process_frame
	var gunship:Dictionary=app.core.view.littoral.groups.filter(func(row):return row.id=="MCP-027")[0]
	check(initial_ammo==12 and gunship_shots.size()>0 and gunship_shots.size()<=12,"027 fires actual limited ammunition, not an invented repeating animation")
	check(int(gunship.vehicle_ammo)==initial_ammo-gunship_shots.size(),"every observed actual gunship shot consumes one real vehicle round")
	for body in app.core.view.littoral.land.entities:
		if str(body.get("unit_id",""))=="MCP-027" and str(body.get("kind","")) in ["gunship","helicopter"]:
			var equipment:Dictionary=TransportArt.specification(body)
			check(bool(equipment.get("exclusive",false)) and str(equipment.get("identity",""))=="MCP-027","actual airborne 027 equipment uses her own registered gunship")
	var saved:String=app.core.request({"op":"save","serialized":true}).serialized
	app.core.close();check(app.core.request({"op":"load","serialized":saved}).get("ok",false),"actual gunship world survives full core restart")
	controller().ui.get_node("LandWindow/Map").prime_visuals();app.update_battle()
	check(str(app.core.request({"op":"save","serialized":true}).serialized)==saved,"resume does not refill gunship or change original bodies")
	check(controller().ui.get_node("LandWindow/Map").actors.values().all(func(actor):return actor.fire_until<0),"restoring public recent shots does not replay old gunship flashes")
	app.running=false;app.update_battle()
	var gallery:Control=load("res://scenes/ui/tactical_transport_preview.tscn").instantiate();gallery.z_index=3500;root.add_child(gallery);await frames();await shot("twenty-original-equipment-editable-preview")
	gallery.preview_deploying=true;await shot("twenty-deployment-fixed-scale-preview");gallery.queue_free();await frames()
	var manifest:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://bin/core-current.json"));var executable:String=OS.get_environment("CAS_SIM_PATH")
	if executable.is_empty():executable=ProjectSettings.globalize_path("res://bin/"+str(manifest.executable))
	FileAccess.open(output_dir+"actual-events.json",FileAccess.WRITE).store_string(JSON.stringify({"runtime":{"override":OS.get_environment("CAS_SIM_PATH"),"path":executable,"sha256":FileAccess.get_sha256(executable),"manifest":manifest},"transport_families":observed_types,"gunship_initial_ammo":initial_ammo,"gunship_remaining_ammo":gunship.get("vehicle_ammo"),"gunship_real_shots":gunship_shots,"gunship_stage":gunship.stage,"atlas_sources":atlas_sources,"snapshots":snapshots,"scope":"Native real placement/deploy/step commands, fresh isolated UI account, no reward/ownership grant or world mutation"},"  "))
	finish()
