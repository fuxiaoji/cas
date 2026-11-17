extends SceneTree
## Isolated archived accounts, real FleetManager composition, time-only multi-fleet voyages.
const Main=preload("res://scenes/main.tscn")
const Economy=preload("res://scripts/economy.gd")
const Settle=preload("res://tests/transition_settle.gd")
const OUTPUT="res://../artifacts/godot/extraction-actual-save/multi-fleet/"
const SOURCE="res://../artifacts/extraction-stall-20261113/actual-account-refilled.json"
var app
var checks:int=0
var failures:Array[String]=[]
var shots:Array[String]=[]
var cases:Array[Dictionary]=[]
var paths:Array[String]=[]
var source_hash:String=""
func _initialize()->void:call_deferred("run")
func check(ok:bool,label:String)->bool:
	checks+=1
	if not ok:failures.append(label);push_error(label)
	return ok
func frames()->void:
	await process_frame;await process_frame
func settled()->void:
	await Settle.wait_for_route(self,app);await frames()
func client(path:String)->void:
	app=Main.instantiate();app.boot_to_title=false;app.economy=Economy.new(path);root.add_child(app);app.set_process(false)
	await settled();app.page_motion=false
func release()->void:
	if is_instance_valid(app):app.audio.shutdown();app.core.close();app.queue_free();await frames()
func windowed()->void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED);app.fullscreen_battle=false;root.size=Vector2i(1280,720);await frames()
func shot(name:String)->void:
	if DisplayServer.get_name()=="headless":return
	await settled();await RenderingServer.frame_post_draw
	var file:String=ProjectSettings.globalize_path(OUTPUT+name+".png")
	check(root.get_texture().get_image().save_png(file)==OK,"GPU "+name);shots.append(file)
func pilot()->Dictionary:return app.core.view.get("salvage",{}).get("expedition",{}).get("autopilot",{})
func raw()->String:return str(app.core.request({"op":"save","serialized":true}).get("serialized",""))
func observe_searches(witnessed:Dictionary,completed:Dictionary,evidence:Array)->void:
	var view:Dictionary=app.core.view
	var search:Variant=view.get("salvage",{}).get("search")
	if search is Dictionary:
		for target in pilot().get("fleet_targets",[]):
			if str(target.get("phase",""))!="search" or int(target.ruin)!=int(search.ruin):continue
			var ruin:Dictionary={}
			for row in view.salvage.ruins:
				if int(row.id)==int(search.ruin):ruin=row;break
			if ruin.is_empty():continue
			var eligible:Array=view.ships.filter(func(ship):return int(ship.get("fleet",-1))==int(target.fleet) and float(ship.speed)<=8.0 and Vector2(float(ship.x),float(ship.y)).distance_to(Vector2(float(ruin.p.x),float(ruin.p.y)))<730.0)
			var group:String=str(int(target.fleet));var identity:String=str(int(search.ruin))
			var key:String=group+":"+identity
			if not witnessed.has(key):
				check(not eligible.is_empty(),"fleet%s physically performs low-speed search at ruin%s"%[group,identity])
				if not eligible.is_empty():
					witnessed[key]={"fleet":int(target.fleet),"ruin":int(search.ruin),"first_tick":int(view.tick),"search_progress":int(search.progress),"actual_ships":eligible.map(func(ship):return int(ship.id)),"prior_item_ids":view.salvage.cargo_grid.items.map(func(item):return str(item.id))}
	for key in witnessed:
		var entry:Dictionary=witnessed[key]
		if view.salvage.cargo_grid.get("completed",[]).any(func(id):return int(id)==int(entry.ruin)) and not completed.has(key):
			var found:Array=view.salvage.cargo_grid.items.filter(func(item):return int(item.get("ruin",-1))==int(entry.ruin) and not entry.prior_item_ids.has(str(item.id)))
			check(not found.is_empty(),"fleet%s search of ruin%s produces genuinely new physical cargo"%[entry.fleet,entry.ruin])
			if not found.is_empty():
				completed[key]=entry.duplicate(true);completed[key]["completed_tick"]=int(view.tick);completed[key]["new_item_ids"]=found.map(func(item):return str(item.id));evidence.append(completed[key])
