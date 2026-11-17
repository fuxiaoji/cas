extends RefCounted
## Local NPC islands use an explicit core version and one atomic account settlement.
const VERSION:String="cas-island-war-v1"
const DATA:String="res://data/island-war-v1.json"
const Core=preload("res://scripts/core_bridge.gd")
var home
var account
var growth
func _init(owner)->void:
	home=owner;account=home.account;growth=home.development()
func catalogue()->Array:
	if not FileAccess.file_exists(DATA):return []
	var raw:Variant=JSON.parse_string(FileAccess.get_file_as_string(DATA))
	return raw.get("islands",raw.get("npc_islands",[])).duplicate(true) if raw is Dictionary else []
func npc(identity:String)->Dictionary:
	for row in catalogue():
		if str(row.get("id",row.get("npc_id","")))==identity:return row.duplicate(true)
	return {}
func _core_build()->String:
	var path:String=OS.get_environment("CAS_SIM_PATH")
	if not path.is_empty() and FileAccess.file_exists(path):return FileAccess.get_sha256(path)
	var manifest:Variant=JSON.parse_string(FileAccess.get_file_as_string("res://bin/core-current.json")) if FileAccess.file_exists("res://bin/core-current.json") else null
	return str(manifest.get("sha256",VERSION)) if manifest is Dictionary else VERSION
func _forts()->Array:
	var result:Array=[]
	for building in home.state().buildings:
		var kind:String=str(building.kind)
		if not growth.FORT_KINDS.has(kind):continue
		result.append({"id":str(building.id),"kind":str(growth.FORT_KINDS[kind]),"level":int(building.level),"x":clampf(float(building.cell.x)/11.0,.08,.92),"y":clampf(float(building.cell.y)/8.0,.08,.92),"hp":int(building.get("hp",100))})
	return result
func prepare(mode:String,npc_id:String,units:Array=[],ships:Array=[],preset:String="balanced",transports:Array=[],seed_override:int=-1)->Dictionary:
	if mode not in ["raid","defense"]:return home._fail("请选择本地人机进攻或防御模拟")
	var target:Dictionary=npc(npc_id)
	if target.is_empty():return home._fail("人机岛屿目录尚未就绪")
	var seed:int=seed_override if seed_override>=0 else int(target.get("seed",18031+catalogue().find(target)*1019))
	var chosen_ships:Array=home.state().garrison.duplicate() if mode=="defense" else ships.duplicate()
	var chosen_units:Array=home.state().tactical_garrison.duplicate() if mode=="defense" else units.duplicate()
	var base:Dictionary=home.prepare_littoral(mode,seed,chosen_units,chosen_ships,preset,home.BATTLE_VERSION,"landing",transports)
	if not base.get("ok",false):return base
	var storage:Dictionary=growth.storage_profile()
	if mode=="defense":
		var warehouses:int=0
		for building in home.state().buildings:
			if str(building.kind)=="depot":warehouses+=1
		if warehouses==0:return home._fail("请先建造补给仓库，再开始本地防御模拟")
	var payload:Dictionary={"npc_id":npc_id,"island_level":growth.level() if mode=="defense" else int(target.get("level",1)),"unit_growth":growth.growth_payload(base.request.roster)}
	if mode=="defense":
		payload["forts"]=_forts();payload["storage"]={}
		for key in ["credits","scrap","alloy","protocols"]:payload.storage[key]=int(storage.exposed.get(key,0))
	var request:Dictionary=base.request.duplicate(true)
	request.op="new_island_battle";request.version=VERSION;request["island"]=payload
	# All physical legality, body/carrier limits and building rules remain in the native core.
	var verifier=Core.new();var verified:Dictionary=verifier.request(request);verifier.close()
	if not verified.get("ok",false):return home._fail(str(verified.get("error","岛屿战配置检查失败")))
	return {"ok":true,"request":request,"loaded_ammo":base.loaded_ammo,"storage":storage,"npc":target,"local_simulation":true}
func _native(serialized:String)->Dictionary:
	var verifier=Core.new();var response:Dictionary=verifier.request({"op":"load","serialized":serialized});verifier.close()
	if not response.get("ok",false):return home._fail("岛屿战快照无法通过原核校验")
	var view:Dictionary=response.get("data",{})
	if str(view.get("island_war",{}).get("version",""))!=VERSION:return home._fail("战报不是本地岛屿战版本")
	return {"ok":true,"view":view}
func _matches(serialized:String,request:Dictionary)->bool:
	var saved:Variant=JSON.parse_string(serialized)
	if not saved is Dictionary or str(saved.get("version",""))!=VERSION or int(saved.get("seed",-1))!=int(request.seed):return false
	var expected:Dictionary=request.duplicate(true)
	for key in ["op","version","seed"]:expected.erase(key)
	# Serde writes these two explicit defaults even when a raid uses the NPC catalogue.
	# Every supplied fort, resource, identity, condition and growth field still compares exactly.
	var island:Dictionary=expected.get("island",{})
	island.get_or_add("forts",[]);island.get_or_add("storage",null)
	return home._same(saved.get("config",{}),expected)
