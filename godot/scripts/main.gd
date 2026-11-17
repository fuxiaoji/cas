extends Control
const Economy = preload("res://scripts/economy.gd")
const Core = preload("res://scripts/core_bridge.gd")
const SeaMap = preload("res://scripts/sea_map.gd")
const LegacyBattle = preload("res://scripts/legacy_battle.gd")
const RecruitPresentation = preload("res://scripts/recruit_presentation.gd")
const PortPresentation = preload("res://scripts/port_presentation.gd")
const Progression = preload("res://scripts/progression.gd")
const ModesPresentation = preload("res://scripts/modes_presentation.gd")
const Design = preload("res://scripts/ui_design.gd")
const FleetManager = preload("res://scripts/fleet_manager.gd")
const Supply = preload("res://scripts/supply_presentation.gd")
const ShipDetail = preload("res://scripts/ship_detail_presentation.gd")
const Chapter = preload("res://scripts/chapter_presentation.gd")
const ChapterGuide = preload("res://scripts/chapter_guide.gd")
const PortServices = preload("res://scripts/port_services.gd")
const PageTransition = preload("res://scenes/ui/page_transition.tscn")
const ActivityHub = preload("res://scenes/ui/activity_hub.tscn")
const PlayerPresentation = preload("res://scripts/player_presentation.gd")
const NavigationHistory=preload("res://scripts/navigation_history.gd")
const TitleScreen=preload("res://scenes/ui/title_screen.tscn")
const ArenaService=preload("res://scripts/arena_service.gd")
const ExtractionPilot=preload("res://scripts/extraction_pilot_service.gd")
const HomeService=preload("res://scripts/home_service.gd")
const LoadingScreen=preload("res://scenes/ui/loading_screen.tscn")
const PagePreparation=preload("res://scripts/page_preparation.gd")
signal startup_stage(progress:float,detail:String)
signal startup_completed(result:Dictionary)
signal page_ready(route:String)
const NAV_KEYS=["activity_tab","campaign_deployment","campaign_difficulty","campaign_focus_id","campaign_region","campaign_side","challenge_focus","detail_ship_id","port_focus_id","recruit_pool","resource_tier","search","ship_detail_tab","supply_category","warehouse_tab","story_chapter_id","story_route_node","arena_mode","home_battle_mode"]
@export var boot_to_title:bool=true
# The lightweight project entrance opts in. The reusable main scene keeps its
# synchronous API for embedded scenes and existing tools.
@export var deferred_startup:bool=false
@export var immersive_fullscreen:bool=true
@export var staged_navigation:bool=false
const INK := Color("182f46")
const MUTED := Color("5e7182")
const GOLD := Color("f2cf84")
var economy = Economy.new()
var progression
var core = Core.new()
var audio: Node
var screen := "harbor"
var page: Control
var toast_label: Label
var toast_tween: Tween
var cards: Dictionary = {}
var sea: Control
var battle_status: Label
var battle_events: Label
var pause_button: Button
var selected: Dictionary = {}
var selection_kind := ""
var running := false
var speed := 1
var elapsed := 0.0
var tide_checkpoint_tick:float=0.0
var run: Dictionary = {}
var campaign_mode := false
var battle_selection: VBoxContainer
var ship_mode := true
var last_receipt: Dictionary = {}
var modal: Control
var first_button: Button
var previous_window_mode := DisplayServer.WINDOW_MODE_WINDOWED
var fullscreen_battle := false
var fullscreen_story := false
var previous_story_window_mode := DisplayServer.WINDOW_MODE_WINDOWED
var battle_controller
var home_replay_session
var home_exercise_session
var fleets
var arena
var home
var page_motion:=true
var battle_motion_strength:float=.75
var page_transition
var navigation=NavigationHistory.new()
var navigation_replaying:=false
var battle_return_route:="modes"
var startup_ready:bool=false
var startup_error:Dictionary={}
var startup_failure:Control
var _route_worker:bool=false
var _route_request:int=0
var _pending_route:Dictionary={}
var _page_resources:Array[Resource]=[]

func _ready() -> void:
	get_tree().auto_accept_quit=false
	if deferred_startup:_startup_async.call_deferred()
	else:_startup_now()

func _setup_presentation()->void:
	theme = Design.theme()
	for card in economy.catalog:
		cards[str(card.id)] = card
	var settings := ConfigFile.new()
	if settings.load("user://settings.cfg") == OK:
		ship_mode = bool(settings.get_value("display", "chibis", true))
		page_motion=bool(settings.get_value("display","page_motion",true))
		battle_motion_strength=clampf(float(settings.get_value("display","battle_motion_strength",.75)),0,1)
	set_meta("reduced_motion",not page_motion)
	if not is_instance_valid(page_transition):
		page_transition=PageTransition.instantiate()
		add_child(page_transition)
	if not is_instance_valid(audio) and ResourceLoader.exists("res://scripts/audio_director.gd"):
		audio = load("res://scripts/audio_director.gd").new()
		add_child(audio)

func _startup_now()->void:
	_setup_presentation()
	var result: Dictionary = economy.load_state()
	if not _initialize_services(result):return
	var first_route:Dictionary=load("res://scripts/first_voyage_onboarding.gd").prepare_route(economy,"title" if boot_to_title else "harbor")
	if not first_route.get("ok",false):_startup_failed(first_route);return
	show_page(str(first_route.route))
	if not boot_to_title:notify(result)
	startup_completed.emit(result)

func _startup_async()->void:
	startup_stage.emit(.76,"整理航海图册")
	await _render_boundary()
	_setup_presentation()
	startup_stage.emit(.83,"读取舰队档案")
	await _render_boundary()
	var result:Dictionary=economy.load_state()
	if not result.get("ok",false) or economy.state.is_empty():
		_startup_failed(result);return
	startup_stage.emit(.91,"准备母港与航线")
	await _render_boundary()
	if not _initialize_services(result):return
	startup_stage.emit(.97,"展开归航画卷")
	await _render_boundary()
	var first_route:Dictionary=load("res://scripts/first_voyage_onboarding.gd").prepare_route(economy,"title" if boot_to_title else "harbor")
	if not first_route.get("ok",false):_startup_failed(first_route);return
	show_page(str(first_route.route))
	await _render_boundary()
	startup_stage.emit(1.0,"航线已就绪")
	startup_completed.emit(result)

func _initialize_services(result:Dictionary)->bool:
	if not result.get("ok",false) or economy.state.is_empty():
		_startup_failed(result);return false
	fleets = FleetManager.new(economy)
	progression = Progression.new(economy)
	arena=ArenaService.new(economy)
	home=HomeService.new(economy)
	last_receipt = economy.latest_receipt()
	if not bool(get_meta("canon_route_hook_bound",false)):
		page_ready.connect(func(route:String):load("res://scripts/canon_story_actions.gd").on_page(self,route))
		set_meta("canon_route_hook_bound",true)
	startup_error.clear();startup_ready=true
	if is_instance_valid(startup_failure):startup_failure.queue_free();startup_failure=null
	return true

func _startup_failed(result:Dictionary)->void:
	startup_ready=false;running=false;screen="startup_error"
	startup_error={"ok":false,"message":str(result.get("message","舰队档案未能读取，原文件已保留。"))}
	if is_instance_valid(page_transition):page_transition.cancel()
	if not deferred_startup:
		if not is_instance_valid(startup_failure):
			startup_failure=LoadingScreen.instantiate();add_child(startup_failure)
			startup_failure.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			startup_failure.retry_requested.connect(_startup_now)
			startup_failure.quit_requested.connect(func():get_tree().quit())
		startup_failure.show_failure(str(startup_error.message))
	startup_completed.emit(startup_error)

func _render_boundary()->void:
	await get_tree().process_frame
	if DisplayServer.get_name()!="headless":await RenderingServer.frame_post_draw

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		if not run.is_empty():
			var saved:bool=checkpoint()
			if not saved and _fluid_battle():
				running=false
				return
		core.close()
		get_tree().quit()

func _exit_tree() -> void:
	if home_exercise_session!=null and home_exercise_session.active:home_exercise_session.restore(self)
	if home_replay_session!=null and home_replay_session.active:home_replay_session.restore(self)
	core.close()
	if fullscreen_battle:
		DisplayServer.window_set_mode(previous_window_mode)
	elif fullscreen_story:
		DisplayServer.window_set_mode(previous_story_window_mode)

func _unhandled_key_input(event: InputEvent) -> void:
	if not startup_ready:return
	if event.is_action_pressed("ui_cancel"):
		if is_instance_valid(modal):
			modal.queue_free()
			modal = null
		elif screen == "battle":
			if is_instance_valid(sea) and sea.has_method("cancel_pending") and sea.cancel_pending():
				return
			if battle_controller != null and not sea.planned.is_empty():
				battle_controller.cancel_draft()
				return
			if battle_controller != null and battle_controller.has_method("open_pause_menu"):
				battle_controller.open_pause_menu()
			else:
				toggle_pause()
		else:
			go_back()

