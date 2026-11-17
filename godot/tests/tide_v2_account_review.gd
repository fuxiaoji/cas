extends SceneTree
## Production account transactions against real native v2 voyages; the main save is read-only.
const Economy=preload("res://scripts/economy.gd")
const Bridge=preload("res://scripts/core_bridge.gd")
const TideService=preload("res://scripts/tide_event_service.gd")
const SOURCE="user://cas_port_v1.json"
const OUTPUT="res://../artifacts/tide-v2-account/"
const VERSION="cas-event-tide-v2"
var checks:int=0
var failures:Array[String]=[]
var report:Dictionary={"normal_account_written":false,"synthetic_combat_state":false,"gpu_used":false}
var paths:Array[String]=[]
var account
var service
var core
var account_path:String
var source_sha:String=""
var source_backup_sha:String=""
var baseline:Dictionary={}
var identities:Array[String]=[]
var request:Dictionary={}
var terminal:Dictionary={}
var terminal_save:String=""
var native_binary:String=""

func record_native_binary()->void:
	var output:Array=[]
	var pid:int=int(core.process.get("pid",0))
	var status:int=OS.execute("powershell.exe",["-NoProfile","-NonInteractive","-Command","(Get-Process -Id %d).Path"%pid],output,true)
	native_binary=str(output[0]).strip_edges() if status==0 and not output.is_empty() else ""
	check(not native_binary.is_empty() and FileAccess.file_exists(native_binary),"resolve the actual running native executable")
	var override_present:bool=OS.has_environment("CAS_SIM_PATH")
	report["native_override_present"]=override_present
	if not override_present:
		var manifest:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://bin/core-current.json"))
		report["default_manifest"]=manifest.duplicate(true)
		check(FileAccess.get_sha256(native_binary)==str(manifest.get("sha256","")),"unoverridden running executable matches the installed default manifest")

func _initialize()->void:call_deferred("run")

func check(ok:bool,label:String)->bool:
	checks+=1
	if not ok:failures.append(label);push_error(label)
	return ok

func canonical(value:Variant)->Variant:
	if value is Dictionary:
		var keys:Array=value.keys();keys.sort()
		var entries:Array=[]
		for key in keys:entries.append([str(key),canonical(value[key])])
		return entries
	if value is Array:
		var entries:Array=[]
		for item in value:entries.append(canonical(item))
		return entries
	# JSON account reloads use floating-point numbers. Compare their exact numeric
	# values, not the incidental "6" versus "6.0" serialization spelling.
	if value is int or value is float:return float(value)
	return value

func same(a:Variant,b:Variant)->bool:return JSON.stringify(canonical(a))==JSON.stringify(canonical(b))

func write_json(name:String,value:Variant)->void:
	var file:=FileAccess.open(OUTPUT+name,FileAccess.WRITE)
	if not check(file!=null,"open artifact "+name):return
	file.store_string(JSON.stringify(value,"  "));file.close()

func ask(command:Dictionary)->Dictionary:
	var response:Dictionary=core.request(command)
	check(bool(response.get("ok",false)),"native "+str(command.get("op",""))+" "+str(response.get("error","")))
	return response.get("data",{})

func snapshot()->String:
	var response:Dictionary=core.request({"op":"save","serialized":true})
	if not check(response.get("ok",false),"opaque native save succeeds"):return ""
	return str(response.get("serialized",""))

func clone_account(label:String)->bool:
	account_path=OUTPUT+"account-%s-%d.json"%[label,OS.get_process_id()]
	paths.append(ProjectSettings.globalize_path(account_path))
	if not check(DirAccess.copy_absolute(ProjectSettings.globalize_path(SOURCE),ProjectSettings.globalize_path(account_path))==OK,"copy actual account into isolated "+label):return false
	account=Economy.new(account_path)
	if not check(account.load_state().get("ok",false),"load real isolated account "+label):return false
	if not check(account.state.owned.size()==43,"isolated source contains the actual 43 owned characters"):return false
	if not account.state.get("active_run",{}).is_empty():
		if not check(account.abandon_sortie().get("ok",false),"normal abandonment ends only the cloned prior voyage"):return false
	service=TideService.new(account);service.ensure()
	return check(account.state.active_run.is_empty(),"isolated profile is ready for a new event")

