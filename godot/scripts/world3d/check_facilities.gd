extends SceneTree
const Core=preload("res://scripts/core_bridge.gd")
const View=preload("res://scripts/world3d/world3d_view.gd")
var checks:Array=[]
var folder:String="D:/desktop/cas/artifacts/world3d-candidate-20261116/facilities"
func _initialize()->void:call_deferred("_run")
func _bounds(node:Node,state:Dictionary)->void:
	if node is MeshInstance3D:
		var mesh:MeshInstance3D=node as MeshInstance3D
		if mesh.mesh!=null:
			var box:AABB=mesh.global_transform*mesh.mesh.get_aabb()
			state.bounds=box if int(state.count)==0 else (state.bounds as AABB).merge(box);state.count+=1
	for child:Node in node.get_children():_bounds(child,state)
func _run()->void:
	DirAccess.make_dir_recursive_absolute(folder)
	var kinds:Array=["hq","recycler","forge","solar","medical","turret","aa","depot","dock","machine_gun","mortar","anti_ship","repair_tower"]
	var buildings:Array=[]
	for i:int in range(kinds.size()):buildings.append({"id":str(kinds[i]),"kind":kinds[i],"level":3,"cell":{"x":4+i%4,"y":3+int(i/4)}})
	var bridge=Core.new();var response:Dictionary=bridge.request({"op":"island_home_preview","version":"cas-island-war-v4","seed":714,"hq_level":5,"buildings":buildings});bridge.close()
	var source:Dictionary=response.get("data",response);var land:Dictionary=source.get("littoral",{}).get("land",{})
	var view=View.new();view.low_detail=false;view.size=Vector2(1600,900);root.add_child(view);view.observe(land,false)
	await process_frame
	for row:Dictionary in land.get("buildings",[]):
		var node:Node3D=view.surface.facilities["building:"+str(row.id)]
		var state:Dictionary={"count":0,"bounds":AABB()};_bounds(node,state)
		checks.append({"kind":row.kind,"meshes":state.count,"height_m":(state.bounds as AABB).size.y,"pass":int(state.count)>0 and (state.bounds as AABB).size.y>2.0})
		if "--capture" in OS.get_cmdline_user_args():
			view.set_camera(Vector2(float(row.x),float(row.y)),100)
			for i:int in range(4):await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(folder+"/"+str(row.kind)+".png")
	var file:=FileAccess.open(folder+"/check.json",FileAccess.WRITE);file.store_string(JSON.stringify({"checks":checks,"pass":checks.size()==13 and checks.all(func(row:Dictionary)->bool:return row.pass)},"\t"));file.close()
	print("WORLD3D_FACILITIES ",JSON.stringify(checks))
	view.free();await process_frame;quit(0 if checks.size()==13 and checks.all(func(row:Dictionary)->bool:return row.pass) else 1)
