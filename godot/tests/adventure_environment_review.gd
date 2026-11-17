extends "res://tests/salvage_environment_v3_review.gd"
## Actual seeded adventure observations, with exact same-seed rendering and privacy checks.
func adventure_start(seed_value:int,theme:String)->Dictionary:
	var response:Dictionary=core.request({"op":"new_salvage","seed":seed_value,"start":{"content":"salvage-v4","gameplay_profile":"cas-adventure-v1","fleet":[{"id":"IBS-U-USN-FLETCHER","hp":100,"ammo":100,"level":0,"equipment":false,"command":false}],"mission":{"kind":"salvage","id":"standard","loot_kind":"scrap"},"cargo_v4":{"commander_level":1,"difficulty":"standard","environment":theme,"weather":"clear","loadouts":{}}}})
	check(response.get("ok",false),"native adventure "+theme+" "+str(seed_value)+": "+str(response.get("error","")))
	return core.view.duplicate(true)

func review()->void:
	output=ProjectSettings.globalize_path("res://../artifacts/godot/adventure-environment")
	DirAccess.make_dir_recursive_absolute(output)
	map=Sea.new();root.add_child(map);map.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	map.environment_layer.set_process(false)
	map.chibis=false
	var results:Array=[]
	for theme in ["atoll","fractured","fjord","drowned_city"]:
		var signatures:Array=[]
		for seed_value in [40,43,64]:
			var source:=adventure_start(seed_value,theme)
			if not source.get("salvage",{}).has("adventure"):continue
			var saved:Dictionary=core.request({"op":"save","serialized":true})
			var repeat:=adventure_start(seed_value,theme)
			check(source.islands==repeat.islands and source.salvage.landmarks==repeat.salvage.landmarks,"same adventure seed reproduces collision coast/landmarks")
			signatures.append(hash(source.islands))
			map.view=source;map.zoom=.92;map.pan=Vector2.ZERO;map.selected_contact=""
			map.environment_layer.weather.current.clear();map.environment_layer.visual_time=2.0;map.environment_layer.drift=Vector2.ZERO
			map.environment_layer._process(0)
			await process_frame;await process_frame
			check(map.environment_layer.land_nodes.size()==source.islands.size(),"new generator draws every collision island")
			var charted:Array=source.salvage.landmarks.filter(func(row):return bool(row.get("charted",false)) and str(row.get("collision",""))=="island")
			check(map.environment_layer.ruin_nodes.size()==charted.size(),"new generator draws every public landmark")
			check(int(map.sea_material.get_shader_parameter("adventure_theme")) in [1,2,3,4],"adventure water biome is procedural uniform")
			await capture(theme+"-seed-"+str(seed_value))
			if seed_value==43 and not charted.is_empty():
				map.zoom=4.3;map.pan=Vector2.ZERO;map.pan=map.size*.5-map.project(map.pos(charted[0]))
				map.environment_layer._process(0);await capture(theme+"-shore-detail")
				if DisplayServer.get_name()!="headless":
					var pixels:=root.get_texture().get_image().get_data()
					map.environment_layer._process(0);await capture(theme+"-same-time")
					check(root.get_texture().get_image().get_data()==pixels,"same source and same visual time reproduce pixels")
					map.environment_layer.visual_time+=2.0;map.environment_layer._process(0);await capture(theme+"-waves-later")
					check(root.get_texture().get_image().get_data()!=pixels,"procedural waves/clouds actually animate")
			check(str(core.request({"op":"save","serialized":true}).serialized)==str(saved.serialized),"renderer does not change original native world")
			results.append({"theme":theme,"seed":seed_value,"layout":source.salvage.adventure.terrain_layout,"islands":source.islands.size(),"geometry":hash(source.islands),"landmarks":charted.size()})
		check(signatures.size()==3 and signatures[0]!=signatures[1] and signatures[1]!=signatures[2],"different seeds actually change "+theme+" collision geometry")
	var receipt:={"checks":checks,"passed":checks-failures.size(),"failures":failures,"source":"native adventure public observations; no fixed map images","gpu":DisplayServer.get_name()!="headless","samples":results,"screenshots":snapshots}
	var file:=FileAccess.open(output.path_join("receipt.json"),FileAccess.WRITE);file.store_string(JSON.stringify(receipt,"\t"));file.close()
	core.close();map.queue_free();await process_frame
	print(JSON.stringify(receipt));quit(0 if failures.is_empty() else 1)
