extends SceneTree
const Bridge=preload("res://scripts/core_bridge.gd")
const Map=preload("res://scripts/battle_map.gd")
var core=Bridge.new()
var failures: Array[String]=[]
var checks:=0
var shots: Array[String]=[]
var selections: Array[Dictionary]=[]
var waypoints: Array[Vector2]=[]
var map
var output:=""
func _initialize() -> void:call_deferred("review")
func check(condition: bool, description: String) -> void:
	checks+=1
	if not condition:failures.append(description);push_error(description)
func request(command: Dictionary) -> Dictionary:
	var result: Dictionary=core.request(command)
	check(result.get("ok",false),"native "+str(command.op)+": "+str(result.get("error","ok")))
	return result
func pointer(world: Vector2) -> void:
	var p: Vector2=map.get_viewport().get_screen_transform()*map.get_global_transform_with_canvas()*map.project(world)
	var move:=InputEventMouseMotion.new();move.position=p;Input.parse_input_event(move)
	for pressed in [true,false]:
		var button:=InputEventMouseButton.new();button.button_index=MOUSE_BUTTON_LEFT;button.position=p;button.pressed=pressed;Input.parse_input_event(button)
		await process_frame
	await process_frame
func capture(name: String) -> void:
	if DisplayServer.get_name()=="headless":return
	map.queue_redraw()
	await process_frame
	await RenderingServer.frame_post_draw
	var path:=output.path_join(name+".png")
	check(root.get_texture().get_image().save_png(path)==OK,"saved "+name)
	shots.append(path)
func review() -> void:
	output=ProjectSettings.globalize_path("res://../artifacts/godot/extraction-region")
	DirAccess.make_dir_recursive_absolute(output)
	var raw: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/ships.json"))
	var fleet: Array[Dictionary]=[]
	var groups: Array[Dictionary]=[{"id":"group-a","name":"第一编队","ships":[]},{"id":"group-b","name":"第二编队","ships":[]}]
	for card in raw.ships:
		if not str(card.id).begins_with("IBS-U-USN-") or not bool(card.get("playable",false)):continue
		var id:=str(card.id)
		fleet.append({"id":id,"hp":100,"ammo":100,"level":0,"equipment":false,"command":false})
		groups[0 if fleet.size()<=8 else 1].ships.append(id)
		if fleet.size()==15:break
	check(fleet.size()==15,"15 actual registered hulls assembled without duplicates")
	request({"op":"new_salvage","seed":42,"start":{"content":"salvage-v2","fleet":fleet,"groups":groups}})
	var source: Dictionary=core.view.duplicate(true)
	check(source.ships.size()==15 and source.fleets.size()==2,"native observation contains fifteen hulls in two real fleets")
	var exit: Dictionary=source.salvage.exits[0]
	if not exit.has("bounds"):
		check(false,"v2 public rectangular exit available")
		core.close();quit(1);return
	var bounds: Dictionary=exit.bounds
	map=Map.new();root.add_child(map)
	map.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	map.view=source.duplicate(true)
	map.chibis=false
	map.ranges_visible=false
	map.object_selected.connect(func(kind: String,object: Dictionary):selections.append({"kind":kind,"object":object}))
	map.point_selected.connect(func(point: Vector2):waypoints.append(point))
	await process_frame
	var region: Rect2=map.exit_region(0)
	check(region==Rect2(Vector2(float(bounds.min_x),float(bounds.min_y)),Vector2(float(bounds.max_x)-float(bounds.min_x),float(bounds.max_y)-float(bounds.min_y))),"render reads exact authoritative bounds")
	var min_point:=Vector2(INF,INF);var max_point:=Vector2(-INF,-INF)
	for ship in source.ships:
		var p: Vector2=map.pos(ship)
		min_point=min_point.min(p);max_point=max_point.max(p)
		check(region.has_point(p),"initial hull inside gathering region: "+str(ship.id))
	check(region.position==min_point-Vector2(500,500) and region.end==max_point+Vector2(500,500),"fixed region is initial full fleet footprint plus 500m")
	check(map.pos(exit)==region.get_center(),"click marker uses authoritative rectangle center")
	check(not source.salvage.exits[1].has("bounds") and source.salvage.exits[1].shape=="circle" and source.salvage.exits[1].radius==1000,"eastern exit remains original 1000m circle")
	check(not source.salvage.exits[2].has("bounds") and source.salvage.exits[2].shape=="circle" and source.salvage.exits[2].radius==1000,"other exit remains original 1000m circle")
	map.zoom=3.0;map.pan=Vector2.ZERO
	map.pan=map.size*.5-map.project(region.get_center())
	map.queue_redraw()
	await process_frame
	var screen: Rect2=map.exit_screen_region(0)
	check(map.unproject(screen.position).distance_to(Vector2(region.position.x,region.end.y))<.01,"top-left border projects exact min_x max_y")
	check(map.unproject(screen.end).distance_to(Vector2(region.end.x,region.position.y))<.01,"bottom-right border projects exact max_x min_y")
	check(map._get_tooltip(map.project(map.pos(exit))).contains("矩形"),"marker tooltip explains rectangular gathering area")
	await capture("01-fifteen-ships-two-fleets-region")
	await pointer(map.pos(exit))
	check(selections.size()==1 and selections[0].kind=="exit" and int(selections[0].object.index)==0,"only center marker retains exit selection")
	var empty_point:=Vector2(region.position.x+100.0,region.get_center().y)
	var count:=selections.size()
	await pointer(empty_point)
	check(selections.size()==count,"empty area does not capture exit selection")
	map.editing=true
	await pointer(empty_point)
	check(waypoints.size()==1 and waypoints[0].distance_to(empty_point)<.01,"route drafting still works inside gathering rectangle")
	map.editing=false
	check(core.view==source and map.view==source,"drawing and input never mutate authoritative observation")
	request({"op":"salvage_collect","ruin":1})
	request({"op":"step","seconds":int(source.salvage.searchDuration)})
	check(core.view.salvage.cargo.size()==5,"two-fleet sortie collects five real scrap")
	request({"op":"salvage_extract","exit":0})
	check(core.view.salvage.extracting is Dictionary,"all fifteen hulls begin actual gathering extraction")
	request({"op":"step","seconds":12})
	check(bool(core.view.salvage.extracted) and core.view.salvage.cargo.size()==5,"all fifteen hulls complete actual extraction with cargo")
	map.view=core.view.duplicate(true)
	await capture("02-native-extracted-fifteen-ships")
	var hull:=fleet[0].duplicate(true);hull.level=1
	request({"op":"new_salvage","seed":42,"start":{"content":"salvage-v1","fleet":[hull]}})
	check(core.view.salvage.exits[0]=={"x":2200.0,"y":2200.0},"v1 exact original exit observation preserved")
	map.view=core.view.duplicate(true)
	check(not map.exit_region(0).has_area(),"v1 draws no inferred rectangular region")
	check(not map.exit_tooltip(0).contains("矩形"),"v1 retains circular extraction explanation")
	var report:={"checks":checks,"passed":checks-failures.size(),"failures":failures,"initial_bounds":bounds,"exit_center":map.pos(exit),"ships":15,"groups":2,"actual_cargo_recovered":5,"screenshots":shots,"source":"public observation only; no inferred geometry or state edits"}
	var file:=FileAccess.open(output.path_join("receipt.json"),FileAccess.WRITE);file.store_string(JSON.stringify(report,"\t"));file.close()
	core.close();map.queue_free();await process_frame
	print(JSON.stringify(report));quit(0 if failures.is_empty() else 1)
