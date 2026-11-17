extends RefCounted
## Own progress, concrete receipt proofs and one unique protocol. No battle verdict
## is manufactured here; the active native mode and normal services settle it.
const Data=preload("res://scripts/canon_story_data.gd")
const VERSION:String="story-canon-v2"
const KEY:String="story_canon_v2"
const PROTOCOL:String="canon-v2-beacon-MCP-011"
const TOUR:Array[String]=["roster","campaign","arena","ship_detail","shop","warehouse"]
var account
func _init(owner)->void:account=owner
func enabled()->bool:return account.state.get("progression",{}).has(KEY)
func ensure()->void:
	account.state.get_or_add("progression",{})
	account.state.progression.get_or_add(KEY,{"version":VERSION,"selected":"chapter-01","chapters":{},"pending":{},"protocol":{"id":PROTOCOL,"unit_id":"MCP-011","custody":"undiscovered","redeemed":false},"tour_seen":[],"visits":[],"transactions":{}})
	for id in Data.IDS:
		var data:Dictionary=Data.chapter(id)
		if data.is_empty():continue
		account.state.progression[KEY].chapters.get_or_add(id,{"node":str(data.get("entry","")),"line":0,"seen":[],"choices":{},"proofs":{},"complete":false})
func state()->Dictionary:
	ensure();return account.state.progression[KEY]
func chapter()->Dictionary:return state().chapters.get(str(state().selected),{})
func node()->Dictionary:return Data.scene(str(state().selected),str(chapter().get("node","")))
func visible_lines(current:Dictionary)->Array:
	var lines:Array=[]
	for line in current.get("lines",[]):
		var condition:Dictionary=line.get("if_choice",{})
		if not condition.is_empty():
			var source:Dictionary=state().chapters.get(str(condition.get("chapter",state().selected)),{})
			if str(source.get("choices",{}).get(str(condition.get("node","")),""))!=str(condition.get("value","")):continue
		lines.append(line)
	return lines
func _commit(before:Dictionary,message:String,extra:Dictionary={})->Dictionary:return account._commit(before,message,extra)
func _fail(message:String)->Dictionary:return {"ok":false,"message":message}
func select(id:String)->Dictionary:
	if not Data.IDS.has(id) or Data.chapter(id).is_empty():return _fail("这一章还未装入航海日志")
	if not account.state.get("active_run",{}).is_empty():return _fail("先继续或结束当前行动，再翻开新篇章")
	var before:Dictionary=account.state.duplicate(true);ensure()
	var index:int=Data.IDS.find(id)
	if index>0 and not bool(state().chapters.get(Data.IDS[index-1],{}).get("complete",false)):
		account.state=before;return _fail("先完成上一章")
	state().selected=id
	return _commit(before,"航海日志已展开")
func _advance()->void:
	var current:Dictionary=node();var saved:Dictionary=chapter()
	if not saved.seen.has(str(current.id)):saved.seen.append(str(current.id))
	if str(current.get("kind",""))=="complete":saved.complete=true;return
	saved.node=str(current.get("next",current.id));saved.line=0
func move(kind:String,value:String="")->Dictionary:
	if not account.state.get("active_run",{}).is_empty():return _fail("海上行动尚未结束，请先安全返航")
	var before:Dictionary=account.state.duplicate(true);var current:Dictionary=node();var saved:Dictionary=chapter()
	var category:String=str(current.get("kind",""))
	if kind=="complete" and category=="complete":
		if bool(saved.get("complete",false)):return {"ok":true,"message":"这一章已记入航海日志"}
		_advance()
	elif category=="dialogue" and kind in ["next","skip","choice"]:
		var last:int=maxi(0,visible_lines(current).size()-1)
		if kind=="choice":
			if int(saved.line)<last:return _fail("先把这段话听完")
			var choices:Array=current.get("choices",[])
			if not choices.any(func(row):return str(row.get("id",""))==value):return _fail("请选择当前对话中的回答")
			saved.choices[str(current.id)]=value;_advance()
			var branch:String=str(current.get("choice_next",{}).get(value,""))
			if not branch.is_empty() and not Data.scene(str(state().selected),branch).is_empty():saved.node=branch
		elif int(saved.line)<last:saved.line=last if kind=="skip" else int(saved.line)+1
		elif not current.get("choices",[]).is_empty():return _fail("这句话需要你的决定")
		else:_advance()
	elif kind=="defer" and bool(current.get("optional",false)):
		saved.proofs[str(current.id)]={"deferred":true};_advance()
	else:return _fail("这一段需要实际行动，跳过对白不能替代完成任务")
	if str(saved.node)!=str(current.id) or bool(saved.get("complete",false)):_apply_story_custody(current)
	return _commit(before,"故事进度已保存")
