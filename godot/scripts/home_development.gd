extends RefCounted
## Account-side development and local island war ledger. Frozen littoral requests stay unchanged.
const VERSION:String="home-development-v2"
const WAR_VERSION:String="cas-island-war-v1"
const SPECIALIZATIONS:Dictionary={"assault":"突击火控","vanguard":"前卫防护","support":"协同支援","mobility":"机动插入","precision":"精确射击","logistics":"战场后勤"}
const FORT_KINDS:Dictionary={"hq":"hq","depot":"warehouse","turret":"cannon","aa":"aa","machine_gun":"machine_gun","mortar":"mortar","anti_ship":"anti_ship","repair_tower":"repair"}
var home
var account
func _init(owner,read_only:bool=false)->void:
	home=owner;account=home.account
	if not read_only:ensure()
func ensure()->void:
	if account.state.is_empty():return
	var island:Dictionary=home.state()
	island.get_or_add("development_v2",{"version":VERSION,"replays":{},"island_xp":0,"battle_claims":{}})
	for saved in island.units.values():
		saved.get_or_add("level",1);saved.get_or_add("xp",0);saved.get_or_add("ascension",0);saved.get_or_add("specialization","")
func level()->int:
	var result:int=1
	for building in home.state().buildings:
		if str(building.kind)=="hq":result=maxi(result,int(building.level))
	return clampi(result,1,5)
func island_profile()->Dictionary:
	var lv:int=level();var commander:int=int(account.player_profile().level)
	if not home.v4_cards.is_empty():
		var geometry:Dictionary=home.geometry_v4()
		return {"version":"home-development-v4","level":lv,"max_level":5,"commander_level":commander,"buildable_cells":geometry.get("construction_grid",{}).get("buildable_cells",[]).size(),"width_m":float(geometry.get("width_m",0)),"height_m":float(geometry.get("height_m",0)),"building_limit":20+maxi(0,lv-3)*8,"next_commander_level":[1,3,6,10,15][mini(4,lv)],"warehouse":storage_profile(),"local_simulation":true}
	var cells:int=0
	for y in range(home.GRID.y):
		for x in range(home.GRID.x):
			if buildable(Vector2i(x,y)):cells+=1
	var radius:float=float([.30,.43,.57,.72,1.0][lv-1])
	for building in home.state().buildings:
		var relative:Vector2=(Vector2(float(building.cell.x),float(building.cell.y))-Vector2(5.5,4))/Vector2(5.3,3.8)
		radius=maxf(radius,relative.length_squared()+.10)
	return {"version":VERSION,"level":lv,"max_level":5,"commander_level":commander,"buildable_cells":cells,"area_radius_squared":radius,"buildable_radius_squared":float([.30,.43,.57,.72,1.0][lv-1]),"building_limit":20+maxi(0,lv-3)*8,"next_commander_level":[1,3,6,10,15][mini(4,lv)],"warehouse":storage_profile(),"local_simulation":true}
func buildable(cell:Vector2i)->bool:
	if not home.v4_cards.is_empty():return not home.building_at(cell).is_empty() or home.is_land(cell)
	if not home.is_land(cell):return false
	# Existing facilities are retained in place when a previous account is opened.
	if not home.building_at(cell).is_empty():return true
	var lv:int=level();var relative:Vector2=(Vector2(cell)-Vector2(5.5,4))/Vector2(5.3,3.8)
	return relative.length_squared()<[.30,.43,.57,.72,1.0][lv-1]
func storage_profile(resources:Dictionary={})->Dictionary:
	var stock:Dictionary=home.state().resources if resources.is_empty() else resources
	var depot_levels:int=0
	for building in home.state().buildings:
		if str(building.kind)=="depot" and int(building.get("hp",100))>0:depot_levels+=int(building.level)
	var protected:Dictionary={};var exposed:Dictionary={};var caps:Dictionary={}
	for key in home.RESOURCE_NAMES:
		var floor_value:int=(100+level()*50+depot_levels*120) if key!="protocols" else 10+level()*4+depot_levels*5
		var amount:int=maxi(0,int(stock.get(key,0)))
		protected[key]=mini(amount,floor_value) if key!="energy" else amount
		# Only a limited share is at risk in a manually started local defense.
		exposed[key]=mini(1500 if key!="protocols" else 30,int(floor(float(maxi(0,amount-int(protected[key])))*.20))) if key!="energy" else 0
		caps[key]=floor_value
	return {"resources":stock.duplicate(true),"protected":protected,"exposed":exposed,"protection_capacity":caps,"depot_levels":depot_levels,"local_simulation":true,"raid_fraction":.20,"scope":"仅手动开启本地防御模拟会产生损耗；基地仓库实物不进入岛屿掠夺"}