func expect_begin_rejected(label:String,offered:Dictionary,serialized:String)->bool:
	var before:Dictionary=account.state.duplicate(true)
	var disk:String=FileAccess.get_sha256(account_path)
	var response:Dictionary=service.begin(offered,serialized)
	var rejected:bool=check(not response.get("ok",false),label+" is rejected")
	check(same(account.state,before),label+" leaves every account field unchanged")
	check(FileAccess.get_sha256(account_path)==disk,label+" does not replace the account file")
	return rejected

func expect_settle_rejected(label:String,view:Dictionary,serialized:String)->bool:
	var before:Dictionary=account.state.duplicate(true)
	var disk:String=FileAccess.get_sha256(account_path)
	var response:Dictionary=service.settle(view,serialized)
	var rejected:bool=check(not response.get("ok",false),label+" is rejected")
	check(same(account.state,before),label+" is fully atomic")
	check(FileAccess.get_sha256(account_path)==disk,label+" preserves the previous disk state")
	return rejected

func assert_borrowed_state(before:Dictionary,label:String)->void:
	var mutable:Array[String]=["wallet","active_run","settled","last_receipt_id","run_sequence","tide_event_v1"]
	for key in before:
		if str(key) not in mutable:check(same(account.state.get(key),before[key]),label+" preserves "+str(key))
	for key in before.wallet:
		if str(key) not in ["tide_tokens","origins"]:check(same(account.state.wallet.get(key),before.wallet[key]),label+" preserves wallet "+str(key))
	for key in ["intro_read","ending_read","purchases","version"]:
		check(same(account.state.tide_event_v1.get(key),before.tide_event_v1.get(key)),label+" preserves aggregate event "+key)

func choose(tide:Dictionary)->Dictionary:
	var options:Array=tide.get("choices",[])
	for option in options:
		if str(option.get("id","")).begins_with("reinforce:"):return option
	var priority:Array[String]=["chain","lightning","nova","barrage","multishot","haste","damage","blast","torpedo","magnet","repair","shield","maneuver"]
	var best:Dictionary=options[0]
	var best_rank:int=999
	for option in options:
		var rank:int=priority.find(str(option.get("id","")))
		if rank>=0 and rank<best_rank:best=option;best_rank=rank
	return best

func drive_direction(view:Dictionary)->Vector2:
	var ship:Dictionary=view.ships[0]
	var position:=Vector2(float(ship.x),float(ship.y))
	var tick:float=float(view.tick)
	var target:=Vector2(12000,7000)+Vector2.from_angle((tick+12.0)*.105)*1800.0
	var nearest:float=INF
	for drop in view.tide.get("drops",[]):
		var p:=Vector2(float(drop.x),float(drop.y));var distance:float=p.distance_to(position)
		if distance<nearest:nearest=distance;target=p
	for contact in view.get("contacts",[]):
		if contact.get("boss",false):target=Vector2(float(contact.x),float(contact.y))+Vector2.from_angle(tick*.18)*1200.0;break
	var desired:Vector2=(target-position).normalized()
	var best:=desired
	var best_score:float=-INF
	for index in range(24):
		var candidate:=Vector2.from_angle(float(index)*TAU/24.0)
		var score:float=candidate.dot(desired)
		for warning in view.get("salvage",{}).get("telegraphs",[]):
			var due:float=minf(3.0,maxf(.1,float(warning.get("impact_tick",tick+1.0))-tick))
			var radius:float=float(warning.get("radius",300))+100.0
			var p:=Vector2(float(warning.x),float(warning.y))
			var distance:float=(position+candidate*308.0*due).distance_to(p)
			if distance<radius:score-=12.0*(1.0-distance/radius)
		if score>best_score:best_score=score;best=candidate
	return best

