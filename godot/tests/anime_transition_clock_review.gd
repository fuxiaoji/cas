extends SceneTree
const ClockBackdrop=preload("res://scripts/local_time_backdrop.gd")
var app
var checks:int=0
var failures:Array[String]=[]
var images:Array[String]=[]
var output:String="res://../artifacts/godot/anime-transitions-clock/"
var fake_hour:int=6
func _initialize()->void:call_deferred("run")
func check(ok:bool,title:String)->void:
	checks+=1
	if not ok:failures.append(title);push_error(title)
func frame()->void:
	await process_frame;await process_frame
	if DisplayServer.get_name()!="headless":await RenderingServer.frame_post_draw
func shot(name:String)->Image:
	await frame()
	var img:Image=root.get_texture().get_image()
	var file:String=ProjectSettings.globalize_path(output+name+".png")
	check(img.save_png(file)==OK,"actual GPU capture "+name);images.append(file);return img
func hour_clock()->Dictionary:return {"hour":fake_hour,"minute":0,"second":0}
func signature(transition)->Array:
	var ids:Array=[]
	for state in transition.actor_states:ids.append(str(state.identity))
	return ids
func color_difference(a:Color,b:Color)->float:return absf(a.r-b.r)+absf(a.g-b.g)+absf(a.b-b.b)
func run()->void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	root.content_scale_size=Vector2i(1600,900);root.size=Vector2i(1280,720)
	app=load("res://scenes/main.tscn").instantiate();app.boot_to_title=false
	app.economy=load("res://scripts/economy.gd").new("user://tests/anime-clock-%d.json"%OS.get_process_id())
	root.add_child(app);app.set_process(false);await frame();app.page_motion=false
	var account:String=JSON.stringify(app.economy.state)
	for hour in [0.0,4.99,5.0,7.99,8.0,16.49,16.5,18.99,19.0,23.99]:
		var expected:String="night" if hour<5.0 or hour>=19.0 else "dawn" if hour<8.0 else "day" if hour<16.5 else "dusk"
		check(ClockBackdrop.period_for(hour)==expected,"local wall-time period boundary "+str(hour))
	if DisplayServer.get_name()=="headless":
		check(not app.page_transition.is_busy(),"headless routes cut immediately")
	else:
		for route in ["harbor","title"]:
			app.show_page(route);await frame()
			var service=app.page.find_child("LocalTimeBackdrop",true,false)
			check(service!=null,"production "+route+" binds wall-time backdrop")
			service.clock=hour_clock;service.preview_hour=-1
			var screen_id:int=app.page.get_instance_id()
			var colors:Array=[]
			for hour in [6,12,18,22]:
				fake_hour=hour;service.refresh()
				check(service.period==ClockBackdrop.period_for(hour),route+" follows injected real-time hour "+str(hour))
				check(app.page.get_instance_id()==screen_id,route+" changes lighting without replacing the page")
				var img:Image=await shot(route+"-%02d-1280x720"%hour)
				colors.append(img.get_pixel(int(img.get_width()*.52),int(img.get_height()*.10)))
			check(color_difference(colors[0],colors[1])>.05 and color_difference(colors[1],colors[2])>.05 and color_difference(colors[2],colors[3])>.05,route+" dawn/day/dusk/night visibly differ")
			fake_hour=19;service.elapsed=service.refresh_seconds;service._process(.01)
			check(service.period=="night",route+" automatically crosses the evening boundary while staying open")
			service.animated=false;var phase:float=service.seconds;service._process(.5)
			check(is_equal_approx(service.seconds,phase),route+" reduced motion freezes decorative ripples while preserving clock refresh")
			if route=="harbor":
				var portrait=app.page.find_child("SecretaryPortrait",true,false)
				check(portrait.material==null and portrait.modulate.is_equal_approx(Color.WHITE),"night lighting never darkens the secretary portrait")
			root.size=Vector2i(1600,900);await shot(route+"-night-1600x900");root.size=Vector2i(1280,720)
		app.show_page("harbor");await frame()
		app.page_motion=true;app.show_page("modes")
		var transition=app.page_transition
		check(transition.full_screen_wipe and transition.is_busy() and transition.mask.visible,"actual menu route starts full-screen anime transition by default")
		check(transition.actor_states.size()==3,"actual transition has three large authentic characters")
		transition.player.pause();transition.player.seek(.5*transition._clip_length(),true);transition._process(0)
		var point:Vector2=app.get_viewport().get_screen_transform()*app.page.get_global_transform_with_canvas()*Vector2(100,45)
		for pressed in [true,false]:
			var event:=InputEventMouseButton.new();event.button_index=MOUSE_BUTTON_LEFT;event.pressed=pressed;event.position=point;Input.parse_input_event(event);await process_frame
		check(app.screen=="modes" and transition.overlay.mouse_filter==Control.MOUSE_FILTER_STOP,"real pointer cannot click through the full-screen cover")
		transition.player.play();await create_timer(transition.duration+.16).timeout
		check(not transition.is_busy() and transition.overlay.mouse_filter==Control.MOUSE_FILTER_IGNORE,"actual cover/reveal finishes and returns pointer control")
		var old:Array=signature(transition);var chosen:Dictionary={}
		for sample in range(60):
			transition._pick_characters(app);var current:Array=signature(transition)
			check(current.size()==3,"three random characters on each page change")
			check(current.all(func(id):return id not in old),"consecutive transitions use different faces")
			for id in current:chosen[id]=true
			old=current
		check(chosen.size()>6,"transitions draw from the owned roster rather than a fixed trio")
		for dimension in [Vector2i(960,540),Vector2i(1280,720),Vector2i(1600,900),Vector2i(1600,720)]:
			root.size=dimension;await frame()
			for style in range(3):
				transition.preview_at(style,.5);await shot("%dx%d-style%d-covered"%[dimension.x,dimension.y,style])
				check(transition.mask.visible and not transition.old_frame.visible,"anime cover fully replaces the outgoing frame at midpoint")
				for actor in transition.actor_states:
					var rect:Rect2=actor.sprite.get_global_rect()
					check(rect.size.y>root.get_visible_rect().size.y*.22 and rect.size.y<root.get_visible_rect().size.y*.30,"larger SD scales with window height")
			transition.cancel()
		root.size=Vector2i(1280,720)
		for style in range(3):
			app.set_meta("transition_style",style);app.show_page("harbor");await frame();app.show_page("modes")
			transition.preview_at(style,.25);await shot("actual-menu-style%d-cover"%style)
			transition.preview_at(style,.74);await shot("actual-menu-style%d-reveal"%style)
			transition.cancel()
		app.set_meta("transition_style",-1)
		app.show_page("warehouse");app.show_page("harbor");await create_timer(transition.duration+.16).timeout
		check(app.screen=="harbor" and not transition.is_busy() and not transition.overlay.visible,"rapid routes settle and release the input mask")
		app.set_meta("reduced_motion",true);app.show_page("modes")
		check(not transition.is_busy(),"reduced motion skips full-screen cover")
		app.set_meta("reduced_motion",false);app.page_motion=false;app.show_page("harbor")
		check(not transition.is_busy(),"page motion off skips full-screen cover")
	check(JSON.stringify(app.economy.state)==account,"time backgrounds and transitions do not modify the account")
	app.core.close();app.queue_free();await process_frame
	var report:Dictionary={"checks":checks,"failures":failures,"passed":failures.is_empty(),"screenshots":images,"renderer":RenderingServer.get_video_adapter_name(),"time_source":"Time.get_datetime_dict_from_system(false); tests inject a separate clock; no account or simulation writes"}
	var receipt:String="receipt-headless.json" if DisplayServer.get_name()=="headless" else "receipt.json"
	FileAccess.open(output+receipt,FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	print("ANIME_TRANSITION_CLOCK ",JSON.stringify({"checks":checks,"failures":failures,"passed":failures.is_empty()}));quit(0 if failures.is_empty() else 1)
