extends SceneTree
## Compare complete wire lines against the original reader, including large UTF-8.
var checks:int=0
var failures:Array[String]=[]
var output:String="res://../artifacts/island-war-v2/presentation/"
var bridge
var oracle:Dictionary={}
var compared:int=0
var bytes:int=0
func _initialize()->void:call_deferred("run")
func check(value:bool,message:String)->void:
	checks+=1
	if not value:failures.append(message);push_error(message)
func compare(command:Dictionary)->Dictionary:
	var packet:String=JSON.stringify(command)+"\n"
	oracle.stdio.store_string(packet);oracle.stdio.flush()
	bridge.process.stdio.store_string(packet);bridge.process.stdio.flush()
	var old:String=oracle.stdio.get_line();var current:String=bridge._read_response_line(bridge.process.stdio)
	check(old==current,"complete wire response remains exact for "+str(command.get("op","")))
	compared+=1;bytes+=old.to_utf8_buffer().size()
	var parsed:Variant=JSON.parse_string(current)
	check(parsed is Dictionary,"wire line remains complete JSON")
	return parsed if parsed is Dictionary else {}
func close_process(process:Dictionary)->void:
	if process.is_empty():return
	process.stdio.close()
	if OS.is_process_running(int(process.pid)):OS.kill(int(process.pid))
func run()->void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	bridge=load("res://scripts/core_bridge.gd").new();check(bridge.start(),"candidate native process starts")
	oracle=OS.execute_with_pipe(OS.get_environment("CAS_SIM_PATH"),[],true)
	check(not oracle.is_empty(),"independent original-line-reader oracle starts")
	if oracle.is_empty():finish();return
	for request in [{"op":"new","seed":714},{"op":"observe"},{"op":"presentation"},{"op":"probe-中文-😀"}]:compare(request)
	for index in range(8):compare({"op":"step","seconds":.1})
	var saved:Dictionary=compare({"op":"save","serialized":true})
	if saved.has("serialized"):compare({"op":"load","serialized":saved.serialized})
	var legacy:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://../artifacts/littoral-v4/defense-fifty-air-request.json"))
	check(compare(legacy).get("ok",false),"unchanged v4 fifty-body native fixture opens")
	for index in range(8):compare({"op":"step","seconds":.1})
	var fixture:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://../artifacts/island-war-v2/core/performance-midbattle.json"))
	check(compare(fixture.initial_request).get("ok",false),"v2 large-body native fixture opens")
	check(compare({"op":"load","serialized":fixture.serialized}).get("ok",false),"actual large native snapshot loads")
	for index in range(24):compare({"op":"step","seconds":.1})
	saved=compare({"op":"save","serialized":true})
	if saved.has("serialized"):compare({"op":"load","serialized":saved.serialized})
	close_process(oracle);oracle={};bridge.close()
	check(bridge.response_buffer.is_empty(),"closing the process clears buffered response bytes")
	# Native pipes can split inside an emoji or return two lines in one read.
	var python:String=OS.get_environment("CAS_TEST_PYTHON")
	if FileAccess.file_exists(python):
		var code:String="import sys,time\nsys.stdin.readline()\nb=('{\"text\":\"'+('雨猫😀'*35000)+'\"}\\n{\"second\":true}\\n').encode('utf-8')\nfor n in [1,2,3,65533]:\n sys.stdout.buffer.write(b[:n]);sys.stdout.buffer.flush();b=b[n:];time.sleep(.002)\nsys.stdout.buffer.write(b);sys.stdout.buffer.flush()\nsys.stdin.readline()\nsys.stdout.buffer.write(b'{\"after\":42}\\n');sys.stdout.buffer.flush()\n"
		var helper:String=ProjectSettings.globalize_path(output+"fragmented-pipe-fixture.py")
		FileAccess.open(helper,FileAccess.WRITE).store_string(code)
		var fragmented:Dictionary=OS.execute_with_pipe(python,[helper],true)
		fragmented.stdio.store_string("go\n");fragmented.stdio.flush()
		var first:Variant=JSON.parse_string(bridge._read_response_line(fragmented.stdio))
		check(first is Dictionary and first.get("text","")=="雨猫😀".repeat(35000),"chunk splits preserve every UTF-8 character in a large JSON line")
		check(JSON.parse_string(bridge._read_response_line(fragmented.stdio))=={"second":true},"a following response is retained exactly once")
		fragmented.stdio.store_string("next\n");fragmented.stdio.flush()
		check(bridge._read_response_line(fragmented.stdio)=="{\"after\":42}","next request cannot read stale bytes from the previous response")
		close_process(fragmented)
	else:check(false,"Python pipe-fragment fixture runtime is configured")
	finish()
func finish()->void:
	close_process(oracle)
	if bridge!=null:bridge.close()
	var receipt:Dictionary={"ok":failures.is_empty(),"checks":checks,"failures":failures,"exact_wire_responses":compared,"exact_wire_bytes":bytes,"native_sha256":FileAccess.get_sha256(OS.get_environment("CAS_SIM_PATH"))}
	FileAccess.open(output+"pipe-reader-receipt.json",FileAccess.WRITE).store_string(JSON.stringify(receipt,"\t"));print(JSON.stringify(receipt));quit(0 if failures.is_empty() else 1)