func run_voyage()->bool:
	var restored:bool=false
	var recruits:Array=[]
	var checkpoints:Array=[]
	var previous_members:int=1
	for iteration in range(2600):
		var view:Dictionary=core.view
		if view.get("result")!=null:break
		var tide:Dictionary=view.tide
		if not tide.get("choices",[]).is_empty():
			var selected:Dictionary=choose(tide)
			var before_count:int=view.ships.size()
			var response:Dictionary=ask({"op":"tide_choose","offer_id":int(tide.offer_id),"upgrade":str(selected.id)})
			if response.is_empty():return false
			if str(selected.id).begins_with("reinforce:"):
				check(core.view.ships.size()==before_count+1,"offered owned reserve joins as one real simulated ship")
				recruits.append({"tick":core.view.tick,"id":str(selected.id),"ships":core.view.ships.duplicate(true)})
			continue
		if view.ships.size()>=3 and not restored and float(view.tick)>=30.0:
			var raw:String=snapshot()
			var native:Dictionary=ask({"op":"observe"})
			var wallet:Dictionary=account.state.wallet.duplicate(true)
			check(account.save_sortie(raw).get("ok",false),"normal account checkpoint stores opaque v2 snapshot after two real recruits")
			write_json("before-mid-reload-account.json",account.state)
			write_json("mid-voyage-view.json",native)
			var file:=FileAccess.open(OUTPUT+"mid-voyage-save.json",FileAccess.WRITE);file.store_string(raw);file.close()
			core.close();account=Economy.new(account_path)
			if not check(account.load_state().get("ok",false),"full account restart reloads active v2 voyage"):return false
			service=TideService.new(account)
			write_json("after-mid-reload-account.json",account.state)
			var resumed:Dictionary=account.resume_sortie()
			check(str(resumed.snapshot)==raw,"account preserves exact serialized native save bytes")
			check(str(resumed.ruleset)==VERSION and str(resumed.mode)=="tide_event","resumed account retains explicit v2 mode and ruleset")
			check(same(account.state.wallet,wallet),"restart never charges resources or grants rewards")
			core=Bridge.new()
			var loaded:Dictionary=ask({"op":"load","serialized":raw})
			check(same(loaded,native),"load reconstructs every native field and stable recruited ship ID")
			var replayed:Dictionary=ask({"op":"replay","save":JSON.parse_string(raw)})
			check(same(replayed,native),"independent replay reproduces recruited formation, attacks and progress")
			check(snapshot()==raw,"load and replay do not append commands or rewrite the native save")
			restored=true;view=core.view
		var ship:Dictionary=view.ships[0]
		var goal:=Vector2(float(ship.x),float(ship.y))+drive_direction(view)*1500.0
		goal.x=clampf(goal.x,500,23500);goal.y=clampf(goal.y,500,13500)
		ask({"op":"route","fleet":1,"mode":"follow","speed":60,"points":[{"x":goal.x,"y":goal.y}]})
		var moved:Dictionary=ask({"op":"step","seconds":.5})
		if moved.is_empty():return false
		if moved.ships.size()!=previous_members or int(float(moved.tick)*10.0)%300==0:
			checkpoints.append({"tick":moved.tick,"frame":moved.tide.get("frame"),"members":moved.ships.size(),"kills":moved.tide.kills,"hp":moved.ships[0].hp,"level":moved.tide.level})
		previous_members=moved.ships.size()
	check(restored,"voyage crosses a real save/restart/replay after at least two reinforcements")
	check(recruits.size()>=2,"player actually selects at least two distinct reserve offers")
	terminal=ask({"op":"observe"});terminal_save=snapshot()
	write_json("voyage.json",{"recruits":recruits,"checkpoints":checkpoints,"terminal":terminal})
	var file:=FileAccess.open(OUTPUT+"terminal-save.json",FileAccess.WRITE);file.store_string(terminal_save);file.close()
	return check(terminal.get("result")!=null and terminal.tide.get("outcome",{}).get("success",false),"real played voyage survives to duration and defeats the boss")

