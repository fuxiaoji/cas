extends SceneTree
## Actual user's archived voyage, isolated profile, production UI and real native outcomes.
## Never edit snapshots, world positions, damage, inventory or the normal account.
const Main=preload("res://scenes/main.tscn")
const Economy=preload("res://scripts/economy.gd")
const Bridge=preload("res://scripts/core_bridge.gd")
const Cargo=preload("res://scripts/cargo_presentation.gd")
const Settle=preload("res://tests/transition_settle.gd")
const SOURCE="res://../artifacts/extraction-stall-20261113/actual-account-before.json"
const OUTPUT="res://../artifacts/godot/extraction-actual-save/"
var app
var checks:int=0
var failures:Array[String]=[]
var shots:Array[String]=[]
var paths:Array[String]=[]
var source_hash:String
var original:Dictionary
var raw:String
var report:Dictionary={"synthetic_world_edits":false,"normal_account_accessed":false}
func _initialize()->void:call_deferred("run")
func check(ok:bool,label:String)->bool:
	checks+=1
	if not ok:failures.append(label);push_error(label)
	return ok
func frames()->void:
	await process_frame;await process_frame
func settled()->void:
	await Settle.wait_for_route(self,app);await frames()
func pilot()->Dictionary:return app.core.view.get("salvage",{}).get("expedition",{}).get("autopilot",{})
func native_save()->String:
	var result:Dictionary=app.core.request({"op":"save","serialized":true})
	check(result.get("ok",false),"native serialized save succeeds")
	return str(result.get("serialized",""))
func shot(name:String)->void:
	if DisplayServer.get_name()=="headless":return
	await settled();await RenderingServer.frame_post_draw
	var path:String=ProjectSettings.globalize_path(OUTPUT+name+".png")
	check(root.get_texture().get_image().save_png(path)==OK,"GPU capture "+name);shots.append(path)
func clone_profile(label:String)->String:
	var path:String="user://tests/extraction-actual-%s-%d.json"%[label,OS.get_process_id()]
	var absolute:String=ProjectSettings.globalize_path(path)
	DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
	check(DirAccess.copy_absolute(ProjectSettings.globalize_path(SOURCE),absolute)==OK,"copy read-only archived account into isolated "+label)
	paths.append(path);return path
func client(path:String)->void:
	app=Main.instantiate();app.boot_to_title=false;app.economy=Economy.new(path);root.add_child(app);app.set_process(false)
	await settled();app.page_motion=false
func release()->void:
	if is_instance_valid(app):
		app.audio.shutdown();app.core.close();app.queue_free();await frames()
func windowed()->void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED);app.fullscreen_battle=false;root.size=Vector2i(1280,720);await frames()
func find_button(parent:Node,text:String)->Button:
	for item in parent.find_children("*","Button",true,false):
		if item.text==text and item.is_visible_in_tree() and not item.disabled:return item
	return null
func point(node:Control,local:Vector2)->Vector2:
	return node.get_viewport().get_screen_transform()*node.get_global_transform_with_canvas()*local
func motion(at:Vector2,held:bool=false)->void:
	var event:=InputEventMouseMotion.new();event.position=at;event.button_mask=MOUSE_BUTTON_MASK_LEFT if held else 0;Input.parse_input_event(event);await frames()
func press(at:Vector2,down:bool)->void:
	var event:=InputEventMouseButton.new();event.position=at;event.button_index=MOUSE_BUTTON_LEFT;event.pressed=down;Input.parse_input_event(event);await frames()
func click(button:Button)->bool:
	if not check(is_instance_valid(button),"actual enabled pointer target exists"):return false
	await settled();var at:Vector2=point(button,button.size*.5)
	await motion(at);await press(at,true);await press(at,false);await settled();return true
func operations()->Control:
	return app.page.find_child("ExpeditionOperations",true,false)