func _fluid_battle()->bool:
	return str(core.view.get("tide",{}).get("version",""))=="cas-event-tide-v2" or str(core.view.get("littoral",{}).get("version","")) in ["cas-littoral-v1","cas-littoral-v2","cas-littoral-v3","cas-littoral-v4","cas-littoral-coastal-v1"]

func _process(delta: float) -> void:
	if screen != "battle" or not running:
		return
	elapsed += delta * speed
	var fluid_tide:bool=_fluid_battle()
	var interval:float=0.1 if fluid_tide else 1.0
	if elapsed < interval:
		return
	# Keep accumulated time even at high speed or after a slow rendering frame.
	# Littoral's authority still executes these as fixed 0.1-second microsteps;
	# the larger bounded batch lets 8x catch up below 20 rendered FPS.
	var microstep_cap:int=16 if core.view.has("littoral") else 4
	var ticks := mini(microstep_cap if fluid_tide else 40, int((elapsed+0.000001)/interval))
	elapsed -= ticks*interval
	if battle_controller != null and battle_controller.replay_mode:
		if core.view.has("littoral") and battle_controller.has_method("advance_littoral_replay"):
			battle_controller.advance_littoral_replay(snappedf(ticks*interval,0.1))
		elif fluid_tide and battle_controller.has_method("advance_tide_replay"):
			battle_controller.advance_tide_replay(snappedf(ticks*interval,0.1))
		elif not fluid_tide:
			battle_controller.advance_replay(ticks)
		else:
			# Legacy replay seeks whole seconds, never speed it up with v2 microticks.
			elapsed+=ticks*interval
			if elapsed>=1.0:
				var replay_seconds:int=int(elapsed);elapsed-=replay_seconds
				battle_controller.advance_replay(replay_seconds)
		return
	var step_command:Dictionary={"op":"step","seconds":ticks}
	if fluid_tide:step_command["seconds"]=snappedf(ticks*interval,0.1)
	var response: Dictionary = core.request(step_command)
	if not response.get("ok", false):
		running = false
		notify(response)
		return
	update_battle()
	if fluid_tide:
		if float(core.view.get("tick",0))-tide_checkpoint_tick>=5.0-0.000001 and not checkpoint():running=false
	elif int(core.view.get("tick", 0)) % 5 < ticks:
		checkpoint()
	if core.view.get("result") != null:
		finish_battle()

func place(node: Control, parent: Control, x: float, y: float, w: float, h: float) -> Control:
	parent.add_child(node)
	node.anchor_left = x / 1600.0
	node.anchor_top = y / 900.0
	node.anchor_right = (x + w) / 1600.0
	node.anchor_bottom = (y + h) / 900.0
	node.offset_left = 0
	node.offset_top = 0
	node.offset_right = 0
	node.offset_bottom = 0
	return node

func place_reposition(node: Control, x: float, y: float, w: float, h: float) -> void:
	node.anchor_left=x/1600.0
	node.anchor_top=y/900.0
	node.anchor_right=(x+w)/1600.0
	node.anchor_bottom=(y+h)/900.0

func panel(parent: Control, x: float, y: float, w: float, h: float, color := Color(1.0, 1.0, 1.0, 0.94)) -> Panel:
	var p := Panel.new()
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.set_corner_radius_all(3)
	p.add_theme_stylebox_override("panel", box)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	place(p, parent, x, y, w, h)
	return p

