extends SceneTree
## Isolated client account. All three clears come from actual native commands; no result/HP fixtures.
const Main=preload("res://scenes/main.tscn")
const Economy=preload("res://scripts/economy.gd")
const Content=preload("res://scripts/chapter_story_data.gd")
const Chapter=preload("res://scripts/chapter_presentation.gd")
var app
var checks:=0
var failures:Array[String]=[]
var battles:Array[Dictionary]=[]
var output:="res://../artifacts/godot/chapter-one/"
var completed:=false
func _initialize()->void:call_deferred("run")
func check(value:bool,title:String)->bool:
	checks+=1
	if not value:failures.append(title);push_error(title)
	return value
func command(value:Dictionary)->bool:
	var result:Dictionary=app.issue(value)
	return check(bool(result.get("ok",false)),"actual command "+JSON.stringify(value))
func read_until(target:String)->bool:
	for i in range(80):
		var state:Dictionary=app.progression.chapter_status()
		if str(state.node)==target:return true
		var node:Dictionary=Content.scene(str(state.node))
		if str(node.kind)=="guide":app.progression.chapter_move("guide_skip")
		elif str(node.kind)=="dialogue":
			app.progression.chapter_move("skip")
			if not node.get("choices",[]).is_empty():app.progression.chapter_move("choice",str(node.choices[0].id))
			else:app.progression.chapter_move("next")
		else:return check(false,"cannot read past unresolved native gate "+str(state.node))
	return check(false,"narrative advance bounded")
func launch(stage:String)->bool:
	app.show_page("chapter")
	await process_frame
	var found:Button
	for node in app.find_children("*","Button",true,false):
		if node.is_visible_in_tree() and str(node.get_meta("chapter_launch",""))==stage:found=node
	if not check(found!=null and not found.disabled,"chapter UI launch "+stage):return false
	found.pressed.emit();await process_frame
	return check(app.screen=="battle" and str(app.run.get("mode",""))=="story_chapter" and str(app.core.view.get("chapter",{}).get("stageId",""))==stage,"actual native chapter launch "+stage)
func step(seconds:int)->bool:
	var remaining:=seconds
	while remaining>0 and app.core.view.get("result")==null:
		var amount:=mini(180,remaining)
		if not command({"op":"step","seconds":amount}):return false
		remaining-=amount
	return true
func context_action(kind:String,id:int)->bool:
	var data:Dictionary={}
	if kind=="exit":data=app.core.view.salvage.exits[id].duplicate(true);data["index"]=id
	else:
		for row in app.core.view.salvage.ruins:
			if int(row.id)==id:data=row.duplicate(true)
	app.select_object(kind,data);await process_frame
	var target:Button
	var title:="开始撤离" if kind=="exit" else "打捞残骸"
	for node in app.find_children("*","Button",true,false):
		if node.is_visible_in_tree() and node.text==title:target=node
	if not check(target!=null and not target.disabled,"actual battlefield context button "+title):return false
	target.pressed.emit()
	return check(app.core.view.salvage.get("extracting" if kind=="exit" else "collecting") is Dictionary,"context button starts actual native operation "+title)