func open_board()->Control:
	var ops:Control=operations()
	if not check(ops!=null,"native expedition operations attached"):return null
	await click(ops.get_node("Auto"));return app.modal.find_child("ExpeditionBoard",true,false)
func toggle_auto()->void:
	var board:Control=await open_board()
	if board!=null:await click(board.get_node("Toggle"))
func close_modal()->void:
	await click(find_button(app.modal,"关闭"));await frames()
func open_cargo()->Control:
	var tick:int=int(app.core.view.tick)
	Cargo.open(app);await frames();await create_timer(.08).timeout
	check(not app.running,"opening real cargo organizer pauses simulation")
	app._process(2.0)
	check(int(app.core.view.tick)==tick,"paused cargo organizer does not advance native time")
	return app.modal.get_node("CargoHold")
func cargo_item(panel:Control,id:String)->Button:
	for item in panel.list.find_children("*","Button",true,false):
		if str(item.get_meta("cargo_id",""))==id:return item
	return null
func moved_placement(panel:Control,item:Dictionary)->Array:
	for y in range(int(panel.data.rows)):
		for x in range(int(panel.data.cols)):
			var p:Array=[x,y,int(item.placement[2])]
			var original_cell:=Vector3i(int(item.placement[0]),int(item.placement[1]),int(item.placement[2]))
			if Vector3i(x,y,int(item.placement[2]))!=original_cell and panel.grid.valid_at(item,p):return p
	return []
func summarize(view:Dictionary)->Dictionary:
	# Public ships are already this seat's own ships and have no side field.
	return {"tick":view.get("tick"),"result":view.get("result"),"pilot":view.get("salvage",{}).get("expedition",{}).get("autopilot",{}).duplicate(true),"cargo":view.get("salvage",{}).get("cargo_grid",{}).get("items",[]).size(),"ships":view.get("ships",[]).map(func(s):return {"id":s.id,"x":s.x,"y":s.y,"hp":s.hp})}
func baseline(legacy:bool)->void:
	var core:=Bridge.new()
	var loaded:Dictionary=core.request({"op":"load","serialized":raw})
	check(loaded.get("ok",false),"unmodified original native snapshot loads")
	if not loaded.get("ok",false):core.close();return
	var view:Dictionary=core.view
	check(int(view.tick)==397 and original.active_run.fleet.size()==5 and int(original.active_run.score)==10150,"fixture is exact five-ship 10150-point tick397 voyage")
	var ai:Dictionary=view.salvage.expedition.autopilot
	check(str(ai.version)=="cas-extraction-pilot-v2" and not ai.enabled and str(ai.phase)=="manual","archived v2 pilot was disabled by cargo-only intervention")
	var history:Array=JSON.parse_string(raw).commands
	check(str(history.back().request.op)=="cargo_place" and int(history.back().tick)==397,"last original command proves cargo placement, not explicit automation off")
	check(str(core.request({"op":"save","serialized":true}).get("serialized",""))==raw,"loading old archive retains exact serialized replay bytes")
	report["original"]=summarize(view)
	report.original["cargo_ids"]=view.salvage.cargo_grid.items.filter(func(item):return item.get("placement")!=null).map(func(item):return str(item.id))
	if legacy:
		var path:String=clone_profile("legacy");await client(path)
		app.core.request({"op":"load","serialized":raw});app.run=app.economy.resume_sortie();app.enter_battle();await settled();await windowed();app.running=true
		await shot("legacy-v2-disabled-at-first-wreck")
		for i in range(240):app._process(1.0)
		check(not pilot().get("enabled",true) and app.core.view.get("result")==null,"old raw state stays manual and cannot extract by waiting240seconds")
		report["legacy_time_only"]=summarize(app.core.view);await shot("legacy-v2-still-manual-after240seconds");await release()
	core.close()