func label(parent: Control, text_value: String, x: float, y: float, w: float, h: float, font_size := 23, color := INK) -> Label:
	var l := Label.new()
	l.text = text_value
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_font_override("font", Design.font(600 if font_size >= 28 else 400))
	l.add_theme_color_override("font_color", color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER if h <= 80 else VERTICAL_ALIGNMENT_TOP
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	place(l, parent, x, y, w, h)
	return l

func button(parent: Control, title: String, x: float, y: float, w: float, h: float, action: Callable, primary := false) -> Button:
	var b := Button.new()
	b.text = title
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	Design.apply_button(b, primary)
	place(b, parent, x, y, w, h)
	b.pressed.connect(func() -> void:
		if audio != null:
			audio.ui("confirm" if primary else "tap")
		action.call())
	if first_button == null:
		first_button = b
	return b

func picture(parent: Control, path: String, x: float, y: float, w: float, h: float, cover := false) -> TextureRect:
	var image_node := TextureRect.new()
	image_node.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image_node.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED if cover else TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	image_node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if not path.is_empty() and ResourceLoader.exists(path):
		image_node.texture = load("res://scripts/character_art.gd").texture(path)
	place(image_node, parent, x, y, w, h)
	return image_node

func icon(parent: Control, key: String, x: float, y: float, w: float, h: float, tint := INK) -> TextureRect:
	var node := TextureRect.new()
	node.texture = Design.icon_texture(key)
	node.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	node.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	node.modulate = tint
	place(node, parent, x, y, w, h)
	return node

func portrait(parent: Control, path: String, x: float, y: float, w: float, h: float, portion := 0.56) -> TextureRect:
	var node := picture(parent, path, x, y, w, h, true)
	if node.texture != null:
		node.texture = Design.crop(node.texture, portion)
	return node

func notify(result: Dictionary) -> void:
	if is_instance_valid(toast_label):
		toast_label.text = str(result.get("message", result.get("error", "")))
		toast_label.add_theme_color_override("font_color", (Color.WHITE if screen in ["battle", "harbor","story_catalog","story_route","recruit","activity","home_recruit","canon_catalog","canon_story"] else INK) if result.get("ok", true) else Color("d96c60"))
		if toast_tween != null and toast_tween.is_valid(): toast_tween.kill()
		toast_label.modulate.a = 1.0
		toast_tween = create_tween().bind_node(toast_label)
		toast_tween.tween_interval(5.0 if result.get("ok",true) else 8.0)
		toast_tween.tween_property(toast_label,"modulate:a",0.0,.3)
	if not result.get("ok", true) and audio != null:
		audio.ui("error")

func show_page(next:String)->void:
	if next!="battle" and home_exercise_session!=null and home_exercise_session.active:home_exercise_session.restore(self)
	if not startup_ready:return
	if next!="battle" and home_replay_session!=null and home_replay_session.active:home_replay_session.restore(self)
	if next=="chapter" and screen=="chapter":
		if Chapter.refresh(self):return
	if staged_navigation and is_instance_valid(page) and next!=screen and is_instance_valid(page_transition) and page_transition.full_screen_wipe:
		_queue_page(next,navigation_replaying)
	else:
		_render_page(next)
		page_ready.emit(next)

func wait_for_page(route:String)->bool:
	while staged_navigation and _route_worker:
		await get_tree().process_frame
	return screen==route and is_instance_valid(page)

func _queue_page(next:String,replaying:bool=false,context:Dictionary={})->void:
	_route_request+=1
	_pending_route={"route":next,"request":_route_request,"replaying":replaying,"context":context.duplicate(true)}
	if not _route_worker:
		_route_worker=true
		_prepare_routes.call_deferred()

func _prepare_routes()->void:
	while not _pending_route.is_empty() and is_inside_tree():
		var request:Dictionary=_pending_route;_pending_route={}
		var next:String=str(request.route)
		if next==screen:
			_render_page(next);page_ready.emit(next);continue
		if screen=="battle":running=false
		if is_instance_valid(page):page.process_mode=Node.PROCESS_MODE_DISABLED
		page_transition.capture_previous(self,next)
		var generation:int=page_transition.begin_cover(self,screen,next)
		var work:Dictionary=PagePreparation.begin(next,self)
		var began:int=Time.get_ticks_msec()
		var preparation_error:String=""
		while is_inside_tree() and _pending_route.is_empty() and page_transition.is_current_generation(generation):
			var status:Dictionary=PagePreparation.poll(work)
			if not str(status.get("error","")).is_empty():
				preparation_error=str(status.error);break
			page_transition.update_loading(float(status.progress)*.85,PagePreparation.label_for(next),true,generation)
			if bool(status.ready) and page_transition.is_loading_covered(generation):break
			if Time.get_ticks_msec()-began>60000:
				preparation_error="准备页面超时，当前航次与档案均已保留。";break
			await get_tree().process_frame
		if not is_inside_tree():return
		if not _pending_route.is_empty():continue
		if not page_transition.is_current_generation(generation):
			if is_instance_valid(page):page.process_mode=Node.PROCESS_MODE_INHERIT
			break
		if not preparation_error.is_empty():
			page_transition.cancel()
			if is_instance_valid(page):page.process_mode=Node.PROCESS_MODE_INHERIT
			_show_page_failure(next,preparation_error);break
		page_transition.update_loading(.90,"布置画面",true,generation)
		await _render_boundary()
		if not _pending_route.is_empty():continue
		var replaying_before:bool=navigation_replaying
		navigation_replaying=bool(request.replaying)
		_render_page(next,true)
		navigation_replaying=replaying_before
		_page_resources=work.get("resources",[])
		if not request.context.is_empty():_restore_navigation.call_deferred(page,request.context)
		page_transition.update_loading(.97,"即将抵达",true,generation)
		await _render_boundary()
		if not _pending_route.is_empty():continue
		page_transition.update_loading(1.0,"画面已就绪",true,generation)
		page_transition.finish_loading(page,generation)
		while page_transition.is_current_generation(generation) and page_transition.is_busy() and _pending_route.is_empty():
			await get_tree().process_frame
		if _pending_route.is_empty():page_ready.emit(next)
	_route_worker=false

func _show_page_failure(next:String,message:String)->void:
	var failure:Control=LoadingScreen.instantiate();add_child(failure)
	failure.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	failure.show_failure(message)
	failure.retry_requested.connect(func():failure.queue_free();show_page(next))
	failure.quit_requested.connect(func():_notification(NOTIFICATION_WM_CLOSE_REQUEST))

func _render_page(next: String,managed:bool=false) -> void:
	load("res://scripts/ship_appearance_service.gd").refresh(self)
	if next=="chapter" and screen=="chapter":
		if Chapter.refresh(self):return
	# A modal belongs to its page. Never leave its fullscreen input blocker over
	# the next route; both its own navigation buttons and direct routing use this.
	if is_instance_valid(modal):close_modal()
	if not navigation_replaying:navigation.visit(screen,next,_navigation_context())
	if not managed and is_instance_valid(page_transition):page_transition.capture_previous(self,next)
	var previous:=screen
	if screen == "battle" and next != "battle" and fullscreen_battle:
		DisplayServer.window_set_mode(previous_window_mode)
		fullscreen_battle = false
	if screen in ["story","chapter","tide_story","home_story","canon_story"] and next not in ["story","chapter","tide_story","home_story","canon_story"] and fullscreen_story:
		DisplayServer.window_set_mode(previous_story_window_mode)
		fullscreen_story = false
	screen = next
	if audio!=null and audio.has_method("set_dialogue_active"):audio.set_dialogue_active(false)
	first_button = null
	toast_label = null
	if is_instance_valid(page):
		remove_child(page)
		page.queue_free()
	page = Control.new()
	add_child(page)
	page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if not managed and is_instance_valid(page_transition):page_transition.play(self,page,previous,next)
	if next=="title":
		var title=TitleScreen.instantiate();page.add_child(title);title.bind(self)
		return
	if next == "battle":
		# Switch window mode beneath the opaque cover, after resource preparation.
		if immersive_fullscreen and not fullscreen_battle:
			previous_window_mode=DisplayServer.window_get_mode()
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
			fullscreen_battle=true
		battle()
		return
	if next=="canon_catalog":
		load("res://scripts/canon_story_catalog.gd").render(self)
		return
	if next in ["story","chapter","tide_story","home_story","canon_story"]:
		if audio != null:
			audio.set_paused(false)
			if next=="story":audio.set_scene("story")
		if immersive_fullscreen and not fullscreen_story:
			previous_story_window_mode = DisplayServer.window_get_mode()
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
			fullscreen_story = true
		if next=="canon_story":
			var story=load("res://scenes/ui/canon_story.tscn").instantiate();page.add_child(story);story.bind(self)
		elif next=="home_story":
			var story=load("res://scenes/ui/home_story.tscn").instantiate();page.add_child(story);story.bind(self)
		elif next=="tide_story":
			var story=load("res://scenes/ui/tide_story.tscn").instantiate();page.add_child(story);story.bind(self)
		elif next=="chapter":Chapter.render(self)
		else:ModesPresentation.render(self, next)
		return
	if next == "recruit":
		RecruitPresentation.render(self)
		ChapterGuide.render(self)
		if audio != null:
			audio.set_paused(false)
			audio.set_scene("recruit")
		return
	var backdrop_path := "res://assets/backgrounds/harbor-day-v2.png"
	var dark_story_menu:bool=next in ["story_catalog","story_route"]
	var coastal_home:bool=next=="home" and preload("res://scripts/coastal_map_settings.gd").enabled()
	if not ResourceLoader.exists(backdrop_path): backdrop_path = "res://assets/backgrounds/recruit-sky.png"
	if next!="harbor" and not coastal_home:picture(page, backdrop_path, 0, 0, 1600, 900, true)
	if next != "harbor":
		var veil := ColorRect.new()
		veil.color = Color("101b29") if dark_story_menu else Color(0.93, 0.96, 0.98, 0.97)
		veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if not coastal_home:place(veil, page, 0, 0, 1600, 900)
		else:veil.free()
		var back := button(page, "‹  返回", 34, 26, 118, 48, func(): go_back())
		back.name="NavigateBack"
		Design.apply_button(back, false, true)
		if dark_story_menu:Design.apply_overlay_button(back)
		var home_button:=button(page,"母港",164,26,70,48,go_home)
		home_button.name="NavigateHome";home_button.tooltip_text="直接返回母港"
		Design.apply_button(home_button,false,true)
		if dark_story_menu:Design.apply_overlay_button(home_button)
		if coastal_home:
			back.z_index=12;home_button.z_index=12;Design.apply_overlay_button(back);Design.apply_overlay_button(home_button)
		var title_text: String = {"formation":"舰队编成", "roster":"舰娘", "warehouse":"仓库", "shop":"军需处", "campaign":"战役航图", "result":"归航", "settings":"设置", "modes":"出航", "academy":"舰桥学堂", "challenge":"挑战", "activity":"活动", "mail":"邮件", "resources":"资源海域", "ladder":"天梯挑战", "ship_detail":"舰娘档案", "archives":"航次档案", "player":"指挥官档案","story_catalog":"剧情章节","story_route":"返航灯","expedition":"打捞远征","tide_event":"潮汐回响","arena":"竞技航线","home":"返航灯岛","home_recruit":"战术协议"}.get(next,"母港")
		var header := label(page, title_text, 252, 24, 564, 54, 30)
		header.add_theme_font_override("font", Design.font(600))
		if dark_story_menu:header.add_theme_color_override("font_color",Color("eef0e9"))
		if coastal_home:header.z_index=12;header.add_theme_color_override("font_color",Color("fff4d5"));header.add_theme_color_override("font_shadow_color",Color(0,.09,.12,.8));header.add_theme_constant_override("shadow_offset_x",1);header.add_theme_constant_override("shadow_offset_y",2)
	else:
		panel(page, 35, 25, 226, 54, Color(1, 1, 1, .86))
		icon(page, "compass", 49, 34, 34, 34)
		label(page, "CAS / 归航", 95, 29, 160, 45, 22).add_theme_font_override("font", Design.font(600))
	var wallet_keys: Array = []
	if next in ["harbor", "shop", "warehouse", "roster"]: wallet_keys = ["origins", "credits", "stamina"]
	if next == "formation": wallet_keys = ["ammo_stock"]
	if next in ["resources","ladder"]: wallet_keys=["origins","credits","stamina"]
	if next == "ship_detail": wallet_keys=["credits","materials"]
	var wallet: Dictionary = economy.wallet()
	for i in range(wallet_keys.size()):
		var key: String = str(wallet_keys[i])
		var x := 832.0 + i * 154.0
		if next == "harbor": panel(page, x, 25, 145, 54, Color(1,1,1,.86))
		var currency_icon: String = {"origins":"recruit","credits":"coin","stamina":"heart","ammo_stock":"ammo","materials":"cargo"}.get(key,"coin")
		var currency_name: String = {"origins":"元词","credits":"银币","stamina":"体力","ammo_stock":"弹药","materials":"养成材料"}.get(key,key)
		icon(page, currency_icon, x + 8, 39, 24, 24, Color("267c9e")).tooltip_text=currency_name
		var amount:=_compact_amount(int(wallet.get(key,0)))
		if key=="stamina": amount+="/%d"%int(wallet.get("stamina_max",120))
		label(page, amount, x + 41, 27, 102, 49, 21).tooltip_text=currency_name
	if next == "harbor":
		var profile:Dictionary=economy.player_profile()
		button(page,"指挥官 Lv.%d"%int(profile.level),280,25,205,54,func():show_page("player"))
		var island_entry:=button(page,"返航灯岛",500,25,155,54,func():show_page("home"))
		island_entry.name="HomeIslandEntry";island_entry.tooltip_text="家园建设与海陆空协同行动"
		button(page,"活动",1304,25,79,54,func():show_page("activity"))
		var mail_button:=button(page,"",1394,25,79,54,func():show_page("mail"))
		mail_button.tooltip_text="邮件"
		icon(page,"mail",1417,39,29,29)
	var settings_button := button(page, "", 1493, 25, 65, 54, func(): show_page("settings"))
	settings_button.tooltip_text = "设置"
	if dark_story_menu:Design.apply_overlay_button(settings_button)
	if coastal_home:settings_button.z_index=12;Design.apply_overlay_button(settings_button)
	var settings_icon:TextureRect=icon(page, "gear", 1511, 37, 29, 29,Color("eef0e9") if dark_story_menu or coastal_home else INK)
	if coastal_home:settings_icon.z_index=13
	toast_label = label(page, "", 48, 865 if next == "harbor" else 843, 1504, 30, 18, MUTED)
	match next:
		"harbor": harbor()
		"roster": roster()
		"formation": formation()
		"shop": shop()
		"ship_detail":
			var entry: Dictionary={}
			for row in economy.roster():
				if str(row.id)==str(get_meta("detail_ship_id","")): entry=row
			ShipDetail.render(self,entry)
		"warehouse": warehouse()
		"campaign": campaign()
		"result": result_screen()
		"settings": settings_screen()
		"activity":
			var hub=ActivityHub.instantiate()
			page.add_child(hub)
			hub.bind(self)
		"tide_event":
			var event=load("res://scenes/ui/tide_event_hub.tscn").instantiate();page.add_child(event);event.bind(self)
		"home":
			var island=load("res://scenes/ui/home_island.tscn").instantiate();page.add_child(island);island.bind(self)
		"home_recruit":
			var recruit=load("res://scenes/ui/tactical_recruit.tscn").instantiate();recruit.mouse_filter=Control.MOUSE_FILTER_IGNORE;page.add_child(recruit);recruit.bind(self)
		"player":PlayerPresentation.render(self)
		"story_catalog":load("res://scripts/story_catalog.gd").render(self)
		"story_route":load("res://scripts/story_route.gd").render(self)
		"expedition":load("res://scripts/difficulty_presentation.gd").render(self)
		"arena":load("res://scripts/arena_presentation.gd").render(self)
		"modes", "academy", "challenge", "mail", "resources", "ladder", "archives": ModesPresentation.render(self,next)
	ChapterGuide.render(self)
	if audio != null:
		audio.set_paused(false)
		audio.set_scene({"formation":"formation","shop":"shop","warehouse":"shop","home":"home","home_recruit":"home","tide_event":"tide"}.get(next,"harbor"))
	if not economy.state.get("active_run", {}).is_empty(): notify({"message":"航次已保存，可从母港继续。"})

func harbor() -> void:
	PortPresentation.render_harbor(self)

func _compact_amount(value:int)->String:
	if value>=100000000:return "%.2f亿"%(value/100000000.0)
	if value>=10000:return "%.1f万"%(value/10000.0)
	return str(value)

func _navigation_context() -> Dictionary:
	var values:Dictionary={}
	for key in NAV_KEYS:
		if has_meta(key):
			var value:Variant=get_meta(key)
			values[key]=value.duplicate(true) if value is Array or value is Dictionary else value
	var scrolls:Dictionary={}
	var focus_path:=""
	var focus_hint:Dictionary={}
	if is_instance_valid(page):
		var scroll_index:=0
		for node in page.find_children("*","ScrollContainer",true,false):
			scrolls[str(scroll_index)]={"path":str(page.get_path_to(node)),"position":Vector2i(node.scroll_horizontal,node.scroll_vertical)}
			scroll_index+=1
		var focus:Control=get_viewport().gui_get_focus_owner()
		if focus!=null and page.is_ancestor_of(focus):
			focus_path=str(page.get_path_to(focus))
			if focus is BaseButton:focus_hint={"text":focus.text if focus is Button else "","tooltip":focus.tooltip_text}
	return {"meta":values,"scrolls":scrolls,"focus":focus_path,"focus_hint":focus_hint}

func go_back(fallback:String="") -> void:
	if is_instance_valid(modal):close_modal();return
	if screen=="home":
		var island:Node=page.get_node_or_null("HomeIsland")
		if island!=null and island.has_method("consume_back") and island.consume_back():return
	if screen=="battle":
		if battle_controller!=null:battle_controller.open_pause_menu()
		return
	_navigate_frame(navigation.previous(screen,fallback))

func return_to(route:String) -> void:
	_navigate_frame(navigation.return_to(route))

func go_home() -> void:
	if is_instance_valid(modal):close_modal()
	if screen=="battle":
		running=false
		if battle_controller!=null and battle_controller.replay_mode:
			battle_controller.end_replay()
		elif not run.is_empty() and not checkpoint():return
	return_to("harbor")

func _navigate_frame(frame:Dictionary) -> void:
	if str(frame.get("route",""))!="battle" and home_exercise_session!=null and home_exercise_session.active:home_exercise_session.restore(self)
	var context:Dictionary=frame.get("context",{})
	if context.has("meta"):
		for key in NAV_KEYS:
			if has_meta(key):remove_meta(key)
		for key in context.meta:set_meta(key,context.meta[key])
	navigation_replaying=true
	if staged_navigation and str(frame.get("route","harbor"))!=screen and is_instance_valid(page_transition) and page_transition.full_screen_wipe:
		_queue_page(str(frame.get("route","harbor")),true,context)
		navigation_replaying=false
		return
	show_page(str(frame.get("route","harbor")))
	navigation_replaying=false
	_restore_navigation.call_deferred(page,context)

func _restore_navigation(target:Control,context:Dictionary) -> void:
	await get_tree().process_frame
	if not is_instance_valid(target) or page!=target:return
	var current_scrolls:Array=target.find_children("*","ScrollContainer",true,false)
	for index in context.get("scrolls",{}):
		var saved:Dictionary=context.scrolls[index]
		var scroll:ScrollContainer=target.get_node_or_null(str(saved.path))
		if scroll==null and int(index)<current_scrolls.size():scroll=current_scrolls[int(index)]
		if scroll!=null:
			scroll.scroll_horizontal=int(saved.position.x);scroll.scroll_vertical=int(saved.position.y)
	var focus:Control=target.get_node_or_null(str(context.get("focus",""))) if not str(context.get("focus","")).is_empty() else null
	var hint:Dictionary=context.get("focus_hint",{})
	if focus==null and (not str(hint.get("text","")).is_empty() or not str(hint.get("tooltip","")).is_empty()):
		for node in target.find_children("*","BaseButton",true,false):
			if node is Button and node.text==str(hint.get("text","")) and node.tooltip_text==str(hint.get("tooltip","")):
				focus=node;break
	if focus!=null and focus.is_visible_in_tree() and focus.focus_mode!=Control.FOCUS_NONE:focus.grab_focus()

func roster() -> void:
	PortPresentation.render_roster(self)

func bulk_service(service:String="both") -> void:
	PortServices.open(self,service)

func ship_detail(ship: Dictionary) -> void:
	set_meta("detail_ship_id",str(ship.get("id","")))
	show_page("ship_detail")

func formation() -> void:
	var composer=load("res://scenes/ui/sortie_formation.tscn").instantiate()
	place(composer,page,40,116,1520,720)
	composer.initialize(self)

func shop() -> void:
	Supply.render(self)

func warehouse() -> void:
	button(page,"编队货舱",915,128,290,50,func():load("res://scripts/cargo_presentation.gd").open_stash(self,"fleet"))
	button(page,"基地仓库",1220,128,315,50,func():load("res://scripts/cargo_presentation.gd").open_stash(self,"base"))
	button(page,"物资",60,128,175,50,func():set_meta("warehouse_tab","materials");show_page("warehouse"),str(get_meta("warehouse_tab","materials"))=="materials")
	button(page,"舰装与水手",252,128,230,50,func():set_meta("warehouse_tab","gear");show_page("warehouse"),str(get_meta("warehouse_tab","materials"))=="gear")
	if str(get_meta("warehouse_tab","materials"))=="gear":
		gear_warehouse()
		return
	label(page,"返港物资可兑换银币；装备与水手保存在独立库页。",60,193,1400,42,22,MUTED)
	var names := {"scrap": "旧世零件", "alloy": "合金箱", "equipment": "打捞装备", "command": "指挥组"}
	var i := 0
	for key in names:
		var id: String = key
		var count := int(economy.state.get("inventory", {}).get(id, 0))
		var x := 60 + i * 375
		panel(page, x, 265, 345, 405, Color(0.97, 0.98, 0.94, 0.98))
		var rule := ColorRect.new()
		rule.color = Color("9dbdbb") if i < 2 else GOLD
		rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
		place(rule, page, x, 265, 345, 3)
		picture(page, "res://assets/items/" + id + ".png", x + 26, 275, 292, 185)
		label(page, str(names[id]), x + 25, 451, 295, 49, 29)
		label(page, "× %d" % count, x + 25, 503, 290, 49, 30, INK)
		if id in ["scrap", "alloy"]:
			label(page, "每件兑换 %d 银币" % int(economy.config.get("salvage_prices", {}).get(id, 0)), x + 25, 552, 295, 35, 19, MUTED)
			var sell_button := button(page, "兑换全部", x + 25, 596, 292, 55, func(): confirm_action("兑换 %d 件%s？" % [count, names[id]], func():
				var response: Dictionary = economy.sell(id, count)
				show_page("warehouse")
				notify(response)), true)
			sell_button.disabled = count <= 0 or not economy.state.get("active_run", {}).is_empty()
		else:
			label(page, "在舰娘详情中装配", x + 25, 581, 295, 60, 22, MUTED)
		i += 1
	button(page, "舰娘整备", 61, 716, 340, 59, func(): show_page("roster"))

func gear_warehouse() -> void:
	label(page,"每件装备与水手组都有独立词条，装配后归属对应舰娘。",60,195,1450,42,22,MUTED)
	var scroll:=ScrollContainer.new()
	scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	place(scroll,page,60,260,1480,480)
	var grid:=GridContainer.new()
	grid.columns=4
	grid.add_theme_constant_override("h_separation",18)
	grid.add_theme_constant_override("v_separation",18)
	scroll.add_child(grid)
	var slots:Dictionary={"equipment":"舰装","helmsman":"舵手组","gunnery":"火炮组","damage_control":"损管组","command":"指挥组"}
	var stats:Dictionary={"hp":"船体","speed":"航速","firepower":"火力","base_hit":"基础命中","repair":"损管","command":"同步指挥"}
	for instance in economy.state.get("item_instances",{}).values():
		var item:Dictionary=instance
		var slot:=str(item.get("slot","equipment"))
		var tile:=Panel.new()
		tile.add_theme_stylebox_override("panel",Design.panel_style())
		tile.custom_minimum_size=Vector2(350,315)
		grid.add_child(tile)
		var asset:="res://assets/items/equipment.png" if slot=="equipment" else "res://assets/items/crew-%s-v1.png"%slot
		if not ResourceLoader.exists(asset): asset="res://assets/items/command.png"
		picture(tile,asset,440,15,720,400)
		label(tile,str(item.get("name",slots.get(slot,slot))),90,440,1400,95,24)
		var main_affix:Dictionary=item.get("main",{})
		var sub:Dictionary=item.get("sub",{})
		var description:="舰装提升 +%.2f%%"%(float(item.get("bonus_bp",0))/100.0) if slot=="equipment" else "%s +%.2f%%\n%s +%.2f%%"%[stats.get(str(main_affix.get("stat","")),"主词条"),float(main_affix.get("bp",0))/100.0,stats.get(str(sub.get("stat","")),"副词条"),float(sub.get("bp",0))/100.0]
		label(tile,description,90,553,1400,160,21,MUTED)
		var location:=str(item.get("location","warehouse"))
		label(tile,"未装配" if location=="warehouse" else "已装配 · %s"%str(cards.get(location,{}).get("name",location)),90,750,1400,90,19,Design.ACCENT)
	if grid.get_child_count()==0: label(page,"尚无舰装与水手组，出航打捞或挑战资源海域后可获得。",70,350,1400,90,26,MUTED)
	button(page,"选择舰娘装配",1130,775,360,60,func():show_page("roster"),true)

func recruit_screen() -> void:
	RecruitPresentation.render(self)

func draw_recruit(count: int) -> void:
	var response: Dictionary = economy.recruit(count)
	show_page("recruit")
	if not await wait_for_page("recruit"):return
	notify(response)
	if response.get("ok", false):
		RecruitPresentation.reveal(self, response)

func start_local_mode(request: Dictionary, context: Dictionary) -> void:
	request=request.duplicate(true)
	if str(request.get("op","")) not in ["new_campaign","new_island_battle"] and str(request.get("variant",""))!="empress-augusta-bay":request["intel_profile"]="open-intel-v1"
	if not economy.state.get("active_run", {}).is_empty():
		notify({"ok": false, "message": "请先继续或结束当前航次。"})
		return
	var generated: Dictionary = core.request(request)
	if not generated.get("ok", false):
		notify(generated)
		return
	var saved: Dictionary = core.request({"op": "save", "serialized": true})
	if not saved.get("ok", false) or str(saved.get("serialized", "")).is_empty():
		notify({"ok": false, "message": "战斗快照无法创建，尚未开始航次。"})
		return
	var mode_context: Dictionary = context.duplicate(true)
	mode_context["request"] = request.duplicate(true)
	var begun: Dictionary = progression.begin_mode(mode_context, str(saved.serialized))
	if not begun.get("ok", false):
		notify(begun)
		return
	run = begun
	campaign_mode = true
	await enter_battle()

func campaign() -> void:
	PortPresentation.render_campaign(self)

func launch_mission(kind: String, id: String) -> void:
	await launch(false,{"kind":kind,"id":id})

func launch_arena(mode:String="ranked")->void:
	var plan:Dictionary=arena.preview(mode)
	if not plan.get("ok",false):notify(plan);return
	var request:Dictionary={"op":"new_arena","arena_version":ArenaService.VERSION,"seed":int(get_meta("next_arena_seed",Time.get_unix_time_from_system()))%4294967295,"mode":mode,"groups":plan.groups}
	var generated:Dictionary=core.request(request)
	if not generated.get("ok",false):notify(generated);return
	var saved:Dictionary=core.request({"op":"save","serialized":true})
	if not saved.get("ok",false):notify(saved);return
	var begun:Dictionary=arena.begin(request,core.view,str(saved.serialized))
	if not begun.get("ok",false):notify(begun);return
	run=begun;campaign_mode=true;set_meta("arena_mode",mode);battle_return_route="arena"
	await enter_battle()

func launch_tide(character_id:String,difficulty:String="normal",reserves:Variant=null,version:String="cas-event-tide-v2")->void:
	if not economy.state.get("active_run",{}).is_empty():notify({"ok":false,"message":"请先继续或结束当前航次"});return
	if not economy.state.owned.has(character_id):notify({"ok":false,"message":"请选择已获得的舰娘"});return
	var request:Dictionary={"op":"new_tide","seed":int(get_meta("next_tide_seed",Time.get_unix_time_from_system()))%4294967295,"character_id":character_id,"difficulty":difficulty,"intel_profile":"open-intel-v1"}
	if version=="cas-event-tide-v2":
		var roster:Array=[]
		if reserves==null:
			for row in economy.roster():
				if str(row.id)!=character_id and roster.size()<64:roster.append(str(row.id))
		elif reserves is Array:
			roster=reserves.duplicate()
		else:notify({"ok":false,"message":"援军阵容无效"});return
		var unique:Dictionary={};unique[character_id]=true
		if roster.size()>64:notify({"ok":false,"message":"援军候选过多"});return
		for reserve in roster:
			if not reserve is String or unique.has(reserve) or not economy.state.owned.has(reserve):notify({"ok":false,"message":"援军必须是已获得且不重复的舰娘"});return
			unique[reserve]=true
		request["version"]=version;request["roster"]=roster
	elif version!="cas-event-tide-v1":notify({"ok":false,"message":"活动规则版本不受支持"});return
	var generated:Dictionary=core.request(request)
	if not generated.get("ok",false):notify(generated);return
	var saved:Dictionary=core.request({"op":"save","serialized":true})
	if not saved.get("ok",false):notify(saved);return
	var begun:Dictionary=load("res://scripts/tide_event_service.gd").new(economy).begin(request,str(saved.serialized))
	if not begun.get("ok",false):notify(begun);return
	run=begun;campaign_mode=true;battle_return_route="tide_event";await enter_battle()

func launch(basic: bool, mission: Dictionary={}) -> void:
	if not economy.state.get("active_run",{}).is_empty():
		notify({"ok":false,"message":"请先继续或结束当前航次。"})
		return
	var seed_value:=int(get_meta("next_sortie_seed",int(Time.get_unix_time_from_system())%4294967295))
	var prepared:Dictionary=economy.preview_sortie(seed_value,basic,mission)
	if not prepared.get("ok",false): notify(prepared);return
	# The native generator validates the exact frozen loadout before any currency is spent.
	var generated:Dictionary=core.request({"op":"new_salvage","seed":seed_value,"start":economy.native_start(prepared)})
	if not generated.get("ok",false): notify(generated);return
	var previous:Dictionary=economy.state.duplicate(true)
	var response:Dictionary=economy.begin_sortie(seed_value,basic,mission)
	if not response.get("ok",false): notify(response);return
	var committed:Dictionary=core.request({"op":"new_salvage","seed":seed_value,"start":economy.native_start(response)})
	if not committed.get("ok",false):
		economy.state=previous;economy._sync_formation();economy.save_state();notify(committed);return
	run=response
	campaign_mode=false
	if not core.view.get("salvage",{}).get("expedition",{}).is_empty():
		var pilot:Dictionary=core.request(ExtractionPilot.command(true))
		if not pilot.get("ok",false):notify(pilot)
	checkpoint()
	await enter_battle()
	if screen!="battle":return
	if bool(core.view.get("salvage",{}).get("expedition",{}).get("autopilot",{}).get("enabled",false)):
		running=true
		if audio!=null:audio.set_paused(false)
		update_battle()

func launch_littoral(request:Dictionary)->void:
	if not economy.state.get("active_run",{}).is_empty():
		notify({"ok":false,"message":"请先继续或结束已保存的行动。"});return
	var opened:Dictionary=core.request(request)
	if not opened.get("ok",false):notify(opened);return
	var saved:Dictionary=core.request({"op":"save","serialized":true})
	if not saved.get("ok",false):notify(saved);return
	var begun:Dictionary=home.begin(request,str(saved.serialized))
	if not begun.get("ok",false):notify(begun);return
	run=begun;campaign_mode=true;battle_return_route="home";await enter_battle()

func launch_home_exercise(request:Dictionary)->void:
	if home_exercise_session!=null and home_exercise_session.active:return
	if home_replay_session!=null and home_replay_session.active:notify({"ok":false,"message":"请先退出录像，再开始演习。"});return
	home_exercise_session=load("res://scripts/home_exercise_session.gd").new()
	var response:Dictionary=home_exercise_session.open(self,request)
	if not response.get("ok",false):notify(response);return
	close_modal();await enter_battle()

func close_home_exercise()->void:
	if home_exercise_session==null or not home_exercise_session.active:return
	close_modal();home_exercise_session.restore(self);show_page("home")

func resume_run() -> void:
	var response: Dictionary = economy.resume_sortie()
	if not response.get("ok", false):
		notify(response)
		return
	if response.get("snapshot", {}).is_empty():
		notify({"ok": false, "message": "该航次缺少完整快照。原存档已保留，请明确结束后重试。"})
		return
	var loaded: Dictionary = core.request({"op": "load", "serialized": response.snapshot} if response.snapshot is String else {"op": "load", "save": response.snapshot})
	if not loaded.get("ok", false):
		notify(loaded)
		return
	run = response
	campaign_mode = str(run.get("mode", "salvage")) not in ["salvage", "basic"]
	var pilot_resume:Dictionary=ExtractionPilot.resume(core,response.snapshot)
	await enter_battle()
	if screen!="battle":return
	if not pilot_resume.get("ok",false):notify(pilot_resume)
	elif pilot_resume.get("changed",false):
		checkpoint()
		notify(pilot_resume)
	if core.view.get("result") != null:
		finish_battle()
	elif bool(core.view.get("salvage",{}).get("expedition",{}).get("autopilot",{}).get("enabled",false)):
		# Continue the saved authorization, without enabling a pilot the player disabled.
		running=true
		if audio!=null:audio.set_paused(false)
		update_battle()

func start_campaign() -> void:
	start_local_mode({"op": "new_campaign", "id": "CAMP-ALLIES-02", "difficulty": "standard", "seed": 6106, "profile": "coord"}, {"mode": "campaign", "id": "CAMP-ALLIES-02", "difficulty": "standard", "title": "埃斯佩兰斯角"})

func enter_battle() -> void:
	if screen!="battle":
		battle_return_route="home" if str(run.get("mode",""))=="littoral" else "arena" if str(run.get("mode",""))=="arena" else "tide_event" if str(run.get("mode",""))=="tide_event" else "story_route" if str(run.get("mode",""))=="story_chapter" else screen if screen not in ["title","result"] else "modes"
	running = false
	var adventure:Dictionary=core.view.get("salvage",{}).get("adventure",{})
	speed = 1 if not adventure.is_empty() or core.view.has("tide") else 4 if str(run.get("content","")) in ["salvage-v2","salvage-v3","salvage-v4"] else 1
	elapsed = 0.0
	tide_checkpoint_tick=float(core.view.get("tick",0))
	selected = {}
	selection_kind = ""
	show_page("battle")
	# Normal routes now build under a real loading cover. Do not touch the old
	# controller or start simulation until the new battle has actually rendered.
	if not await wait_for_page("battle") or not is_instance_valid(sea) or battle_controller==null:return
	if audio != null:
		audio.set_session(str(run.get("run_id", "campaign-%s" % Time.get_ticks_msec())), str(core.view.get("side", "allies")))
		audio.set_paused(true)
		audio.set_scene("landing" if core.view.has("littoral") else "tide" if core.view.has("tide") else "battle" if campaign_mode else "salvage")
	update_battle()
	sea.call_deferred("focus_fleet")

func battle() -> void:
	if core.view.has("littoral"):
		battle_controller=load("res://scripts/littoral_battle.gd").new(self)
		var viewing:bool=home_replay_session!=null and home_replay_session.active
		if viewing:home_replay_session.configure(battle_controller)
		battle_controller.build()
		if viewing:
			battle_controller.ui.get_node("Tray").hide()
			var controls=load("res://scenes/ui/home_replay_controls.tscn").instantiate();controls.z_index=100;page.add_child(controls);controls.setup(self,battle_controller)
		elif (home_exercise_session==null or not home_exercise_session.active) and battle_controller.has_method("restore_ui_state"):battle_controller.restore_ui_state(economy.state.get("active_run",{}).get("ui_state",{}))
		return
	if core.view.has("tide"):
		battle_controller=load("res://scripts/tide_battle.gd").new(self);battle_controller.build();return
	battle_controller = LegacyBattle.new(self)
	battle_controller.build()
	if ResourceLoader.exists("res://scripts/chapter_battle_guide.gd"):
		load("res://scripts/chapter_battle_guide.gd").attach(self)
	if core.view.get("salvage",{}).has("cargo_grid"):
		load("res://scripts/cargo_presentation.gd").attach_search(self)
	load("res://scripts/expedition_operations.gd").attach(self)

func cargo_manifest() -> void:
	if core.view.get("salvage",{}).has("cargo_grid"):
		load("res://scripts/cargo_presentation.gd").open(self)
		return
	running = false
	if audio != null:
		audio.set_paused(true)
	var layer := open_modal("航次货舱")
	var cargo: Array = core.view.get("salvage", {}).get("cargo", [])
	label(layer, "未撤出的物资无法出售或装配。弃置后不再恢复。", 380, 223, 835, 65, 22, MUTED)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 15)
	place(grid, layer, 380, 325, 835, 330)
	for i in range(cargo.size()):
		var index := i
		var title: String = {"scrap": "零件", "alloy": "合金", "equipment": "打捞装备", "command": "指挥组"}.get(cargo[i], str(cargo[i]))
		var b := button(layer, "弃置 " + title, 0, 0, 1, 1, func(): confirm_action("确定弃置这件物资？", func(): issue({"op": "salvage_drop", "index": index})))
		layer.remove_child(b)
		grid.add_child(b)
		b.custom_minimum_size = Vector2(250, 126)
		b.alignment = HORIZONTAL_ALIGNMENT_RIGHT
		picture(b, "res://assets/items/" + str(cargo[i]) + ".png", 25, 50, 650, 800)

