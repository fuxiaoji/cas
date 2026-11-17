extends "res://tests/littoral_drag_v2_review.gd"
## Actual native seeded town, not a painted background or composed mockup.
func polygon_area(raw:Array)->float:
	var total:float=0
	for index in range(raw.size()):
		var a:Dictionary=raw[index];var b:Dictionary=raw[(index+1)%raw.size()]
		total+=float(a.x)*float(b.y)-float(b.x)*float(a.y)
	return absf(total)*.5
func run()->void:
	output_dir="res://../artifacts/combined-arms-v4/town/";DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_dir))
	main_hash=FileAccess.get_sha256("user://cas_port_v1.json");backup_hash=FileAccess.get_sha256("user://cas_port_v1.json.bak")
	profile=output_dir+"isolated-%d.json"%OS.get_process_id()
	var account=load("res://scripts/economy.gd").new(profile);account.load_state()
	app=load("res://scenes/main.tscn").instantiate();app.economy=account;app.boot_to_title=false;app.fullscreen_battle=true
	root.content_scale_size=Vector2i(1600,900);root.size=Vector2i(1280,720);root.add_child(app);await frames();app.set_process(false);app.page_motion=false
	var request:Dictionary={"op":"new_littoral","version":"cas-littoral-v4","seed":42,"mode":"defense","ships":[{"id":"IBS-U-USN-ERMA-IOWA","hp":100,"ammo":100},{"id":"CAS-O-LHA-RETURNLIGHT","hp":100,"ammo":100}],"roster":["MCP-034","MCP-001"],"unit_condition":[{"id":"MCP-034","hp":100},{"id":"MCP-001","hp":100}],"company_transports":[{"id":"MCP-034","kind":"landing_craft"},{"id":"MCP-001","kind":"helicopter"}],"transport_preset":"balanced","defense":[]}
	if not check(app.core.request(request).get("ok",false),"actual native city defense created"):return finish()
	var town:Dictionary=app.core.view.littoral.land.get("town",{})
	if not check(not town.get("buildings",[]).is_empty(),"native collision buildings available"):return finish()
	check(town.get("roads",[]).size()>=4,"native town has continuous street network")
	var baseline=load("res://scripts/core_bridge.gd").new()
	var old_request:Dictionary=request.duplicate(true);old_request.version="cas-littoral-v3";old_request.ships=[{"id":"IBS-U-USN-ERMA-IOWA","hp":100,"ammo":100},{"id":"IBS-U-IJN-NISSHIN","hp":100,"ammo":100}]
	var legacy:Dictionary=baseline.request(old_request)
	if check(legacy.get("ok",false),"query unchanged original v3 island"):
		check(polygon_area(app.core.view.littoral.land.polygon)>10000000,"v4 island retains actual multi kilometre tactical space")
	baseline.close()
	for building in town.get("buildings",[]):
		var footprint:Array=building.get("footprint",[])
		if footprint.size()<3:continue
		var a:Vector2=Vector2(float(footprint[0].x),float(footprint[0].y));var b:Vector2=Vector2(float(footprint[1].x),float(footprint[1].y))
		check(a.distance_to(b)<=100,"native building frontage is measured in tens of metres")
	for road in town.get("roads",[]):check(float(road.get("width",0))<=30,"native road width is measured in tens of metres")
	var terrain:Dictionary=app.core.view.littoral.land.get("terrain",{})
	check(terrain.get("elevation_zones",[]).size()>=2,"native high and low hill zones available")
	check(not terrain.get("ramps",[]).is_empty(),"native hill approach ramps available")
	app.show_page("battle");controller().set_primary_map("land");app.running=false;app.update_battle();await frames(5)
	var land:Control=controller().ui.get_node("LandWindow/Map")
	check(land._isometric(),"actual land map uses reversible isometric projection")
	for zone in terrain.get("elevation_zones",[]):
		if float(zone.get("height_m",0))<=0:continue
		var center:Vector2=Vector2.ZERO
		for point in zone.get("polygon",[]):center+=Vector2(float(point.x),float(point.y))
		center/=maxi(1,zone.get("polygon",[]).size())
		var raised:Vector2=land.project(center)
		check(raised.distance_to(land.project_base(center))>1,"actual highland rises above base projection")
		check(land.unproject(raised).distance_to(center)<1,"highland actor and command projection roundtrip")
	for size in [Vector2i(960,540),Vector2i(1280,720),Vector2i(1920,1080)]:
		root.size=size;await frames(5);await shot("city-main-%dx%d"%[size.x,size.y])
	root.size=Vector2i(1280,720);await frames(4)
	var buildings:Array=town.get("buildings",[])
	var center:Vector2=Vector2.ZERO
	var middle:int=buildings.size()/2
	for point in buildings[middle].footprint:center+=Vector2(float(point.x),float(point.y))
	center/=maxi(1,buildings[middle].footprint.size())
	var span:Vector2=land.bounds().size
	land.zoom=clampf(maxf(span.x,span.y)/900.0,3,12);land.camera_center=center;land._resize_visuals();land._sync_projection();await frames(4);await shot("city-street-detail")
	await click(controller().ui.get_node("MiniMap"));await shot("city-sea-overview")
	check(is_instance_valid(app.sea.environment_layer) and app.sea.environment_layer.visible,"dynamic cloud and weather layer remains visible with native town")
	var before:String=app.core.request({"op":"save","serialized":true}).serialized
	app.update_battle();await frames(8)
	check(str(app.core.request({"op":"save","serialized":true}).serialized)==before,"new visuals never mutate native collision state")
	FileAccess.open(output_dir+"native-town.json",FileAccess.WRITE).store_string(JSON.stringify(town,"\t"))
	finish()
