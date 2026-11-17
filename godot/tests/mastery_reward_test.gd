extends SceneTree
## Isolated account fixtures exercise claims; gameplay accrual is covered by meta_economy_core_test.
const Economy=preload("res://scripts/economy.gd")
var checks:=0
var failures:Array[String]=[]
func _initialize()->void:call_deferred("_run")
func check(value:bool,name:String)->void:
	checks+=1
	if not value:failures.append(name);push_error(name)
func _run()->void:
	var path:="user://tests/mastery-rewards-%d.json"%OS.get_process_id()
	var account=Economy.new(path);check(account.load_state().ok,"profile created")
	var first:=str(account.formation[0]);var second:=str(account.formation[1])
	check(account.mastery_rewards(first).size()==4 and account.mastery_rewards("unknown").is_empty(),"four known thresholds only for owned ship")
	var before:Dictionary=account.wallet()
	check(not account.claim_mastery_reward(first,250).ok and not account.claim_mastery_reward(first,100).ok,"unearned and unknown thresholds rejected")
	check(int(account.wallet().origins)==int(before.origins) and int(account.wallet().credits)==int(before.credits),"rejected claims preserve balances")
	account.state.owned[first].mastery=1000
	account.state.owned[second].mastery=250
	for threshold in [250,500,750,1000]:
		var result:Dictionary=account.claim_mastery_reward(first,threshold)
		check(result.ok and result.grants.origins==5 and result.grants.credits==50,"actual small grant at %d"%threshold)
		check(account.claim_mastery_reward(first,threshold).get("duplicate",false),"duplicate claim safe at %d"%threshold)
	check(int(account.wallet().origins)==int(before.origins)+20 and int(account.wallet().credits)==int(before.credits)+200,"four milestones pay exactly twenty origins and two hundred silver")
	check(account.mastery_rewards(first).all(func(row):return row.status=="claimed"),"claimed status exposed")
	check(account.claim_mastery_reward(second,250).ok,"different ship has independent milestone ledger")
	var restored=Economy.new(path);check(restored.load_state().ok and restored.claim_mastery_reward(first,250).get("duplicate",false),"claims remain idempotent after application restart")
	restored.state.owned[second].mastery=500
	restored.state.active_run={"run_id":"isolated-lock-fixture"}
	check(not restored.claim_mastery_reward(second,500).ok,"in-voyage transaction lock applies")
	restored.state.active_run={}
	var broken=Economy.new("res://data")
	broken.state=restored.state.duplicate(true);broken.formation.assign(restored.formation)
	var saved:Dictionary=broken.state.duplicate(true)
	check(not broken.claim_mastery_reward(second,500).ok and broken.state==saved,"atomic write failure rolls back reward and per-ship claim ledger")
	if FileAccess.file_exists("res://data.tmp"):DirAccess.remove_absolute(ProjectSettings.globalize_path("res://data.tmp"))
	var report:Dictionary={"checks":checks,"passed":checks-failures.size(),"failures":failures,"fixture_scope":"isolated account reward boundaries; no invented combat receipt"}
	var file=FileAccess.open("res://../artifacts/mastery-rewards.json",FileAccess.WRITE);file.store_string(JSON.stringify(report,"  "));file.close()
	print(JSON.stringify(report));quit(0 if failures.is_empty() else 1)