func run()->void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	if not check(FileAccess.file_exists(SOURCE),"actual main account exists"):return finish()
	source_sha=FileAccess.get_sha256(SOURCE)
	if FileAccess.file_exists(SOURCE+".bak"):source_backup_sha=FileAccess.get_sha256(SOURCE+".bak")
	if not clone_account("v2"):return finish()
	identities.assign(account.state.owned.keys());identities.sort()
	var primary:String="IBS-U-USN-FLETCHER" if account.state.owned.has("IBS-U-USN-FLETCHER") else identities[0]
	var reserves:Array[String]=[]
	for identity in identities:
		if identity!=primary and reserves.size()<5:reserves.append(identity)
	if not check(reserves.size()==5,"real ownership supplies five unique reserves"):return finish()
	request={"op":"new_tide","version":VERSION,"seed":42,"character_id":primary,"difficulty":"normal","intel_profile":"open-intel-v1","roster":reserves}
	core=Bridge.new()
	var initial:Dictionary=ask(request)
	record_native_binary()
	if not check(str(initial.get("tide",{}).get("version",""))==VERSION,"candidate starts explicit v2 rather than silently falling back"):return finish()
	check(int(initial.tide.get("simulation_hz",0))==10 and int(initial.tide.get("frame",-1))==0,"native v2 publishes its 10Hz clock and initial frame")
	var initial_save:String=snapshot()
	write_json("initial-request.json",request)
	var unowned:String=""
	for card in account.catalog:
		if str(card.get("id","")).begins_with("IBS-U-") and not account.state.owned.has(str(card.id)):unowned=str(card.id);break
	if not check(not unowned.is_empty(),"catalogue supplies a genuinely unowned identity for rejection tests"):return finish()
	var bad:Dictionary=request.duplicate(true);bad.roster=[unowned]
	if not expect_begin_rejected("unowned reserve",bad,initial_save):return finish()
	bad=request.duplicate(true);bad.roster=[reserves[0],reserves[0]]
	if not expect_begin_rejected("duplicate reserve",bad,initial_save):return finish()
	bad=request.duplicate(true);bad.roster=[primary]
	if not expect_begin_rejected("flagship repeated as reserve",bad,initial_save):return finish()
	bad=request.duplicate(true);bad.character_id=unowned
	if not expect_begin_rejected("unowned flagship",bad,initial_save):return finish()
	bad=request.duplicate(true);bad.roster=[reserves[0]]
	if not expect_begin_rejected("snapshot with different reserve configuration",bad,initial_save):return finish()
	var altered:Dictionary=JSON.parse_string(initial_save);altered.frame=1;altered.tick=0
	if not expect_begin_rejected("inconsistent initial frame/seconds",request,JSON.stringify(altered)):return finish()
	ask({"op":"step","seconds":.1})
	if not expect_begin_rejected("already advanced genuine snapshot",request,snapshot()):return finish()
	initial=ask(request);initial_save=snapshot()
	baseline=account.state.duplicate(true)
	write_json("baseline-account.json",baseline)
	var begun:Dictionary=service.begin(request,initial_save)
	if not check(begun.get("ok",false),"production account begins legitimate v2 event"):return finish()
	check(str(account.state.active_run.ruleset)==VERSION and account.state.active_run.fleet.is_empty(),"v2 active run remains a borrowed roster without permanent fleet deployment")
	check(same(account.state.wallet,baseline.wallet),"event entry does not consume port ammo, fuel, stamina or currencies")
	check(same(account.state.tide_event_v1,baseline.tide_event_v1),"v2 begin preserves existing aggregate event progress")
	if not run_voyage():return finish()
	var forged:Dictionary=terminal.duplicate(true);forged.tide.outcome.event_tokens=int(forged.tide.outcome.event_tokens)+10
	if not expect_settle_rejected("forged terminal token reward within former numeric cap",forged,terminal_save):return finish()
	forged=terminal.duplicate(true);forged.ships[1].characterId=unowned
	if not expect_settle_rejected("forged recruited ship identity",forged,terminal_save):return finish()
	forged=terminal.duplicate(true);forged.tide.members=[]
	if not expect_settle_rejected("forged terminal membership list",forged,terminal_save):return finish()
	altered=JSON.parse_string(terminal_save);altered.tick=float(altered.tick)-.1
	if not expect_settle_rejected("terminal snapshot seconds disagree with native frame",terminal,JSON.stringify(altered)):return finish()
	altered=JSON.parse_string(terminal_save);altered.config.roster=[reserves[0]]
	if not expect_settle_rejected("terminal snapshot swaps reserve configuration",terminal,JSON.stringify(altered)):return finish()
	var before_tokens:int=int(account.state.wallet.tide_tokens)
	var before_origins:int=int(account.state.wallet.origins)
	var before_wins:int=int(account.state.tide_event_v1.wins)
	var settled:Dictionary=service.settle(terminal,terminal_save)
	if not check(settled.get("ok",false),"production verifier accepts real native victory and grants its receipt"):return finish()
	var receipt:Dictionary=settled.receipt
	write_json("after-victory-account.json",account.state)
	check(int(account.state.wallet.tide_tokens)==before_tokens+int(terminal.tide.outcome.event_tokens),"only real terminal event tokens enter the wallet")
	check(int(account.state.wallet.origins)==before_origins+(160 if before_wins==0 else 0),"first-win resource is paid only according to existing aggregate progress")
	check(int(account.state.tide_event_v1.wins)==before_wins+1,"v2 adds exactly one win to existing event history")
	check(str(receipt.ruleset)==VERSION and same(receipt.members,terminal.tide.members),"receipt preserves true recruited identities and explicit v2 ruleset")
	check(account.state.active_run.is_empty(),"real completion clears only this borrowed active event")
	assert_borrowed_state(baseline,"v2 victory")
	var after:Dictionary=account.state.duplicate(true)
	check(service.settle(terminal,terminal_save).get("duplicate",false),"repeat settlement is an idempotent existing receipt")
	check(same(account.state,after),"repeat settlement grants no resources or progression")
	account=Economy.new(account_path);check(account.load_state().get("ok",false),"full account reload accepts saved victory")
	write_json("after-victory-reload-account.json",account.state)
	service=TideService.new(account)
	check(same(account.state,after),"victory resources, memberships and aggregate progress survive reload exactly")
	write_json("victory-receipt.json",receipt)
	var abandoned_request:Dictionary=request.duplicate(true);abandoned_request.seed=43
	ask(abandoned_request)
	if not check(service.begin(abandoned_request,snapshot()).get("ok",false),"second real event begins after completed victory"):return finish()
	for iteration in range(35):
		if not core.view.tide.get("choices",[]).is_empty():
			var pick:Dictionary=choose(core.view.tide);ask({"op":"tide_choose","offer_id":int(core.view.tide.offer_id),"upgrade":str(pick.id)})
		else:ask({"op":"step","seconds":.5})
		if float(core.view.tick)>=6.0:break
	check(int(core.view.tide.kills)>0,"abandoned event has actually killed enemies before exit")
	ask({"op":"tide_abandon"})
	var abort_view:Dictionary=ask({"op":"observe"})
	var abort_save:String=snapshot();before_tokens=int(account.state.wallet.tide_tokens);before_origins=int(account.state.wallet.origins)
	var aborted:Dictionary=service.settle(abort_view,abort_save,true)
	check(aborted.get("ok",false) and not aborted.get("receipt",{}).get("success",true),"production abandonment settles as a genuine failure")
	check(int(account.state.wallet.tide_tokens)==before_tokens and int(account.state.wallet.origins)==before_origins,"manual exit grants zero event coins and zero first-win resources")
	check(int(aborted.get("receipt",{}).get("rewards",{}).get("tide_tokens",-1))==0,"abandonment receipt explicitly contains zero token reward")
	write_json("abandon-receipt.json",aborted)
	checkpoint_failure_pause()
	legacy_compatibility()
	finish()