func begin(request:Dictionary,serialized:String)->Dictionary:
	if not home._idle():return home._fail("当前行动尚未结束")
	var ids:Array=[]
	for row in request.get("ships",[]):ids.append(str(row.get("id","")))
	var plan:Dictionary=prepare(str(request.get("mode","")),str(request.get("island",{}).get("npc_id","")),request.get("roster",[]),ids,str(request.get("transport_preset","")),request.get("company_transports",[]),int(request.get("seed",0)))
	if not plan.get("ok",false):return plan
	var supplied:Variant=request.get("unit_condition",[])
	if not supplied is Array or supplied.size()!=plan.request.unit_condition.size():return home._fail("部队整备配置不完整")
	for index in range(supplied.size()):
		var row:Variant=supplied[index]
		if not row is Dictionary or str(row.get("id",""))!=str(plan.request.unit_condition[index].id):return home._fail("部队整备身份不符")
		var hp:float=float(row.get("hp",-1))
		if not is_finite(hp) or hp<10 or hp>float(plan.request.unit_condition[index].hp)+.000001:return home._fail("不能提高本人实际整备率")
	plan.request.unit_condition=supplied.duplicate(true)
	if not home._same(request,plan.request):return home._fail("岛屿出航计划已变化，请重新确认")
	var proof:Dictionary=_native(serialized)
	if not proof.get("ok",false):return proof
	if float(proof.view.get("tick",-1))!=0 or proof.view.get("result")!=null or not _matches(serialized,request):return home._fail("只能绑定同一配置的全新岛屿战")
	var before:Dictionary=account.state.duplicate(true);account.state.run_sequence=int(account.state.get("run_sequence",0))+1
	var run_id:String="island-%d-%d"%[int(account.state.run_sequence),int(request.seed)]
	var title:String=("防御模拟 · " if str(request.mode)=="defense" else "人机突袭 · ")+str(plan.npc.get("name",request.island.npc_id))
	var active:Dictionary={"run_id":run_id,"mode":"littoral","ruleset":VERSION,"stage_id":str(request.mode),"title":title,"request":request.duplicate(true),"snapshot":serialized,"fleet":ids.duplicate(),"home_frozen":{"units":home.state().units.duplicate(true),"ships":request.ships.duplicate(true),"resources":home.state().resources.duplicate(true),"loaded_ammo":int(plan.loaded_ammo),"borrowed_tutorial":false,"loan_units":[],"loan_ships":[],"storage":plan.storage.duplicate(true)},"home_replay":{"initial_snapshot":serialized,"initial_request":request.duplicate(true),"local_simulation":true,"core_version":_core_build()}}
	account.state.wallet.ammo_stock=int(account.state.wallet.ammo_stock)-int(plan.loaded_ammo)
	for row in request.ships:account.state.owned[str(row.id)].ammo=0
	account.state.active_run=active
	return home._commit(before,"本地人机模拟已开始 · 实际弹药与损耗生效",active.duplicate(true))
