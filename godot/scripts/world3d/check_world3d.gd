extends SceneTree
const View=preload("res://scripts/world3d/world3d_view.gd")
const Core=preload("res://scripts/core_bridge.gd")
var checks:Array=[]
func _initialize()->void:call_deferred("_run")
func check(label:String,valid:bool,details:Variant=null)->void:
	checks.append({"label":label,"pass":valid,"details":details})
	if not valid:push_error(label+": "+str(details))
func _run()->void:
	var bridge=Core.new()
	var response:Dictionary=bridge.request({"op":"island_home_preview","version":"cas-island-war-v4","seed":714,"hq_level":5,"buildings":[{"id":"hq","kind":"hq","cell":{"x":6,"y":4},"level":5},{"id":"store","kind":"warehouse","cell":{"x":5,"y":4},"level":4},{"id":"farm","kind":"farm","cell":{"x":5,"y":3},"level":4}]})
	bridge.close()
	check("verified native home responds",bool(response.get("ok",false)))
	var source:Dictionary=response.get("data",response);var land:Dictionary=source.get("littoral",{}).get("land",{})
	check("native polygon",land.get("polygon",[]).size()>3)
	var bodies:Array=[]
	for i:int in range(3):bodies.append({"id":i+1,"unit_id":"MCP-034","company_id":"MCP-034-C01","kind":"infantry","side":"allies","x":14580+i*7,"y":13000,"hp":100,"max_hp":100,"velocity":{"x":1,"y":0}})
	bodies.append({"id":40,"unit_id":"MCP-022","company_id":"MCP-022-C01","kind":"tank","vehicle_kind":"tank","side":"allies","x":14610,"y":13010,"hp":100,"heading":90})
	land["entities"]=bodies;land["tick"]=0;land["equipment_version"]="tactical-vehicles-v4"
	var view=View.new();view.size=Vector2(1600,900);root.add_child(view);view.observe(land,false);view.set_camera(Vector2(14600,13000),18)
	await process_frame
	print("WORLD3D_NATIVE_HEIGHT_MODEL ",land.get("terrain",{}).get("height_model",""))
	var native_mesh:MeshInstance3D=view.surface.root.get_node("NativeGround") as MeshInstance3D
	print("WORLD3D_GROUND_NORMAL ",(native_mesh.mesh.surface_get_arrays(0)[Mesh.ARRAY_NORMAL] as PackedVector3Array)[0])
	var worst:float=0
	for x:int in range(-7,8):
		for y:int in range(-7,8):
			var point:=Vector2(14600+x*23,13000+y*23)
			var restored:Vector2=view.unproject(view.project(point));worst=maxf(worst,point.distance_to(restored))
	check("project/unproject native close-up 225 probes",worst<.08,worst)
	var root_id:int=view.surface.root.get_instance_id();var actor_id:int=view.actors["entity:1"].node.get_instance_id()
	land["tick"]=1.0;land.entities[0].hp=90;view.observe(land,true)
	check("tick/HP preserves terrain instance",view.surface.root.get_instance_id()==root_id)
	check("stable body ID preserves anchor",view.actors["entity:1"].node.get_instance_id()==actor_id)
	check("independent tank loaded GLB",view.actors["entity:40"].model!=null)
	check("tank native heading 90 faces east",absf(sin(view.actors["entity:40"].node.rotation.y)+1.0)<.001)
	check("only person is billboard",view.actors["entity:1"].sprite is Sprite3D and view.actors["entity:40"].sprite==null)
	var before:Vector3=view.actors["entity:1"].node.position
	view.set_camera(Vector2(14600,13000),36)
	check("zoom leaves physical anchor",before.is_equal_approx(view.actors["entity:1"].node.position))
	view.set_view_mode("sea");var sea_error:float=view.unproject(view.project(Vector2(14622,13010))).distance_to(Vector2(14622,13010))
	check("sea top-view metre roundtrip",sea_error<.08,sea_error)
	view.set_chart_camera(Vector2(14600,13000),2.0)
	var east:Vector2=view.project(Vector2(14620,13000))-view.project(Vector2(14600,13000))
	var north:Vector2=view.project(Vector2(14600,13020))-view.project(Vector2(14600,13000))
	check("chart east +X right / north +Y up",east.x>0 and north.y<0,{"east":east,"north":north})
	check("chart exact requested metres/pixel",absf(east.length()-10.0)<.02,east.length())
	worst=0
	for offset:Vector2 in [Vector2(-900,-500),Vector2(-900,500),Vector2(900,-500),Vector2(900,500)]:
		var point:Vector2=Vector2(14600,13000)+offset;worst=maxf(worst,view.unproject(view.project(point)).distance_to(point))
	check("chart four-corner metre roundtrip",worst<.08,worst)
	# Exercise the continuous read-only contract separately. This does not install
	# a new rule or modify the native fixture used for the actual candidate.
	var continuous:Dictionary={"polygon":[{"x":0,"y":0},{"x":900,"y":0},{"x":900,"y":900},{"x":0,"y":900}],"terrain":{"height_model":"inset_edge_blend_v1","elevation_zones":[{"polygon":[{"x":200,"y":200},{"x":700,"y":200},{"x":700,"y":700},{"x":200,"y":700}],"height_m":80,"level":2,"blend_width_m":120}]}}
	var other=View.new();other.size=Vector2(1600,900);root.add_child(other);other.observe(continuous);other.set_camera(Vector2(450,450),1.5)
	worst=0
	for x:int in range(10):
		for y:int in range(10):
			var point:=Vector2(207+x*13,230+y*15);worst=maxf(worst,other.unproject(other.project(point)).distance_to(point))
	check("continuous slope ray solves 100 probes",worst<.08,worst)
	other.free()
	view.set_view_mode("land");view.set_camera(Vector2(14600,13000),18)
	var folder:String="D:/desktop/cas/artifacts/world3d-candidate-20261116"
	DirAccess.make_dir_recursive_absolute(folder)
	var file:=FileAccess.open(folder+"/native-land.json",FileAccess.WRITE);file.store_string(JSON.stringify(land));file.close()
	if "--capture" in OS.get_cmdline_user_args():
		root.size=Vector2i(1600,900)
		for i:int in range(8):await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(folder+"/land-native-close.png")
		view.set_camera(Vector2(14600,13000),1)
		for i:int in range(4):await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(folder+"/land-native-overview.png")
		view.set_camera(Vector2(14600,13000),72)
		for i:int in range(4):await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(folder+"/units-native-close.png")
		for feature:Dictionary in land.terrain.features:
			if str(feature.kind)=="forest":
				var center:Vector2=Vector2.ZERO;var shape:Array=feature.polygon
				for p:Dictionary in shape:center+=Vector2(p.x,p.y)
				center/=shape.size();view.set_camera(center,30)
				for i:int in range(4):await process_frame
				await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png(folder+"/forest-native-close.png");break
	var report:Dictionary={"checks":checks,"pass":checks.all(func(row:Dictionary)->bool:return row.pass),"statistics":view.statistics(),"native_height_model":land.get("terrain",{}).get("height_model","")}
	file=FileAccess.open(folder+"/renderer-check.json",FileAccess.WRITE);file.store_string(JSON.stringify(report,"\t"));file.close()
	print("WORLD3D_RENDERER_CHECK ",JSON.stringify(report))
	view.free();await process_frame
	quit(0 if report.pass else 1)