func first_fleet() -> int:
	if battle_controller != null:
		var fleet: Dictionary = battle_controller._fleet()
		if not fleet.is_empty():
			return int(fleet.id)
	return int(core.view.get("fleets", [{}])[0].get("id", 1)) if not core.view.get("fleets", []).is_empty() else 1

func toggle_pause() -> void:
	if core.view.get("result") != null and not (battle_controller != null and battle_controller.replay_mode):
		notify({"ok": false, "message": "本局已结束，可在战情中重演。"})
		return
	running = not running
	if not running and battle_controller != null:
		battle_controller.record_signal("paused")
	if audio != null:
		audio.set_paused(not running)
	if battle_controller != null:
		battle_controller.update()

func confirm_route() -> void:
	if battle_controller != null:
		battle_controller.refresh_preview()
		battle_controller.commit_route()

func issue(command: Dictionary) -> Dictionary:
	if battle_controller != null and battle_controller.replay_mode:
		var denied := {"ok": false, "error": "回放为只读，不能改变当前航次、库存或命令。"}
		notify(denied)
		return denied
	var response: Dictionary = core.request(command)
	if not response.get("ok", false):
		notify(response)
	else:
		var service = get("progression")
		var fluid_tide:bool=_fluid_battle()
		if not fluid_tide and service != null and service.has_method("record_command"):
			service.record_command(command, core.view)
		update_battle()
		# Continuous movement stays in the native log; durable checkpoints are batched.
		if not fluid_tide or str(command.get("op","")) not in ["route","speed","littoral_ship_order","littoral_order"]:
			if not checkpoint() and fluid_tide:running=false
	return response