func checkpoint_failure_pause()->void:
	var failed_request:Dictionary=request.duplicate(true);failed_request.seed=45
	ask(failed_request)
	if not check(service.begin(failed_request,snapshot()).get("ok",false),"isolated event begins for real save-failure pause verification"):return
	for iteration in range(200):
		if not core.view.tide.get("choices",[]).is_empty():break
		ask({"op":"step","seconds":.1})
	if not check(not core.view.tide.get("choices",[]).is_empty(),"save-failure scenario reaches a genuine native upgrade offer"):return
	var blocker_path:String=OUTPUT+"save-directory-blocker-"+str(OS.get_process_id())
	var blocker:=FileAccess.open(blocker_path,FileAccess.WRITE)
	if not check(blocker!=null,"create isolated regular-file save-directory blocker"):return
	blocker.store_string("This regular file intentionally prevents creating a save directory beneath it.");blocker.close()
	var original_path:String=account.save_path
	var before_disk:String=FileAccess.get_sha256(original_path)
	var before:Dictionary=account.state.duplicate(true)
	var app=load("res://scripts/main.gd").new()
	app.core.close();app.core=core;app.economy=account;app.run=account.state.active_run.duplicate(true);app.running=true
	account.save_path=blocker_path+"/blocked.json"
	var offered:Dictionary=choose(core.view.tide)
	var accepted:Dictionary=app.issue({"op":"tide_choose","offer_id":int(core.view.tide.offer_id),"upgrade":str(offered.id)})
	check(accepted.get("ok",false),"native accepts the real upgrade before durable save failure")
	check(not app.running,"v2 non-movement command pauses combat when durable checkpoint fails")
	check(core.view.tide.get("choices",[]).is_empty(),"failed durable write does not pretend the accepted native choice was rejected")
	check(same(account.state,before) and FileAccess.get_sha256(original_path)==before_disk,"failed checkpoint retains every last durable account field and exact file bytes")
	account.save_path=original_path
	var accepted_save:String=snapshot()
	check(app.checkpoint(),"restoring the isolated save destination persists the accepted native choice")
	check(str(account.state.active_run.snapshot)==accepted_save,"successful retry saves the actual native log without losing the upgrade")
	check(not app.running,"successful checkpoint retry does not silently resume paused combat")
	app.free()
	report["save_failure_pause"]={"real_io_failure":true,"paused":true,"durable_account_preserved":true,"native_choice_retained":true,"successful_retry":true}