func inside_exit(ship:Dictionary,exit:Dictionary)->bool:
	if exit.get("bounds") is Dictionary:
		var bounds:Dictionary=exit.bounds
		return float(ship.x)>=float(bounds.min_x)-.01 and float(ship.x)<=float(bounds.max_x)+.01 and float(ship.y)>=float(bounds.min_y)-.01 and float(ship.y)<=float(bounds.max_y)+.01
	var center:Dictionary=exit.get("p",exit)
	return Vector2(float(ship.x),float(ship.y)).distance_to(Vector2(float(center.x),float(center.y)))<=float(exit.get("radius",1000))+.01
func exercise(count:int,seed:int)->void:
	var starter_risk:bool="--starter-risk" in OS.get_cmdline_user_args()
	var path:String="user://tests/extraction-multi-%d-%d.json"%[count,OS.get_process_id()];paths.append(path)
	if not starter_risk:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path).get_base_dir())
		check(DirAccess.copy_absolute(ProjectSettings.globalize_path(SOURCE),ProjectSettings.globalize_path(path))==OK,"read-only archived account is cloned into isolated multi-group profile")
	await client(path)
	var source_account:Dictionary={} if starter_risk else JSON.parse_string(FileAccess.get_file_as_string(SOURCE))
	check(str(app.economy.state.get("test_account",""))==str(source_account.get("test_account","")),"%d groups retain the source account's existing authorized resource marker"%count)
	var identities:Array=app.economy.state.owned.keys() if starter_risk else app.economy.state.active_run.fleet.map(func(ship):return str(ship.id))
	check(app.economy.state.owned.size()==(3 if starter_risk else 43),"account owns the genuine starter or archived character collection")
	if not starter_risk:
		check(app.economy.abandon_sortie().get("ok",false) and app.economy.state.active_run.is_empty(),"normal account abandonment ends only the isolated copy's existing voyage before new composition")
	if not check(identities.size()==(3 if starter_risk else 5),"deployment uses genuinely owned starter or original five-hull roster"):await release();return
	check(app.economy.service_all(identities,100).get("ok",false),"purchase100 ammunition per hull through normal combined service")
	var compositions:Array=[]
	if starter_risk:compositions=[[identities[0],identities[1]],[identities[2]]] if count==2 else [[identities[0]],[identities[1]],[identities[2]]]
	else:compositions=[[identities[0],identities[1]],[identities[2],identities[3],identities[4]]] if count==2 else [[identities[0],identities[1]],[identities[2],identities[3]],[identities[4]]]
	check(app.fleets.set_members(compositions[0]).get("ok",false),"set first group through normal FleetManager")
	for index in range(1,count):
		check(app.fleets.create("搜集分队%d"%(index+1)).get("ok",false),"create real saved group%d"%(index+1))
		check(app.fleets.set_members(compositions[index]).get("ok",false),"assign nonduplicated owned hull to group%d"%(index+1))
		check(app.fleets.select(str(app.fleets.active().id),true).get("ok",false),"select saved group%d for sortie"%(index+1))
	check(app.fleets.groups().size()==count and app.economy.formation.size()==identities.size(),"normal selection freezes %d groups and every distinct owned deployment hull"%count)
	check(app.economy.set_salvage_options({"difficulty":"calm","environment":"drowned_city","weather":"clear","scene":"sunken_metropolis"}).get("ok",false),"normal salvage configuration is saved before deployment")
	var preview:Dictionary=app.economy.preview_sortie(seed,false,{"kind":"salvage","id":"calm"})
	if not check(preview.get("ok",false) and preview.get("groups",[]).size()==count,"real normal sortie preview accepts complete multi-group deployment"):await release();return
	if "--fixture-only" in OS.get_cmdline_user_args():
		cases.append({"groups":count,"seed":seed,"fixture_only":true,"group_ids":app.fleets.groups().map(func(group):return str(group.id)),"owned_hulls":identities,"wallet":app.economy.wallet(),"native_start":app.economy.native_start(preview)})
		await release();return
	var stamina:int=int(app.economy.wallet().stamina)
	app.set_meta("next_sortie_seed",seed);app.show_page("expedition");await settled();app.launch(false,{"kind":"salvage","id":"calm"});await settled();await windowed()
	if not check(app.screen=="battle" and app.running,"production launch starts autonomous %d-group voyage"%count):await release();return
	check(str(pilot().get("version",""))=="cas-extraction-pilot-v3" and pilot().get("enabled",false),"latest v3 controls %d real deployed groups"%count)
	var fleet_ids:Array=app.core.view.fleets.map(func(fleet):return int(fleet.id))
	check(fleet_ids.size()==count,"native representation preserves all selected groups")
	var run_id:String=str(app.run.run_id);var warehouse_key:String=str(app.run.cargo_warehouse_key)
	check(int(app.economy.wallet().stamina)==stamina-8,"multi-group voyage pays entry exactly once")
	await shot("groups%d-departure"%count)
	var witnessed:Dictionary={};var completed:Dictionary={};var evidence:Array=[];var restored:bool=false;var restored_tick:int=-1;var last:int=0;var saw_parallel_travel:bool=false;var parallel_sample:Array=[];var saw_serial_wait:bool=false
	for second in range(2400):
		if app.screen!="battle":break
		app._process(1.0);last=int(app.core.view.tick)
		observe_searches(witnessed,completed,evidence)
		var targets:Array=pilot().get("fleet_targets",[])
		var moving_targets:Array=[];var target_ruins:Array=[]
		for target in targets:
			if not target_ruins.has(int(target.ruin)):target_ruins.append(int(target.ruin))
			if str(target.phase)=="approach" and app.core.view.ships.any(func(ship):return int(ship.get("fleet",-1))==int(target.fleet) and float(ship.speed)>1):moving_targets.append(target)
		if not saw_parallel_travel and target_ruins.size()>=2 and (moving_targets.size()>=2 or (not moving_targets.is_empty() and targets.any(func(row):return str(row.phase)=="search"))):
			saw_parallel_travel=true;parallel_sample=targets.duplicate(true)
		if targets.any(func(row):return str(row.phase)=="search") and targets.any(func(row):return str(row.phase)=="wait_search"):saw_serial_wait=true
		if not restored and not completed.is_empty() and app.screen=="battle":
			var snapshot:String=raw();var saved_targets:Array=targets.duplicate(true);var saved_completed:Array=app.core.view.salvage.cargo_grid.completed.duplicate()
			app.go_home();await settled();app.close_modal();await release();await client(path);app.resume_run();await settled();await windowed()
			check(raw()==snapshot,"%d-group in-progress save restores exact serialized native state"%count)
			check(pilot().get("fleet_targets",[])==saved_targets and app.core.view.salvage.cargo_grid.completed==saved_completed,"each group target and actual completed ruin survive native/account restart")
			check(app.fleets.groups().size()==count and str(app.run.run_id)==run_id and app.running,"same selected groups and original voyage resume without new entry")
			restored=true;restored_tick=last;await shot("groups%d-midvoyage-restored"%count)
		if second%30==0:await frames()
	check(restored,"multi-group route was saved only after actual search evidence")
	check(saw_parallel_travel,"independent groups actually travel toward separate assignments")
	# There is one authoritative search channel; waiting/approaching is explicit.
	var covered:Array=[];var distinct_ruins:Array=[]
	for record in completed.values():
		if not covered.has(int(record.fleet)):covered.append(int(record.fleet))
		if not distinct_ruins.has(int(record.ruin)):distinct_ruins.append(int(record.ruin))
	check(fleet_ids.all(func(id):return covered.has(id)),"all %d deployed groups really finish at least one attributed search"%count)
	check(distinct_ruins.size()>=count,"each deployed group searches a distinct actual ruin")
	check(app.screen=="result" and app.last_receipt.get("success",false) and app.core.view.salvage.extracted,"time-only multi-group route reaches true common extraction")
	var exit_index:int=int(pilot().get("target_exit",0));var exit:Dictionary=app.core.view.salvage.exits[exit_index]
	check(app.core.view.ships.size()==identities.size() and app.core.view.ships.all(func(ship):return float(ship.hp)>0 and inside_exit(ship,exit)),"all owned deployment hulls from every group physically finish inside the same authoritative rendezvous")
	var items:Array=app.last_receipt.get("cargo_items",[]);var stored:Array=app.economy.state.get("fleet_cargo_v1",{}).get("holds",{}).get(warehouse_key,{}).get("items",[])
	check(items.size()>0 and items.size()==stored.size(),"all actually recovered physical items enter shared selected-fleet warehouse")
	check(items.all(func(item):return stored.any(func(row):return str(row.id)==str(item.id))),"shared warehouse preserves all recovered item identities")
	var disk:=Economy.new(path);check(disk.load_state().get("ok",false) and disk.state.active_run.is_empty() and disk.state.settled.has(run_id),"multi-group settlement and empty active session survive full account reload")
	check(disk.state.get("fleet_cargo_v1",{}).get("holds",{}).get(warehouse_key,{}).get("items",[]).size()==stored.size(),"reloaded warehouse contains exact unified recovery count")
	var terminal:String=raw();FileAccess.open(OUTPUT+"groups%d-terminal-native-save.json"%count,FileAccess.WRITE).store_string(terminal)
	cases.append({"groups":count,"seed":seed,"native_fleet_ids":fleet_ids,"search_evidence":evidence,"observed_search_pairs":witnessed.values(),"tick":last,"midvoyage_restored_tick":restored_tick,"parallel_travel":saw_parallel_travel,"parallel_assignments":parallel_sample,"single_channel_wait_seen":saw_serial_wait,"warehouse_key":warehouse_key,"deposited":stored.size(),"terminal_pilot":pilot().duplicate(true),"success":app.last_receipt.get("success",false)})
	await shot("groups%d-true-extraction-and-deposit"%count);await release()
