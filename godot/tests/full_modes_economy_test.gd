extends SceneTree
const Economy=preload("res://scripts/economy.gd")
const Progression=preload("res://scripts/progression.gd")
const Core=preload("res://scripts/core_bridge.gd")
var checks:=0
var failures:Array[String]=[]
var actual_results:Array=[]

func _initialize() -> void:call_deferred("_run")
func check(value:bool,name:String) -> void:
	checks+=1
	if not value:failures.append(name);push_error(name)

func _run() -> void:
	var path:="user://tests/full-modes-%d.json"%OS.get_process_id()
	var account=Economy.new(path)
	check(account.load_state().ok,"new account")
	var service=Progression.new(account)
	check(service.challenges.size()==5 and service.ai_catalog.size()==6,"all source challenge and evolved AI rows")
	check(service.story_data.variants.size()==15,"all five leaders and three story answers")
	check(service.available_ai_profiles()==["coord"],"only owned base AI initially selectable")
	check(service.claim_mail().ok and not service.claim_mail().ok,"welcome mail exactly once")
	var now:=1794355200
	check(service.claim_attendance(now).ok and not service.claim_attendance(now).ok,"Beijing same-day claim idempotent")
	check(not service.claim_attendance(now-86400).ok,"backward calendar cannot duplicate rewards")
	for i in range(1,7):check(service.claim_attendance(now+i*86400).ok,"attendance day %d"%(i+1))
	check(account.state.owned.has("IBS-U-USN-UNNAMED-T01-R03"),"seventh-day verified ship owned locally")
	check(not service.claim_attendance(now+8*86400).ok,"seven-day schedule finite")
	check(service.buy_weekly_ticket(now).ok and not service.buy_weekly_ticket(now).ok,"weekly ticket purchase once")
	# Explicit isolated fixture: exercise the conditional 50% UR split at scale.
	# This does not alter shipped 2/8/20/70 configuration or the real player save.
	var weights:Dictionary=account.config.gacha.weights.duplicate(true)
	account.config.gacha.weights={"ur":100,"elite":0,"rare":0,"common":0}
	account.state.wallet.up_tickets=400
	var featured:=0
	for i in range(40):
		var result:Dictionary=account.recruit(10,"up-stat-%d"%i,"up")
		check(result.ok,"UP batch committed %d"%i)
		for row in result.draws:
			if str(row.id)=="IBS-U-USN-ERMA-MISSOURI":featured+=1
	check(featured>160 and featured<240,"UP featured UR conditional frequency near 50%")
	var sequence:=int(account.state.draw_sequence)
	var batch_id:=str(account.state.pending_recruit.batch_id)
	check(account.recruit_animation("approach").ok,"animation phase saves without reward")
	var reloaded=Economy.new(path)
	check(reloaded.load_state().ok and str(reloaded.state.pending_recruit.batch_id)==batch_id and int(reloaded.state.draw_sequence)==sequence,"reopen committed animation never rerolls")
	check(account.recruit_animation("complete").ok and int(account.state.draw_sequence)==sequence,"skip/complete does not draw again")
	account.config.gacha.weights=weights
	check(service.buy_profile("gunnery").ok and not service.buy_profile("gunnery").ok,"six-medal base AI purchase no duplicates")
	check(not service.buy_profile("evo-screen").ok,"evolved AI campaign prerequisite enforced")
	var core=Core.new()
	check(core.start(),"native core subprocess")
	var personal:Dictionary=account.state.owned.duplicate(true)
	var ammo:=int(account.wallet().ammo_stock)
	var opened:Dictionary=core.request({"op":"new_campaign","id":"CAMP-ALLIES-02","difficulty":"standard","seed":6106,"profile":"coord"})
	check(opened.ok,"real historical mode opens")
	var raw:Dictionary=core.request({"op":"save","serialized":true})
	check(service.begin_mode({"mode":"campaign","id":"CAMP-ALLIES-02","difficulty":"standard","title":"埃斯佩兰斯角","side":"allies"},str(raw.serialized)).ok,"borrowed mode committed with raw snapshot")
	check(not service.claim_mail().ok and not account.buy("ammo_pack").ok and not account.recruit().ok,"borrowed modes also lock all port transactions")
	for fleet in core.view.get("fleets",[]):core.request({"op":"ai","fleet":int(fleet.id),"mode":"auto","profile":"coord","move":true,"gun":true,"torpedo":true})
	for i in range(3):
		if core.view.get("result")!=null:break
		core.request({"op":"step","seconds":2700})
	raw=core.request({"op":"save","serialized":true})
	var campaign:Dictionary=service.finish_mode(core.view,str(raw.serialized))
	check(campaign.ok and int(service.data().campaign.get("CAMP-ALLIES-02",{}).get("stars",0))>0,"real campaign result records stars")
	actual_results.append({"mode":"campaign","result":core.view.get("result"),"receipt":campaign.get("receipt",{})})
	var tickets:=int(account.wallet().tickets)
	check(service.finish_mode(core.view,str(raw.serialized)).get("duplicate",false) and int(account.wallet().tickets)==tickets,"mode finish cannot reward twice")
	check(account.state.owned==personal and int(account.wallet().ammo_stock)==ammo,"borrowed combat never changes personal damage or ammo")
	account.state.wallet.tickets=1000 # Explicit price-boundary fixture, not a gameplay grant.
	check(service.buy_profile("evo-screen").ok and int(account.wallet().tickets)==200,"existing 800-ticket evolved price and unlock")
	check(service.set_profile("evo-screen").ok and service.selected_profile()=="evo-screen","owned evolved profile available")
	for match_index in range(5):
		opened=core.request({"op":"new","variant":"challenge","stage":"challenge-01","seed":6100,"side":"allies","enemy":"gunnery","profile":"gunnery","leaderSlot":1})
		raw=core.request({"op":"save","serialized":true})
		check(opened.ok and service.begin_mode({"mode":"challenge","id":"challenge-01","title":"哨戒接触","side":"allies"},str(raw.serialized)).ok,"real repeat challenge starts %d"%match_index)
		for fleet in core.view.get("fleets",[]):core.request({"op":"ai","fleet":int(fleet.id),"mode":"auto","profile":"gunnery","move":true,"gun":true,"torpedo":true})
		for i in range(3):
			if core.view.get("result")!=null:break
			core.request({"op":"step","seconds":2700})
		raw=core.request({"op":"save","serialized":true})
		var finished:Dictionary=service.finish_mode(core.view,str(raw.serialized))
		check(finished.ok and finished.receipt.success,"challenge primary objective actually achieved %d"%match_index)
		check(int(finished.receipt.rewards.tickets)==(2 if match_index<4 else 0),"global-first then weekly-three reward cap %d"%match_index)
		actual_results.append({"mode":"challenge","result":core.view.get("result"),"receipt":finished.get("receipt",{})})
	check(service.available_ai_profiles().has("torpedo"),"challenge global first unlocks torpedo AI")
	check(service.claim_weekly_supply().ok and not service.claim_weekly_supply().ok,"real three-clear weekly supply once")
	opened=core.request({"op":"new","variant":"","seed":6106,"side":"allies","enemy":"gunnery","profile":"coord","realtime":true})
	raw=core.request({"op":"save","serialized":true})
	check(service.begin_mode({"mode":"training","id":"day","course_id":"day","title":"昼间实操","side":"allies"},str(raw.serialized)).ok,"training active")
	check(not service.finish_mode(core.view,str(raw.serialized)).ok,"course cannot finish without real evidence")
	service.record_command({"op":"ai","mode":"manual","move":true},core.view)
	check(not account.state.active_run.evidence.get("aiDelegated",false),"manual AI settings never count as delegation")
	service.record_command({"op":"route","mode":"follow"},core.view)
	check(not account.state.active_run.evidence.get("followPreview",false),"accepted route alone is not a preview")
	service.record_command({"op":"fire","weapon":"torpedo"},core.view)
	check(not account.state.active_run.evidence.get("torpedoAimed",false) and not account.state.active_run.evidence.get("torpedoAdjusted",false),"accepted torpedo alone is not aimed or adjusted")
	check(service.abandon_mode(core.view,str(raw.serialized)).ok,"explicit unfinished mode abandon without fake battle result")
	check(account.latest_receipt().status=="abandoned" and account.latest_receipt().rewards.is_empty(),"abandon receipt truthful and unrewarded")
	core.close()
	for suffix in ["",".bak",".tmp"]:
		if FileAccess.file_exists(path+suffix):DirAccess.remove_absolute(ProjectSettings.globalize_path(path+suffix))
	var report:={"checks":checks,"passed":checks-failures.size(),"failures":failures,"featured_ur_out_of_400":featured,"actual_native_results":actual_results}
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://../artifacts/godot/full-modes"))
	var file:=FileAccess.open("res://../artifacts/godot/full-modes/economy-receipt.json",FileAccess.WRITE)
	if file:file.store_string(JSON.stringify(report,"\t"));file.close()
	print(JSON.stringify({"checks":checks,"passed":checks-failures.size(),"failures":failures,"featured_ur_out_of_400":featured}))
	quit(0 if failures.is_empty() else 1)
