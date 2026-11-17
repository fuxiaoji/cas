extends RefCounted
## Local bot league. Rating and rewards follow verified native arena snapshots.
const VERSION:="cas-local-arena-v1"
const Core=preload("res://scripts/core_bridge.gd")
const FleetBook=preload("res://scripts/fleet_manager.gd")
const MODES=["ranked","team3"]
var account
var config:Dictionary

func _init(owner)->void:
	account=owner
	config=JSON.parse_string(FileAccess.get_file_as_string("res://data/arena-league.json"))
	ensure()

func ensure()->void:
	var league:Dictionary=account.state.get_or_add("arena_league",{"version":"cas-local-league-v1","records":[],"selection":{}})
	for mode in MODES:
		league.get_or_add(mode,{"rating":1000,"peak":1000,"wins":0,"losses":0,"draws":0,"played":0,"completed":0,"claims":[]})
		league[mode].get_or_add("completed",0)
		if not league.selection.has(mode):
			var chosen:Array=[]
			for group in FleetBook.new(account).rows():
				if not group.ships.is_empty():chosen.append(str(group.id));break
			league.selection[mode]=chosen

func profile(mode:String)->Dictionary:
	ensure()
	var result:Dictionary=account.state.arena_league.get(mode,{}).duplicate(true)
	for key in ["rating","peak","wins","losses","draws","played","completed"]:
		if result.has(key):result[key]=int(result[key])
	return result

func tiers()->Array:
	return config.get("tiers",[]).duplicate(true)

func selected(mode:String)->Array:
	ensure()
	return account.state.arena_league.selection.get(mode,[]).duplicate()

func history(mode:String)->Array:
	ensure()
	return account.state.arena_league.records.filter(func(row):return str(row.get("arena_mode",""))==mode).duplicate(true)

func tier_for(rating:int)->Dictionary:
	var found:Dictionary={}
	for row in tiers():
		if rating>=int(row.minimum):found=row
	return found

func toggle_group(mode:String,id:String,on:bool)->Dictionary:
	if mode not in MODES:return account._fail("竞技模式无效")
	if not account.state.get("active_run",{}).is_empty():return account._fail("先继续或结束当前航次")
	var found:bool=FleetBook.new(account).rows().any(func(row):return str(row.id)==id and not row.ships.is_empty())
	if not found:return account._fail("请选择已有的非空编队")
	var choices:Array=selected(mode)
	if on and not choices.has(id):
		if choices.size()>=4:return account._fail("竞技最多同时部署四个编队")
		choices.append(id)
	if not on:choices.erase(id)
	var previous:Dictionary=account.state.duplicate(true)
	account.state.arena_league.selection[mode]=choices
	return account._commit(previous,"竞技编队已保存")

func preview(mode:String)->Dictionary:
	var budget:int=3400 if mode=="team3" else 10000
	var result:Dictionary={"ok":false,"message":"请选择1至4个编队","groups":[],"points":0,"budget":budget}
	if mode not in MODES:result.message="竞技模式无效";return result
	var choices:Array=selected(mode)
	var used:Array=[]
	for row in FleetBook.new(account).rows():
		if not choices.has(str(row.id)):continue
		var group:Dictionary={"id":str(row.id),"name":str(row.name),"ships":[]}
		if row.ships.is_empty():result.message="编队为空，请先管理成员";return result
		if row.ships.size()>16:result.message="竞技单个编队最多16艘，请拆分编队";return result
		for identity in row.ships:
			var id:=str(identity)
			if used.has(id):result.message="同一舰娘不能同时编入两个竞技编队";return result
			if not account.state.owned.has(id) or not account._cards.get(id,{}).get("playable",false):result.message="编队含未拥有或不能出航的舰娘";return result
			if not account._cards.get(id,{}).get("special_mode_scope",[]).is_empty():result.message="海陆空专用新舰请在海陆空行动或携带陆军的搜打撤中使用";return result
			used.append(id);group.ships.append(id)
			result.points=int(result.points)+int(account._cards.get(id,{}).get("points",0))
		result.groups.append(group)
	if result.groups.is_empty() or result.groups.size()>4:return result
	if used.size()>32:result.message="竞技单席最多32艘";return result
	if int(result.points)>budget:result.message="编队超出%d分预算，请减少舰只"%budget;return result
	if not account.state.get("active_run",{}).is_empty():result.message="先继续或结束当前航次";return result
	result.ok=true;result.message="可出击"
	return result