func run()->void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT));root.content_scale_size=Vector2i(1600,900);root.size=Vector2i(1280,720)
	source_hash=FileAccess.get_sha256(SOURCE)
	await exercise(2,40);await exercise(3,41)
	check(FileAccess.get_sha256(SOURCE)==source_hash,"archived original account remains byte-identical")
	var result:Dictionary={"checks":checks,"failures":failures,"cases":cases,"screenshots":shots,"core_override":OS.get_environment("CAS_SIM_PATH"),"source_hash":source_hash,"source_unchanged":FileAccess.get_sha256(SOURCE)==source_hash,"profile":"starter-risk" if "--starter-risk" in OS.get_cmdline_user_args() else "archived43-owned-five-deployed","normal_account_modified":false,"synthetic_snapshots_or_world_edits":false,"field_inputs":"only production normal launch, elapsed time, checkpoint/home/resume; no routes/searches/tasks/cargo/health supplied by test"}
	result["default_core_manifest"]=JSON.parse_string(FileAccess.get_file_as_string("res://bin/core-current.json"))
	var receipt_name:String="fixture-receipt.json" if "--fixture-only" in OS.get_cmdline_user_args() else "starter-risk-receipt.json" if "--starter-risk" in OS.get_cmdline_user_args() else "receipt.json"
	FileAccess.open(OUTPUT+receipt_name,FileAccess.WRITE).store_string(JSON.stringify(result,"  "))
	for path in paths:
		for suffix in ["",".bak",".tmp"]:
			if FileAccess.file_exists(path+suffix):DirAccess.remove_absolute(ProjectSettings.globalize_path(path+suffix))
	print("EXTRACTION_MULTI_FLEET ",JSON.stringify({"checks":checks,"failures":failures,"cases":cases.map(func(item):return {"groups":item.groups,"tick":item.get("tick"),"deposited":item.get("deposited"),"success":item.get("success"),"fixture_only":item.get("fixture_only",false)})}));quit(0 if failures.is_empty() else 1)
