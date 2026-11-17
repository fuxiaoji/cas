extends "res://scripts/legacy_battle.gd"
const Sea=preload("res://scripts/tide_sea.gd")
var ui:Control
var offer_seen:=-1
var replay_seconds:=0.0
func build()->void:
	app.sea=Sea.new();app.sea.world_seed=int(app.run.get("request",{}).get("seed",app.get_meta("tide_replay_seed",42)));app.place(app.sea,app.page,0,0,1600,900);app.sea.cards=app.cards;app.sea.chibis=app.ship_mode
	app.sea.point_selected.connect(move);app.sea.object_selected.connect(app.select_object)
	ui=load("res://scenes/ui/tide_battle_hud.tscn").instantiate();app.page.add_child(ui);ui.bind(self)
	app.pause_button=ui.get_node("Pause");app.battle_status=ui.get_node("Clock")
	update()
func update()->void:
	if not is_instance_valid(ui):return
	var view:Dictionary=app.core.view;var tide:Dictionary=view.get("tide",{})
	if app.audio!=null:app.audio.ingest_events(view.get("events",[]),view.get("ships",[]),view.get("contacts",[]),not replay_mode,int(view.get("tick",0)))
	app.sea.motion_strength=app.battle_motion_strength
	app.sea.observe(view,replay_mode,app.core.observation_epoch,app.running,float(app.speed))
	ui.sync_team(view.get("ships",[]),app.cards,app.sea.drain_joins())
	app.sea.projectile_rate=float(app.speed) if app.running else 0.0
	app.sea.projectile_readonly=replay_mode
	app.sea.projectile_epoch=app.core.observation_epoch
	var remaining:int=maxi(0,int(tide.get("duration",180))-int(view.get("tick",0)))
	ui.get_node("Clock").text="%02d:%02d"%[remaining/60,remaining%60]
	ui.get_node("Status/Body/Wave").text="潮汐回响 · 第 %d 波"%int(tide.get("wave",1))
	ui.get_node("Status/Body/Level").text="共鸣 Lv.%d  ·  击退 %d"%[int(tide.get("level",1)),int(tide.get("kills",0))]
	var hp:ProgressBar=ui.get_node("Status/Body/Hp");var xp:ProgressBar=ui.get_node("Status/Body/Xp")
	if not view.get("ships",[]).is_empty():hp.max_value=float(tide.get("team_max_hp",view.ships[0].maxHp));hp.value=float(tide.get("team_hp",view.ships[0].hp));hp.tooltip_text="舰队耐久 %.0f / %.0f"%[hp.value,hp.max_value]
	xp.max_value=maxi(1,int(tide.get("xp_required",12)));xp.value=int(tide.get("xp",0))
	ui.get_node("Pause").text="暂停" if app.running else "继续" if int(view.get("tick",0))>0 else "开始"
	var choices:Array=tide.get("choices",[])
	ui.get_node("Upgrades").visible=not choices.is_empty() and not replay_mode
	app.sea.cinematic=not choices.is_empty() and not replay_mode
	if not choices.is_empty() and not replay_mode:
		app.running=false
		if offer_seen!=int(tide.get("offer_id",0)):_choices(tide)
	ui.get_node("Hint").text="潮环看守出现 · 避开红圈" if bool(tide.get("boss_spawned",false)) and not bool(tide.get("boss_defeated",false)) else "WASD / 点击航行 · 全队自动齐射"
func move(point:Vector2)->void:
	if replay_mode:return
	if not app.core.view.get("tide",{}).get("choices",[]).is_empty() or app.core.view.get("result")!=null:return
	var response:Dictionary=app.issue({"op":"route","fleet":1,"mode":"follow","speed":60,"points":[{"x":clampf(point.x,300,float(app.core.view.width)-300),"y":clampf(point.y,300,float(app.core.view.height)-300)}]})
	if response.get("ok",false):app.running=true
func select(kind:String,object:Dictionary)->void:
	if kind=="contact":app.sea.intel_contact=str(object.id);app.sea.selected_contact=str(object.id);app.sea.queue_redraw()
func cancel_draft(_announce:bool=true)->void:
	app.sea.planned.clear()