func unit_profile(id:String)->Dictionary:
	var saved:Dictionary=home.state().units.get(id,{})
	var row:Dictionary=home.unit(id)
	var bodies:int=0;var layout:Dictionary=home.company_layout(id)
	for company in layout.get("companies",[]):bodies+=int(company.get("personnel_count",company.get("count",0)))
	if bodies==0:bodies=int(layout.get("company_count",1))*int(layout.get("bodies_per_company",9))
	if bodies<=0:bodies=home.profile(id).get("bodies",[]).size()
	var latest:Dictionary=home.latest_profile(id) if not home.latest_profile(id).is_empty() else home.v2_profile(id)
	if not latest.is_empty():bodies=int(latest.get("company_count",0))*int(latest.get("personnel_per_company",0));row=home.latest_unit(id) if not home.latest_profile(id).is_empty() else home.v2_unit(id)
	var lv:int=clampi(int(saved.get("level",1)),1,30);var ready:float=home.condition(id)
	return {"id":id,"owned":not saved.is_empty(),"level":lv,"xp":int(saved.get("xp",0)),"xp_next":100+lv*20,"ascension":clampi(int(saved.get("ascension",0)),0,2),"level_cap":mini(30,10+int(saved.get("ascension",0))*10),"specialization":str(saved.get("specialization","")),"specializations":SPECIALIZATIONS.duplicate(),"condition":ready,"deployed_bodies":bodies,"ready_body_equivalent":float(bodies)*ready/100.0,"protocol_body_cap":int(row.get("personnel_cap",1000)),"stat_bonus":float(lv-1)/29.0*.05,"losses":int(saved.get("losses",0))}
func _gain_xp(id:String,amount:int)->void:
	var saved:Dictionary=home.state().units[id];saved.xp=int(saved.get("xp",0))+maxi(0,amount)
	saved.get_or_add("level",1);saved.get_or_add("ascension",0);saved.get_or_add("specialization","")
	var cap:int=mini(30,10+int(saved.get("ascension",0))*10)
	while int(saved.level)<cap and int(saved.xp)>=100+int(saved.level)*20:
		saved.xp=int(saved.xp)-(100+int(saved.level)*20);saved.level=int(saved.level)+1
	if int(saved.level)>=30:saved.xp=0
func training_preview(id:String,amount:int=1)->Dictionary:
	var row:Dictionary=unit_profile(id)
	if not row.owned:return home._fail("先同步这位战术人格")
	if amount<1 or amount>10:return home._fail("训练份数需在1至10之间")
	var cost:Dictionary={"energy":12*amount,"credits":60*amount}
	return {"ok":true,"id":id,"amount":amount,"xp":100*amount,"cost":cost,"ready":home._idle() and int(row.level)<int(row.level_cap) and _afford(cost),"at_cap":int(row.level)>=int(row.level_cap)}
func train(id:String,amount:int,request_id:String="")->Dictionary:
	var replay:Dictionary=account._request(request_id,["tactical_train_v2",id,amount])
	if not replay.is_empty():return replay
	var quote:Dictionary=training_preview(id,amount)
	if not quote.get("ok",false):return quote
	if not quote.ready:return home._fail("请返航，确认资源充足且未达到当前等级上限")
	var before:Dictionary=account.state.duplicate(true);home._charge(quote.cost);_gain_xp(id,int(quote.xp))
	return home._commit(before,"战术训练完成",{"unit":unit_profile(id),"cost":quote.cost})
