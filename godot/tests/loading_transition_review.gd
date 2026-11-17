extends SceneTree
## Public two-stage protocol against the actual overlay; no account/core mutation.
const Output:String="res://../artifacts/loading-transition/"
class EmptyRoster extends RefCounted:
	func roster()->Array:return []
class Host extends Node:
	var page_motion:bool=true
	var economy=EmptyRoster.new()
	var screen:String="old"
	var page:Control
var host:Host
var transition
var page:Control
var checks:int=0
var failures:Array[String]=[]
var covered_tokens:Array[int]=[]
var finished_count:int=0
var clicks:int=0
var parade_motion:Array=[]
func _initialize()->void:call_deferred("run")
func check(ok:bool,text:String)->void:
	checks+=1
	if not ok:failures.append(text);push_error(text)
func frames(count:int=2)->void:
	for index in range(count):await process_frame
func settled(maximum:float=2)->void:
	var start:int=Time.get_ticks_msec()
	while transition.is_busy() and Time.get_ticks_msec()-start<int(maximum*1000):await process_frame
func covered(maximum:float=2)->void:
	var start:int=Time.get_ticks_msec()
	while not transition.is_covered() and Time.get_ticks_msec()-start<int(maximum*1000):await process_frame
func shot(name:String)->void:
	if DisplayServer.get_name()=="headless":return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path(Output+name+".png"))
func pointer()->void:
	var at:Vector2=root.get_screen_transform()*Vector2(110,80)
	for pressed in [true,false]:
		var event:=InputEventMouseButton.new();event.button_index=MOUSE_BUTTON_LEFT;event.pressed=pressed;event.position=at;Input.parse_input_event(event);await process_frame