func main_voyage()->void:
	var path:String=clone_profile("complete");await client(path)
	var wallet:Dictionary=app.economy.wallet().duplicate(true)
	var hold_key:String=str(original.active_run.cargo_warehouse_key)
	var prior_items:int=app.economy.state.get("fleet_cargo_v1",{}).get("holds",{}).get(hold_key,{}).get("items",[]).size()
	var prior_extractions:int=int(app.economy.state.extractions)
	app.resume_run();await settled();await windowed()
	if not check(app.screen=="battle" and pilot().get("enabled",false) and str(pilot().get("version",""))=="cas-extraction-pilot-v3","production resume records authorized v3 repair of cargo-disabled v2"):await release();return
	check(int(app.core.view.tick)==397 and app.running,"repair starts original tick without injecting movement or advancing time")
	var wallet_after:Dictionary=app.economy.wallet();var changed_resources:Array=[]
	for key in wallet:
		# The regeneration countdown is wall-clock UI, not a charged resource.
		if key!="stamina_next_seconds" and int(wallet_after.get(key,-1))!=int(wallet[key]):changed_resources.append(key)
	check(changed_resources.is_empty(),"resume/upgrade does not charge entry resources")
	report["resume_wallet"]={"before":wallet,"after":wallet_after,"changed_resources":changed_resources}
	var upgraded:String=native_save();var upgrade:Dictionary=JSON.parse_string(upgraded)
	check(upgrade.commands.size()==JSON.parse_string(raw).commands.size()+1 and str(upgrade.commands.back().request.version)=="cas-extraction-pilot-v3","upgrade appends one v3 authorization to original command history")
	check(str(app.economy.state.active_run.snapshot)==upgraded,"upgrade checkpoints appended command into isolated account")
	await shot("repaired-five-ships-v3-at-original-tick")
	var id:String=str(app.economy.state.active_run.run_id)
	app.go_home();await settled();app.close_modal();await release();await client(path);app.resume_run();await settled();await windowed()
	check(native_save()==upgraded and app.running,"closing native process and reopening v3 resumes exact snapshot with no new authorization")
	var phases:Array[String]=[];var last_tick:int=397
	for second in range(1400):
		if app.screen!="battle":break
		app._process(1.0)
		last_tick=int(app.core.view.tick)
		var phase:String=str(pilot().get("phase",""));if not phases.has(phase):phases.append(phase)
		if second==35:await shot("time-only-v3-orders-live-fleet")
		if second%25==0:await frames()
	check(app.screen=="result" and app.last_receipt.get("success",false),"real five-ship voyage extracts and production account settles using only elapsed time")
	check(app.core.view.get("salvage",{}).get("extracted",false),"native extracted flag confirms success rather than UI fabrication")
	check(app.core.view.ships.size()==5 and app.core.view.ships.all(func(ship):return float(ship.hp)>0),"all five original actual hulls survive the completed extraction")
	check(app.last_receipt.get("cargo_items",[]).size()>=4,"at least original four physical items actually recovered")
	check(app.economy.state.active_run.is_empty() and app.economy.state.settled.has(id),"real settlement clears active voyage and journals same run")
	var deposited:Array=app.economy.state.get("fleet_cargo_v1",{}).get("holds",{}).get(hold_key,{}).get("items",[])
	check(deposited.size()==prior_items+app.last_receipt.get("cargo_items",[]).size(),"real recovered items enter original fleet warehouse exactly once")
	check(int(app.economy.state.extractions)==prior_extractions+1,"actual account extraction count increments once")
	var cargo_ids:Array=app.last_receipt.get("cargo_items",[]).map(func(item):return str(item.id))
	var original_ids:Array=report.original.get("cargo_ids",[])
	check(original_ids.all(func(item):return cargo_ids.has(item)),"all original four stowed items are retained even when v3 explores further")
	check(cargo_ids.all(func(item):return deposited.any(func(row):return str(row.id)==item)),"all recovered item identities persist in actual fleet hold")
	var account:=Economy.new(path);check(account.load_state().get("ok",false) and account.state.active_run.is_empty() and account.state.settled.has(id),"complete extraction and settlement survive disk reload")
	var before_count:int=deposited.size();check(app.economy.settle_sortie(app.last_receipt).get("duplicate",false),"duplicate result cannot award again")
	check(app.economy.state.fleet_cargo_v1.holds[hold_key].items.size()==before_count,"duplicate settlement leaves physical warehouse unchanged")
	report["completion"]={"tick":last_tick,"phases":phases,"recovered":cargo_ids,"warehouse_key":hold_key,"before_count":prior_items,"after_count":deposited.size(),"terminal":summarize(app.core.view),"snapshot":ProjectSettings.globalize_path(OUTPUT+"terminal-native-save.json")}
	FileAccess.open(OUTPUT+"terminal-native-save.json",FileAccess.WRITE).store_string(native_save())
	await shot("true-five-ship-extraction-and-account-result");await release()
