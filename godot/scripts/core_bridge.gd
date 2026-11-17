class_name CasCoreBridge
extends RefCounted
## Persistent local Rust process; never exposes host authority to the UI.
var process: Dictionary = {}
var view: Dictionary = {}
var error: String = ""
var presentation_supported := true
var observation_epoch := 0
var response_buffer:PackedByteArray=PackedByteArray()
var coastal_geography_cache:Dictionary={}

func start() -> bool:
	if not process.is_empty():
		return true
	# Versioned runtime copies remain replaceable while another game uses an older exe.
	var candidates := [ProjectSettings.globalize_path("res://../target/release/cas-sim.exe"), ProjectSettings.globalize_path("res://bin/cas-sim.exe")]
	var manifest_path:="res://bin/core-current.json"
	if FileAccess.file_exists(manifest_path):
		var manifest:Variant=JSON.parse_string(FileAccess.get_file_as_string(manifest_path))
		if manifest is Dictionary:
			var relative:=str(manifest.get("executable",""))
			if relative.begins_with("runtime/") and not relative.contains(".."):
				var installed:=ProjectSettings.globalize_path("res://bin/"+relative)
				if FileAccess.file_exists(installed) and FileAccess.get_sha256(installed)==str(manifest.get("sha256","")):
					candidates.push_front(installed)
	if OS.has_environment("CAS_SIM_PATH"):
		candidates.push_front(OS.get_environment("CAS_SIM_PATH"))
	for path in candidates:
		if FileAccess.file_exists(path):
			process = OS.execute_with_pipe(path, [], true)
			if not process.is_empty():
				return true
	error = "战斗核心尚未就绪，请使用项目启动器构建后重试。"
	return false

func request(command: Dictionary) -> Dictionary:
	if not start():
		return {"ok": false, "error": error}
	if not OS.is_process_running(int(process.pid)):
		error = "战斗核心已退出，已保留航次存档。请重新启动并继续航次。"
		return {"ok": false, "error": error}
	var pipe: FileAccess = process.stdio
	pipe.store_string(JSON.stringify(command) + "\n")
	pipe.flush()
	var response: Variant = JSON.parse_string(_read_response_line(pipe))
	if not response is Dictionary:
		error = "战斗核心响应无法读取。"
		return {"ok": false, "error": error}
	if response.get("ok", false) and response.get("data") is Dictionary and response.data.has("ships") and response.data.has("contacts"):
		if str(command.get("op","")) in ["new","new_campaign","new_chapter","new_salvage","new_tide","new_arena","new_littoral","new_island_battle","load","replay"]:
			observation_epoch += 1
		# The original response remains the exact default observation. Only this
		# client's local copy is enriched by an explicitly requested read-only stream.
		view = response.data.duplicate()
		_enrich_coastal_geography()
		if view.get("presentation",{}) is Dictionary and str(view.get("presentation",{}).get("version",""))=="projectile-fx-v1" and view.get("presentation",{}).get("shots") is Array:
			# Explicit combined-arms observations may already contain the exact
			# authorized World stream. Reuse it instead of a second round trip.
			pass
		elif str(view.get("tide",{}).get("version",""))=="cas-event-tide-v2" or str(view.get("littoral",{}).get("version","")) in ["cas-littoral-v1","cas-littoral-v2","cas-littoral-v3"]:
			# This standalone mode publishes its actual projectiles in the observation.
			view["presentation"]={"version":"projectile-fx-v1","tick":view.get("tick",0),"shots":[]}
		elif presentation_supported:
			var fx: Dictionary = request({"op":"presentation"})
			if fx.get("ok",false) and fx.get("data",{}).get("version","") == "projectile-fx-v1":
				view["presentation"] = fx.data
			else:
				presentation_supported = false
	return response

func _enrich_coastal_geography()->void:
	var land:Dictionary=view.get("littoral",{}).get("land",{})
	var header:Dictionary=land.get("geography",{})
	if str(header.get("version",""))!="cas-coastal-geography-v1":return
	var key:String=str(header.get("geometry_hash",header.get("hash","")))
	if key.is_empty():return
	if not coastal_geography_cache.has(key):
		var response:Dictionary=request({"op":"geography_snapshot"})
		if not response.get("ok",false):return
		var snapshot:Dictionary=response.get("data",{})
		var full:Dictionary=snapshot.get("land",{}).get("geography",{})
		if str(full.get("geometry_hash",full.get("header",{}).get("geometry_hash",full.get("hash",""))))!=key or not full.get("heightfield",{}).has("heights"):return
		# Retain the current island only. Save/replay owns its validated geometry;
		# the client cache is disposable and never changes a command or raw reply.
		coastal_geography_cache.clear();coastal_geography_cache[key]=full
	var local_littoral:Dictionary=view.get("littoral",{}).duplicate()
	var local_land:Dictionary=land.duplicate()
	local_land["geography"]=coastal_geography_cache[key]
	local_littoral["land"]=local_land;view["littoral"]=local_littoral

func _read_response_line(pipe:FileAccess)->String:
	# Pipe get_length is the available byte count. Reading ready chunks avoids
	# get_line's byte-at-a-time Windows reads for large body observations. Keep
	# UTF-8 intact across chunks and retain any following response for its caller.
	var scanned:int=0
	while true:
		var end:int=response_buffer.find(10,scanned)
		if end>=0:
			var line:String=response_buffer.slice(0,end).get_string_from_utf8()
			response_buffer=response_buffer.slice(end+1)
			return line.trim_suffix("\r")
		scanned=response_buffer.size()
		var available:int=int(pipe.get_length())
		var chunk:PackedByteArray=pipe.get_buffer(mini(available,65536) if available>0 else 1)
		if chunk.is_empty():
			response_buffer.clear()
			return ""
		response_buffer.append_array(chunk)
	return ""

func close() -> void:
	if not process.is_empty():
		var pipe: FileAccess = process.stdio
		pipe.close()
		if OS.is_process_running(int(process.pid)):
			OS.kill(int(process.pid))
		process = {}
		response_buffer.clear()
		presentation_supported = true
		observation_epoch += 1
		coastal_geography_cache.clear()
