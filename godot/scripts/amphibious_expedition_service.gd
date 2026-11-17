extends RefCounted
## Opt-in transport plans and terminal evidence for original naval extraction.
const VERSION:String="cas-adventure-v3"
const COMPANY_LAYOUT:String="multi-company-v1"
const Core=preload("res://scripts/core_bridge.gd")
const Home=preload("res://scripts/home_service.gd")
var account
var home
var multi_catalogue:Dictionary={}
var multi_profiles:Dictionary={}
func _init(owner)->void:
	account=owner;home=Home.new(owner)
	if FileAccess.file_exists("res://data/tactical-profiles-v4.json"):
		var raw:Variant=JSON.parse_string(FileAccess.get_file_as_string("res://data/tactical-profiles-v4.json"))
		if raw is Dictionary:
			multi_catalogue=raw.get("multi_company",{})
			for row in raw.get("cards",[]):multi_profiles[str(row.id)]=row
func layout(id:String)->Dictionary:return multi_profiles.get(id,{}).get("company_layout",{}).duplicate(true)
func multi_enabled()->bool:return str(account.state.get("amphibious_expedition_v1",{}).get("company_layout",""))==COMPANY_LAYOUT
func choices()->Array:
	return account.state.get("amphibious_expedition_v1",{}).get("companies",[]).duplicate(true)
func set_choices(companies:Array,multi:bool=false)->Dictionary:
	if not account.state.get("active_run",{}).is_empty():return account._fail("请先完成当前航次")
	if companies.size()>(25 if multi else 5):return account._fail("本航次陆军连队数量超过上限")
	var seen:Array=[]
	for row in companies:
		if not row is Dictionary:return account._fail("请选择真实连队")
		var key:String=str(row.get("company_id","")) if multi else str(row.get("unit_id",""))
		if key.is_empty() or key in seen or not home.state().units.has(str(row.get("unit_id",""))):return account._fail("请选择已拥有且不重复的战术连队")
		if multi and layout(str(row.unit_id)).get("companies",[]).filter(func(c):return str(c.company_id)==key).is_empty():return account._fail("连队未在本人完整编制登记")
		seen.append(key)
	var before:Dictionary=account.state.duplicate(true)
	account.state["amphibious_expedition_v1"]={"companies":companies.duplicate(true)}
	if multi:account.state.amphibious_expedition_v1["company_layout"]=COMPANY_LAYOUT
	return account._commit(before,"陆军搭载计划已保存")
func prepare(fleet:Array)->Dictionary:
	return prepare_plan(fleet,choices(),multi_enabled())
func prepare_plan(fleet:Array,drafts:Array,multi:bool=true)->Dictionary:
	if drafts.size()>(25 if multi else 5):return account._fail("本航次陆军连队数量超过上限")
	var result:Array=[];var loads:Dictionary={};var capacities:Dictionary={};var personnel:int=0;var seen:Dictionary={}
	for draft in drafts:
		var id:String=str(draft.get("unit_id",""));var carrier:String=str(draft.get("carrier_identity",""));var kind:String=str(draft.get("transport_kind","landing_craft"))
		var company:String=str(draft.get("company_id",id))
		if seen.has(company):return account._fail("同一连队不能重复携行")
		seen[company]=true
		if multi and layout(id).get("companies",[]).filter(func(c):return str(c.company_id)==company).is_empty():return account._fail("连队未在本人完整编制登记")
		if not home.state().units.has(id):return account._fail("陆军编制尚未获得")
		var p:Dictionary=multi_profiles.get(id,{}) if multi else home.profiles.get(id,{})
		var option:Dictionary={}
		for row in p.get("transport_options",[]):
			if str(row.kind)==kind:option=row
		if option.is_empty():return account._fail("该部队没有所选运输载具")
		var ship:Dictionary={}
		for row in fleet:
			if str(row.id)==carrier:ship=row
		if ship.is_empty():return account._fail("请将陆军搭载舰加入当前出航舰队")
		var role:String=str(p.get("role","infantry"));var ship_kind:String=str(ship.get("type","DD"))
		if (kind=="helicopter" or role in ["air_assault","airborne","gunship"]) and ship_kind not in ["CV","LHA"]:return account._fail("空输与伞兵需要航母或两栖攻击舰")
		if (kind=="amphibious_vehicle" or role in ["armor","transport"]) and ship_kind not in ["CV","LHA","APV"]:return account._fail("装甲部队需要装甲运输舰、两栖攻击舰或航母")
		var condition:int=int(floor(home.condition(id)))
		if condition<10:return account._fail("战术部队整备不足10%")
		var capacity:int=int({"DD":8,"BB":16,"CA":12,"CL":10,"AV":14,"CV":24,"LHA":28,"APV":30}.get(ship_kind,8))+(100-int(ship.get("ammo",100)))/20
		if multi:
			if not option.has("multi_company_slots"):return account._fail("多连运力表尚未登记")
			capacity*=int(multi_catalogue.get("capacity_multiplier",6));personnel+=int(layout(id).get("personnel_per_company",0))
		loads[carrier]=int(loads.get(carrier,0))+int(option.get("multi_company_slots",0) if multi else option.get("transport_slots",6))
		capacities[carrier]=capacity
		if int(loads[carrier])>capacity:return account._fail("搭载舰舱位不足：换舰或减少炮弹")
		result.append({"unit_id":id,"carrier_identity":carrier,"transport_kind":kind,"condition_percent":condition})
		if multi:result[-1]["company_id"]=str(draft.get("company_id",""))
	if multi and personnel>int(multi_catalogue.get("max_personnel",250)):return account._fail("本次真实陆军身体超过上限")
	var capacity_rows:Array=[]
	for carrier in loads:capacity_rows.append({"carrier_identity":carrier,"used":int(loads[carrier]),"capacity":int(capacities[carrier])})
	var response:Dictionary={"ok":true,"companies":result,"transport_capacity":capacity_rows,"personnel":personnel}
	if multi:response["company_layout"]=COMPANY_LAYOUT
	return response