func legacy_compatibility()->void:
	var fixture:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://../artifacts/tide-account-audit/fixtures.json"))
	if not check(not fixture.is_empty(),"frozen real v1 fixture is available"):return
	if not clone_account("legacy-v1"):return
	var legacy_request:Dictionary={"op":"new_tide","seed":44,"character_id":"IBS-U-USN-FLETCHER","difficulty":"hard","intel_profile":"open-intel-v1"}
	var begun:Dictionary=service.begin(legacy_request,str(fixture.hard_initial_serialized))
	if not check(begun.get("ok",false),"version-omitted frozen v1 event still begins normally"):return
	check(str(account.state.active_run.ruleset)=="cas-event-tide-v1","legacy account event is never silently upgraded")
	var old_view:Dictionary=ask({"op":"load","serialized":str(fixture.hard_serialized)})
	check(str(old_view.get("version",""))=="cas-event-tide-v1" and old_view.ships.size()==1,"native frozen v1 keeps its original one-ship ruleset")
	check(same(old_view.tide,fixture.hard_view.tide),"frozen v1 full real terminal remains identical")
	var settled:Dictionary=service.settle(old_view,str(fixture.hard_serialized))
	check(settled.get("ok",false) and settled.get("receipt",{}).get("success",false),"legacy real victory still settles through its original service path")
	check(not settled.get("receipt",{}).has("members") and not settled.get("receipt",{}).has("ruleset"),"v1 receipt does not gain v2-only fields")
	report["legacy"]={"begun":begun,"settled":settled,"native_tick":old_view.get("tick")}

func finish()->void:
	if core!=null:core.close()
	if not source_sha.is_empty():check(FileAccess.get_sha256(SOURCE)==source_sha,"main account exact bytes remain unchanged")
	if not source_backup_sha.is_empty():check(FileAccess.get_sha256(SOURCE+".bak")==source_backup_sha,"main account backup exact bytes remain unchanged")
	var binary:String=native_binary
	var receipt_file:=FileAccess.open(OUTPUT+"receipt.json",FileAccess.WRITE)
	check(receipt_file!=null,"open final account receipt artifact")
	report.merge({"checks":checks,"failures":failures,"passed":failures.is_empty(),"source":ProjectSettings.globalize_path(SOURCE),"source_sha256":source_sha,"source_backup_sha256":source_backup_sha,"isolated_profiles":paths,"native":binary,"native_sha256":FileAccess.get_sha256(binary) if FileAccess.file_exists(binary) else "","service_sha256":FileAccess.get_sha256("res://scripts/tide_event_service.gd"),"test_sha256":FileAccess.get_sha256("res://tests/tide_v2_account_review.gd")})
	if receipt_file!=null:receipt_file.store_string(JSON.stringify(report,"  "));receipt_file.close()
	print("TIDE_V2_ACCOUNT "+JSON.stringify({"checks":checks,"failures":failures,"passed":failures.is_empty(),"profiles":paths,"native":binary}))
	quit(0 if failures.is_empty() else 1)
