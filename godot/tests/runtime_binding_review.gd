extends SceneTree
## Default editor/runtime resolution, actual production new/resume and old-snapshot boundary.
const Bridge=preload("res://scripts/core_bridge.gd")
const Settle=preload("res://tests/transition_settle.gd")
var checks:int=0
var failures:Array[String]=[]
func _initialize()->void:call_deferred("run")
func check(ok:bool,title:String)->void:
	checks+=1
	if not ok:failures.append(title);push_error(title)
func run()->void:
	check(not OS.has_environment("CAS_SIM_PATH"),"no environment override in default F5/runtime test")
	var manifest:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://bin/core-current.json"))
	check(manifest.version==1 and FileAccess.get_sha256("res://bin/"+str(manifest.executable))==manifest.sha256,"installed versioned runtime matches manifest")
	var app=load("res://scenes/main.tscn").instantiate()
	app.boot_to_title=false
	app.economy=load("res://scripts/economy.gd").new("user://tests/runtime-binding-%d.json"%OS.get_process_id())
	root.add_child(app);app.set_process(false);await process_frame;await process_frame
	app.page_motion=false;app.set_meta("next_sortie_seed",40)
	var before:int=int(app.economy.wallet().stamina)
	app.show_page("expedition");await Settle.wait_for_route(self,app)
	app.launch(false,{"kind":"salvage","id":"calm"});await Settle.wait_for_route(self,app)
	check(app.screen=="battle","production new expedition opens battle using default runtime")
	check(app.core.view.get("salvage",{}).get("adventure",{}).get("version")=="cas-adventure-v2","default runtime is new extraction-capable core")
	check(app.speed==1 and app.running and app.core.view.salvage.expedition.autopilot.get("version","")=="cas-extraction-pilot-v3","new expedition starts authorized autonomous pilot at 1x clock")
	check(int(app.economy.wallet().stamina)==before-8,"production launch spends only actual calm stamina")
	var active:Dictionary=app.economy.state.active_run.duplicate(true)
	check(str(active.get("gameplay_profile",""))=="cas-adventure-v2","account preserves explicit extraction identity")
	var old_hp:float=app.core.view.ships[0].hp
	var response:Dictionary=app.core.request({"op":"step","seconds":2})
	check(response.get("ok",false) and app.core.view.tick==2,"default executable accepts actual simulation steps")
	var before_save:Dictionary=app.core.request({"op":"save","serialized":true})
	app.save_leave();await Settle.wait_for_route(self,app);app.close_modal()
	check(app.screen=="expedition","save returns to invoking expedition route")
	check(app.economy.state.active_run.run_id==active.run_id,"saving preserves one existing voyage")
	app.resume_run();await Settle.wait_for_route(self,app)
	check(app.screen=="battle" and app.speed==1 and app.running and app.core.view.tick==2,"resume preserves saved pilot authorization and exact tick at 1x clock")
	var after_save:Dictionary=app.core.request({"op":"save","serialized":true})
	check(not str(before_save.get("serialized","")).is_empty() and str(before_save.serialized)==str(after_save.get("serialized","")),"save/resume keeps exact serialized native snapshot")
	check(is_equal_approx(float(app.core.view.ships[0].hp),old_hp),"resume did not apply unrequested damage or advance")
	app.core.close();app.queue_free();await process_frame
	var bridge=Bridge.new()
	var legacy:Dictionary=bridge.request({"op":"new_chapter","id":"c1-breakout","seed":6109})
	check(legacy.get("ok",false) and not bridge.view.salvage.has("adventure"),"absent old chapter profile remains original")
	bridge.close()
	var output:="res://../artifacts/godot/runtime-binding/"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	var report:Dictionary={"checks":checks,"failures":failures,"manifest":manifest,"passed":failures.is_empty()}
	FileAccess.open(output+"report.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print(JSON.stringify(report));quit(0 if failures.is_empty() else 1)
