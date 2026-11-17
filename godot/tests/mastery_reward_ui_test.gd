extends SceneTree
## Threshold fixture is isolated; claim callbacks and persistence are real account transactions.
const Main=preload("res://scenes/main.tscn")
const Economy=preload("res://scripts/economy.gd")
var app
var checks:=0
var failures:Array[String]=[]

func _initialize()->void:call_deferred("run")
func check(value:bool,title:String)->void:
	checks+=1
	if not value:failures.append(title);push_error(title)
func reward_button(threshold:int)->Button:
	for node in app.find_children("*","Button",true,false):
		if node.is_visible_in_tree() and int(node.get_meta("mastery_threshold",-1))==threshold:return node
	return null
func refresh()->void:
	app.show_page("ship_detail")
	await process_frame

func run()->void:
	var path:="user://tests/mastery-ui-%d.json" % OS.get_process_id()
	app=Main.instantiate();app.economy=Economy.new(path);root.add_child(app)
	app.set_process(false)
	await process_frame
	var id:="IBS-U-USN-FLETCHER"
	app.set_meta("detail_ship_id",id);app.set_meta("ship_detail_tab","growth")
	await refresh()
	var initial:Dictionary=app.economy.wallet().duplicate(true)
	var thresholds:Array=[]
	for row in app.economy.mastery_rewards(id):thresholds.append(int(row.threshold))
	check(thresholds==[250,500,750,1000],"actual four-tier reward catalogue")
	for threshold in thresholds:
		var control:=reward_button(threshold)
		check(control!=null and control.disabled and control.text.contains("未达成"),"unearned tier visibly disabled: "+str(threshold))
	check(not app.economy.claim_mastery_reward(id,250).ok and app.economy.wallet()==initial,"unearned direct claim cannot mint currency")
	# Test-only threshold setup; no battle victory, earned mastery or production reward is fabricated.
	app.economy.state.owned[id].mastery=249
	await refresh()
	check(reward_button(250).disabled and not app.economy.claim_mastery_reward(id,250).ok,"249 mastery cannot claim 250 tier")
	app.economy.state.owned[id].mastery=250
	await refresh()
	check(not reward_button(250).disabled and reward_button(250).text.contains("领取") and reward_button(500).disabled,"only reached tier becomes claimable")
	reward_button(250).pressed.emit();await process_frame
	check(int(app.economy.wallet().origins)==int(initial.origins)+5 and int(app.economy.wallet().credits)==int(initial.credits)+50,"actual UI claim credits exactly five origins and fifty silver")
	check(reward_button(250).disabled and reward_button(250).text.contains("已领取"),"successful claim visibly disables tier")
	var claimed:Dictionary=app.economy.wallet().duplicate(true)
	var duplicate:Dictionary=app.economy.claim_mastery_reward(id,250)
	check(duplicate.get("duplicate",false) and app.economy.wallet()==claimed,"repeated transaction cannot pay twice")
	check(int(app.economy.state.owned[id].mastery)==250,"claim neither spends nor increases mastery")
	var restored=Economy.new(path)
	var loaded:Dictionary=restored.load_state()
	var restored_wallet:Dictionary=restored.wallet()
	check(loaded.ok and restored.mastery_rewards(id)[0].claimed and claimed.keys().all(func(key):return int(restored_wallet.get(key,-1))==int(claimed[key])),"reward and claim flag persist across account reload")
	app.economy.state.owned[id].mastery=1000
	await refresh()
	for threshold in [500,750,1000]:
		check(not reward_button(threshold).disabled,"reached tier button enabled: "+str(threshold))
		reward_button(threshold).pressed.emit();await process_frame
		check(reward_button(threshold).disabled and reward_button(threshold).text.contains("已领取"),"tier callback commits once: "+str(threshold))
	check(int(app.economy.wallet().origins)==int(initial.origins)+20 and int(app.economy.wallet().credits)==int(initial.credits)+200,"four independent tiers award exact lifetime total")
	check(not app.economy.claim_mastery_reward(id,999).ok,"undefined milestone rejected")
	app.audio.shutdown();app.core.close();app.queue_free();await process_frame
	for suffix in ["",".bak",".tmp"]:
		if FileAccess.file_exists(path+suffix):DirAccess.remove_absolute(ProjectSettings.globalize_path(path+suffix))
	var report:={"checks":checks,"passed":checks-failures.size(),"failures":failures,"scope":"real growth-page reward callbacks and account reload; isolated mastery threshold fixture; no fake battle result"}
	var output:="res://../artifacts/godot/meta-ui/mastery-receipt.json"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output.get_base_dir()))
	var file:=FileAccess.open(output,FileAccess.WRITE);file.store_string(JSON.stringify(report,"\t"));file.close()
	print(JSON.stringify(report));quit(0 if failures.is_empty() else 1)
