class_name CasAudioDirector
extends Node
## Original scene score, equal-power crossfades and an independent radio duck envelope.
## Event input must be the player's observation.events, never World truth.

signal voice_started(cue: String, path: String)
signal scene_changed(scene: String, path: String)

const SETTINGS_PATH := "user://cas_audio_v1.json"
var settings_path:String=SETTINGS_PATH
var music_volume := 0.42
var voice_volume := 0.9
var ui_volume := 0.45
var enabled := true
var voices_enabled := true
var side := "allies"
var current_scene := ""
var current_music_path := ""
var ledger: Dictionary = {}
var last_voice_path := ""
var last_voice_cue := ""
var _music: AudioStreamPlayer
var _music_players:Array[AudioStreamPlayer]=[]
var _gains:Array[float]=[0.0,0.0]
var _fade_from:Array[float]=[0.0,0.0]
var _fade_to:Array[float]=[0.0,0.0]
var _crossfade_elapsed:=0.0
var crossfade_seconds:=.85
var _crossfading:=false
var _duck_gain:=1.0
var _duck_target:=1.0
var _dialogue_active:=false
var _radio_active:=false
var _time_poll:=0.0
var time_provider:Callable
var _voice: AudioStreamPlayer
var _ui_players: Array[AudioStreamPlayer] = []
var _seen: Dictionary = {}
var _cooldowns: Dictionary = {}
var _queue: Array[Dictionary] = []
var _scope := ""
var _paused := false
var _fade: Tween
var _ui_index := 0
var _shutting_down := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_music = AudioStreamPlayer.new()
	_voice = AudioStreamPlayer.new()
	_music.name = "Music"
	_voice.name = "FleetRadio"
	add_child(_music)
	_music_players.append(_music)
	var alternate:=AudioStreamPlayer.new();alternate.name="MusicAlternate";add_child(alternate);_music_players.append(alternate)
	add_child(_voice)
	_voice.finished.connect(_voice_finished)
	for i in range(4):
		var player := AudioStreamPlayer.new()
		player.name = "Interface%d" % i
		add_child(player)
		_ui_players.append(player)
	if FileAccess.file_exists("res://data/audio.json"):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/audio.json"))
		if parsed is Dictionary:
			ledger = parsed
	if FileAccess.file_exists(settings_path):
		var saved: Variant = JSON.parse_string(FileAccess.get_file_as_string(settings_path))
		if saved is Dictionary:
			music_volume = clampf(float(saved.get("music", music_volume)), 0, 1)
			voice_volume = clampf(float(saved.get("voice", voice_volume)), 0, 1)
			ui_volume = clampf(float(saved.get("ui", ui_volume)), 0, 1)
			enabled = bool(saved.get("enabled", true))
			voices_enabled = bool(saved.get("voices_enabled", true))
	_sync_volumes()


func set_scene(scene: String) -> void:
	if _shutting_down:
		return
	current_scene = scene
	var resolved:String=scene
	if scene=="salvage":resolved="story"
	if scene in ["harbor","formation","shop","recruit"]:
		var now:Dictionary=time_provider.call() if time_provider.is_valid() else Time.get_datetime_dict_from_system()
		var hour:int=int(now.get("hour",12))
		resolved="harbor_night" if hour<6 or hour>=18 else "harbor_day"
	var selected := ""
	var loop:bool=true
	var loop_start:=0.0
	for row in ledger.get("music", []):
		if str(row.get("scene", "")) == resolved:
			selected = str(row.get("path", ""))
			loop=bool(row.get("loop",true))
			loop_start=float(row.get("loop_start_seconds",0.0))
			break
	if selected == current_music_path:
		return
	var stream := _load_stream(selected)
	if stream == null:
		return
	current_music_path = selected
	if stream is AudioStreamOggVorbis:
		stream.loop=loop
		stream.loop_offset=loop_start
	var incoming:int=0 if _gains[0]<=_gains[1] else 1
	_music=_music_players[incoming];_music.stop()
	_music.stream = stream
	_music.volume_db = -60
	if enabled:
		_music.play()
		_music.stream_paused = _paused
	_fade_from=_gains.duplicate();_fade_to=[0.0,0.0];_fade_to[incoming]=1.0
	_crossfade_elapsed=0;_crossfading=true
	scene_changed.emit(scene, selected)

func set_dialogue_active(active:bool)->void:
	_dialogue_active=active;_refresh_duck()

