extends SceneTree
const Core=preload("res://scripts/core_bridge.gd")
const Audio=preload("res://scripts/audio_director.gd")
var played:Array=[]
func _initialize() -> void:call_deferred("_run")
func _run() -> void:
	var core=Core.new()
	var radio=Audio.new();root.add_child(radio)
	radio.enabled=true;radio.voices_enabled=true;radio.set_session("native-radio-audit","allies")
	radio.voice_started.connect(func(cue:String,path:String):played.append({"cue":cue,"path":path}))
	var events:Array=[]
	var found:Dictionary={}
	var initialized:Dictionary=core.request({"op":"new","variant":"night","seed":6106,"side":"allies","enemy":"torpedo","profile":"coord","realtime":true})
	if initialized.get("ok",false):
		for fleet in core.view.get("fleets",[]):core.request({"op":"ai","fleet":int(fleet.id),"mode":"auto","profile":"coord","move":true,"gun":true,"torpedo":true})
		for tick in range(1600):
			core.request({"op":"step","seconds":1})
			for event in core.view.get("events",[]):
				var cue:=str(event.get("voiceCue",""))
				if cue.begins_with("torpedo_warning_"):cue="torpedo_warning"
				if cue in ["contact","torpedo_warning"] and not found.has(cue):
					found[cue]=event.duplicate(true)
					# Stop the previous test line to audit both real native cues
					# immediately, without a long voice queue masking the second.
					radio._voice.stop();radio._queue.clear()
					radio.ingest_events([event],core.view.get("ships",[]),core.view.get("contacts",[]),true,int(core.view.tick))
					events.append({"event":event.duplicate(true),"voice_playing":radio._voice.playing,"voice_path":radio.last_voice_path})
			if found.size()==2 or core.view.get("result")!=null:break
	var success:=found.has("contact") and found.has("torpedo_warning") and played.size()==2 and events.all(func(row):return bool(row.voice_playing))
	radio.shutdown();core.close();radio.queue_free();await process_frame
	var report:={"ok":success,"observed_native_cues":found.keys(),"playback":played,"native_events":events,"scope":"real native night exercise seat-visible events; same ingest signature as battle UI; no synthetic cue injection"}
	var file:=FileAccess.open("res://../artifacts/godot/full-modes/native-radio.json",FileAccess.WRITE)
	if file:file.store_string(JSON.stringify(report,"\t"));file.close()
	print(JSON.stringify(report));quit(0 if success else 1)
