extends SceneTree
## GPU rendering of the exact frozen generator input. Pending native adoption;
## this scene is an art fixture, never a playable authority or account mutation.
const View=preload("res://scripts/world3d/world3d_view.gd")
var folder:String="D:/desktop/cas/artifacts/world3d-coastal-pending-core-20261116"
func _initialize()->void:call_deferred("_run")
func _run()->void:
	DirAccess.make_dir_recursive_absolute(folder)
	var geography:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/coastal-demo-v1-714.json"))
	geography["geometry_hash"]="pending-core-frozen-input-714"
	var pivot:=Vector2(14600,13000)
	var land:Dictionary={"geography":geography,"polygon":[{"x":14240,"y":12640},{"x":14960,"y":12640},{"x":14960,"y":13360},{"x":14240,"y":13360}],"terrain":{"features":[],"roads":[]},"buildings":[],"entities":[],"transports":[]}
	var kinds:Array=["hq","recycler","forge","solar","medical","depot","aa","turret","dock","machine_gun","mortar","anti_ship","repair_tower"]
	for i:int in range(kinds.size()):
		land.buildings.append({"id":str(i),"kind":kinds[i],"x":14600-63+(i%4)*40,"y":13000+106+floori(i/4.0)*37,"hp":100})
	for x:float in [-84,-24,64]:land.terrain.roads.append({"width":6,"points":[{"x":14600+x,"y":13080},{"x":14600+x,"y":13240}]})
	for y:float in [84,124,162,198,237]:land.terrain.roads.append({"width":6,"points":[{"x":14516,"y":13000+y},{"x":14664,"y":13000+y}]})
	for i:int in range(4):land.entities.append({"id":i+1,"unit_id":"MCP-034","kind":"infantry","side":"allies","x":14580+i*7,"y":13129,"hp":100,"max_hp":100})
	var view=View.new();view.low_detail=false;view.size=Vector2(1600,900);root.size=Vector2i(1600,900);root.add_child(view);view.observe(land)
	var road_area:float=0;var height_difference:float=0
	for child:Node in view.surface.root.get_children():
		if str(child.name).begins_with("NativeRoad"):
			var positions:PackedVector3Array=(child.mesh as Mesh).surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
			for i:int in range(0,positions.size(),3):
				var a:=Vector2(positions[i].x,positions[i].z);var b:=Vector2(positions[i+1].x,positions[i+1].z);var c:=Vector2(positions[i+2].x,positions[i+2].z)
				road_area+=absf((b-a).cross(c-a))*.5
				var p:Vector3=(positions[i]+positions[i+1]+positions[i+2])/3.0
				height_difference=maxf(height_difference,absf(p.y-view.surface.height_at(Vector2(p.x,p.z)+view.surface.origin)-.14))
	print("ROAD_AUDIT ",road_area," max height error ",height_difference)
	print("NATIVE_OCCLUSION_HEIGHTS ",view.height_at(Vector2(14455.74707,12962.5625))," front ",view.height_at(Vector2(14467.73,12946.68)))
	var cameras:Array=[{"name":"home-whole","point":pivot+Vector2(0,105),"span":300.0},{"name":"home-base","point":pivot+Vector2(0,157),"span":175.0},{"name":"home-close-90m","point":pivot+Vector2(8,133),"span":90.0},{"name":"coastal-water","point":pivot+Vector2(0,-42),"span":205.0},{"name":"forest-mountain","point":pivot+Vector2(160,95),"span":230.0}]
	var worst:float=0.0
	for entry:Dictionary in cameras:
		view.set_camera(entry.point,720.0/float(entry.span))
		for y:int in range(-3,4):
			for x:int in range(-3,4):
				var p:Vector2=entry.point+Vector2(x*4,y*4);worst=maxf(worst,view.unproject(view.project(p)).distance_to(p))
		for i:int in range(8):await process_frame
		if DisplayServer.get_name()!="headless":
			await RenderingServer.frame_post_draw;root.get_texture().get_image().save_png(folder+"/"+str(entry.name)+".png")
	var report:Dictionary={"scope":"pending-core art fixture; frozen input only","source_sha256":FileAccess.get_sha256("res://data/coastal-demo-v1-714.json"),"grid":view.surface.has_grid,"max_roundtrip_m":worst,"pass":view.surface.has_grid and worst<.05}
	view.set_chart_camera(pivot,30000.0/900.0)
	for i:int in range(5):await process_frame
	if DisplayServer.get_name()!="headless":
		await RenderingServer.frame_post_draw;root.get_texture().get_image().save_png(folder+"/chart-30km.png")
	if "--diagnose" in OS.get_cmdline_user_args():
		view.set_camera(pivot+Vector2(8,133),8.0)
		for cloud:MeshInstance3D in view._clouds:cloud.visible=false
		for i:int in range(5):await process_frame
		await RenderingServer.frame_post_draw;root.get_texture().get_image().save_png(folder+"/debug-no-cloud.png")
		view.world_root.get_node("CoastalSun").shadow_enabled=false
		for i:int in range(5):await process_frame
		await RenderingServer.frame_post_draw;root.get_texture().get_image().save_png(folder+"/debug-no-shadow.png")
	FileAccess.open(folder+"/check.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"));print("WORLD3D_COASTAL_GRID ",JSON.stringify(report))
	view.free();await process_frame;quit(0 if report.pass else 1)