func _process(delta:float)->void:
	if _shutting_down:return
	_time_poll+=delta
	if _time_poll>=30:
		_time_poll=0
		if current_scene in ["harbor","formation","shop","recruit"]:set_scene(current_scene)
	if _crossfading:
		_crossfade_elapsed+=delta;var progress:float=clampf(_crossfade_elapsed/maxf(.05,crossfade_seconds),0,1)
		for i in 2:_gains[i]=sqrt(lerpf(_fade_from[i]*_fade_from[i],_fade_to[i]*_fade_to[i],progress))
		if progress>=1:
			_crossfading=false
			for i in 2:
				if _gains[i]<=.0001:_music_players[i].stop();_music_players[i].stream=null
	var smoothing:float=1-exp(-delta/(.06 if _duck_target<_duck_gain else .32))
	_duck_gain=lerpf(_duck_gain,_duck_target,smoothing)
	_apply_music_gain()

func _apply_music_gain()->void:
	for i in _music_players.size():
		var gain:float=music_volume*_gains[i]*_duck_gain if enabled else 0.0
		_music_players[i].volume_db=linear_to_db(gain) if gain>.0001 else -80.0

func _refresh_duck()->void:
	_duck_target=.26 if _radio_active or _dialogue_active else 1.0


func ui(cue: String = "tap") -> void:
	if _shutting_down or not enabled or ui_volume <= 0 or _ui_players.is_empty():
		return
	var stream := _load_stream("res://assets/audio/ui/%s.ogg" % cue)
	if stream == null:
		return
	var player: AudioStreamPlayer = _ui_players[_ui_index % _ui_players.size()]
	_ui_index += 1
	player.stream = stream
	player.volume_db = linear_to_db(maxf(0.0001, ui_volume))
	player.play()


func configure(music: float, voice: float, interface_volume: float, audio_enabled: bool = true, radio_enabled: bool = true) -> void:
	if _shutting_down:
		return
	var was_enabled:bool=enabled
	music_volume = clampf(music, 0, 1)
	voice_volume = clampf(voice, 0, 1)
	ui_volume = clampf(interface_volume, 0, 1)
	enabled = audio_enabled
	voices_enabled = radio_enabled
	var file := FileAccess.open(settings_path, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify({"music": music_volume, "voice": voice_volume, "ui": ui_volume, "enabled": enabled, "voices_enabled": voices_enabled}))
	_sync_volumes()
	if not enabled:
		for player in _music_players:player.stop()
		_voice.stop()
		_queue.clear()
	elif not was_enabled and _music.stream and not _music.playing:
		_music.play()
	if not voices_enabled:
		_voice.stop()
		_queue.clear()
		_duck(false)


func set_paused(value: bool) -> void:
	_paused = value
	if _music:
		for player in _music_players:player.stream_paused=value
	if _voice:
		_voice.stream_paused = value
	if not value:
		_pump()


func set_session(scope: String, seat: String = "allies") -> void:
	if _scope == scope and side == seat:
		return
	_scope = scope
	side = seat
	_seen.clear()
	_cooldowns.clear()
	_queue.clear()
	if _voice:
		_voice.stop()
	_duck(false)


func ingest_events(events: Array, ships: Array = [], contacts: Array = [], live: bool = true, tick: int = -1) -> void:
	if _shutting_down or not live or not enabled or not voices_enabled or _paused:
		return
	for item in events:
		if not item is Dictionary:
			continue
		var event: Dictionary = item
		var key := str(event.get("id", "%s:%s:%s" % [event.get("tick", 0), event.get("kind", ""), event.get("text", "")]))
		if _seen.has(key):
			continue
		_seen[key] = true
		if tick >= 0 and tick - int(event.get("tick", tick)) > 4:
			continue
		var cue := str(event.get("voiceCue", event.get("voice_cue", "")))
		# CAS adds seat-relative suffixes after detecting a torpedo. They are
		# variants of one warning cue, not separate unregistered voice events.
		if cue.begins_with("torpedo_warning_"):
			cue = "torpedo_warning"
		var text := str(event.get("text", ""))
		if cue in ["", "<null>"] and str(event.get("kind", "")) == "critical":
			if "火灾" in text or "起火" in text:
				cue = "fire"
			elif "进水" in text or "主炮" in text or "损管" in text:
				cue = "damage"
		if cue in ["", "<null>"]:
			continue
		var now := Time.get_ticks_msec()
		if now - int(_cooldowns.get(cue, -12000)) < 12000:
			continue
		var variant := _variant(event, ships, contacts, cue)
		var path := _voice_path(cue, variant)
		if path.is_empty():
			continue
		_cooldowns[cue] = now
		if _queue.size() < 3:
			_queue.append({"cue": cue, "path": path, "time": now})
	_pump()


