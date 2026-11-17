extends RefCounted
const VERSION="cas-event-tide-v1"
const CURRENT_VERSION="cas-event-tide-v2"
const MAX_RESERVES=64
var account
var content:Dictionary
func _init(owner):
	account=owner;content=JSON.parse_string(FileAccess.get_file_as_string("res://data/tide-event-v1.json"))
func ensure()->void:
	account.state.wallet.get_or_add("tide_tokens",0)
	account.state.get_or_add("tide_event_v1",{"version":VERSION,"intro_read":false,"ending_read":false,"wins":0,"best_score":0,"purchases":{}})
func read_story(ending:bool=false)->Dictionary:
	ensure();var before:Dictionary=account.state.duplicate(true)
	account.state.tide_event_v1["ending_read" if ending else "intro_read"]=true
	return account._commit(before,"活动故事已记入档案")
func begin(request:Dictionary,serialized:String)->Dictionary:
	ensure()
	if not account.state.get("active_run",{}).is_empty():return account._fail("请先继续或结束当前行动")
	var id:String=str(request.get("character_id",""))
	if str(request.get("op",""))!="new_tide" or not account.state.owned.has(id):return account._fail("请选择已获得的舰娘")
	var version:String=str(request.get("version",VERSION))
	if version not in [VERSION,CURRENT_VERSION]:return account._fail("活动规则版本不受支持")
	if version==CURRENT_VERSION:
		var roster:Variant=request.get("roster",[])
		if not roster is Array or roster.size()>MAX_RESERVES:return account._fail("援军阵容无效")
		var seen:Dictionary={}
		seen[id]=true
		for reserve in roster:
			if not reserve is String or seen.has(reserve) or not account.state.owned.has(reserve):return account._fail("援军必须是已获得且不重复的舰娘")
			seen[reserve]=true
	var saved:Variant=JSON.parse_string(serialized)
	if not _matches(saved,request) or float(saved.get("tick",-1))!=0 or not saved.get("commands",[]).is_empty():return account._fail("活动快照版本、初始状态或配置不符")
	var before:Dictionary=account.state.duplicate(true)
	account.state.run_sequence=int(account.state.run_sequence)+1
	var active:Dictionary={"run_id":"tide-%d-%d"%[int(account.state.run_sequence),int(request.seed)],"mode":"tide_event","stage_id":"tide-v2" if version==CURRENT_VERSION else "tide-v1","title":"潮汐回响","snapshot":serialized,"request":request.duplicate(true),"character_id":id,"fleet":[],"ruleset":version,"native_variant":str(saved.get("variant",""))}
	account.state.active_run=active.duplicate(true)
	return account._commit(before,"回响舰装已激活 · 不消耗港口弹药与油料",active)
