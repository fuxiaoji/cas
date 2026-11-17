class_name CasPrologueFilm
extends Control
## Read-only film from real CAS observations. Its opening process is isolated
## from the player's active battle; later films use the player's own recording.
const Core=preload("res://scripts/core_bridge.gd")
const Sea=preload("res://scripts/sea_map.gd")
const Design=preload("res://scripts/ui_design.gd")
var app
var opening:=false
var recording:Array=[]
var replay_snapshot:=""
var cursor:=0
var playing:=true
var interval:=0.18
var elapsed:=0.0
var map
var strip:Label
var toggle:Button
var frames:Array=[]
var error:=""
var voice_live:=false
var observed_ticks:Array[int]=[]
var focused:=false

func _ready() -> void:
	mouse_filter=Control.MOUSE_FILTER_STOP
	clip_contents=true
	map=Sea.new();add_child(map);map.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	map.cards=app.cards if app!=null else {};map.chibis=false;map.mouse_filter=Control.MOUSE_FILTER_IGNORE
	map.zoom=1.55
	if "cinematic" in map: map.cinematic = true
	strip=Label.new();strip.add_theme_font_override("font",Design.font(500));strip.add_theme_font_size_override("font_size",20);strip.add_theme_color_override("font_color",Color("e6eff0"));add_child(strip)
	strip.anchor_left=1;strip.anchor_right=1;strip.offset_left=-475;strip.offset_right=-210;strip.offset_top=28;strip.offset_bottom=68
	strip.horizontal_alignment=HORIZONTAL_ALIGNMENT_RIGHT
	toggle=Button.new();toggle.text="暂停回放";add_child(toggle)
	toggle.anchor_left=1;toggle.anchor_right=1;toggle.offset_left=-190;toggle.offset_right=-40;toggle.offset_top=28;toggle.offset_bottom=70
	Design.apply_button(toggle,false,true)
	toggle.add_theme_font_size_override("font_size",20)
	for state in ["normal", "hover", "pressed", "focus"]:
		var style:=Design.box(Color(0.04,0.13,0.2,0.16 if state=="normal" else 0.7),3)
		toggle.add_theme_stylebox_override(state,style)
	for key in ["font_color","font_hover_color","font_pressed_color","font_focus_color"]:toggle.add_theme_color_override(key,Design.PAPER)
	toggle.pressed.connect(func():
		if cursor>=frames.size()-1:cursor=0;playing=true
		else:playing=not playing
		if voice_live:app.audio.set_paused(not playing)
		_refresh())
	if opening:_capture_opening()
	else:
		frames=recording.duplicate(true)
		if frames.is_empty() and not replay_snapshot.is_empty():_capture_replay()
	if frames.is_empty():
		strip.text=error if not error.is_empty() else "本段尚未保存实操影像；回到相应实操后可生成本席记录。"
		toggle.disabled=true
	else:_refresh()

func _capture_opening() -> void:
	var core=Core.new()
	var response:Dictionary=core.request({"op":"new","seed":6106,"side":"allies","enemy":"gunnery","profile":"coord","variant":"prologue","realtime":true})
	if not response.get("ok",false):error=str(response.get("error","开场记录暂时无法播放"));core.close();return
	frames.append(response.data.duplicate(true))
	while int(core.view.get("tick",0))<204:
		response=core.request({"op":"step","seconds":mini(4,204-int(core.view.tick))})
		if not response.get("ok",false):error=str(response.get("error","开场记录捕获失败"));break
		frames.append(response.data.duplicate(true))
	var handover:Dictionary=core.request({"op":"save","serialized":true})
	if app!=null and handover.get("ok",false):app.progression.cache_story_handover(str(handover.get("serialized","")))
	core.close()
	voice_live=app!=null and app.audio!=null and app.economy.state.get("active_run",{}).is_empty() and not bool(app.progression.data().get("prologue_reward",false))
	if voice_live:app.audio.set_session("prologue-opening-first", "allies");app.audio.set_paused(false)

func _capture_replay() -> void:
	var core=Core.new()
	var loaded:Dictionary=core.request({"op":"load","serialized":replay_snapshot})
	if not loaded.get("ok",false):error=str(loaded.get("error","本局记录无法恢复"));core.close();return
	var limit:=int(core.view.get("tick",0))
	var stride:=maxi(4,int(ceil(float(limit)/100.0)))
	for tick in range(0,limit+1,stride):
		var response:Dictionary=core.request({"op":"replay","serialized":replay_snapshot,"tick":tick})
		if not response.get("ok",false):error=str(response.get("error","本局记录读取失败"));break
		frames.append(response.data.duplicate(true))
	var end:Dictionary=core.request({"op":"replay","serialized":replay_snapshot,"tick":limit})
	if end.get("ok",false) and (frames.is_empty() or int(frames.back().get("tick",-1))!=limit):frames.append(end.data.duplicate(true))
	core.close()

func _process(delta:float) -> void:
	if frames.is_empty():return
	if playing and cursor<frames.size()-1:
		elapsed+=delta
		if elapsed>=interval:
			elapsed-=interval;cursor+=1;_refresh()
	var frame:Dictionary=frames[cursor]
	var focus:=opening and int(frame.get("tick",0))>=188
	var target_zoom:=1.85 if focus else 1.55
	map.zoom=lerpf(map.zoom,target_zoom,minf(1.0,delta*4.5))
	var target_pan:=Vector2.ZERO
	if focus:
		focused=true
		var center:=Vector2.ZERO;var count:=0
		for ship in frame.get("ships",[]):
			if int(ship.get("fleet",0))==1:center+=Vector2(float(ship.x),float(ship.y));count+=1
		if count>0:
			center/=count
			target_pan=map.size*Vector2(0.5,0.55)-(map.project(center)-map.pan-map.combat_offset)
	map.pan=map.pan.lerp(target_pan,minf(1.0,delta*4.5))
	map.queue_redraw()

func _refresh() -> void:
	if frames.is_empty():return
	var frame:Dictionary=frames[clampi(cursor,0,frames.size()-1)]
	map.view=frame
	var tick:=int(frame.get("tick",0));observed_ticks.append(tick)
	strip.text="%02d:%02d"%[tick/60,tick%60]
	toggle.text="重播" if cursor>=frames.size()-1 else ("暂停回放" if playing else "继续回放")
	if voice_live and playing:app.audio.ingest_events(frame.get("events",[]),frame.get("ships",[]),frame.get("contacts",[]),true,tick)
	map.queue_redraw()

func _exit_tree() -> void:
	if voice_live and is_instance_valid(app) and app.audio!=null:app.audio.set_session("port","allies")
