extends "res://tests/salvage_environment_v3_review.gd"
## GPU verification of native v2 observations, procedural set pieces and original Atlas poses.
const EnemyPose = preload("res://scripts/enemy_animation.gd")
const Markers = preload("res://scripts/expedition_markers.gd")
const SCENES := ["sunken_metropolis","cult_relay","storm_wrecks","thermal_vent","refugee_causeway"]
var poses_seen: Dictionary={}
var native_kinds: Dictionary={}
var creature_poses: Dictionary={}
var sample_results: Array=[]

func start_v2(seed_value: int,scene: String,heavy: bool=false)->Dictionary:
	var fleet: Array=[]
	for id in (["IBS-U-USN-WASHINGTON","IBS-U-USN-PENSACOLA","IBS-U-USN-FLETCHER"] if heavy else ["IBS-U-USN-FLETCHER"]):fleet.append({"id":id,"hp":100,"ammo":100,"level":0})
	var response: Dictionary=core.request({"op":"new_salvage","seed":seed_value,"start":{"content":"salvage-v4","gameplay_profile":"cas-adventure-v2","fleet":fleet,"mission":{"kind":"salvage","id":"calm","loot_kind":"scrap"},"cargo_v4":{"commander_level":1,"difficulty":"calm","environment":"fractured","weather":"clear" if heavy else "auto","loadouts":{}},"expedition_v2":{"scene":scene,"munitions":{}}}})
	check(response.get("ok",false),"actual native v2 "+scene+" seed "+str(seed_value)+": "+str(response.get("error","")))
	return core.view.duplicate(true)

func bind(source: Dictionary,clock: float=3.0)->void:
	map.view=source.duplicate(true)
	map.environment_layer.visual_time=clock;map.environment_layer.drift=Vector2.ZERO
	map.environment_layer._process(0);map.queue_redraw()
	await process_frame

func focus(point: Vector2,level: float=4.0)->void:
	map.zoom=level;map.pan=Vector2.ZERO;map.pan=map.size*.5-map.project(point)
	map.environment_layer._process(0)
	await process_frame

func atlas_boundary_checks()->void:
	for species in ["scavenger","spitter","warden","leviathan","aversion","rust_crab","cult_ray"]:
		var frames: SpriteFrames=EnemyPose.frames_for(species,map.textures)
		check(frames!=null,"registered north-facing SpriteFrames "+species)
		if frames==null:continue
		var unique_regions: Array=[]
		for pose in EnemyPose.POSES:
			var texture: AtlasTexture=frames.get_frame_texture(pose,0)
			check(texture!=null and texture.region.size==Vector2(512,512),species+" actual Atlas pose "+pose)
			unique_regions.append(texture.region)
		check(unique_regions[0]!=unique_regions[1] and unique_regions[2]!=unique_regions[3] and unique_regions[4]!=unique_regions[5],species+" uses six distinct original pixel regions")
	var animation=EnemyPose.new()
	var observed: Dictionary={"id":"C1","health":100,"speed":0,"attack":{"state":"approach"}}
	var view: Dictionary={"tick":0,"contacts":[observed]}
	animation.update(view,0);check(animation.pose(observed,0)=="idle","stopped visible observation plays idle")
	observed.speed=5;animation.update(view,1);check(animation.pose(observed,1)=="swim","actual observed speed selects swim")
	observed.attack.state="windup";animation.update(view,2);check(animation.pose(observed,2)=="windup","observed attack selects windup")
	observed.attack.state="recover";animation.update(view,3);check(animation.pose(observed,3)=="strike","actual windup to recover plays strike")
	observed.health=85;animation.update(view,4);check(animation.pose(observed,4)=="hurt","observed HP decrease plays hurt")
	view.contacts=[];animation.update(view,5);check(animation.observed.is_empty(),"lost contact clears animation memory and never fabricates down")
	view.contacts=[observed];animation.update(view,6)
	var new_battle: Dictionary={"tick":0,"contacts":[{"id":"C1","health":10,"speed":0,"attack":{"state":"recover"}}],"islands":[[{"x":1,"y":1},{"x":2,"y":1},{"x":2,"y":2}]]}
	animation.update(new_battle,7)
	check(animation.pose(new_battle.contacts[0],7)=="idle","new world reusing C1 at same tick cannot inherit hurt or strike")
	var task: Dictionary={"title":"公开测试任务","x":5000,"y":3000,"status":"accepted"}
	var task_view: Dictionary={"salvage":{"expedition":{"tasks":[task]}}}
	check(Markers.tooltip(map,task_view,map.project(map.pos(task))).contains("已接取"),"task tooltip uses exact public position and status")
	task.erase("x");check(Markers.tooltip(map,task_view,map.project(Vector2(5000,3000))).is_empty(),"task without public coordinates is not positioned")
	task.x=5000
	for status in ["offered","accepted","working","complete","abandoned"]:
		task.status=status
		check(Markers.tooltip(map,task_view,map.project(map.pos(task))).ends_with(str(Markers.STATUS[status])),"public task status tooltip "+status)