func settle(stage:String,next:String,origins:int)->bool:
	var view:Dictionary=app.core.view
	if not check(view.get("result") is Dictionary and view.result.winner=="allies" and bool(view.result.primary) and view.chapter.status=="won","real terminal victory "+stage):
		var diagnostic:=FileAccess.open(output+"failed-native-view.json",FileAccess.WRITE);diagnostic.store_string(JSON.stringify(view,"\t"));diagnostic.close()
		return false
	var saved:Dictionary=app.core.request({"op":"save","serialized":true})
	var before:=int(app.economy.wallet().origins)
	var first_clear:bool=not app.progression.chapter_status().claimed.has(stage)
	battles.append({"stage":stage,"tick":int(view.tick),"events":view.chapter.events.duplicate(),"result":view.result.duplicate(true),"seed":6109})
	app.finish_battle()
	check(app.screen=="result" and app.last_receipt.mode=="story_chapter" and app.last_receipt.success,"client result remains chapter "+stage)
	check(app.progression.chapter_status().node==next and app.progression.chapter_status().cleared.has(stage),"only native win advances story "+stage)
	check(int(app.economy.wallet().origins)==before+origins and int(app.last_receipt.stars)==0,"exact first chapter award and no historical stars "+stage)
	check(int(app.last_receipt.rewards.get("commander_xp",0))==(150 if first_clear else 0) and bool(app.economy.state.commander.claims.get("chapter:"+stage,false)),"only first real chapter victory grants 150 commander experience "+stage)
	var wallet:Dictionary=app.economy.wallet().duplicate(true)
	var commander:Dictionary=app.economy.state.commander.duplicate(true)
	var duplicate:Dictionary=app.progression.finish_mode(view,str(saved.serialized))
	check(duplicate.ok and duplicate.get("duplicate",false) and app.economy.wallet()==wallet,"duplicate native result cannot regrant "+stage)
	check(app.economy.state.commander==commander,"duplicate native result cannot regrant commander experience "+stage)
	return true
func run()->void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	var path:="user://tests/chapter-integration-%d.json"%OS.get_process_id()
	OS.set_environment("CAS_SIM_PATH",ProjectSettings.globalize_path("res://../target/release/cas-sim.exe"))
	app=Main.instantiate();app.boot_to_title=false;app.economy=Economy.new(path);root.add_child(app);app.set_process(false)
	await process_frame
	await exercise(path)
	check(completed,"complete first chapter through actual three missions")
	app.audio.shutdown();app.core.close();app.queue_free();await process_frame
	for suffix in ["",".bak",".tmp"]:
		if FileAccess.file_exists(path+suffix):DirAccess.remove_absolute(ProjectSettings.globalize_path(path+suffix))
	var report:={"checks":checks,"passed":checks-failures.size(),"failures":failures,"battles":battles,"scope":"actual UI/native/client account chain; no fake battle results, HP, chapter unlocks or rewards"}
	var file:=FileAccess.open(output+"integration-receipt.json",FileAccess.WRITE);file.store_string(JSON.stringify(report,"\t"));file.close()
	print(JSON.stringify(report));quit(0 if failures.is_empty() else 1)