func ascent_preview(id:String)->Dictionary:
	var row:Dictionary=unit_profile(id)
	if not row.owned:return home._fail("先同步这位战术人格")
	var stage:int=int(row.ascension)
	if stage>=2:return {"ok":true,"maxed":true,"ready":false,"cost":{}}
	var cost:Dictionary={"alloy":100 if stage==0 else 240,"energy":80 if stage==0 else 180,"credits":300 if stage==0 else 800,"protocols":4 if stage==0 else 10}
	var commander:int=3 if stage==0 else 6
	return {"ok":true,"maxed":false,"id":id,"stage":stage,"next_cap":int(row.level_cap)+10,"commander":commander,"cost":cost,"ready":home._idle() and int(row.level)>=int(row.level_cap) and int(account.player_profile().level)>=commander and _afford(cost)}
func ascend(id:String,request_id:String="")->Dictionary:
	var replay:Dictionary=account._request(request_id,["tactical_ascend_v2",id])
	if not replay.is_empty():return replay
	var quote:Dictionary=ascent_preview(id)
	if not quote.get("ok",false):return quote
	if not quote.ready:return home._fail("需达到当前等级上限、指挥官等级并备齐突破资源")
	var before:Dictionary=account.state.duplicate(true);home._charge(quote.cost)
	home.state().units[id].ascension=int(quote.stage)+1;_gain_xp(id,0)
	return home._commit(before,"战术协议突破完成",{"unit":unit_profile(id),"cost":quote.cost})
func specialization_preview(id:String,kind:String)->Dictionary:
	var row:Dictionary=unit_profile(id);var cost:Dictionary={"alloy":80,"energy":100,"protocols":12}
	if not row.owned or not SPECIALIZATIONS.has(kind):return home._fail("请选择本人及有效专精")
	return {"ok":true,"id":id,"kind":kind,"cost":cost,"ready":home._idle() and int(row.level)>=15 and str(row.specialization)!=kind and _afford(cost)}
func specialize(id:String,kind:String,request_id:String="")->Dictionary:
	var replay:Dictionary=account._request(request_id,["tactical_specialization_v2",id,kind])
	if not replay.is_empty():return replay
	var quote:Dictionary=specialization_preview(id,kind)
	if not quote.get("ok",false):return quote
	if not quote.ready:return home._fail("专精需要本人达到15级并备齐资源")
	var before:Dictionary=account.state.duplicate(true);home._charge(quote.cost);home.state().units[id].specialization=kind
	return home._commit(before,"已切换战术专精 · 仅新岛屿行动生效",{"unit":unit_profile(id),"cost":quote.cost})
func replenishment_preview(id:String,target:int=100)->Dictionary:
	var row:Dictionary=unit_profile(id)
	if not row.owned or target<1 or target>100:return home._fail("请选择本人及1至100%的目标整备率")
	var missing:int=maxi(0,target-int(floor(float(row.condition))))
	var equivalent:float=float(row.deployed_bodies)*float(missing)/100.0
	var cost:Dictionary={"alloy":int(ceil(equivalent*5)),"energy":int(ceil(equivalent*8)),"credits":int(ceil(equivalent*12))}
	return {"ok":true,"id":id,"target":target,"condition":row.condition,"body_equivalent":equivalent,"deployed_bodies":row.deployed_bodies,"cost":cost,"ready":home._idle() and missing>0 and _afford(cost),"scope":"补回本次先遣编制的缺损；不会增加1000–6000个免费储备身体"}
func replenish(id:String,target:int,request_id:String="",confirmed_cost:Dictionary={})->Dictionary:
	var replay:Dictionary=account._request(request_id,["tactical_replenish_v2",id,target])
	if not replay.is_empty():return replay
	var quote:Dictionary=replenishment_preview(id,target)
	if not quote.get("ok",false):return quote
	if not quote.ready:return home._fail("请返航后补员，并确认缺损与资源")
	if not confirmed_cost.is_empty():
		for key in quote.cost:
			if int(quote.cost[key])>int(confirmed_cost.get(key,0)):return home._fail("整备费用已变化，请重新预览")
	var before:Dictionary=account.state.duplicate(true);home._charge(quote.cost)
	home.state().units[id].condition=maxf(home.condition(id),float(target));home.state().units[id].at=home._now()
	return home._commit(before,"缺损身体已补充 · 费用单次结算",{"unit":unit_profile(id),"cost":quote.cost,"body_equivalent":quote.body_equivalent})