func _native(serialized:String)->Dictionary:
	if serialized.is_empty():return account._fail("竞技快照缺失")
	var verifier=Core.new()
	var response:Dictionary=verifier.request({"op":"load","serialized":serialized})
	var observed:Dictionary=verifier.view.duplicate(true) if response.get("ok",false) else {}
	verifier.close()
	if observed.get("arena",{}).get("version","")!=VERSION:return account._fail("快照不是本地竞技对局")
	return {"ok":true,"view":observed}

func _same_evidence(left:Dictionary,right:Dictionary)->bool:
	return left.get("arena",{})==right.get("arena",{}) and left.get("result")==right.get("result") and int(left.get("tick",-1))==int(right.get("tick",-2)) and left.get("ships",[])==right.get("ships",[])

func _roster_identity(arena:Dictionary)->Array:
	var identities:Array=[]
	for row in arena.get("roster",[]):
		identities.append({"ship":int(row.ship),"character_id":str(row.character_id),"side":str(row.side),"points":int(row.points)})
	identities.sort_custom(func(a,b):return int(a.ship)<int(b.ship))
	return identities

func begin(request:Dictionary,view:Dictionary,serialized:String)->Dictionary:
	if not account.state.get("active_run",{}).is_empty():return account._fail("已有进行中的航次")
	var mode:=str(request.get("mode",""))
	var plan:Dictionary=preview(mode)
	if not plan.ok:return plan
	if plan.groups!=request.get("groups",[]) or str(request.get("arena_version",""))!=VERSION:return account._fail("竞技编队与出航计划不一致")
	var evidence:Dictionary=_native(serialized)
	if not evidence.get("ok",false):return evidence
	var frozen:Dictionary=JSON.parse_string(serialized)
	var native_start:Dictionary=frozen.get("arena",{})
	if native_start.get("groups",[])!=plan.groups:return account._fail("原核竞技编成与账户计划不一致")
	var observed:Dictionary=evidence.view
	if not _same_evidence(view,observed) or observed.get("result")!=null or int(observed.get("tick",-1))!=0:return account._fail("竞技开局观察与原核快照不一致")
	var arena:Dictionary=observed.arena
	if str(arena.mode)!=mode or int(arena.seed)!=int(request.get("seed",-1)):return account._fail("竞技模式或种子不匹配")
	var previous:Dictionary=account.state.duplicate(true)
	account.state.run_sequence=int(account.state.get("run_sequence",0))+1
	var id:="arena-%d-%s"%[int(account.state.run_sequence),str(arena.match_id)]
	var rating:int=int(profile(mode).rating)
	var opponent_rating:int=maxi(0,rating+int(request.seed)%201-100)
	var active:Dictionary={"run_id":id,"mode":"arena","arena_mode":mode,"title":"10000分人机排位" if mode=="ranked" else "3v3人机团战","snapshot":serialized,"context":{"mode":"arena","request":request.duplicate(true)},"arena_match_id":str(arena.match_id),"arena_initial":arena.duplicate(true),"opponent_rating":opponent_rating,"ruleset":VERSION,"fleet":[],"evidence":{}}
	account.state.active_run=active.duplicate(true)
	return account._commit(previous,"本地人机对局已建立，竞技不损耗港口舰只",active)