func cargo_branch()->void:
	var path:String=clone_profile("cargo");await client(path);app.resume_run();await settled();await windowed()
	if not check(pilot().get("enabled",false),"cargo branch starts upgraded automation"):await release();return
	var panel:Control=await open_cargo();var item:Dictionary=panel.data.items[0].duplicate(true);var target:Array=moved_placement(panel,item)
	if check(not target.is_empty(),"actual loaded shape has a different valid free placement"):
		var source:Button=cargo_item(panel,str(item.id));var from:Vector2=point(source,source.size*.5);var to:Vector2=point(panel.grid,Vector2((float(target[0])+.5)*44,(float(target[1])+.5)*44))
		await motion(from);await press(from,true)
		for i in range(1,8):await motion(from.lerp(to,float(i)/7),true)
		check(panel.dragging and panel.grid.preview_valid,"real pointer drag previews valid shape on original voyage")
		await press(to,false)
		var placed:Dictionary=app.core.view.salvage.cargo_grid.items.filter(func(row):return str(row.id)==str(item.id))[0]
		var position_matches:bool=true
		for i in range(3):position_matches=position_matches and int(placed.placement[i])==int(target[i])
		check(position_matches,"mouse release commits real native cargo position")
		check(pilot().get("enabled",false),"v3 remains enabled after native cargo_place")
	await click(panel.get_node("Sort"));check(pilot().get("enabled",false),"v3 remains enabled after real cargo_sort")
	await shot("cargo-drag-and-sort-retain-auto");await close_modal()
	check(app.running,"closing organizer resumes prior running state")
	var tick:int=int(app.core.view.tick);app._process(1.0);check(int(app.core.view.tick)==tick+1 and pilot().get("enabled",false),"time resumes and automation keeps executing after cargo close")
	await toggle_auto();check(not pilot().get("enabled",true),"real player toggle explicitly disables automation")
	if is_instance_valid(app.modal):await close_modal()
	panel=await open_cargo();await click(panel.get_node("Sort"));await close_modal()
	check(not pilot().get("enabled",true),"cargo sort/close never re-enables a player's explicit manual choice")
	app.go_home();await settled();app.close_modal();var manual_snapshot:String=str(app.economy.state.active_run.snapshot)
	await release();await client(path);app.resume_run();await settled();await windowed()
	check(not pilot().get("enabled",true) and not app.running,"manual v3 authorization remains off after account/native restart")
	check(native_save()==manual_snapshot,"manual save resumes byte-identically with no injected enable command")
	report["cargo_branch"]={"tick":app.core.view.tick,"manual_retained":not pilot().get("enabled",true),"native_commands":JSON.parse_string(native_save()).commands}
	await shot("explicit-manual-choice-retained-after-restart");await release()