func _apply_story_custody(current:Dictionary)->void:
	# Explicit script events move the SAME object; none create a second protocol.
	var event:String=str(current.get("protocol_event",current.get("action",{}).get("protocol_event","")))
	var target:String=str(current.get("protocol_custody",""))
	if event in ["confiscate","surrender","alliance_custody"]:target="alliance"
	elif event in ["return","returned","return_protocol"]:target="returned"
	if target in ["alliance","returned"] and str(state().protocol.custody)!="undiscovered" and not state().protocol.redeemed:state().protocol.custody=target
func visit(route:String)->void:
	if not enabled():return
	if route in ["canon_story","canon_catalog","battle","result","title"]:return
	var before:Dictionary=account.state.duplicate(true);var s:Dictionary=state();var changed:bool=false
	if not s.visits.has(route):s.visits.append(route);changed=true
	if Data.action(node())=="harbor_tour" and TOUR.has(route) and not s.tour_seen.has(route):s.tour_seen.append(route);changed=true
	if changed:_commit(before,"参观位置已记入日志")
func arm()->Dictionary:
	if not state().pending.is_empty():return _fail("已有这段故事的行动记录，先核对结果或继续航次")
	if not account.state.get("active_run",{}).is_empty():return _fail("请先继续或结束当前航次")
	var current:Dictionary=node();var before:Dictionary=account.state.duplicate(true)
	state().pending={"chapter":str(state().selected),"node":str(current.id),"action":Data.action(current),"run_id":"","stage":str(current.get("native_stage","")),"created_at":int(Time.get_unix_time_from_system())}
	if current.has("tactical_lesson"):
		state().pending["tactical_lesson"]=str(current.tactical_lesson)
		state().pending["mechanics_version"]=str(current.get("mechanics_version","cas-island-war-v3"))
	return _commit(before,"行动已登记，等待真实结果")
func bind_run()->Dictionary:
	var active:Dictionary=account.state.get("active_run",{})
	if active.is_empty():return _fail("行动未能开始，尚未记录通关")
	var pending:Dictionary=state().pending
	if pending.is_empty() or str(pending.get("chapter",""))!=str(state().selected) or str(pending.get("node",""))!=str(node().id):return _fail("航次不属于当前故事节点")
	var matching:bool=false
	if str(active.get("mode",""))=="exercise":
		var context:Dictionary=active.get("context",{})
		matching=str(context.get("canon_version",""))==VERSION and str(active.get("stage_id",""))==str(pending.node)
		if pending.has("tactical_lesson"):matching=matching and str(context.get("tactical_lesson",""))==str(pending.tactical_lesson) and str(context.get("request",{}).get("version",""))==str(pending.get("mechanics_version","cas-island-war-v3"))
	elif str(active.get("mode",""))=="littoral":
		var request:Dictionary=active.get("request",{})
		var expected:String=str({"littoral_sea":"sea_control","littoral_landing":"landing","littoral_combined":"combined"}.get(str(pending.action),""))
		matching=str(request.get("version",""))=="cas-littoral-v4" and int(request.get("seed",-1))==Data.seed(node()) and (str(request.get("mode",""))=="defense" if str(pending.action)=="island_defense" else str(request.get("mode",""))=="tutorial" and str(request.get("lesson",""))==expected)
	if not matching:return _fail("现有航次与故事委托不匹配，未变更日志")
	if str(pending.get("run_id",""))==str(active.run_id):return {"ok":true,"message":"同一航次已绑定"}
	var before:Dictionary=account.state.duplicate(true)
	state().pending.run_id=str(active.run_id)
	return _commit(before,"已绑定本次真实航次")
func cancel_empty_pending()->void:
	if not state().pending.is_empty() and str(state().pending.get("run_id","")).is_empty() and account.state.get("active_run",{}).is_empty():
		var before:Dictionary=account.state.duplicate(true);state().pending={};_commit(before,"未开始的行动已清理")
