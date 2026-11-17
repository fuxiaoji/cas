extends SceneTree
const Bridge=preload("res://scripts/core_bridge.gd")
const Sea=preload("res://scripts/sea_map.gd")
const Art=preload("res://scripts/character_art.gd")
var core=Bridge.new()
var map
var checks:=0
var failures: Array[String]=[]
var shots: Array[String]=[]
var output:=""
func _initialize() -> void:call_deferred("review")
func check(condition:bool,message:String)->void:
	checks+=1
	if not condition:failures.append(message);push_error(message)
func request(value:Dictionary)->void:
	var response:Dictionary=core.request(value)
	check(response.get("ok",false),str(value.op)+" "+str(response.get("error","")))
func capture(name:String)->void:
	map.queue_redraw();map.environment_layer._process(0)
	await process_frame;await process_frame
	if DisplayServer.get_name()=="headless":return
	await RenderingServer.frame_post_draw
	var path:=output.path_join(name+".png")
	check(root.get_texture().get_image().save_png(path)==OK,"saved "+name);shots.append(path)
func review()->void:
	output=ProjectSettings.globalize_path("res://../artifacts/godot/chapter-environment")
	DirAccess.make_dir_recursive_absolute(output)
	map=Sea.new();root.add_child(map);map.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	map.environment_layer.set_process(false)
	var catalog:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/ships.json"))
	for card in catalog.ships:map.cards[str(card.id)]=card
	for stage in ["c1-breakout","c1-salvage","c1-boss"]:
		request({"op":"new_chapter","id":stage,"seed":6109})
		var source:Dictionary=core.view.duplicate(true)
		map.view=source.duplicate(true);map.zoom=2.5;map.pan=Vector2.ZERO
		map.pan=map.size*.5-map.project(Vector2(5400,2800))
		map.environment_layer.weather.current.clear();map.environment_layer.visual_time=3.5;map.environment_layer.drift=Vector2.ZERO
		check(source.chapter.stageId==stage,"correct native stage "+stage)
		for own in source.ships:
			var resolved:=Art.resolve(map.cards,own,false)
			check(not resolved.representative,"own render never substitutes class identity")
		for contact in source.contacts:
			if contact.has("entityKind"):
				var species:=str(contact.visualType)
				var asset:="res://assets/story/chapter1/tideborn.png" if species=="aversion" else "res://assets/enemies/"+species+"-v1.png"
				check(ResourceLoader.exists(asset),"public creature has final sprite: "+species)
		if stage=="c1-breakout":check(source.chapter.objective.beacon is Dictionary,"beacon is public authoritative objective coordinate")
		if stage=="c1-salvage":check(int(source.chapter.objective.archiveRuinId)==1,"archive special mark uses public ruin id")
		if stage=="c1-boss":
			check(source.contacts.any(func(c:Dictionary):return c.get("boss",false) and c.get("phase",0)==1 and is_equal_approx(float(c.get("health_fraction",0)),1.0)),"native Boss phase and health available")
		await capture(stage+"-contact")
		check(map.view==source,"scene render observation read-only: "+stage)
		request({"op":"step","seconds":31})
		map.view=core.view.duplicate(true)
		var warnings:Array=map.view.salvage.get("telegraphs",[])
		for warning in warnings:
			check(map.view.contacts.any(func(c:Dictionary):return str(c.id)==str(warning.source_contact)),"warning always refers to currently visible source contact")
			check(float(warning.radius)>0 and int(warning.impact_tick)>int(map.view.tick),"warning uses authoritative future impact radius/tick")
		if not warnings.is_empty():
			var target:Vector2=map.pos(warnings[0])
			var matching:Array=map.view.contacts.filter(func(c:Dictionary):return str(c.id)==str(warnings[0].source_contact))
			var center:Vector2=target.lerp(map.pos(matching[0]),.5) if not matching.is_empty() else target
			map.zoom=2.3;map.pan=Vector2.ZERO
			map.pan=map.size*.5-map.project(center)
			await capture(stage+"-warning")
	var receipt:={"checks":checks,"passed":checks-failures.size(),"failures":failures,"screenshots":shots,"source":"three actual new_chapter native observations; no enemy truth queries","sprites":"full transparent images; Boss larger, exact contact center retained"}
	receipt["core_sha256"]=FileAccess.get_sha256(OS.get_environment("CAS_SIM_PATH") if OS.has_environment("CAS_SIM_PATH") else ProjectSettings.globalize_path("res://../target/release/cas-sim.exe"))
	var file:=FileAccess.open(output.path_join("receipt-headless.json" if DisplayServer.get_name()=="headless" else "receipt.json"),FileAccess.WRITE);file.store_string(JSON.stringify(receipt,"\t"));file.close()
	core.close();map.queue_free();await process_frame
	print(JSON.stringify(receipt));quit(0 if failures.is_empty() else 1)