func _afford(cost:Dictionary)->bool:
	for key in cost:
		if int(home.state().resources.get(key,0))<int(cost[key]):return false
	return true
func vehicle_repair_preview(id:String,target:int=100,company:int=0)->Dictionary:
	if not home.state().units.has(id) or target<1 or target>100 or company<0:return home._fail("请选择本人的载具及1至100%的维修目标")
	var profiles:Array=home.latest_vehicle_profiles(id);var entries:Array=[];var cost:Dictionary={}
	for vehicle in profiles:
		if company>0 and int(vehicle.company)!=company:continue
		var missing:float=maxf(0,float(target)-float(vehicle.hp_percent))
		var full:Variant=vehicle.get("repair_cost_full")
		if not full is Dictionary or full.is_empty():return home._fail("此载具维修价格尚未就绪，不产生费用")
		for key in full:
			if not home.RESOURCE_NAMES.has(key) or not is_finite(float(full[key])) or float(full[key])<0:return home._fail("此载具维修价格无效")
			cost[key]=int(cost.get(key,0))+int(ceil(float(full[key])*missing/100.0))
		if missing>0:entries.append({"company":int(vehicle.company),"before":float(vehicle.hp_percent),"target":target,"kind":str(vehicle.get("kind",""))})
	if profiles.is_empty() or company>int(home.latest_profile(id).get("company_count",0)):return home._fail("该编制没有可维修的独立作战载具")
	return {"ok":true,"id":id,"company":company,"target":target,"entries":entries,"cost":cost,"ready":home._idle() and not entries.is_empty() and _afford(cost)}
func repair_vehicles(id:String,target:int,company:int=0,request_id:String="",confirmed_cost:Dictionary={})->Dictionary:
	var replay:Dictionary=account._request(request_id,["tactical_vehicle_repair_v3",id,target,company])
	if not replay.is_empty():return replay
	var quote:Dictionary=vehicle_repair_preview(id,target,company)
	if not quote.get("ok",false):return quote
	if not quote.ready:return home._fail("请返航后维修，并确认载具缺损与资源")
	if not confirmed_cost.is_empty() and not home._same(confirmed_cost,quote.cost):return home._fail("载具维修费用已变化，请重新预览")
	var before:Dictionary=account.state.duplicate(true)
	if not home._charge(quote.cost):return home._fail("载具维修资源不足")
	var saved:Dictionary=home.state().units[id].get_or_add("vehicle_condition_v3",{})
	for entry in quote.entries:saved[str(int(entry.company))]=float(entry.target)
	return home._commit(before,"作战载具维修完成 · 身体整备独立",{"vehicles":home.latest_vehicle_profiles(id),"cost":quote.cost})
func growth_payload(ids:Array)->Array:
	var result:Array=[]
	for identity in ids:
		var row:Dictionary=unit_profile(str(identity))
		result.append({"id":str(identity),"level":int(row.level),"ascension":int(row.ascension),"specialization":str(row.specialization)})
	return result
func replay_record(run_id:String)->Dictionary:
	var record:Dictionary=home.state().development_v2.replays.get(run_id,{})
	if record.is_empty():return home._fail("此条旧记录未保存完整初始化与命令，不能伪造录像")
	if str(record.get("snapshot","")).is_empty():return home._fail(str(record.get("replay_unavailable_reason","此记录没有完整录像")))
	var result:Dictionary=record.duplicate(true);var saved:Variant=JSON.parse_string(str(result.snapshot))
	result["commands"]=saved.get("commands",saved.get("command_log",[])).duplicate(true) if saved is Dictionary else []
	return {"ok":true,"record":result}
func records()->Array:
	var result:Array=[]
	for key in home.state().development_v2.replays:
		var record:Dictionary=home.state().development_v2.replays[key]
		result.append({"run_id":str(key),"title":str(record.title),"mode":str(record.get("mode","raid")),"at":int(record.get("at",0)),"success":bool(record.get("success",false)),"local_simulation":true,"replay_available":not str(record.get("snapshot","")).is_empty(),"resources":record.get("resources",{}).duplicate(true),"losses":record.get("losses",{}).duplicate(true)})
	result.sort_custom(func(a:Dictionary,b:Dictionary):return int(a.at)>int(b.at))
	return result