func check_action(home=null)->Dictionary:
	var current:Dictionary=node();var action:String=Data.action(current)
	if action.is_empty():return _fail("当前不是操作关卡")
	if not account.state.get("active_run",{}).is_empty():return _fail("请先完成当前行动并安全返航")
	var before:Dictionary=account.state.duplicate(true);var proof:Dictionary={}
	if action=="harbor_tour":
		for route in TOUR:
			if not state().tour_seen.has(route):return _fail("下一站："+str({"roster":"舰娘","campaign":"战役航图","arena":"竞技航线","ship_detail":"养成档案","shop":"军需处","warehouse":"仓库"}.get(route,route)))
		proof={"routes":state().tour_seen.duplicate()}
	elif action=="growth":
		if not state().visits.has("ship_detail"):return _fail("先打开一位舰娘的详细档案，查看等级、熟练与舰装")
		proof={"visited":"ship_detail"}
	elif action in ["home_build","home_garrison"]:
		if home==null:return _fail("请先进入家园")
		var island:Dictionary=home.state()
		if action=="home_build":
			if island.get("buildings",[]).size()<3:return _fail("在岛上实际建好至少两座设施，再回来继续")
			proof={"buildings":island.buildings.duplicate(true)}
		else:
			if island.get("garrison",[]).is_empty():return _fail("在家园驻防里确认至少一位留守舰娘")
			var tactical:Array=island.get("tactical_garrison",[])
			if not tactical.has("MCP-034") or not tactical.has("MCP-011"):return _fail("在「驻防 → 战术驻防」安排礁刃与灯鲨并保存，舰队和岸上部队都要有人留守")
			proof={"garrison":island.garrison.duplicate(),"tactical_garrison":tactical.duplicate()}
	elif action=="fixed_recruit":return redeem_protocol(home)
	else:
		var pending:Dictionary=state().pending
		if str(pending.get("chapter",""))!=str(state().selected) or str(pending.get("node",""))!=str(current.id) or str(pending.get("action",""))!=action or str(pending.get("run_id","")).is_empty():return _fail("先开始这一段的真实行动")
		var receipt:Dictionary=account.state.get("settled",{}).get(str(pending.run_id),{})
		if receipt.is_empty():return _fail("这次行动还没有已保存的战报")
		var actual_success:bool=bool(receipt.get("success",false))
		if pending.has("tactical_lesson"):
			if home==null:return _fail("训练战报读取服务尚未就绪")
			var trained:Dictionary=home._native(str(receipt.get("snapshot","")))
			var native:Dictionary=trained.get("view",{})
			var training_value:Variant=native.get("littoral",{}).get("training")
			var checks:Dictionary=training_value if training_value is Dictionary else {}
			var expected_version:String=str(pending.get("mechanics_version","cas-island-war-v3"))
			if not trained.get("ok",false) or str(native.get("island_war",{}).get("version",""))!=expected_version or str(checks.get("lesson",""))!=str(pending.tactical_lesson):return _fail("缺少属于本次课程的真实新版战报")
			var native_won:bool=native.get("result") is Dictionary and str(native.result.get("version",""))==expected_version and bool(native.result.get("success",false)) and bool(native.get("littoral",{}).get("outcome",{}).get("success",false))
			if not actual_success or not native_won or not bool(checks.get("complete",false)):
				state().pending={};_commit(before,"本次武器训练尚未完成，可重新练习")
				return _fail("需在实战中完成武器分工与撤收；拖卡或读完提示不能代替。")
			proof["tactical_training"]=checks.duplicate(true)
		if action=="island_defense":
			if home==null or str(receipt.get("mode",""))!="littoral" or str(receipt.get("request",{}).get("mode",""))!="defense":return _fail("缺少本次真实迎敌战报")
			var terminal:Dictionary=home._native(str(receipt.get("snapshot","")))
			if not terminal.get("ok",false) or terminal.get("view",{}).get("result")==null:return _fail("迎敌尚未抵达真实终局")
			proof["terminal_result"]=terminal.view.result.duplicate(true)
			proof["native_outcome"]=terminal.view.get("littoral",{}).get("outcome",{}).duplicate(true)
		if not actual_success and action!="island_defense":
			state().pending={};_commit(before,"本次未完成目标，可整备后重试")
			return _fail("本次未完成目标。你的剧情选择仍然保留，可重试这一关")
		proof.merge({"run_id":str(pending.run_id),"receipt":receipt.duplicate(true),"actual_success":actual_success,"terminal_status":"won" if actual_success else "lost_or_withdrawn"},true)
		var protocol_search:bool=str(current.get("protocol_identity",""))==PROTOCOL or str(state().selected)=="chapter-01" and str(current.id)=="v2c1-salvage"
		if action=="salvage_tutorial" and protocol_search and str(state().protocol.custody)=="undiscovered":state().protocol.custody="recovered"
	chapter().proofs[str(current.id)]=proof;state().pending={};_advance()
	if action=="island_defense":
		var branch:String=str(current.get("success_next" if bool(proof.get("actual_success",false)) else "failure_next",""))
		if not branch.is_empty() and not Data.scene(str(state().selected),branch).is_empty():chapter().node=branch
	return _commit(before,"行动结果已核对，继续故事",{"proof":proof})
func redeem_protocol(home)->Dictionary:
	if home==null:return _fail("战术协议终端尚未准备")
	var s:Dictionary=state()
	if bool(s.protocol.redeemed):return _fail("同一份协议已经完成同步，不会重复发放")
	if str(s.protocol.custody)!="returned":return _fail("协议尚未由联盟归还，请先继续故事")
	var before:Dictionary=account.state.duplicate(true);var duplicate:bool=home.state().units.has("MCP-011")
	home._own_unit("MCP-011");s.protocol.redeemed=true;s.protocol.custody="bound"
	s.transactions[PROTOCOL]={"unit_id":"MCP-011","existing_identity":duplicate,"no_duplicate_currency":true}
	chapter().proofs[str(node().id)]={"protocol":PROTOCOL,"unit_id":"MCP-011"};_advance()
	return _commit(before,"灯鲨已应答 · 同一协议只同步一次",{"unit_id":"MCP-011","duplicate_identity":duplicate})
