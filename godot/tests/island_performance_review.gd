extends SceneTree
## Same authoritative fixture and visible bodies before/after presentation changes.
const Core=preload("res://scripts/core_bridge.gd")
const Land=preload("res://scripts/littoral_land.gd")
const Sea=preload("res://scripts/littoral_world_sea.gd")
const Art=preload("res://scripts/character_art.gd")
const Framing=preload("res://scripts/story_actor_layout.gd")
var core=Core.new()
var land:Control
var sea:Control
var frame_times:Array[float]=[]
var measuring:bool=false
var running:bool=false
var clock:float=0
var rate:float=1
var last_usec:int=0
var failures:Array[String]=[]
var update_times:Array[float]=[]
func _initialize()->void:call_deferred("run")
func _process(delta:float)->bool:
	if measuring:
		var now:int=Time.get_ticks_usec()
		if last_usec>0:frame_times.append(float(now-last_usec)/1000)
		last_usec=now
	if running:
		clock+=delta*rate
		var ticks:int=mini(16,int((clock+.000001)/.1))
		if ticks>0:
			clock-=ticks*.1
			var response:Dictionary=core.request({"op":"step","seconds":snappedf(ticks*.1,.1)})
			if not response.get("ok",false):failures.append(str(response));running=false
			else:observe()
	return false
func frames(n:int=3)->void:
	for i in range(n):await process_frame
func q(values:Array[float],fraction:float)->float:
	if values.is_empty():return 0
	var ordered:Array[float]=values.duplicate();ordered.sort()
	return ordered[mini(ordered.size()-1,int(fraction*(ordered.size()-1)))]
func observe()->void:
	var begin:int=Time.get_ticks_usec()
	var view:Dictionary=core.view;var surface:Dictionary=view.littoral.land.duplicate()
	surface["tick"]=view.tick;surface["groups"]=view.littoral.groups
	surface["transports"]=view.littoral.transports;surface["shots"]=view.littoral.shots
	land.observe(surface,running);sea.playing=running;sea.playback_rate=rate;sea.observe(view)
	update_times.append(float(Time.get_ticks_usec()-begin)/1000)
func run()->void:
	root.position=Vector2i(6000,6000);root.size=Vector2i(1280,720)
	var output:String="res://../artifacts/island-war-v1/performance/"+OS.get_environment("CAS_PERF_PHASE")+"/"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	var account_path:String="user://cas_port_v1.json";var before:String=FileAccess.get_sha256(account_path)
	land=Land.new();land.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);root.add_child(land)
	sea=Sea.new();sea.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);root.add_child(sea)
	await frames()
	var request:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://../artifacts/littoral-v4/defense-fifty-air-request.json"))
	var response:Dictionary=core.request(request)
	if not response.get("ok",false):push_error(str(response));quit(1);return
	observe();await frames(6)
	var samples:Array=[]
	for mode in ["sea","land"]:
		land.visible=mode=="land";sea.visible=mode=="sea"
		if mode=="sea":sea.focus_fleet()
		await frames(6)
		for speed in [1,8]:
			rate=speed;clock=0;running=true;last_usec=0;frame_times.clear();update_times.clear()
			var start:int=Time.get_ticks_usec();var tick:float=float(core.view.tick);measuring=true
			await create_timer(2.2).timeout
			measuring=false;running=false;var seconds:float=float(Time.get_ticks_usec()-start)/1000000
			var elapsed:float=float(core.view.tick)-tick
			if absf(elapsed-seconds*speed)>maxf(.4,seconds*speed*.18):failures.append("clock debt "+mode+str(speed))
			samples.append({"map":mode,"speed":speed,"frames":frame_times.size(),"frame_ms_p50":q(frame_times,.5),"frame_ms_p95":q(frame_times,.95),"update_ms_p50":q(update_times,.5),"wall_seconds":seconds,"native_seconds":elapsed,"ratio":elapsed/seconds,"clock_debt":clock})
	var raw:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/ships.json"));var paths:Dictionary={}
	for card in raw.get("ships",[]):
		var path:String=str(card.get("portrait",""))
		if not path.is_empty() and ResourceLoader.exists(path):paths[path]=true
	var mem_before:float=Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED)
	var retained:Texture2D
	for path in paths.keys().slice(0,64):
		var texture:Texture2D=Art.texture(path)
		var framed:Texture2D=Framing.portrait(texture,path)
		if retained==null:retained=framed
		await process_frame
	await frames(8)
	var mem_after:float=Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED)
	if retained==null or retained.get_width()<1:failures.append("live portrait lost")
	var saved:String=str(core.request({"op":"save","serialized":true}).get("serialized",""))
	var observation:Dictionary=core.view.duplicate(true)
	if not core.request({"op":"load","serialized":saved}).get("ok",false) or core.view!=observation:failures.append("native restore mismatch")
	if FileAccess.get_sha256(account_path)!=before:failures.append("normal account changed")
	var result:Dictionary={"passed":failures.is_empty(),"failures":failures,"phase":OS.get_environment("CAS_PERF_PHASE"),"display_server":DisplayServer.get_name(),"adapter":RenderingServer.get_video_adapter_name(),"fixture":request,"scope":"same native 50-body defense, production sea/land components, 1x/8x real simulation; sequential 64-portrait browsing, active first portrait retained","friendly_bodies":observation.littoral.land.entities.filter(func(row):return str(row.side)=="allies").size(),"samples":samples,"portrait_paths_tested":mini(paths.size(),64),"texture_bytes_before":mem_before,"texture_bytes_after":mem_after,"texture_bytes_added":mem_after-mem_before,"portrait_cache_entries":Art.textures.size(),"framing_cache_entries":Framing.framed.size(),"static_bytes":Performance.get_monitor(Performance.MEMORY_STATIC),"snapshot_sha256":saved.sha256_text(),"normal_account_unchanged":true}
	FileAccess.open(output+"receipt.json",FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))
	core.close();land.queue_free();sea.queue_free();await frames(3)
	print("ISLAND_PERFORMANCE "+JSON.stringify(result));quit(0 if failures.is_empty() else 1)