func native_combat()->void:
	var source:=start_v2(43,"sunken_metropolis",true)
	map.zoom=2.0;map.pan=Vector2.ZERO
	var death_seen:=false
	for i in range(600):
		if i%35==0:
			var targets: Array=core.view.get("contacts",[]).duplicate()
			targets.sort_custom(func(a,b):
				if Monster.is_creature(a)!=Monster.is_creature(b):return Monster.is_creature(a)
				return float(a.get("health",999))<float(b.get("health",999)))
			for ship in core.view.get("ships",[]):
				if float(ship.get("hp",0))<=0:continue
				for target in targets:
					var aim: Dictionary=core.request({"op":"aim","ship":int(ship.id),"target":str(target.id),"weapon":"gun"})
					if aim.get("ok",false) and aim.get("data",{}).get("valid",false):
						core.request({"op":"fire","ship":int(ship.id),"target":str(target.id),"weapon":"gun"});break
		if i>0:
			var response: Dictionary=core.request({"op":"step","seconds":1})
			if not response.get("ok",false):break
			source=core.view.duplicate(true)
		await bind(source,float(i)*.75)
		for contact in source.get("contacts",[]):
			if not Monster.is_creature(contact) and str(contact.get("entityKind",""))!="naval":continue
			var species:=str(contact.get("species",contact.get("vessel_type","naval")))
			native_kinds[species]=true
			var pose: String=map.enemy_animation.pose(contact,float(i)*.75)
			if Monster.is_creature(contact) and not creature_poses.has(pose):
				creature_poses[pose]={"tick":source.tick,"species":species}
				await focus(map.pos(contact),4.0);await capture("native-creature-"+pose)
			if not poses_seen.has(pose):
				poses_seen[pose]={"tick":source.tick,"species":species,"attack":contact.get("attack",{}).duplicate(true)}
				await focus(map.pos(contact),4.0);await capture("native-pose-"+pose)
		var confirmed_creatures: Array=source.get("salvage",{}).get("defeated_entities",[]).filter(func(record):return str(record.get("entityKind",""))=="monster")
		if not death_seen and not confirmed_creatures.is_empty():
			death_seen=true;var record: Dictionary=confirmed_creatures[0]
			check(record.has_all(["source_contact","species","x","y","death_tick"]),"down state requires native public confirmed death record")
			creature_poses["down"]={"tick":source.tick,"species":record.get("species","")}
			poses_seen["down"]={"tick":source.tick,"species":record.get("species",""),"source":"public defeated_entities"}
			await focus(map.pos(record),4);await capture("native-confirmed-down")
		if str(source.get("salvage",{}).get("expedition",{}).get("boss",{}).get("status",""))=="announced":
			var boss: Dictionary=source.salvage.expedition.boss
			if not poses_seen.has("boss_announcement"):
				poses_seen["boss_announcement"]={"tick":source.tick,"status":"announced"}
				await focus(map.pos(boss),2.2);await capture("native-boss-region-not-an-entity")
		if not source.get("result")==null:break
	check(poses_seen.has("windup") and poses_seen.has("strike") and poses_seen.has("hurt"),"real native combat exercises windup/strike/hurt poses")
	check(death_seen,"real native combat produces visible confirmed creature down pose")
	check(creature_poses.has("hurt"),"actual visible monster HP decrease plays original hurt Atlas pose")