func settle(view:Dictionary,serialized:String,forfeit:bool=false)->Dictionary:
	ensure()
	var active:Dictionary=account.state.get("active_run",{})
	if active.is_empty():
		var latest:Dictionary=account.latest_receipt()
		if str(latest.get("mode",""))=="arena" and str(latest.get("arena_match_id",""))==str(view.get("arena",{}).get("match_id","")):
			return {"ok":true,"duplicate":true,"receipt":latest,"message":"本局已结算，未重复发奖"}
		return account._fail("没有待结算的竞技对局")
	if str(active.get("mode",""))!="arena":return account._fail("当前不是竞技对局")
	var native:Dictionary=_native(serialized)
	if not native.get("ok",false):return native
	var actual:Dictionary=native.view
	var initial:Dictionary=active.get("arena_initial",{})
	var frozen:Dictionary=JSON.parse_string(serialized)
	if frozen.get("arena",{}).get("groups",[])!=active.get("context",{}).get("request",{}).get("groups",[]):return account._fail("竞技快照初始编成不属于当前对局")
	if not _same_evidence(view,actual) or str(actual.arena.match_id)!=str(active.arena_match_id) or _roster_identity(actual.arena)!=_roster_identity(initial):return account._fail("结算快照与本局身份、编队或观察不一致")
	if not forfeit and not actual.get("result") is Dictionary:return account._fail("实际竞技对局尚未结束")
	var mode:=str(active.arena_mode)
	var winner:=str(actual.get("result",{}).get("winner","")) if actual.get("result") is Dictionary else ""
	var outcome:float=0.0 if forfeit else 1.0 if winner=="allies" else .5 if winner=="draw" else 0.0
	var previous:Dictionary=account.state.duplicate(true)
	var record:Dictionary=account.state.arena_league[mode]
	var before:int=int(record.rating)
	var expected:float=1.0/(1.0+pow(10.0,(float(active.opponent_rating)-before)/400.0))
	var delta:int=roundi(32.0*(outcome-expected))
	record.rating=maxi(0,before+delta);record.peak=maxi(int(record.peak),int(record.rating))
	record.played=int(record.played)+1
	if not forfeit:record.completed=int(record.get("completed",0))+1
	var counter:String="wins" if outcome==1.0 else "draws" if outcome==.5 else "losses"
	record[counter]=int(record[counter])+1
	var grant:Dictionary={} if forfeit else {"credits":240 if outcome==1.0 else 120 if outcome==.5 else 80}
	for key in grant:account.state.wallet[key]=int(account.state.wallet.get(key,0))+int(grant[key])
	var summary:Dictionary={"run_id":str(active.run_id),"mode":"arena","arena_mode":mode,"arena_match_id":str(active.arena_match_id),"success":outcome==1.0,"won":outcome==1.0,"result":"forfeit" if forfeit else "win" if outcome==1.0 else "draw" if outcome==.5 else "loss","title":str(active.title),"borrowed":true,"return_route":"arena","tick":int(actual.tick),"rating_before":before,"rating_after":int(record.rating),"delta":int(record.rating)-before,"rewards":grant,"loot":{},"ships":[],"primary":"主动认输，本次不发对局奖励" if forfeit else "本地人机 · %s · 积分 %d（%+d）"%[str(tier_for(int(record.rating)).get("name","见习")),int(record.rating),int(record.rating)-before],"opponents":actual.arena.get("groups",[]).filter(func(row):return str(row.get("side",""))=="axis")}
	account.state.arena_league.records.push_front(summary.duplicate(true))
	if account.state.arena_league.records.size()>50:account.state.arena_league.records.resize(50)
	account.state.settled[str(active.run_id)]=summary.duplicate(true)
	account.state.last_receipt_id=str(active.run_id)
	account.state.active_run={}
	return account._commit(previous,"竞技积分与奖励已保存",{"receipt":summary})

func claim_tier(mode:String,id:String)->Dictionary:
	if mode not in MODES:return account._fail("竞技模式无效")
	if not account.state.get("active_run",{}).is_empty():return account._fail("航次进行中，请返港结算后领取")
	var row:Dictionary={}
	for entry in tiers():
		if str(entry.id)==id:row=entry
	var current:Dictionary=profile(mode)
	if row.is_empty() or int(current.completed)<1 or int(current.peak)<int(row.get("minimum",0)):return account._fail("完成真实对局并达到该段位后可领取")
	if current.claims.has(id):return account._fail("此段位奖励已领取")
	var previous:Dictionary=account.state.duplicate(true)
	account.state.arena_league[mode].claims.append(id)
	for key in row.rewards:account.state.wallet[key]=int(account.state.wallet.get(key,0))+int(row.rewards[key])
	return account._commit(previous,"%s段位奖励已到账"%str(row.name),{"rewards":row.rewards.duplicate(true)})