func _variant(event: Dictionary, ships: Array, contacts: Array, resolved_cue: String = "") -> String:
	var cue := resolved_cue if not resolved_cue.is_empty() else str(event.get("voiceCue", event.get("voice_cue", "")))
	var text := str(event.get("text", ""))
	if cue == "torpedo_warning":
		var native_cue := str(event.get("voiceCue", event.get("voice_cue", "")))
		if native_cue in ["torpedo_warning_back","torpedo_warning_right","torpedo_warning_left"]:
			return str({"torpedo_warning_back":"astern","torpedo_warning_right":"starboard","torpedo_warning_left":"port"}[native_cue])
		if not event.has("x") or not event.has("y") or ships.is_empty():
			return "unknown-direction"
		var closest: Dictionary = {}
		var distance := INF
		for ship in ships:
			var d := Vector2(float(event.x) - float(ship.get("x", 0)), float(event.y) - float(ship.get("y", 0))).length_squared()
			if d < distance:
				distance = d
				closest = ship
		var bearing := fposmod(rad_to_deg(atan2(float(event.x) - float(closest.get("x", 0)), float(event.y) - float(closest.get("y", 0)))) - float(closest.get("heading", 0)), 360)
		return "front" if bearing < 45 or bearing >= 315 else ("starboard" if bearing < 135 else ("astern" if bearing < 225 else "port"))
	if cue == "contact" and not contacts.is_empty() and event.has("x") and event.has("y"):
		var closest_kind := ""
		var distance := INF
		for contact in contacts:
			var d := Vector2(float(event.x) - float(contact.get("x", 0)), float(event.y) - float(contact.get("y", 0))).length_squared()
			if d < distance:
				distance = d
				closest_kind = str(contact.get("kind", "")).to_lower()
		return str({"dd":"dd", "cl":"cl", "ca":"cl", "cb":"cl", "bb":"bb", "bc":"bb", "cv":"cv"}.get(closest_kind, ""))
	if cue == "damage" or (cue != "fire" and str(event.get("kind", "")) == "critical"):
		if "主炮" in text:
			return "turret"
		if "进水" in text or "水线" in text:
			return "flood"
		if "中雷" in text or "鱼雷" in text:
			return "torpedo"
		return "gun"
	if cue == "fire":
		return "damage" if "起火" in text or "火灾" in text else "open"
	return ""


func _voice_path(cue: String, variant: String) -> String:
	if variant == "unknown-direction":
		return ""
	var exact: Array[String] = []
	var generic: Array[String] = []
	for row in ledger.get("voices", []):
		if str(row.get("seat", "")) != side or str(row.get("event", "")) != cue:
			continue
		var path := str(row.get("path", ""))
		var row_variant := str(row.get("variant", "")) if row.get("variant") != null else ""
		if row_variant == variant:
			exact.append(path)
		elif row_variant.is_empty():
			generic.append(path)
	var choices: Array[String] = exact if not exact.is_empty() else generic
	if choices.is_empty():
		return ""
	var index := 0
	if choices.size() > 1:
		index = int(Time.get_ticks_msec() % choices.size())
		if choices[index] == last_voice_path:
			index = (index + 1) % choices.size()
	return choices[index]


func _pump() -> void:
	if _shutting_down or _voice == null or _voice.playing or _paused or not enabled or not voices_enabled:
		return
	while not _queue.is_empty():
		var item: Dictionary = _queue.pop_front()
		if Time.get_ticks_msec() - int(item.time) > 10000:
			continue
		var stream := _load_stream(str(item.path))
		if stream == null:
			continue
		_voice.stream = stream
		_voice.volume_db = linear_to_db(maxf(0.0001, voice_volume))
		last_voice_path = str(item.path)
		last_voice_cue = str(item.cue)
		_duck(true)
		_voice.play()
		voice_started.emit(last_voice_cue, last_voice_path)
		return
	_duck(false)


func _voice_finished() -> void:
	_pump()


func _duck(active: bool) -> void:
	if _shutting_down or not _music:
		return
	_radio_active=active;_refresh_duck()


func _sync_volumes() -> void:
	if _music:
		_apply_music_gain()
	if _voice:
		_voice.volume_db = linear_to_db(maxf(0.0001, voice_volume))


func _load_stream(path: String) -> AudioStream:
	if path.is_empty() or not ResourceLoader.exists(path):
		return null
	return load(path) as AudioStream


func shutdown() -> void:
	if _shutting_down:
		return
	_shutting_down = true
	enabled = false
	voices_enabled = false
	_queue.clear()
	_seen.clear()
	_cooldowns.clear()
	if _fade and _fade.is_valid():
		_fade.kill()
	_fade = null
	for player in _music_players + [_voice] + _ui_players:
		if is_instance_valid(player):
			player.stop()
			player.stream = null
	# Audio playback references are released on the mixer thread. During final
	# tree teardown there is no next frame to await; give that thread one buffer
	# interval before the engine destroys its resource registry. Close only.
	OS.delay_msec(100)


func _exit_tree() -> void:
	shutdown()