func review()->void:
	output=ProjectSettings.globalize_path("res://../artifacts/godot/expedition-presentation")
	DirAccess.make_dir_recursive_absolute(output)
	map=Sea.new();root.add_child(map);map.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	map.environment_layer.set_process(false);map.chibis=false;map.cinematic=false
	atlas_boundary_checks()
	for scene in SCENES:
		var geometries: Array=[]
		for seed_value in [43,57]:
			var source:=start_v2(seed_value,scene)
			if source.is_empty():continue
			var saved: Dictionary=core.request({"op":"save","serialized":true})
			var repeated:=start_v2(seed_value,scene)
			check(source.islands==repeated.islands and source.salvage.expedition.tasks==repeated.salvage.expedition.tasks,"same seed reproduces physical coast/tasks "+scene)
			geometries.append(hash(source.islands))
			map.zoom=.92;map.pan=Vector2.ZERO;await bind(source)
			check(map.environment_layer.land_nodes.size()==source.islands.size(),"every v2 physical coast is rendered "+scene)
			check(map.environment_layer.ruin_nodes.size()==source.salvage.landmarks.filter(func(row):return bool(row.get("charted",false)) and str(row.get("collision",""))=="island").size(),"every public v2 landmark is rendered "+scene)
			check(int(map.sea_material.get_shader_parameter("expedition_scene"))==SCENES.find(scene)+1,"scenario has its own procedural colour atmosphere")
			await capture(scene+"-seed-"+str(seed_value))
			if seed_value==43 and not source.salvage.landmarks.is_empty():
				await focus(map.pos(source.salvage.landmarks[0]),4.8);await capture(scene+"-public-landmark-detail")
				var pixels:=root.get_texture().get_image().get_data()
				await bind(source);await capture(scene+"-same-time")
				check(root.get_texture().get_image().get_data()==pixels,"same observation/time reproduces GPU scene pixels "+scene)
				await bind(source,6.0);await capture(scene+"-later-time")
				check(root.get_texture().get_image().get_data()!=pixels,"waves/clouds/local scenery animate procedurally "+scene)
			if scene=="sunken_metropolis" and seed_value==43:
				await bind(source,9);await capture("dormant-boss-public-coordinates-hidden")
				var dormant_pixels:=root.get_texture().get_image().get_data()
				var alternate:=source.duplicate(true)
				alternate.salvage.expedition.boss.x=1000;alternate.salvage.expedition.boss.y=1000
				await bind(alternate,9);await capture("dormant-boss-alternate-coordinate")
				check(root.get_texture().get_image().get_data()==dormant_pixels,"dormant Boss coordinates never create a visible region")
			check(str(core.request({"op":"save","serialized":true}).serialized)==str(saved.serialized),"rendering cannot mutate native world "+scene)
			sample_results.append({"scene":scene,"seed":seed_value,"coast":hash(source.islands),"tasks":source.salvage.expedition.tasks.size(),"naval":source.salvage.expedition.opposition.naval_hulls})
		check(geometries.size()==2 and geometries[0]!=geometries[1],"scene retains seeded physical variety "+scene)
	await native_combat()
	var report: Dictionary={"checks":checks,"passed":checks-failures.size(),"failures":failures,"gpu":DisplayServer.get_name()!="headless","samples":sample_results,"native_poses":poses_seen,"native_kinds":native_kinds,"creature_poses":creature_poses,"screenshots":snapshots,"source":"only public native v2 observations; original unchanged generated Atlas assets"}
	var file:=FileAccess.open(output.path_join("receipt.json"),FileAccess.WRITE);file.store_string(JSON.stringify(report,"\t"));file.close()
	core.close();map.queue_free();await process_frame
	print(JSON.stringify(report));quit(0 if failures.is_empty() else 1)
