extends SceneTree
## Actual production page changes, with real GPU frame capture of each hop.
const Economy=preload("res://scripts/economy.gd")
const Wait=preload("res://tests/transition_settle.gd")
const OUTPUT:String="res://../artifacts/hop-transition/"
var app
var checks:int=0
var failures:Array[String]=[]
var captures:Array=[]
var frame_sequence:int=0
var routes:Array=[]
func _initialize()->void:call_deferred("run")
func check(ok:bool,label:String)->bool:
	checks+=1
	if not ok:failures.append(label);push_error(label)
	return ok
func frame()->void:await process_frame;RenderingServer.force_draw()
func run()->void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT+"frames/"))
	var primary:String="user://cas_port_v1.json";var primary_sha:String=FileAccess.get_sha256(primary);var backup_sha:String=FileAccess.get_sha256(primary+".bak")
	var preference:String="user://cas_audio_v1.json";var settings_sha:String=FileAccess.get_sha256(preference)
	var manifest_sha:String=FileAccess.get_sha256("res://bin/core-current.json")
	var previous_fps:int=Engine.max_fps;Engine.max_fps=60
	root.content_scale_size=Vector2i(1600,900);root.content_scale_mode=Window.CONTENT_SCALE_MODE_CANVAS_ITEMS;root.size=Vector2i(1280,720)
	app=load("res://scenes/main.tscn").instantiate();app.boot_to_title=false
	app.economy=Economy.new("user://tests/hop-transition-%d.json"%OS.get_process_id())
	root.add_child(app);app.set_process(false);await frame();await frame()
	app.page_motion=false;app.show_page("harbor");await frame();await frame()
	var account:String=JSON.stringify(app.economy.state)
	app.page_motion=true;app.set_meta("reduced_motion",false)
	var transition:Node=app.page_transition
	check(is_equal_approx(transition.duration,1.18) and transition.hop_count==3,"readable 1.18-second three-hop default")
	check(transition.full_screen_wipe and transition.max_transition_characters==3,"full-screen anime wipe and three-person cap retained")
	for pair in [{"route":"formation","style":0},{"route":"modes","style":1},{"route":"home","style":2}]:await record_route(str(pair.route),int(pair.style))
	check(routes.all(func(row):return bool(row.settled)),"all actual page changes release mask and finish synchronously built pages")
	var last_cast:Array=[]
	for row in routes:
		check(row.identities.size()==3,"three authentic unique SD identities in actual "+str(row.route))
		check(row.identities.all(func(id):return not last_cast.has(id)),"actual next page chooses different SD faces")
		last_cast=row.identities
	# Sample dense preview timing as supplementary motion evidence, then compare
	# actual captured frames below. Preview alone is never the visual acceptance.
	for dimensions in [Vector2i(960,540),Vector2i(1280,720),Vector2i(1920,1080),Vector2i(1600,720)]:
		root.size=dimensions;await frame();transition._pick_characters(app)
		var series:Array=[[],[],[]]
		for sample in range(121):
			transition.preview_at(0,float(sample)/120.0)
			for index in range(3):
				var state:Dictionary=transition.actor_states[index]
				series[index].append({"height":state.hop_height_pixels,"foot":state.foot_position,"grounded":state.grounded,"alpha":state.sprite.modulate.a})
		for index in range(3):
			var samples:Array=series[index];var peaks:int=0;var locked:bool=true;var last_ground:Variant=null
			var peak_height:float=0
			for i in range(1,samples.size()-1):
				peak_height=maxf(peak_height,float(samples[i].height))
				if samples[i].height>10 and samples[i].height>samples[i-1].height and samples[i].height>=samples[i+1].height:peaks+=1
				if samples[i].grounded:
					if last_ground!=null and last_ground.i==i-1:locked=locked and samples[i].foot.distance_to(last_ground.foot)<.01
					last_ground={"i":i,"foot":samples[i].foot}
			check(peaks==3,"three complete visible arcs at "+str(dimensions)+" actor"+str(index))
			check(locked,"feet stop horizontally while grounded at "+str(dimensions)+" actor"+str(index))
			check(peak_height>root.get_visible_rect().size.y*.05,"jump rises visibly above the ground at "+str(dimensions)+" actor"+str(index))
			var travel:float=samples[-1].foot.x-samples[0].foot.x
			check(travel>root.get_visible_rect().size.x*.13 and travel<root.get_visible_rect().size.x*.15,"short total distance avoids a screen-wide slide "+str(dimensions))
		transition.preview_at(0,.5);await frame()
		for state in transition.actor_states:
			check(state.sprite.get_global_rect().intersection(root.get_visible_rect()).get_area()>state.sprite.get_global_rect().get_area()*.95,"three large characters remain inside safe area "+str(dimensions))
	transition.cancel();root.size=Vector2i(1280,720);await frame()
	# Real pointer must be blocked during the hop, then released without a hold.
	app.show_page("modes");await frame()
	var point:Vector2=app.get_viewport().get_screen_transform()*app.page.get_global_transform_with_canvas()*Vector2(100,45)
	for pressed in [true,false]:
		var event:=InputEventMouseButton.new();event.button_index=MOUSE_BUTTON_LEFT;event.pressed=pressed;event.position=point;Input.parse_input_event(event);await frame()
	check(app.screen=="modes" and transition.overlay.mouse_filter==Control.MOUSE_FILTER_STOP,"real pointer cannot click through during the hopping parade")
	await Wait.wait_for_route(self,app)
	check(not transition.is_busy() and transition.overlay.mouse_filter==Control.MOUSE_FILTER_IGNORE,"real barrier and route helper finish without bypass")
	app.show_page("warehouse");app.show_page("harbor");await Wait.wait_for_route(self,app)
	check(app.screen=="harbor" and not transition.is_busy() and not transition.overlay.visible,"rapid routes cancel old actors and settle on final page")
	app.set_meta("reduced_motion",true);app.show_page("modes");check(not transition.is_busy() and not transition.overlay.visible,"reduced motion stays immediate")
	app.set_meta("reduced_motion",false);app.page_motion=false;app.show_page("harbor");check(not transition.is_busy(),"animation off stays immediate")
	check(JSON.stringify(app.economy.state)==account,"all recorded navigation and animation leave isolated account unchanged")
	check(FileAccess.get_sha256(primary)==primary_sha and FileAccess.get_sha256(primary+".bak")==backup_sha,"normal account and backup untouched")
	check(FileAccess.get_sha256(preference)==settings_sha,"normal audio settings untouched")
	check(FileAccess.get_sha256("res://bin/core-current.json")==manifest_sha,"7134 default core manifest untouched")
	var packed:PackedScene=PackedScene.new();var editable=load("res://scenes/ui/page_transition.tscn").instantiate()
	editable.duration=1.23;editable.hop_count=4;editable.travel_distance_fraction=.12;editable.hop_height=66;editable.show_ground_shadow=false
	check(packed.pack(editable)==OK,"native transition and hop parameters remain packable")
	var copy:String="user://tests/hop-scene-%d.tscn"%OS.get_process_id();check(ResourceSaver.save(packed,copy)==OK,"save designer-edited scene copy")
	var restored=ResourceLoader.load(copy,"PackedScene",ResourceLoader.CACHE_MODE_IGNORE).instantiate()
	check(is_equal_approx(restored.duration,1.23) and restored.hop_count==4 and is_equal_approx(restored.travel_distance_fraction,.12) and is_equal_approx(restored.hop_height,66) and not restored.show_ground_shadow,"duration, steps, distance, height and shadow Inspector overrides survive reload")
	check(restored.has_node("Overlay/ActorShadow") and restored.has_node("Overlay/Actor") and restored.has_node("Overlay/Timeline"),"native actor, shadow and timeline remain directly editable")
	editable.free();restored.free();app.core.close();app.queue_free();await process_frame;Engine.max_fps=previous_fps
	var report:Dictionary={"checks":checks,"failures":failures,"passed":failures.is_empty(),"actual_route_frames":captures,"routes":routes,"normal_account_sha256":primary_sha,"normal_backup_sha256":backup_sha,"core_manifest_sha256":manifest_sha,"core_override":OS.get_environment("CAS_SIM_PATH"),"account_access":"PID-isolated new profile only; no combat or economic commands","gpu":RenderingServer.get_video_adapter_name(),"visual_acceptance":"Actual timed GPU frame sequence captured; inspect generated video/storyboard before signing visual review."}
	FileAccess.open(OUTPUT+"receipt.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	print("HOP_TRANSITION ",JSON.stringify({"checks":checks,"failures":failures,"frames":captures.size()}));quit(0 if failures.is_empty() else 1)

func record_route(route:String,style:int)->void:
	var transition:Node=app.page_transition;app.set_meta("transition_style",style)
	RenderingServer.force_draw();app.show_page(route)
	var began:int=Time.get_ticks_msec();var identities:Array=[]
	for state in transition.actor_states:identities.append(str(state.identity))
	var first:int=captures.size()
	while transition.is_busy() and Time.get_ticks_msec()-began<2200:
		await frame()
		if not transition.is_busy():break
		transition._process(0);RenderingServer.force_draw()
		var actors:Array=[]
		for state in transition.actor_states:actors.append({"identity":state.identity,"foot_x":state.foot_position.x,"foot_y":state.foot_position.y,"height":state.hop_height_pixels,"grounded":state.grounded,"step":state.step_index,"scale":str(state.sprite.scale),"rotation":state.sprite.rotation})
		var path:String=OUTPUT+"frames/%04d.png"%frame_sequence
		if root.get_texture().get_image().save_png(ProjectSettings.globalize_path(path))!=OK:check(false,"save actual transition frame")
		captures.append({"path":ProjectSettings.globalize_path(path),"route":route,"style":style,"elapsed_ms":Time.get_ticks_msec()-began,"phase":transition.player.current_animation_position/transition._clip_length(),"actors":actors});frame_sequence+=1
	var elapsed:int=Time.get_ticks_msec()-began
	routes.append({"route":route,"style":style,"identities":identities,"frames":captures.size()-first,"wall_ms":elapsed,"settled":not transition.is_busy() and not transition.overlay.visible})
	check(elapsed>=1080 and elapsed<1750,"actual "+route+" duration is readable with no extra loading hold")
	await frame()
