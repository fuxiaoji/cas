extends SceneTree
const Audio=preload("res://scripts/audio_director.gd")
const Art=preload("res://scripts/character_art.gd")
const OUTPUT="res://../artifacts/godot/original-music-transition/"
class FixtureRoster extends RefCounted:
	var rows:Array=[]
	func roster()->Array:return rows
class FixtureApp extends Control:
	var page_motion:=true
	var screen:="outgoing"
	var page:Control
	var economy:=FixtureRoster.new()
var checks:=0
var failures:Array=[]
var samples:Array=[]
func _initialize()->void:call_deferred("run")
func check(value:bool,label:String)->void:
	checks+=1
	if not value:failures.append(label);push_error(label)
func frames(n:int)->void:
	for i in n:await process_frame
func wait(seconds:float)->void:await create_timer(seconds).timeout
func shot(label:String)->void:
	await frames(2);RenderingServer.force_draw();root.get_texture().get_image().save_png(ProjectSettings.globalize_path(OUTPUT+label+".png"))
func run()->void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT));root.size=Vector2i(1280,720)
	var settings:String="user://tests/original-audio-%d.json"%OS.get_process_id();DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(settings).get_base_dir())
	var normal_sha:String=FileAccess.get_sha256(Audio.SETTINGS_PATH) if FileAccess.file_exists(Audio.SETTINGS_PATH) else "absent"
	var audio=Audio.new();audio.settings_path=settings;var clock:Dictionary={"hour":12}
	audio.time_provider=func():return clock
	root.add_child(audio);await frames(2);audio.configure(.30,.75,.25)
	check(audio.ledger.get("music",[]).size()==11,"eleven independently authored scene masters registered")
	for cue in ["title","harbor_day","harbor_night","story","story_tension","battle","landing","home","tide","victory","defeat"]:
		audio.set_scene(cue);await wait(.95)
		var stream=audio._music.stream;check(stream is AudioStreamOggVorbis and audio._music.playing,"actual Vorbis playback "+cue)
		check(audio.current_music_path=="res://assets/audio/original/"+cue+".ogg","original path "+cue)
		check(stream.loop==(cue not in ["victory","defeat"]),"loop or one-shot policy "+cue)
		check(stream.loop_offset>0 if stream.loop else is_zero_approx(stream.loop_offset),"authored introduction then segmented loop "+cue)
		check(audio._music.get_playback_position()>.2,"actual audio clock advances "+cue)
		var seek:float=stream.get_length()*.55;audio._music.seek(seek);await wait(.35)
		check(audio._music.get_playback_position()>seek,"contrasting section plays "+cue)
		audio._music.seek(stream.get_length()-.15);await wait(.40)
		if stream.loop:
			check(audio._music.playing and absf(audio._music.get_playback_position()-stream.loop_offset)<1.0,"real decoder wraps to authored body "+cue)
		else:check(not audio._music.playing,"real decoder ends one-shot "+cue)
		samples.append({"cue":cue,"length":stream.get_length(),"sample_a_seconds":.95,"sample_b_at":seek,"sample_b_seconds":.35,"bus_peak_left_db":AudioServer.get_bus_peak_volume_left_db(0,0)})
	clock.hour=12;audio.set_scene("harbor");await wait(.95);check(audio.current_music_path.ends_with("harbor_day.ogg"),"real local day harbor selection")
	clock.hour=20;audio._time_poll=30;audio._process(.01);await wait(.95);check(audio.current_music_path.ends_with("harbor_night.ogg"),"injected local boundary refresh without page or account change")
	audio.set_scene("story");await wait(.95);audio.set_dialogue_active(true);await wait(.3);check(audio._duck_gain<.3,"spoken dialogue leaves musical headroom")
	audio.set_scene("battle");await wait(.35);check(audio._music_players.all(func(p):return p.playing),"real overlap during crossfade")
	check(audio._duck_gain<.3 and audio._crossfading,"duck envelope independent of music crossfade")
	audio.set_dialogue_active(false);await wait(1.5);check(audio._duck_gain>.95 and audio._music_players.filter(func(p):return p.playing).size()==1,"duck recovers and old decoder stops")
	audio.set_session("original-audio-review","allies");audio.ingest_events([{"id":"contact","tick":1,"voiceCue":"contact","text":"发现敌舰"}],[],[],true,1);await wait(.25)
	check(audio.last_voice_cue=="contact" and not audio.last_voice_path.is_empty(),"existing true-event radio mapping preserved")
	check(audio._duck_target<.3,"archive radio also ducks original score")
	audio.set_paused(true);check(audio._music_players.filter(func(p):return p.playing).all(func(p):return p.stream_paused) and (not audio._voice.playing or audio._voice.stream_paused),"pause reaches active music decks and radio")
	audio.set_paused(false);audio.configure(.22,.63,.31,true,false);var restored=Audio.new();restored.settings_path=settings;root.add_child(restored);await frames(2)
	check(is_equal_approx(restored.music_volume,.22) and is_equal_approx(restored.voice_volume,.63) and is_equal_approx(restored.ui_volume,.31) and not restored.voices_enabled,"user volume schema survives save/rebuild")
	restored.shutdown();restored.queue_free();audio.configure(0,.63,.31);await wait(.08);check(audio._music_players.all(func(p):return p.volume_db<=-79.9),"zero music slider is inaudible")
	audio.configure(.22,.63,.31,false);check(audio._music_players.all(func(p):return not p.playing),"master disable stops both decks")
	print("AUDIO_PLAYBACK_COMPLETE")
	audio.shutdown();audio.queue_free();await frames(2)
	var app:=FixtureApp.new();root.add_child(app);app.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);var bg:=ColorRect.new();bg.color=Color("163e58");app.add_child(bg);bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);app.page=bg
	var catalog:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/ships.json"))
	for card in catalog.ships:
		if Art.projection(card).kind in ["generated_chibi","reference_sd"]:app.economy.rows.append(card)
	var transition=load("res://scenes/ui/page_transition.tscn").instantiate();app.add_child(transition);await frames(3);transition.random.seed=20261113
	print("TRANSITION_FIXTURE_READY")
	var poses:Array=[]
	for size in [Vector2i(960,540),Vector2i(1280,720),Vector2i(1920,1080),Vector2i(1600,720)]:
		root.size=size;await frames(3);transition._pick_characters(app);check(transition.actor_states.size()==3,"three authentic SD identities "+str(size))
		var logical:Rect2=root.get_visible_rect()
		var before:Array=[];var after:Array=[];transition.preview_at(0,.23)
		for state in transition.actor_states:before.append(state.sprite.position.x)
		transition.preview_at(0,.76)
		for state in transition.actor_states:after.append(state.sprite.position.x)
		for i in 3:check(float(after[i])-float(before[i])>logical.size.x*.06 and float(after[i])-float(before[i])<logical.size.x*.18,"short visible horizontal hop advance "+str(size)+" actor"+str(i))
		transition.preview_at(0,.5);await shot("parade-%dx%d"%[size.x,size.y]);var mid:Array=[]
		for state in transition.actor_states:
			var rect:Rect2=state.sprite.get_global_rect();mid.append({"identity":state.identity,"rect":str(rect)})
			check(rect.intersection(logical).get_area()>rect.get_area()*.90,"large walker readable at covered midpoint "+str(size))
			check(state.sprite.material.shader==transition.StrideShader,"existing-image lower-body stride material")
		poses.append({"window":str(size),"logical_viewport":str(logical),"before_x":before,"after_x":after,"mid":mid})
		for style in 3:
			transition.preview_at(style,.5);await frames(2);RenderingServer.force_draw();var image:Image=root.get_texture().get_image();var covered:=true
			for point in [Vector2(.01,.01),Vector2(.5,.01),Vector2(.99,.01),Vector2(.01,.5),Vector2(.99,.5),Vector2(.01,.99),Vector2(.5,.99),Vector2(.99,.99)]:covered=covered and not image.get_pixelv(Vector2i(Vector2(image.get_size())*point)).is_equal_approx(bg.color)
			check(covered,"full-screen anime cover remains "+str(style)+str(size))
	root.size=Vector2i(1280,720);transition.cancel();await frames(2);transition.capture_previous(app,"incoming");var began:int=Time.get_ticks_msec();transition.play(app,bg,"outgoing","incoming")
	check(transition.is_busy() and is_equal_approx(transition.duration,1.18),"readable three-hop duration and transient input barrier active")
	await wait(transition.duration+.16);check(not transition.is_busy() and not transition.overlay.visible and Time.get_ticks_msec()-began<int((transition.duration+.5)*1000),"no extra loading hold; barrier releases")
	app.set_meta("reduced_motion",true);transition.capture_previous(app,"incoming");transition.play(app,bg,"outgoing","incoming");check(not transition.is_busy(),"reduced motion cuts immediately")
	app.set_meta("reduced_motion",false);app.page_motion=false;transition.play(app,bg,"outgoing","incoming");check(not transition.is_busy(),"disabled transitions add no delay")
	app.queue_free();await frames(2)
	var after_sha:String=FileAccess.get_sha256(Audio.SETTINGS_PATH) if FileAccess.file_exists(Audio.SETTINGS_PATH) else "absent";check(after_sha==normal_sha,"normal user audio settings never written")
	if FileAccess.file_exists(settings):DirAccess.remove_absolute(ProjectSettings.globalize_path(settings))
	var report:Dictionary={"checks":checks,"failures":failures,"passed":failures.is_empty(),"music_playback":samples,"bus_peak_sample_phase":"after loop/end decoder probe; victory and defeat are correctly silent at this point","poses":poses,"normal_settings_unchanged":after_sha==normal_sha,"account_access":"no profile constructed; read-only registered cast fixture","actual_audio_driver":AudioServer.get_driver_name(),"core_override":OS.get_environment("CAS_SIM_PATH"),"core_access":"no battle core constructed; scene/audio rendering only"}
	FileAccess.open(OUTPUT+"receipt.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "));print("ORIGINAL_MUSIC_TRANSITION ",JSON.stringify(report));quit(0 if failures.is_empty() else 1)