func record_signal(_signal:String)->void:pass
func _choices(tide:Dictionary)->void:
	offer_seen=int(tide.offer_id)
	var reinforcement:bool=str(tide.get("offer_kind","upgrade"))=="reinforcement"
	ui.get_node("Upgrades/Choices").visible=not reinforcement;ui.get_node("Upgrades/ReserveScroll").visible=reinforcement
	ui.get_node("Upgrades/Title").text="呼叫一位援军" if reinforcement else "选择这一次的回响"
	var parent:Container=ui.get_node("Upgrades/ReserveScroll/CrewGrid" if reinforcement else "Upgrades/Choices")
	for node in parent.get_children():parent.remove_child(node);node.queue_free()
	for raw in tide.choices:
		var choice:Dictionary=raw;var recruit:bool=str(choice.get("kind",""))=="reinforcement"
		var button:=Button.new();button.name=("Upgrade_"+str(choice.id)).validate_node_name();button.set_meta("tide_choice_id",str(choice.id));button.size_flags_horizontal=Control.SIZE_EXPAND_FILL;Design.apply_button(button,recruit or not reinforcement);parent.add_child(button)
		if reinforcement:button.custom_minimum_size=Vector2(200,252)
		var body:=VBoxContainer.new();body.mouse_filter=Control.MOUSE_FILTER_IGNORE;body.add_theme_constant_override("separation",12 if reinforcement else 28);button.add_child(body);body.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);body.offset_left=20;body.offset_top=22;body.offset_right=-20;body.offset_bottom=-18
		var art:=TextureRect.new();art.texture=Design.icon_texture(str(choice.get("icon","shield")));art.custom_minimum_size.y=140 if reinforcement else 96;art.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;art.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED;art.mouse_filter=Control.MOUSE_FILTER_IGNORE;body.add_child(art)
		if recruit:
			var card:Dictionary=app.cards.get(str(choice.get("character_id","")),{});var portrait:Texture2D=Art.texture(str(card.get("portrait","")))
			if portrait!=null:art.texture=load("res://scripts/story_actor_layout.gd").portrait(portrait,str(card.get("id","")))
		var role:String=str({"torpedo":"雷击支援","barrage":"速射炮幕","heavy":"重炮轰击"}.get(str(choice.get("role","")),"协同齐射"))
		var title:String=str(choice.name) if recruit or not reinforcement else "暂不招募 · "+str(choice.name)
		for text in [title,role if recruit else str(choice.description)]:
			var line:=Label.new();line.text=text;line.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;line.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;line.add_theme_font_size_override("font_size",27 if text==title else 21);line.add_theme_color_override("font_color",Design.INK);line.mouse_filter=Control.MOUSE_FILTER_IGNORE;body.add_child(line)
		var offer:int=offer_seen;var id:String=str(choice.id)
		button.pressed.connect(func():
			var response:Dictionary=app.issue({"op":"tide_choose","offer_id":offer,"upgrade":id})
			if response.get("ok",false):app.running=true;update())
	if parent.get_child_count()>0:parent.get_child(0).grab_focus()
func advance_tide_replay(seconds:float)->void:
	seek_tide(replay_seconds+seconds)
	if replay_seconds>=float(replay_limit):app.running=false
func seek(tick:int)->void:
	if str(app.core.view.get("tide",{}).get("version",""))=="cas-event-tide-v2":seek_tide(float(tick))
	else:
		replay_seconds=float(tick)
		super.seek(tick)
func seek_tide(seconds:float)->void:
	if not replay_mode:return
	replay_seconds=clampf(snappedf(seconds,.1),0,float(replay_limit));replay_tick=int(replay_seconds)
	var response:Dictionary=app.core.request({"op":"replay","serialized":replay_save,"tick":replay_seconds})
	if response.get("ok",false):update()
	else:app.notify(response)
func open_pause_menu()->void:
	app.running=false
	if replay_mode:
		var menu:Control=app.open_modal("潮汐回响 · 重演")
		var slider:HSlider=HSlider.new();slider.name="ReplaySeek";slider.min_value=0;slider.max_value=replay_limit;slider.step=.1 if str(app.core.view.tide.version)=="cas-event-tide-v2" else 1;slider.value=float(app.core.view.tick);app.place(slider,menu,400,275,790,48)
		slider.value_changed.connect(func(value):seek_tide(value) if slider.step<1 else seek(int(value)))
		app.button(menu,"播放 / 暂停",400,380,790,65,func():app.close_modal();app.running=not app.running;update(),true)
		app.button(menu,"返回档案",400,480,790,65,func():app.close_modal();end_replay())
		return
	var layer:Control=app.open_modal("潮汐回响 · 暂停")
	app.button(layer,"继续回响",400,255,790,65,func():app.close_modal();app.running=app.core.view.get("tide",{}).get("choices",[]).is_empty();update(),true)
	app.button(layer,"保存暂离",400,355,790,65,func():app.close_modal();app.save_leave())
	app.button(layer,"结束本次活动",400,475,790,65,func():app.close_modal();app.abandon())
	app.label(layer,"战斗震动",400,590,180,50,23,Design.INK)
	app.add_combat_motion_slider(layer,600,605,550)
	var home:Button=app.button(layer,"保存并返回母港",400,690,790,52,app.go_home)
	home.name="NavigateHome"