func select_object(kind: String, object: Dictionary) -> void:
	selection_kind = kind
	selected = object
	if battle_controller != null:
		battle_controller.select(kind, object)

func selection_action(title: String, callback: Callable) -> void:
	var b := button(page, title, 0, 0, 1, 1, callback)
	page.remove_child(b)
	battle_selection.add_child(b)
	b.custom_minimum_size.y = 48

func attack(target: String, weapon: String) -> void:
	var id := int(sea.selected_ship)
	if id == 0 and not core.view.get("ships", []).is_empty():
		id = int(core.view.ships[0].id)
	issue({"op": "fire", "ship": id, "target": target, "weapon": weapon})

func update_battle() -> void:
	if battle_controller != null:
		battle_controller.update()
		var operations:Control=page.get_node_or_null("ExpeditionOperations")
		if operations!=null:operations.refresh()
		if audio != null and not campaign_mode and not battle_controller.replay_mode:
			audio.set_scene("salvage" if core.view.get("contacts", []).is_empty() else "battle")

func checkpoint() -> bool:
	if home_exercise_session!=null and home_exercise_session.active:return true
	if run.is_empty() or (battle_controller != null and battle_controller.replay_mode):
		return true
	var saved: Dictionary = core.request({"op": "save", "serialized": true})
	if not saved.get("ok", false):
		notify(saved)
		return false
	var ui_state:Dictionary={}
	if str(run.get("mode",""))=="littoral" and battle_controller!=null and battle_controller.has_method("serialize_ui_state"):ui_state=battle_controller.serialize_ui_state()
	var response: Dictionary = economy.save_sortie(saved.get("serialized", ""),ui_state)
	if not response.get("ok", false):
		notify(response)
	elif _fluid_battle():
		tide_checkpoint_tick=float(core.view.get("tick",0))
	return bool(response.get("ok", false))

