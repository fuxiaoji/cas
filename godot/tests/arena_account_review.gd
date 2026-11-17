extends SceneTree
const Economy=preload("res://scripts/economy.gd")
const League=preload("res://scripts/arena_service.gd")
const Core=preload("res://scripts/core_bridge.gd")
var checks:=0
var failures:Array[String]=[]
var evidence:Array=[]
func _initialize()->void:call_deferred("run")
func check(ok:bool,title:String)->void:
	checks+=1
	if not ok:failures.append(title);push_error(title)
func save(core)->String:return str(core.request({"op":"save","serialized":true}).get("serialized",""))
func run()->void:
	var account=Economy.new("user://tests/arena-economy-%d.json"%OS.get_process_id())
	check(account.load_state().ok,"isolated real account initialized")
	var league=League.new(account)
	var core=Core.new()
	var wallet:Dictionary=account.wallet().duplicate(true)
	check(not league.claim_tier("ranked","cadet").ok,"new profile cannot claim a tier before a completed battle")
	for mode in ["ranked","team3"]:
		var plan:Dictionary=league.preview(mode)
		check(plan.ok,"owned fleet fits real "+mode+" budget")
		var request:Dictionary={"op":"new_arena","arena_version":League.VERSION,"seed":6106 if mode=="ranked" else 6111,"mode":mode,"groups":plan.groups}
		check(core.request(request).get("ok",false),"real native arena generated "+mode)
		var initial:String=save(core)
		var begun:Dictionary=league.begin(request,core.view,initial)
		check(begun.get("ok",false),"verified real arena begins "+mode)
		var run_id:=str(begun.get("run_id",""))
		var frozen:Dictionary=account.state.duplicate(true)
		check(not league.begin(request,core.view,initial).get("ok",false),"active battle cannot be replaced")
		check(not league.settle(core.view,initial).ok,"no result cannot settle or award")
		var fake:Dictionary=core.view.duplicate(true);fake.result={"winner":"allies"}
		check(not league.settle(fake,initial).ok,"UI-only fabricated victory rejected against native snapshot")
		check(account.state==frozen,"all rejected result mutations preserve exact account")
		var moved:Dictionary=core.request({"op":"step","seconds":25})
		check(moved.get("ok",false),"actual battle advances before restart")
		var mid:String=save(core)
		check(account.save_sortie(mid).ok,"battle snapshot saved through real account journal")
		var restarted=Economy.new(account.save_path)
		check(restarted.load_state().ok,"account restarts with active arena")
		check(str(restarted.state.active_run.run_id)==run_id and str(restarted.state.active_run.snapshot)==mid,"restart retains exact arena identity and raw RNG snapshot")
		account=restarted;league=League.new(account)
		check(core.request({"op":"load","serialized":str(account.state.active_run.snapshot)}).get("ok",false),"mid-battle native state resumes")
		check(core.request({"op":"step","seconds":1200}).get("ok",false) and core.view.get("result") is Dictionary,"real native combat reaches terminal "+mode)
		var terminal:String=save(core)
		var actual:Dictionary=core.view.duplicate(true)
		var wrong_request:Dictionary=request.duplicate(true);wrong_request.seed=int(wrong_request.seed)+1
		core.request(wrong_request);core.request({"op":"step","seconds":1200})
		check(not league.settle(core.view,save(core)).ok,"different real match cannot settle active identity")
		core.request({"op":"load","serialized":terminal})
		var before:Dictionary=account.state.duplicate(true)
		var original_path:String=account.save_path
		account.save_path="res://tests/arena_account_review.gd/blocked.json"
		check(not league.settle(actual,terminal).ok,"failed disk transaction does not claim success")
		check(account.state==before,"failed settlement restores exact rating wallet and active run")
		account.save_path=original_path
		var result:Dictionary=league.settle(actual,terminal)
		check(result.ok and account.state.active_run.is_empty(),"terminal result commits exactly once "+mode)
		var paid:Dictionary=account.state.duplicate(true)
		check(league.settle(actual,terminal).get("duplicate",false),"duplicate result recognized")
		check(account.state==paid,"duplicate cannot add rating coins or records")
		var claimed:Dictionary=league.claim_tier(mode,"cadet")
		check(claimed.ok,"actual completed match unlocks reached tier "+mode)
		var once:Dictionary=account.state.duplicate(true)
		check(not league.claim_tier(mode,"cadet").ok and account.state==once,"tier reward cannot be claimed twice")
		var loaded=Economy.new(account.save_path);loaded.load_state()
		check(League.new(loaded).profile(mode)==league.profile(mode),"rating statistics and claim IDs persist with stable types")
		evidence.append({"mode":mode,"result":actual.result,"tick":actual.tick,"receipt":result.receipt,"profile":league.profile(mode)})
		account=loaded;league=League.new(account)
	# Explicit forfeit is a loss with no battle grant; no fake native winner is created.
	var plan:Dictionary=league.preview("ranked")
	var request:Dictionary={"op":"new_arena","arena_version":League.VERSION,"seed":6190,"mode":"ranked","groups":plan.groups}
	core.request(request);league.begin(request,core.view,save(core))
	var before_coins:int=int(account.wallet().credits)
	var before_rating:int=int(league.profile("ranked").rating)
	var forfeited:Dictionary=league.settle(core.view,save(core),true)
	check(forfeited.ok and str(forfeited.receipt.result)=="forfeit","explicit forfeit records its own result")
	check(int(league.profile("ranked").rating)<before_rating and int(account.wallet().credits)==before_coins,"forfeit costs rating without granting battle coins")
	check(core.view.get("result")==null,"forfeit does not invent native victory")
	core.close()
	var folder:="res://../artifacts/godot/arena-account/"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	FileAccess.open(folder+"receipt.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"evidence":evidence,"original_wallet":wallet},"  "))
	print("ARENA_ACCOUNT ",JSON.stringify({"checks":checks,"failures":failures}));quit(0 if failures.is_empty() else 1)