func quick_branch()->void:
	var path:String=clone_profile("quick");await client(path)
	# Native replay is read-only. Recreate this exact seeded original deployment
	# and reapply its recorded tick-zero authorization to observe the real search.
	var saved:Dictionary=JSON.parse_string(raw)
	var started:Dictionary=app.core.request({"op":"new_salvage","seed":int(saved.seed),"start":saved.salvage})
	if not check(started.get("ok",false),"identical original start and seed recreate original deployment"):await release();return
	var authorized:Dictionary=app.core.request(saved.commands[0].request)
	check(authorized.get("ok",false),"only original tick-zero v2 authorization is repeated before search")
	app.run=app.economy.resume_sortie();app.enter_battle();await settled();await windowed();app.running=true
	var searching:bool=false
	for second in range(397):
		if app.core.view.get("result")!=null:break
		app._process(1.0)
		if app.core.view.salvage.get("search")!=null:searching=true;break
		if second%30==0:await frames()
	if not check(searching,"actual archived autonomous route starts a physical search"):await release();return
	await toggle_auto();check(not pilot().get("enabled",true),"player pauses automation while existing real search continues")
	if is_instance_valid(app.modal):await close_modal()
	var pending:Dictionary={}
	for second in range(15):
		app._process(1.0)
		for row in app.core.view.salvage.cargo_grid.items:
			if row.get("placement")==null:pending=row.duplicate(true);break
		if not pending.is_empty():break
	if not check(not pending.is_empty(),"native search reveals an actual pending item with automation held"):await release();return
	await toggle_auto();check(pilot().get("enabled",false) and str(pilot().get("version",""))=="cas-extraction-pilot-v3","player explicitly restarts v3 before quickly stowing found cargo")
	var panel:Control=await open_cargo();await click(cargo_item(panel,str(pending.id)));await click(panel.get_node("Quick"))
	var item:Dictionary=app.core.view.salvage.cargo_grid.items.filter(func(row):return str(row.id)==str(pending.id))[0]
	check(item.get("placement")!=null and pilot().get("enabled",false),"real Quick button packs physical discovered item and preserves automatic control")
	await shot("real-search-quick-stow-preserves-auto");await close_modal()
	var tick:int=int(app.core.view.tick);app._process(1.0)
	check(app.running and int(app.core.view.tick)==tick+1 and pilot().get("enabled",false),"closing quick-stow organizer continues automatic time")
	report["quick_branch"]={"exact_original_start_and_seed":true,"actual_search_tick":tick,"stowed_id":str(pending.id),"synthetic_items":false};await release()
func run()->void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	root.content_scale_size=Vector2i(1600,900);root.size=Vector2i(1280,720)
	source_hash=FileAccess.get_sha256(SOURCE);original=JSON.parse_string(FileAccess.get_file_as_string(SOURCE));raw=str(original.active_run.snapshot)
	var legacy:bool=OS.get_cmdline_user_args().has("--legacy")
	report["source_sha256"]=source_hash;report["core_override"]=OS.get_environment("CAS_SIM_PATH");report["legacy_diagnosis_only"]=legacy
	report["default_core_manifest"]=JSON.parse_string(FileAccess.get_file_as_string("res://bin/core-current.json"))
	await baseline(legacy)
	if not legacy:await main_voyage();await cargo_branch();await quick_branch()
	check(FileAccess.get_sha256(SOURCE)==source_hash,"read-only actual archived account remains byte-identical")
	report.merge({"checks":checks,"failures":failures,"screenshots":shots,"source_untouched":FileAccess.get_sha256(SOURCE)==source_hash,"isolated_profiles":paths,"allowed_input":"production resume/explicit auto toggle; normal cargo pointer operations; main completion branch elapsed time only"})
	FileAccess.open(OUTPUT+("legacy-receipt.json" if legacy else "receipt.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	for path in paths:
		for suffix in ["",".bak",".tmp"]:
			if FileAccess.file_exists(path+suffix):DirAccess.remove_absolute(ProjectSettings.globalize_path(path+suffix))
	print("EXTRACTION_ACTUAL_SAVE ",JSON.stringify({"checks":checks,"failures":failures,"legacy":legacy,"completion":report.get("completion",{})}));quit(0 if failures.is_empty() else 1)