func save_leave() -> void:
	if home_exercise_session!=null and home_exercise_session.active:close_home_exercise();return
	running = false
	if battle_controller != null and battle_controller.replay_mode:
		var archived: bool = battle_controller.archive_replay
		battle_controller.end_replay()
		if archived:
			return
	if not run.is_empty():
		if checkpoint():
			return_to(battle_return_route)
			if await wait_for_page(battle_return_route):notify({"message": "已保存同一行动，返港期间暂停交易。"})
	elif campaign_mode:
		confirm_action("返回档案会结束本次借用战役。", func(): show_page("campaign"))
	else:
		show_page("harbor")

func abandon() -> void:
	if home_exercise_session!=null and home_exercise_session.active:close_home_exercise();return
	if str(run.get("mode",""))=="littoral":
		var ended:Dictionary=issue({"op":"littoral_abandon"})
		if ended.get("ok",false):finish_battle()
		return
	if str(run.get("mode",""))=="arena":
		running=false
		var snapshot:Dictionary=core.request({"op":"save","serialized":true})
		if not snapshot.get("ok",false):notify(snapshot);return
		var settled:Dictionary=arena.settle(core.view,str(snapshot.serialized),true)
		if not settled.get("ok",false):notify(settled);return
		last_receipt=settled.receipt.duplicate(true);run={};show_page("result");return
	if str(run.get("mode",""))=="tide_event":
		var ended:Dictionary=issue({"op":"tide_abandon"})
		if ended.get("ok",false):finish_battle()
		return
	running = false
	if battle_controller != null and battle_controller.replay_mode:
		battle_controller.end_replay()
		return
	var service = get("progression")
	if not run.is_empty() and str(run.get("mode", "salvage")) not in ["salvage", "basic"] and service != null:
		var saved: Dictionary = core.request({"op": "save", "serialized": true})
		if not saved.get("ok", false):
			notify(saved)
			return
		var ended: Dictionary = service.abandon_mode(core.view, str(saved.get("serialized", "")))
		if ended.get("ok", false):
			last_receipt = ended.get("receipt", {})
			run = {}
			show_page("result")
		else:
			notify(ended)
		return
	if campaign_mode:
		show_page("campaign")
		return
	var response: Dictionary = issue({"op": "salvage_abandon"})
	if response.get("ok", false):
		finish_battle()

