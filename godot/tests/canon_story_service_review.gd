extends SceneTree
## Explicit state fixtures exercise service boundaries; actual arena outcomes use
## native commands. This is not a chapter playthrough or authored-content audit.
const Economy=preload("res://scripts/economy.gd")
const Progression=preload("res://scripts/progression.gd")
const Home=preload("res://scripts/home_service.gd")
const Core=preload("res://scripts/core_bridge.gd")
const Service=preload("res://scripts/canon_story_service.gd")
const Data=preload("res://scripts/canon_story_data.gd")
const Actions=preload("res://scripts/canon_story_actions.gd")
var checks:int=0
var failures:Array=[]
var records:Array=[]
var directory:String="res://../artifacts/story-canon-v2/service-%d/"%OS.get_process_id()
func _initialize()->void:call_deferred("run")
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures.append(label);push_error(label)
func find_action(kind:String)->String:
	for node in Data.chapter("chapter-01").scenes:
		if Data.action(node)==kind:return str(node.id)
	return ""
func run()->void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	var normal:Dictionary={"main":FileAccess.get_sha256("user://cas_port_v1.json"),"backup":FileAccess.get_sha256("user://cas_port_v1.json.bak")}
	var source:String="res://../artifacts/boot-loading-20261114/max-level-test-account-64476.json"
	var copied:int=DirAccess.copy_absolute(ProjectSettings.globalize_path(source),ProjectSettings.globalize_path(directory+"max-clone.json"))
	check(copied==OK,"clone preserved full test fixture, not normal user's active account")
	var account=Economy.new(directory+"max-clone.json");check(account.load_state().ok,"max-level clone loads through real economy")
	var service=Service.new(account);var home=Home.new(account)
	check(service.select("chapter-01").ok,"new canon independently selected on max profile")
	var old:Dictionary=account.state.progression.duplicate(true);old.erase(Service.KEY)
	service.chapter().node=find_action("home_build")
	check(service.check_action(home).ok,"existing maximum buildings satisfy construction mastery without impossible new build")
	service.chapter().node=find_action("growth")
	service.visit("ship_detail")
	check(service.check_action(home).ok,"max-level growth requires viewing, not impossible further levels")
	service.chapter().node=find_action("home_garrison")
	check(home.set_garrison([str(account.formation[0])]).ok,"save real naval garrison through current home service")
	check(home.set_tactical_garrison([]).ok,"explicit fixture has no tactical garrison yet")
	check(not service.check_action(home).ok,"naval garrison alone cannot skip the ground defense teaching")
	check(home.set_tactical_garrison(["MCP-034","MCP-011"]).ok,"save actual owned reef-blade and lamp-shark tactical defenders")
	check(service.check_action(home).ok,"current naval and tactical garrisons jointly complete defense setup")
	var owned:Dictionary=home.state().units.duplicate(true)
	var currency:Dictionary=account.state.wallet.duplicate(true)
	var resources:Dictionary=home.state().resources.duplicate(true)
	service.chapter().node=find_action("fixed_recruit")
	service.state().protocol.custody="recovered"
	check(not service.redeem_protocol(home).ok,"recovered protocol cannot skip confiscation and return")
	service.state().protocol.custody="returned"
	check(service.redeem_protocol(home).ok,"already-owned max account can bind same returned story protocol once")
	check(home.state().units==owned and account.state.wallet==currency and home.state().resources==resources,"already-owned MCP011 preserves condition/personality and gives no duplicate currency")
	check(not service.redeem_protocol(home).ok,"second fixed redemption rejected")
	service.chapter().choices["boundary-choice"]="keep"
	var visible:Array=service.visible_lines({"lines":[{"text":"keep","if_choice":{"chapter":"chapter-01","node":"boundary-choice","value":"keep"}},{"text":"exchange","if_choice":{"chapter":"chapter-01","node":"boundary-choice","value":"exchange"}}]})
	check(visible.size()==1 and visible[0].text=="keep","later chapter conditional echoes preserve actual recorded choice")
	# Journal failure must roll back the unique transaction and identity together.
	service.chapter().node=find_action("fixed_recruit");service.state().protocol.redeemed=false;service.state().protocol.custody="returned";service.state().transactions={}
	var before:Dictionary=account.state.duplicate(true);var path:String=account.save_path
	account.save_path="res://tests/canon_story_service_review.gd/impossible.json"
	check(not service.redeem_protocol(home).ok and account.state==before,"failed journal commit rolls back protocol redemption atomically")
	account.save_path=path
	var core=Core.new();var progression=Progression.new(account)
	for kind in ["arena_ranked","arena_3v3"]:
		service.chapter().node=find_action(kind);service.state().pending={}
		check(service.arm().ok,"arm actual optional "+kind)
		var mode:String="ranked" if kind=="arena_ranked" else "team3"
		var request:Dictionary={"op":"new_arena","arena_version":preload("res://scripts/arena_service.gd").VERSION,"seed":6109,"mode":mode,"groups":[{"id":"canon-fifth","name":"第五驱逐舰小队","ships":Actions.FIFTH.duplicate()}]}
		check(core.request(request).get("ok",false),"actual borrowed arena native request accepted "+mode)
		var save:Dictionary=core.request({"op":"save","serialized":true})
		var begun:Dictionary=progression.begin_mode({"mode":"exercise","id":str(service.node().id),"title":"新正史战网教学","canon_version":Service.VERSION,"side":"allies","request":request},str(save.serialized))
		check(begun.ok and service.bind_run().ok,"exercise-context new_arena correctly binds story identity "+mode)
		check(not service.check_action(home).ok,"active optional arena cannot be skipped as a completed win "+mode)
		check(core.request({"op":"step","seconds":1200}).get("ok",false) and core.view.get("result")!=null,"actual bot match reaches terminal "+mode)
		save=core.request({"op":"save","serialized":true})
		var settled:Dictionary=progression.finish_mode(core.view,str(save.serialized))
		check(settled.ok,"actual arena result settles in separate practice context "+mode)
		var advanced:Dictionary=service.check_action(home)
		check(bool(advanced.ok)==bool(settled.receipt.success),"only actual optional arena victory advances gate "+mode)
		if not advanced.ok:check(service.move("defer").ok,"optional loss still permits explicit defer "+mode)
		records.append({"action":kind,"native_result":core.view.result.duplicate(true),"receipt":settled.receipt.duplicate(true)})
	core.close()
	var after:Dictionary=account.state.progression.duplicate(true);after.erase(Service.KEY)
	for key in ["chapter1","chapter2","chapter3","story","campaign"]:check(after.get(key)==old.get(key),"existing legacy progress not advanced "+key)
	var current:Dictionary={"main":FileAccess.get_sha256("user://cas_port_v1.json"),"backup":FileAccess.get_sha256("user://cas_port_v1.json.bak")}
	check(normal==current,"normal active account and backup bytes unchanged during isolated service review")
	var report:Dictionary={"checks":checks,"passed":failures.is_empty(),"failures":failures,"records":records,"scope":"explicit max-profile state fixtures plus actual native arena settlement; not a story playthrough"}
	FileAccess.open(directory+"receipt.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("CANON_SERVICE "+JSON.stringify(report));quit(0 if failures.is_empty() else 1)
