extends SceneTree
## Presentation fixtures only. Real World/aircraft/deployment integration is a separate gate.
var checks:int=0
var failures:Array[String]=[]
func _initialize()->void:call_deferred("run")
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures.append(label);push_error(label)
func run()->void:
	var formation=load("res://scripts/tactical_formation_mark.gd")
	for row in [{"designation":"第1空中突击旅","expected":"X"},{"designation":"第11陆战师","expected":"XX"},{"designation":"第34海军派遣团","expected":"III"},{"designation":"第9工兵营","expected":"II"}]:
		check(str(formation.resolve(row).symbol)==str(row.expected),"registered formation "+str(row.designation))
	check(str(formation.resolve({"company_count":5,"personnel_count":50,"personnel_cap":6000}).symbol).is_empty(),"sortie count and body cap never manufacture a formation rank")
	check(str(formation.resolve({"formation_echelon":"brigade","designation":"独立试验队"}).symbol)=="X","explicit catalogue echelon takes precedence")
	var art=load("res://scripts/tactical_casualty_art.gd")
	for id in ["MCP-034","MCP-001","MCP-076","MCP-009","MCP-022"]:
		for seed in range(3):
			var row:Dictionary={"unit_id":id,"side":"allies","pose_seed":seed}
			var first:Dictionary=art.lookup(row);var restored:Dictionary=art.lookup(JSON.parse_string(JSON.stringify(row)))
			check(first==restored and int(first.index)==seed,"saved pose seed stays stable "+id+" "+str(seed))
			check(str(first.atlas).contains(id),"casualty art belongs to her original identity "+id+" "+str(seed))
	check(art.lookup({"unit_id":"MCP-018","side":"allies","pose_seed":0}).is_empty(),"missing independent corpse atlas never borrows another woman's art")
	var land=load("res://scripts/littoral_land.gd").new();land.size=Vector2(1280,710);root.add_child(land);await process_frame
	land.land={"persistent_corpses":true,"bounds":{"x":7000,"y":4000,"width":10000,"height":8000},"polygon":[{"x":9000,"y":7000},{"x":15000,"y":6000},{"x":17000,"y":9500},{"x":11500,"y":11500}]}
	for dimensions in [Vector2(960,426),Vector2(1280,570),Vector2(1920,850)]:
		for small in [false,true]:
			for magnification in [1.0,2.25]:
				land.size=dimensions;land.set_miniature(small);land.zoom=magnification;land.camera_center=Vector2(12500,9000);land._resize_visuals()
				var maximum_error:float=0
				for point in [Vector2(7000,4000),Vector2(9000,7000),Vector2(15000,6000),Vector2(12520.25,8345.75),Vector2(17000,12000)]:maximum_error=maxf(maximum_error,land.unproject(land.project(point)).distance_to(point))
				check(maximum_error<.01,"isometric command roundtrip "+str(dimensions)+" miniature="+str(small)+" zoom="+str(magnification))
	land.land["terrain"]={"elevation_zones":[{"polygon":[{"x":10000,"y":7000},{"x":14000,"y":7000},{"x":14000,"y":10000},{"x":10000,"y":10000}],"level":1,"height_m":24,"cover_multiplier":.9},{"polygon":[{"x":11500,"y":7800},{"x":13200,"y":7800},{"x":13200,"y":9300},{"x":11500,"y":9300}],"level":2,"height_m":64,"cover_multiplier":.8}],"ramps":[{"points":[{"x":10900,"y":8500},{"x":11900,"y":8500}],"width":400,"from_level":1,"to_level":2}]}
	check(is_equal_approx(land._height_at(Vector2(11400,8500)),44),"ramp midpoint uses interpolated true level heights rather than a platform step")
	check(is_equal_approx(land._height_at(Vector2(10800,8500)),24),"ramp start cap never extends beyond the native segment")
	check(is_equal_approx(land._height_at(Vector2(12000,8500)),64),"ramp end cap never extends beyond the native segment")
	for dimensions in [Vector2(960,426),Vector2(1280,570),Vector2(1920,850)]:
		for small in [false,true]:
			for magnification in [1.0,2.25]:
				land.size=dimensions;land.set_miniature(small);land.zoom=magnification;land.camera_center=Vector2(12500,8500);land._resize_visuals()
				var maximum_error:float=0
				for point in [Vector2(9000,6500),Vector2(10500,7500),Vector2(12500,8500),Vector2(11400,8500)]:maximum_error=maxf(maximum_error,land.unproject(land.project(point)).distance_to(point))
				check(maximum_error<.01,"elevated ground and ramp command roundtrip "+str(dimensions)+" miniature="+str(small)+" zoom="+str(magnification))
	check(land.project(Vector2(12500,8500)).y<land.project_base(Vector2(12500,8500)).y,"high ground and entities share the same elevated anchor")
	land.land.terrain["height_model"]="inset_edge_blend_v1";land.land.terrain.elevation_zones[0]["blend_width_m"]=120;land.land.terrain.elevation_zones[1]["blend_width_m"]=120;land._resize_visuals()
	check(is_zero_approx(land._height_at(Vector2(10000,8500))),"continuous native height is zero exactly at an outer edge")
	check(is_equal_approx(land._height_at(Vector2(10060,8500)),12),"continuous native edge blend reaches half elevation at sixty metres")
	check(is_equal_approx(land._height_at(Vector2(10120,8500)),24),"continuous native edge blend reaches platform elevation at its published width")
	check(is_equal_approx(land._height_at(Vector2(11400,8500)),24),"suggested ramp no longer overrides the versioned continuous height model")
	for point in [Vector2(10003,8500),Vector2(10060,8500),Vector2(10120,8500),Vector2(11560,8500),Vector2(12500,8500)]:check(land.unproject(land.project(point)).distance_to(point)<.02,"continuous sloping terrain visible top inverse "+str(point))
	land.land.erase("terrain")
	land.set_miniature(false);land.zoom=1;land._resize_visuals();check(land._body_height(true,true)<=12,"whole-island bodies use a small per-body overview level of detail")
	land.zoom=12;land._resize_visuals();check(land._body_height(true,true)>=20 and land._body_height(true,true)<=28,"local street camera reveals the same identity at a readable twenty-to-twenty-eight pixels")
	land.zoom=1;land.set_miniature(false);land.land.erase("persistent_corpses");land.size=Vector2(1280,710);land._resize_visuals()
	check(land.project(Vector2(7000,4000)).distance_to(Vector2(16,686))<.01,"old v1-v3 orthographic projection remains exact")
	var corpse:Dictionary={"id":701,"unit_id":"MCP-034","side":"allies","x":11000,"y":9000,"kind":"rifle","death_tick":4.5,"pose_seed":3}
	var observation:Dictionary={"tick":40.0,"persistent_corpses":true,"corpses":[corpse],"entities":[],"groups":[{"id":"MCP-034","stage":"lost"}],"transports":[]}
	land.observe(observation,false);await process_frame
	check(land.actors.has(701),"restored casualty is rendered from a durable public record")
	var actor=land.actors[701]
	check(actor.persistent_defeat and actor.frame_index==11,"historical casualty restores directly to its settled pose")
	check(actor.fire_until<0 and actor.hurt_until<0,"restoring a casualty does not replay hurt or gunfire")
	check(not actor.expired(),"v4 casualty remains after the old four-second window")
	var instance:int=actor.get_instance_id()
	land.set_miniature(true);land.set_miniature(false);land.size=Vector2(960,426);await process_frame;await process_frame
	check(land.actors[701].get_instance_id()==instance,"map swap and resize retain the same casualty identity")
	check(actor.target_position.distance_to(land.project(Vector2(11000,9000)))<.01,"casualty projection follows its true death coordinate")
	observation.tick=240.0;land.observe(observation,false);await process_frame
	check(land.actors.has(701) and not actor.expired(),"casualty remains at a later voyage time")
	land.prime_visuals();observation.tick=0.0;observation.corpses=[];observation.groups=[];land.observe(observation,false)
	check(land.actors.is_empty(),"replay before the casualty does not invent a future body")
	var body:Dictionary={"id":702,"unit_id":"MCP-034","side":"allies","x":11000,"y":9000,"kind":"rifle","hp":10,"max_hp":10}
	observation.tick=.1;observation.entities=[body];observation.groups=[{"id":"MCP-034","stage":"ground"}];land.observe(observation,false)
	observation.tick=.2;observation.entities=[];observation.groups=[{"id":"MCP-034","stage":"returning"}];land.observe(observation,false)
	check(not land.actors.has(702),"normal return to a transport never becomes a casualty")
	var old=load("res://scripts/tactical_sprite.gd").new();root.add_child(old);old.defeat(0);old.clock=10
	check(old.expired(),"old v1-v3 four-second defeat presentation remains unchanged")
	old.queue_free();land.queue_free();await process_frame
	var output:String="res://../artifacts/littoral-v4-ui/components/"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	FileAccess.open(output+"receipt.json",FileAccess.WRITE).store_string(JSON.stringify({"passed":failures.is_empty(),"checks":checks,"failures":failures,"scope":"pure presentation fixtures, not native gameplay proof"},"  "))
	print("LITTORAL_V4_COMPONENTS ",checks-failures.size(),"/",checks);quit(0 if failures.is_empty() else 1)