func finish_battle() -> void:
	running = false
	if home_exercise_session!=null and home_exercise_session.active:home_exercise_session.finish(self);return
	if battle_controller != null and battle_controller.replay_mode:
		return
	var mode: String = str(run.get("mode", "salvage"))
	var service = get("progression")
	if mode=="arena":
		var snapshot:Dictionary=core.request({"op":"save","serialized":true})
		if not snapshot.get("ok",false):notify(snapshot);return
		var settled:Dictionary=arena.settle(core.view,str(snapshot.serialized))
		if not settled.get("ok",false):notify(settled);checkpoint();return
		last_receipt=settled.receipt.duplicate(true);set_meta("arena_mode",str(last_receipt.arena_mode));run={}
	elif mode=="littoral":
		var snapshot:Dictionary=core.request({"op":"save","serialized":true})
		if not snapshot.get("ok",false):notify(snapshot);return
		var settled:Dictionary=home.settle(core.view,str(snapshot.serialized))
		if not settled.get("ok",false):notify(settled);checkpoint();return
		last_receipt=settled.receipt.duplicate(true);run={}
	elif mode=="tide_event":
		var snapshot:Dictionary=core.request({"op":"save","serialized":true})
		if not snapshot.get("ok",false):notify(snapshot);return
		var settled:Dictionary=load("res://scripts/tide_event_service.gd").new(economy).settle(core.view,str(snapshot.serialized))
		if not settled.get("ok",false):notify(settled);checkpoint();return
		last_receipt=settled.receipt.duplicate(true);run={}
	elif str(run.get("gameplay_profile",""))=="cas-adventure-v3":
		var snapshot:Dictionary=core.request({"op":"save","serialized":true})
		if not snapshot.get("ok",false):notify(snapshot);return
		var settled:Dictionary=load("res://scripts/amphibious_expedition_service.gd").new(economy).finish(core.view,str(snapshot.serialized))
		if not settled.get("ok",false):notify(settled);checkpoint();return
		last_receipt=settled.receipt.duplicate(true);run={}
	elif not run.is_empty() and mode not in ["salvage", "basic"] and service != null:
		var saved: Dictionary = core.request({"op": "save", "serialized": true})
		if not saved.get("ok", false):
			notify(saved)
			return
		var settled: Dictionary = service.finish_mode(core.view, str(saved.get("serialized", "")))
		if not settled.get("ok", false):
			notify(settled)
			checkpoint()
			return
		last_receipt = settled.get("receipt", {})
		run = {}
	elif campaign_mode:
		last_receipt = {"success": core.view.get("result", {}).get("winner", "") == "allies", "campaign": true, "loot": {}}
	else:
		var salvage: Dictionary = core.view.get("salvage", {})
		var receipt := {"run_id": str(run.get("run_id", "")), "success": bool(salvage.get("extracted", false)), "loot": salvage.get("loot", {}), "ships": salvage.get("ships", [])}
		if str(run.get("content",""))=="salvage-v4":
			receipt["cargo_items"]=salvage.get("cargo_grid",{}).get("items",[]).filter(func(item):return item.get("placement")!=null)
		if core.view.has("fuel_receipt"):receipt["fuel_receipt"]=core.view.fuel_receipt.duplicate(true)
		var response: Dictionary = economy.settle_sortie(receipt)
		if not response.get("ok", false):
			notify(response)
			checkpoint()
			return
		last_receipt = response.get("receipt", receipt).duplicate(true)
		if receipt.has("cargo_items"):last_receipt["cargo_items"]=receipt.cargo_items.duplicate(true)
		run = {}
	show_page("result")
	if audio != null:
		audio.set_scene("victory" if last_receipt.get("success", false) else "defeat")