func settle(view:Dictionary,serialized:String,abandon:bool=false)->Dictionary:
	ensure()
	var active:Dictionary=account.state.get("active_run",{})
	if active.is_empty():
		var last:Dictionary=account.latest_receipt()
		return {"ok":true,"duplicate":true,"receipt":last} if str(last.get("mode",""))=="tide_event" else account._fail("没有活动行动")
	if str(active.get("mode",""))!="tide_event":return account._fail("当前行动不属于潮汐回响")
	var tide:Dictionary=view.get("tide",{})
	var version:String=str(active.get("ruleset",VERSION))
	if version not in [VERSION,CURRENT_VERSION] or str(tide.get("version",""))!=version:return account._fail("活动观察版本不符")
	if view.get("result")==null and not abandon:return account._fail("行动尚未结束")
	var saved:Variant=JSON.parse_string(serialized)
	if not _matches(saved,active.request) or float(saved.get("tick",-1))!=float(view.get("tick",-2)):return account._fail("活动快照与当前行动配置或时刻不符")
	if version==CURRENT_VERSION:
		# Verify the terminal only once, outside active combat, against the native log.
		var verifier=load("res://scripts/core_bridge.gd").new()
		var verified:Dictionary=verifier.request({"op":"load","serialized":serialized})
		verifier.close()
		if not verified.get("ok",false):return account._fail("活动战报无法重演，已保留当前行动")
		var authoritative:Dictionary=verified.get("data",{})
		for field in ["tide","result","ships"]:
			if authoritative.get(field)!=view.get(field):return account._fail("活动战报与真实战况不符")
	var outcome:Dictionary=tide.get("outcome",{}) if tide.get("outcome") is Dictionary else {}
	var result:Dictionary=view.get("result",{}) if view.get("result") is Dictionary else {}
	if not abandon and (outcome.is_empty() or result.is_empty() or bool(result.get("primary",false))!=bool(outcome.get("success",false)) or str(result.get("winner",""))!=("allies" if bool(outcome.get("success",false)) else "axis")):return account._fail("活动终局与奖励回执不一致")
	if not abandon:
		if float(outcome.get("duration",-1))!=float(view.get("tick",-2)) or int(outcome.get("kills",-1))!=int(tide.get("kills",-2)) or int(result.get("allies",-1))!=int(tide.get("kills",-2)):return account._fail("活动终局时长或击退记录不一致")
		if bool(outcome.get("success",false)) and (float(view.get("tick",0))<float(tide.get("duration",180)) or not bool(tide.get("boss_defeated",false)) or not bool(outcome.get("boss_defeated",false))):return account._fail("尚未达成活动目标")
	for field in ["event_tokens","score"]:
		var amount:Variant=outcome.get(field,0)
		if not (amount is int or amount is float) or not is_finite(float(amount)) or float(amount)!=floor(float(amount)):return account._fail("活动奖励值无效")
	var tokens:int=0 if abandon else int(outcome.get("event_tokens",0))
	if bool(outcome.get("abandoned",false)) or int(view.get("tick",0))==0:tokens=0
	var score:int=0 if abandon else int(outcome.get("score",0))
	if tokens<0 or tokens>1000 or score<0 or score>1000000:return account._fail("活动奖励超出有效范围")
	var success:bool=not abandon and bool(outcome.get("success",false))
	var before:Dictionary=account.state.duplicate(true)
	account.state.wallet.tide_tokens=int(account.state.wallet.tide_tokens)+tokens
	var first:bool=success and int(account.state.tide_event_v1.wins)==0
	var rewards:Dictionary={"tide_tokens":tokens}
	if first:account.state.wallet.origins=int(account.state.wallet.origins)+160;rewards["origins"]=160
	if success:account.state.tide_event_v1.wins=int(account.state.tide_event_v1.wins)+1
	account.state.tide_event_v1.best_score=maxi(int(account.state.tide_event_v1.best_score),score)
	var receipt:Dictionary={"run_id":str(active.run_id),"mode":"tide_event","success":success,"borrowed":true,"title":"潮汐回响 · "+("信标守住了" if success else "下次再一起回来"),"rewards":rewards,"score":score,"kills":int(tide.get("kills",0)),"level":int(tide.get("level",1)),"primary":"存活至三分钟并击败潮环看守" ,"return_route":"tide_event","snapshot":serialized,"request":active.request.duplicate(true)}
	if version==CURRENT_VERSION:
		receipt["members"]=tide.get("members",[]).duplicate(true)
		receipt["ruleset"]=CURRENT_VERSION
	account.state.settled[str(active.run_id)]=receipt.duplicate(true);account.state.last_receipt_id=str(active.run_id);account.state.active_run={}
	return account._commit(before,"回响徽片已入库" if not abandon else "已退出回响海域",{"receipt":receipt})
func _matches(saved:Variant,request:Dictionary)->bool:
	var version:String=str(request.get("version",VERSION))
	if version not in [VERSION,CURRENT_VERSION] or not saved is Dictionary or str(saved.get("version",""))!=version or not saved.get("config") is Dictionary:return false
	var config:Dictionary=saved.config
	for field in ["character_id","difficulty","intel_profile"]:
		if str(config.get(field,""))!=str(request.get(field,"")):return false
	if version==CURRENT_VERSION:
		if config.get("roster",[])!=request.get("roster",[]):return false
		var frame:Variant=saved.get("frame",-1)
		var tick:Variant=saved.get("tick",-1)
		if not (frame is int or frame is float) or not (tick is int or tick is float):return false
		if not is_finite(float(frame)) or not is_finite(float(tick)) or float(frame)<0 or float(frame)!=floor(float(frame)) or absf(float(frame)-float(tick)*10.0)>0.000001:return false
	var seed:Variant=saved.get("seed",-1)
	return (seed is int or seed is float) and is_finite(float(seed)) and float(seed)==float(request.get("seed",-2))
func purchase(id:String,count:int=1)->Dictionary:
	ensure()
	if not account.state.get("active_run",{}).is_empty():return account._fail("结束行动后可兑换")
	if count<1 or count>100:return account._fail("兑换数量无效")
	var product:Dictionary={}
	for row in content.shop:
		if str(row.id)==id:product=row;break
	if product.is_empty():return account._fail("活动商品不存在")
	var bought:int=int(account.state.tide_event_v1.purchases.get(id,0))
	if bought+count>int(product.limit):return account._fail("已达本期兑换上限")
	var cost:int=int(product.cost)*count
	if int(account.state.wallet.tide_tokens)<cost:return account._fail("回响徽片不足")
	var before:Dictionary=account.state.duplicate(true)
	account.state.wallet.tide_tokens=int(account.state.wallet.tide_tokens)-cost
	account.state.wallet[str(product.grant)]=int(account.state.wallet.get(str(product.grant),0))+int(product.amount)*count
	account.state.tide_event_v1.purchases[id]=bought+count
	return account._commit(before,"%s ×%d已入库"%[str(product.name),int(product.amount)*count])