func settle(view:Dictionary,serialized:String,abandon:bool=false)->Dictionary:
	var active:Dictionary=account.state.get("active_run",{})
	if active.is_empty():
		var last:Dictionary=account.latest_receipt()
		return {"ok":true,"duplicate":true,"receipt":last} if str(last.get("ruleset",""))==VERSION else home._fail("没有岛屿战行动")
	if str(active.get("ruleset",""))!=VERSION:return home._fail("当前不是新版岛屿战")
	var proof:Dictionary=_native(serialized)
	if not proof.get("ok",false):return proof
	var actual:Dictionary=proof.view
	for key in ["littoral","ships","result","tick","island_war"]:
		if not home._same(actual.get(key),view.get(key)):return home._fail("结算必须使用同一原核战况")
	if not _matches(serialized,active.request):return home._fail("岛屿战报属于其他行动")
	var outcome:Dictionary=actual.get("littoral",{}).get("outcome",{}) if actual.get("littoral",{}).get("outcome") is Dictionary else {}
	if actual.get("result")==null or outcome.is_empty():return home._fail("请先完成原核行动或明确撤退")
	if abandon and not bool(outcome.get("abandoned",false)):return home._fail("请先执行原核撤退")
	var success:bool=bool(outcome.get("success",false)) and not bool(outcome.get("abandoned",false))
	var rewards:Dictionary=outcome.get("resources",{}).duplicate(true) if success else {}
	for key in rewards:
		if not home.RESOURCE_NAMES.has(key) or int(rewards[key])<0 or int(rewards[key])>10000:return home._fail("岛屿奖励超出有效范围")
	var plundered:Dictionary=actual.get("island_war",{}).get("outcome",{}).get("plundered",{})
	var losses:Dictionary={}
	if str(active.request.mode)=="defense":
		for key in plundered:
			if not home.RESOURCE_NAMES.has(key) or int(plundered[key])<0 or int(plundered[key])>int(active.home_frozen.storage.exposed.get(key,0)):return home._fail("掠夺超过出航时公示的可掠份额")
			losses[key]=int(plundered[key])
	var before:Dictionary=account.state.duplicate(true);var seen:Array=[];var now:int=home._now()
	for row in outcome.get("units",[]):
		var id:String=str(row.get("id",""))
		if not active.request.roster.has(id) or seen.has(id) or not home.state().units.has(id):account.state=before;return home._fail("战术本人战损记录不完整或重复")
		seen.append(id)
		var hp:float=clampf(float(row.get("hp_percent",0)),0,100)
		if bool(row.get("missing",false)) or bool(row.get("incapacitated",false)):hp=0
		home.state().units[id].condition=hp;home.state().units[id].at=now
		if hp<=0:home.state().units[id].losses=int(home.state().units[id].get("losses",0))+1
		if float(actual.get("tick",0))>=15:growth._gain_xp(id,80 if success else 30)
	if seen.size()!=active.request.roster.size():account.state=before;return home._fail("本人战损未覆盖全部出动编制")
	var returned:int=0;seen.clear()
	for row in outcome.get("ships",[]):
		var id:String=str(row.get("id",""))
		if not active.fleet.has(id) or seen.has(id):account.state=before;return home._fail("舰娘返航记录身份不一致")
		seen.append(id);account.state.owned[id].hp=clampi(int(floor(float(row.get("hp_percent",0)))),0,100);account.state.owned[id].ammo=0
		if not bool(row.get("sunk",false)) and bool(row.get("recovered",false)):returned+=clampi(int(floor(float(row.get("ammo_percent",0)))),0,100)
	if seen.size()!=active.fleet.size():account.state=before;return home._fail("舰娘返航记录未覆盖全部舰只")
	account.state.wallet.ammo_stock=int(account.state.wallet.ammo_stock)+returned
	if str(active.request.mode)=="defense":
		for row in outcome.get("buildings",[]):
			for building in home.state().buildings:
				if str(building.id)==str(row.get("id","")):building.hp=clampi(int(floor(float(row.get("hp_percent",0)))),0,100)
		for key in losses:home.state().resources[key]=maxi(0,int(home.state().resources.get(key,0))-int(losses[key]))
	var credited:Dictionary={};var overflow:Dictionary={};var balances:Dictionary=home.state().resources.duplicate(true)
	home._give(rewards)
	for key in rewards:
		credited[key]=int(home.state().resources.get(key,0))-int(balances.get(key,0));overflow[key]=int(rewards[key])-int(credited[key])
	var run_id:String=str(active.run_id)
	var replay:Dictionary={"run_id":run_id,"title":str(active.title),"mode":str(active.request.mode),"at":now,"success":success,"ruleset":VERSION,"core_version":str(active.home_replay.get("core_version",VERSION)),"local_simulation":true,"snapshot":serialized,"initial_snapshot":str(active.home_replay.initial_snapshot),"initial_request":active.request.duplicate(true),"resources":credited.duplicate(true),"losses":losses.duplicate(true)}
	if serialized.length()>8*1024*1024:
		replay.snapshot="";replay.initial_snapshot="";replay["replay_unavailable_reason"]="完整记录超过本地8MB录像上限；仅保留真实战报，不提供缺失过程的回放"
	home.state().development_v2.replays[run_id]=replay
	# Full recordings are deliberately bounded; older compact records remain honest about availability.
	while home.state().development_v2.replays.size()>8:
		var oldest:String=str(home.state().development_v2.replays.keys()[0]);home.state().development_v2.replays.erase(oldest)
	var receipt:Dictionary={"run_id":run_id,"mode":"littoral","ruleset":VERSION,"success":success,"borrowed":false,"home_tutorial_loan":false,"title":str(active.title),"return_route":"home","rewards":credited,"earned":rewards,"reward_overflow":overflow,"home_losses":losses,"units":outcome.units.duplicate(true),"ships":outcome.ships.duplicate(true),"ammo_loaded":int(active.home_frozen.loaded_ammo),"ammo_returned":returned,"request":active.request.duplicate(true),"replay_id":run_id,"local_simulation":true}
	home.state().records.append({"run_id":run_id,"mode":str(active.request.mode),"success":success,"at":now,"local_simulation":true})
	while home.state().records.size()>50:home.state().records.pop_front()
	account.state.settled[run_id]=receipt.duplicate(true);account.state.last_receipt_id=run_id;account.state.active_run={}
	return home._commit(before,"本地战报、本人战损与可掠物资已单次结算",{"receipt":receipt})