func run()->void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(Output))
	var before:String=FileAccess.get_sha256("user://cas_port_v1.json");var backup:String=FileAccess.get_sha256("user://cas_port_v1.json.bak");var manifest:String=FileAccess.get_sha256("res://bin/core-current.json")
	root.content_scale_size=Vector2i(1600,900);root.size=Vector2i(1280,720)
	page=Control.new();page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);root.add_child(page)
	var background:=ColorRect.new();background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);background.color=Color("102f46");page.add_child(background)
	var button:=Button.new();button.position=Vector2(40,40);button.size=Vector2(150,80);button.text="页面已就绪";button.pressed.connect(func():clicks+=1);page.add_child(button)
	host=Host.new();host.page=page;root.add_child(host)
	transition=load("res://scenes/ui/page_transition.tscn").instantiate();root.add_child(transition);await frames()
	transition.loading_covered.connect(func(token):covered_tokens.append(token));transition.finished.connect(func():finished_count+=1)
	var token:int=transition.begin_cover(host,"old","slow");transition.update_loading(.25,"正在读取页面资源",true,token);await covered()
	check(transition.is_busy() and transition.is_covered(),"cover reaches a real full-screen readiness barrier")
	check(covered_tokens.count(token)==1 and finished_count==0,"covered emitted once without a premature finished")
	check(is_equal_approx(transition.mask.material.get_shader_parameter("coverage"),1),"the entire mask remains opaque while preparation is pending")
	check(transition.loading_status.determinate and is_equal_approx(transition.loading_status.progress,.25),"determinate progress is exactly the reported value")
	var motion_started:int=Time.get_ticks_msec();var sampled_early:bool=false;var sampled_late:bool=false
	for state in transition.actor_states:parade_motion.append({"min_x":INF,"max_x":-INF,"height":0.0,"grounded":0,"airborne":0,"last_ground":false,"last_x":0.0,"ground_locked":true})
	while Time.get_ticks_msec()-motion_started<1250:
		await process_frame
		for index in range(transition.actor_states.size()):
			var state:Dictionary=transition.actor_states[index];var sample:Dictionary=parade_motion[index];var at:Vector2=state.foot_position
			sample.min_x=minf(sample.min_x,at.x);sample.max_x=maxf(sample.max_x,at.x);sample.height=maxf(sample.height,float(state.hop_height_pixels))
			if state.grounded:
				sample.grounded+=1
				if sample.last_ground:sample.ground_locked=sample.ground_locked and absf(at.x-sample.last_x)<.05
			else:sample.airborne+=1
			sample.last_ground=state.grounded;sample.last_x=at.x
		if not sampled_early and Time.get_ticks_msec()-motion_started>=350:sampled_early=true;await shot("hold-hop-early")
		if not sampled_late and Time.get_ticks_msec()-motion_started>=850:sampled_late=true;await shot("hold-hop-late")
	check(transition.is_busy() and transition.is_covered() and finished_count==0,"slow preparation holds longer than the old animation without revealing")
	check(transition.actor_states.size()==3,"hold keeps three authentic registered SD actors")
	check(parade_motion.all(func(row):return row.max_x-row.min_x>root.get_visible_rect().size.x*.04),"each held SD genuinely advances horizontally across the sampled interval")
	check(parade_motion.all(func(row):return row.height>root.get_visible_rect().size.y*.04),"each held SD has a visible airborne arc")
	check(parade_motion.all(func(row):return row.grounded>0 and row.airborne>0),"each held SD alternates real airborne and landing poses")
	check(parade_motion.all(func(row):return row.ground_locked),"horizontal motion stops during consecutive grounded frames")
	await pointer();check(clicks==0,"pointer cannot activate the destination during preparation")
	await shot("slow-real-progress")
	transition.update_loading(.8,"正在整理页面",false,token);await frames()
	check(not transition.loading_status.determinate and not transition.loading_status.get_node("Progress").visible,"unknown work displays activity without an invented percentage")
	await shot("unknown-progress")
	check(transition.finish_loading(page,token),"only explicit destination readiness starts revealing")
	await settled();check(not transition.is_busy() and finished_count==1 and not transition.overlay.visible,"reveal completion releases the loading barrier")
	check(transition.overlay.mouse_filter==Control.MOUSE_FILTER_IGNORE and is_equal_approx(page.modulate.a,1),"finished restores both input and destination opacity")
	await pointer();check(clicks==1,"destination pointer works after finished")
	var started:int=Time.get_ticks_msec();token=transition.begin_cover(host,"slow","fast");transition.finish_loading(page,token);await settled()
	var fast_seconds:float=float(Time.get_ticks_msec()-started)/1000
	check(not transition.is_busy() and fast_seconds<transition.duration+.35,"already-ready pages add no mandatory hold")
	check(covered_tokens.count(token)==1 and finished_count==2,"early readiness still covers before revealing and finishes once")
	host.set_meta("reduced_motion",true);token=transition.begin_cover(host,"fast","reduced");transition.update_loading(.4,"正在准备页面",true,token);await covered()
	check(transition.is_busy() and transition.overlay.visible and transition.is_covered(),"reduced motion retains a visible preparation barrier")
	check(transition.actor_pool.all(func(sprite):return not sprite.visible),"reduced motion has no bouncing SD actors")
	await shot("reduced-visible-state");await create_timer(.2).timeout;check(transition.is_busy(),"reduced motion also waits for actual readiness")
	transition.finish_loading(page,token);await settled();check(finished_count==3,"reduced motion reveals only after readiness")
	host.set_meta("reduced_motion",false)
	var stale:int=transition.begin_cover(host,"reduced","cancelled");await covered();transition.cancel();await frames()
	check(not transition.is_busy() and transition.overlay.mouse_filter==Control.MOUSE_FILTER_IGNORE,"cancellation immediately releases input")
	check(not transition.finish_loading(page,stale) and finished_count==3,"cancelled preparation cannot emit a late finished")
	stale=transition.begin_cover(host,"cancelled","superseded");await covered()
	var current:int=transition.begin_cover(host,"superseded","current")
	check(current!=stale and not transition.finish_loading(page,stale),"a superseded asynchronous ready signal cannot reveal the new route")
	transition.update_loading(.9,"旧回调不得覆盖此文字",true,stale);check(transition.loading_status.get_node("Label").text!="旧回调不得覆盖此文字","stale progress cannot overwrite the new route status")
	await covered();check(transition.is_busy() and finished_count==3,"rapid replacement keeps the current route blocked")
	transition.finish_loading(page,current);await settled();check(finished_count==4,"only the current generation emits completion")
	host.page_motion=false;token=transition.begin_cover(host,"current","motion-off");await covered();check(transition.is_busy() and transition.overlay.visible,"animation-off setting preserves honest loading state")
	transition.finish_loading(page,token);await settled()
	check(not transition.is_busy() and finished_count==5,"animation-off preparation completes normally")
	host.page_motion=true
	for style in range(3):
		transition.preview_at(style,.5);await frames();check(transition.overlay.visible and not transition.loading_status.visible,"legacy editable preview remains independent of loading "+str(style))
	transition.cancel()
	if DisplayServer.get_name()!="headless":
		transition.capture_previous(host,"legacy");transition.play(host,page,"old","legacy");check(transition.is_busy(),"legacy play still starts the authored decorative animation");await settled()
		check(finished_count==6 and not transition.is_busy(),"legacy play retains its own normal finished lifecycle")
	check(FileAccess.get_sha256("user://cas_port_v1.json")==before and FileAccess.get_sha256("user://cas_port_v1.json.bak")==backup,"normal account and backup remain unchanged")
	check(FileAccess.get_sha256("res://bin/core-current.json")==manifest,"presentation tests do not replace the installed core")
	var receipt:Dictionary={"checks":checks,"failures":failures,"passed":failures.is_empty(),"parade_motion":parade_motion,"fast_ready_wall_seconds":fast_seconds,"covered_tokens":covered_tokens,"finished_count":finished_count,"renderer":DisplayServer.get_name(),"scope":"real production overlay, isolated presentation host; no account/core commands or real page loading timing claimed","normal_account_sha256":before,"normal_backup_sha256":backup,"core_manifest_sha256":manifest}
	FileAccess.open(Output+("headless-receipt.json" if DisplayServer.get_name()=="headless" else "gpu-receipt.json"),FileAccess.WRITE).store_string(JSON.stringify(receipt,"  "))
	print("LOADING_TRANSITION ",JSON.stringify({"checks":checks,"failures":failures}));transition.cancel();host.queue_free();page.queue_free();transition.queue_free();await process_frame;quit(0 if failures.is_empty() else 1)