func exercise(path:String)->void:
	var wallet:Dictionary=app.economy.wallet().duplicate(true)
	var owned:Dictionary=app.economy.state.owned.duplicate(true)
	var history:Dictionary=app.progression.data().campaign.duplicate(true)
	var old_story:Dictionary=app.progression.data().story.duplicate(true)
	if not check(read_until("breakout"),"first narrative leads to breakout"):return
	if not await launch("c1-breakout"):return
	check(app.economy.wallet()==wallet and app.economy.state.owned==owned,"borrowed chapter deploy costs no private wallet or hull condition")
	check(app.core.view.ships.size()==5,"fixed fifth destroyer squad has five real hulls")
	var initial:Dictionary=app.core.request({"op":"save","serialized":true})
	check(not app.progression.finish_mode(app.core.view,str(initial.serialized)).ok,"active mission cannot manufacture an early chapter clear")
	check(not app.progression.chapter_move("skip").ok and not app.progression.chapter_prepare("c1-boss").ok,"active world blocks dialogue bypass and future boss launch")
	if not command({"op":"salvage_abandon"}):return
	check(app.core.view.chapter.status=="lost" and not bool(app.core.view.result.primary),"actual retreat returns native chapter loss")
	app.finish_battle()
	check(not app.last_receipt.success and app.progression.chapter_status().node=="breakout" and app.progression.chapter_status().cleared.is_empty() and app.economy.wallet()==wallet,"lost mission gives no reward or narrative advance")
	if not await launch("c1-breakout"):return
	if not command({"op":"route","fleet":1,"mode":"follow","speed":20,"points":[{"x":7400,"y":1200},{"x":7400,"y":2200}]}):return
	if not step(360):return
	var tick:=int(app.core.view.tick)
	var session:=str(app.run.run_id)
	app.save_leave();app.core.close()
	check(app.screen=="story_route" and str(app.economy.state.active_run.run_id)==session,"save and leave returns to chapter route and retains frozen session")
	var disk=Economy.new(path)
	check(disk.load_state().ok and str(disk.state.active_run.mode)=="story_chapter" and str(disk.state.progression.chapter1.node)=="breakout","chapter and active native snapshot survive account reload")
	app.resume_run();await process_frame
	check(app.screen=="battle" and int(app.core.view.tick)==tick and str(app.run.run_id)==session,"process restart resumes exact chapter tick and identity")
	if not step(440):return
	if not await context_action("exit",0) or not step(12):return
	if not settle("c1-breakout","silence",40):return
	check(app.progression.chapter_status().evidence.get("aversion_spared_flagship",false) and app.progression.chapter_status().evidence.get("beacon_reached",false),"immunity clue and beacon are actual native events")
	if not check(read_until("salvage"),"hearing and optional guide lead to salvage") or not await launch("c1-salvage"):return
	check(not app.core.request({"op":"salvage_extract","exit":0}).ok,"archive cannot be skipped by extracting early")
	if not command({"op":"route","fleet":1,"mode":"follow","speed":20,"points":[{"x":7600,"y":2200}]}):return
	if not step(700):return
	if not await context_action("ruin",1) or not step(8):return
	if not app.core.view.chapter.events.has("archive_recovered"):
		if not await context_action("ruin",1) or not step(8):return
	check(app.core.view.chapter.events.has("archive_recovered"),"archive recovered by actual timed collection")
	if not await context_action("exit",0) or not step(12):return
	if not settle("c1-salvage","archive",60):return
	if not check(read_until("boss"),"recovered archive and antagonist dialogue lead to boss") or not await launch("c1-boss"):return
	if not command({"op":"route","fleet":1,"mode":"follow","speed":24,"points":[{"x":8000,"y":1200}]}):return
	if not step(900):return
	if not settle("c1-boss","afterboss",100):return
	check(app.progression.chapter_status().evidence.get("boss_defeated",false) and app.progression.chapter_status().evidence.get("gatekeepers_control_link",false),"boss death and control-link clue come from actual phases")
	if not check(read_until("complete"),"post-boss story reaches chapter ending"):return
	check(app.progression.chapter_status().cleared.size()==3 and app.progression.chapter_status().claimed.size()==3,"exactly three native clears and first rewards")
	check(int(app.economy.wallet().origins)==int(wallet.origins)+200 and int(app.economy.wallet().credits)==int(wallet.credits)+1000 and int(app.economy.wallet().materials)==int(wallet.materials)+20,"chapter total 200 origins 1000 silver 20 materials")
	check(app.economy.state.owned==owned and app.progression.data().campaign==history and app.progression.data().story==old_story,"chapter leaves personal roster historical stars and legacy prologue intact")
	var before_replay:Dictionary=app.progression.chapter_status()
	var before_wallet:Dictionary=app.economy.wallet()
	app.set_meta("chapter_replay_node","hearing");app.set_meta("chapter_replay_line",0);app.show_page("chapter")
	Chapter._skip(app,Content.scene("hearing"),"hearing")
	check(app.progression.chapter_status()==before_replay and app.economy.wallet()==before_wallet,"dialogue replay cannot rewind real progress or grant rewards")
	# Cleared battle replay remains a real battle and cannot re-award its first-clear grant.
	Chapter.launch_stage(app,"c1-breakout")
	check(app.screen=="battle","cleared mission replay creates a real world")
	if not command({"op":"route","fleet":1,"mode":"follow","speed":20,"points":[{"x":7400,"y":1200},{"x":7400,"y":2200}]}) or not step(800):return
	if not command({"op":"salvage_extract","exit":0}) or not step(12):return
	if not settle("c1-breakout","complete",0):return
	check(app.economy.wallet()==before_wallet,"real repeated victory has no duplicate first reward")
	completed=true