func result_screen() -> void:
	if str(last_receipt.get("mode",""))=="littoral":
		var outcome=load("res://scenes/ui/littoral_result.tscn").instantiate();page.add_child(outcome);outcome.bind(self,last_receipt)
		return
	var success: bool=bool(last_receipt.get("success",false))
	var borrowed: bool=bool(last_receipt.get("borrowed",false)) or bool(last_receipt.get("campaign",false))
	var title: String=("目标完成" if success else "行动结束") if borrowed else ("平安归航" if success else "救援返港")
	if str(last_receipt.get("mode",""))=="arena":title="竞技胜利" if success else "平局" if str(last_receipt.get("result",""))=="draw" else "竞技结束"
	if last_receipt.get("fictional_taskforce",false): title="特混行动结束"
	var ship_id: String=str(economy.formation[0]) if not economy.formation.is_empty() else "IBS-U-USN-FLETCHER"
	picture(page,str(cards.get(ship_id,{}).get("portrait","")),28,105,596,716)
	panel(page,638,135,900,650,Color(0.97,0.98,0.94,0.98))
	icon(page,"trophy" if success else "shield",685,177,47,47,Color("c08b39"))
	label(page,title,754,163,720,81,47)
	label(page,str(last_receipt.get("title","")) if borrowed else ("欢迎回来，指挥官。" if success else "先让舰队休整，再一起出发。"),688,265,795,45,25,MUTED)
	if str(last_receipt.get("mode",""))=="arena":
		label(page,"积分 %d（%+d）"%[int(last_receipt.get("rating_after",1000)),int(last_receipt.get("delta",0))],688,307,795,40,26,Design.ACCENT)
	var loot: Dictionary=last_receipt.get("rewards",{}) if borrowed else last_receipt.get("loot",{})
	var recovered:Dictionary={}
	for item in last_receipt.get("cargo_items",[]):
		if not success or str(item.get("loot_id","")).is_empty():continue
		var id:String=str(item.loot_id)
		if not recovered.has(id):recovered[id]={"item":item,"count":0}
		recovered[id].count=int(recovered[id].count)+1
	var keys: Array=[]
	for key in loot:
		if int(loot[key])>0: keys.append(key)
	if not recovered.is_empty():keys=recovered.keys()
	var names: Dictionary={"scrap":"旧世零件","alloy":"合金箱","equipment":"打捞装备","command":"指挥组","credits":"银币","tickets":"常驻券","up_tickets":"UP券","medals":"勋章","tide_tokens":"回响徽片","origins":"元词"}
	for i in range(mini(keys.size(),4)):
		var key: String=str(keys[i])
		var x:=688.0+i*198
		if recovered.has(key):
			picture(page,load("res://scripts/cargo_service.gd").art_path(recovered[key].item),x,343,165,142)
		elif key in ["scrap","alloy","equipment","command"]:
			picture(page,"res://assets/items/"+key+".png",x,343,165,142)
		else:
			icon(page,{"credits":"coin","tickets":"ticket","up_tickets":"recruit","medals":"trophy"}.get(key,"cargo"),x+42,361,82,82,Color("267c9e"))
		label(page,str(recovered[key].item.name) if recovered.has(key) else str(names.get(key,key)),x,494,180,38,22)
		label(page,"× %d"%int(recovered[key].count if recovered.has(key) else loot[key]),x,540,180,39,27)
	if keys.is_empty(): label(page,"这一程的经历，也会成为下一次的力量。",689,382,780,100,28,MUTED)
	button(page,"航次详情",686,615,243,49,func():
		var layer: Control=open_modal("航次详情")
		var detail: String=str(last_receipt.get("primary",""))+"\n"
		for ship in last_receipt.get("ships",[]):
			detail+="%s  耐久%d%%\n耗弹%d  返库%d  遗失%d  维修%d银币\n\n"%[str(ship.get("name","")),int(ship.get("hp",0)),int(ship.get("ammo_spent",0)),int(ship.get("ammo_returned",0)),int(ship.get("ammo_lost",0)),int(ship.get("repair_cost",0))]
		if borrowed: detail+="借用航次不扣个人弹药，不写入自有舰战损。"
		label(layer,detail,385,238,830,453,22,MUTED))
	if borrowed:
		var destination:String=str(last_receipt.get("return_route","story_route" if str(last_receipt.get("mode",""))=="story_chapter" else "story_catalog" if str(last_receipt.get("mode",""))=="story" else battle_return_route))
		button(page,"返回章节路线" if destination=="story_route" else "返回版本活动" if destination=="tide_event" else "返回竞技航线" if destination=="arena" else "返回作战列表",1021,698,470,62,func():return_to(destination),true)
		button(page,"航次档案与重演",686,698,313,62,func():show_page("archives"))
	elif str(last_receipt.get("content",""))=="salvage-v4":
		button(page,"整理带回物资" if success else "维修与整备",1021,698,470,62,func():
			var target:String="warehouse" if success else "roster"
			show_page(target)
			if await wait_for_page(target) and success:load("res://scripts/cargo_presentation.gd").open_stash(self,"fleet" if last_receipt.has("cargo_transfer_v1") else "base"),true)
		button(page,"选择下一次远征",686,698,313,62,func():return_to("expedition"))
	else:
		button(page,"前往仓库兑换",1021,698,470,62,func():show_page("warehouse"),true)
		button(page,"维修与整备",686,698,313,62,func():show_page("roster"))

func settings_screen() -> void:
	label(page, "设置", 60, 130, 1000, 60, 36)
	panel(page, 60, 240, 1480, 500)
	label(page, "战场角色投影", 100, 280, 680, 60, 28)
	label(page, "选择海面上的角色显示方式。", 100, 352, 1080, 100, 23, MUTED)
	button(page, "小人投影" if ship_mode else "原版舰影", 1120, 290, 350, 70, func(): ship_mode = not ship_mode; persist_settings(); show_page("settings"), true)
	if audio != null:
		var names := ["配乐", "战场语音", "界面音效"]
		var values := [float(audio.music_volume), float(audio.voice_volume), float(audio.ui_volume)]
		for i in range(3):
			label(page, names[i], 100, 481 + i * 65, 250, 50, 25)
			var slider := HSlider.new()
			slider.min_value = 0
			slider.max_value = 1
			slider.step = 0.05
			slider.value = values[i]
			place(slider, page, 375, 495 + i * 65, 650, 35)
			var index := i
			slider.value_changed.connect(func(value: float):
				values[index] = value
				audio.configure(values[0], values[1], values[2], true, true))
	label(page, "联合作战筹备中", 1100, 485, 390, 55, 24, MUTED)
	button(page,"转场动效：开" if page_motion else "转场动效：关",1100,405,390,53,func():page_motion=not page_motion;set_meta("reduced_motion",not page_motion);persist_settings();show_page("settings"))
	label(page,"战斗震动",100,405,250,50,25)
	add_combat_motion_slider(page,375,420,650)
	button(page, "返回上一层", 1120, 592, 350, 65, func(): go_back())

func add_combat_motion_slider(parent:Control,x:float,y:float,width:float)->HSlider:
	var slider:=HSlider.new();slider.name="CombatMotionStrength"
	slider.min_value=0;slider.max_value=1;slider.step=.05;slider.value=battle_motion_strength
	slider.tooltip_text="开火与受击震动强度，拖到最左关闭。"
	place(slider,parent,x,y,width,35)
	slider.value_changed.connect(func(value:float):
		battle_motion_strength=value;persist_settings()
		if battle_controller!=null and is_instance_valid(battle_controller.feedback):battle_controller.feedback.configure_motion(value))
	return slider

func persist_settings() -> void:
	var config := ConfigFile.new()
	config.set_value("display", "chibis", ship_mode)
	config.set_value("display","page_motion",page_motion)
	config.set_value("display","battle_motion_strength",battle_motion_strength)
	config.save("user://settings.cfg")

func open_modal(title: String, back_action:Callable=Callable()) -> Control:
	close_modal()
	modal = Control.new()
	add_child(modal)
	modal.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var backdrop := ColorRect.new()
	backdrop.color = Color(0.025, 0.1, 0.14, 0.62)
	modal.add_child(backdrop)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel(modal,26,8,270,88,Color("163844"))
	var modal_back:=button(modal,"‹  返回",34,14,140,80,func():close_modal();if back_action.is_valid():back_action.call())
	modal_back.name="ModalNavigateBack";modal_back.tooltip_text="返回上一层"
	var modal_home:=button(modal,"母港",186,14,100,80,go_home)
	modal_home.name="ModalNavigateHome";modal_home.tooltip_text="直接返回母港"
	Design.apply_overlay_button(modal_back);Design.apply_overlay_button(modal_home)
	panel(modal, 330, 125, 940, 625, Design.PAPER)
	label(modal, title, 370, 145, 795, 65, 30)
	button(modal, "关闭", 1150, 145, 95, 52, close_modal)
	return modal

func close_modal() -> void:
	if is_instance_valid(modal):
		remove_child(modal)
		modal.queue_free()
		modal = null

func confirm_action(text: String, callback: Callable) -> void:
	var layer := open_modal("确认操作")
	label(layer, text, 395, 290, 810, 200, 29)
	button(layer, "确认", 815, 615, 350, 65, func(): close_modal(); callback.call(), true)
	button(layer, "取消", 415, 615, 350, 65, close_modal)


func open_home_replay(run_id:String)->void:
	if home_replay_session!=null and home_replay_session.active:return
	var found:Dictionary=home.replay_record(run_id)
	if not found.get("ok",false):notify(found);return
	home_replay_session=load("res://scripts/home_replay_session.gd").new()
	var response:Dictionary=home_replay_session.open(self,found.record)
	if not response.get("ok",false):notify(response);return
	close_modal();await enter_battle()
	if screen=="battle" and battle_controller!=null:battle_controller.seek_littoral(0.0)

func close_home_replay()->void:
	if home_replay_session==null or not home_replay_session.active:return
	close_modal();home_replay_session.restore(self);show_page("home")
	if await wait_for_page("home"):load("res://scripts/home_conflict_ui.gd").open(self,"records")

func start_replay(record: Dictionary = {}) -> void:
	if record.is_empty() and screen == "battle" and battle_controller != null:
		battle_controller.begin_replay()
		return
	if not economy.state.get("active_run", {}).is_empty():
		notify({"ok": false, "message": "请先继续或结束当前行动，再打开其他存档。"})
		return
	var raw: String = str(record.get("snapshot", ""))
	var saved: Variant = JSON.parse_string(raw)
	if not saved is Dictionary:
		notify({"ok": false, "message": "归档快照无法读取，原档案已保留。"})
		return
	var response: Dictionary = core.request({"op": "replay", "serialized": raw, "tick": 0})
	if not response.get("ok", false):
		notify(response)
		return
	campaign_mode = true
	run = {}
	set_meta("tide_replay_seed",int(saved.get("seed",42)))
	await enter_battle()
	if screen!="battle" or battle_controller==null:return
	battle_controller.archive_replay = true
	battle_controller.replay_mode = true
	battle_controller.replay_save = raw
	battle_controller.replay_limit = int(saved.get("tick", 0))
	if core.view.has("littoral") and battle_controller.has_method("seek_littoral"):
		battle_controller.replay_duration=float(saved.get("tick",0))
		battle_controller.replay_seconds=0.0
		battle_controller.seek_littoral(0.0)
	else:battle_controller.seek(0)