static func same(a:Variant,b:Variant)->bool:
	if a is Dictionary and b is Dictionary:
		if a.size()!=b.size():return false
		for key in a:
			if not b.has(key) or not same(a[key],b[key]):return false
		return true
	if a is Array and b is Array:
		if a.size()!=b.size():return false
		for i in range(a.size()):
			if not same(a[i],b[i]):return false
		return true
	return a==b
func verify_terminal(serialized:String,view:Dictionary={})->Dictionary:
	var active:Dictionary=account.state.get("active_run",{})
	if str(active.get("gameplay_profile",""))!=VERSION:return account._fail("当前不是海陆搜打撤")
	if serialized.is_empty():return account._fail("缺少真实原核战报，已保留行动")
	var saved:Variant=JSON.parse_string(serialized)
	var expected:Dictionary=account.native_start(active)
	for hull in expected.get("fleet",[]):
		for key in ["mastery","equipment_bonus_bp"]:
			if int(hull.get(key,0))==0:hull.erase(key)
		if hull.get("crew",{}).is_empty():hull.erase("crew")
	if not saved is Dictionary or int(saved.get("seed",-1))!=int(active.get("seed",-2)) or not same(saved.get("salvage",{}),expected):return account._fail("战报与本次出航编队或陆军配置不一致")
	var verifier=Core.new();var response:Dictionary=verifier.request({"op":"load","serialized":serialized});verifier.close()
	if not response.get("ok",false):return account._fail("战报未能真实重演，已保留行动")
	var actual:Dictionary=response.get("data",{});var salvage:Dictionary=actual.get("salvage",{})
	if actual.get("result")==null or not salvage.get("amphibious",{}).get("outcome") is Dictionary:return account._fail("请完成撤离或在战场结束行动")
	if not view.is_empty():
		for key in ["tick","result","salvage"]:
			if not same(actual.get(key),view.get(key)):return account._fail("界面战况与原核重演不一致")
	return {"ok":true,"view":actual,"outcome":salvage.amphibious.outcome}
func finish(view:Dictionary,serialized:String)->Dictionary:
	var proof:Dictionary=verify_terminal(serialized,view)
	if not proof.get("ok",false):return proof
	var actual:Dictionary=proof.view;var salvage:Dictionary=actual.salvage
	var receipt:Dictionary={"run_id":str(account.state.active_run.run_id),"success":bool(salvage.get("extracted",false)),"loot":salvage.get("loot",{}),"ships":salvage.get("ships",[]),"cargo_items":salvage.get("cargo_grid",{}).get("items",[]).filter(func(item):return item.get("placement")!=null),"amphibious_serialized":serialized}
	if actual.has("fuel_receipt"):receipt["fuel_receipt"]=actual.fuel_receipt.duplicate(true)
	return account.settle_sortie(receipt)
