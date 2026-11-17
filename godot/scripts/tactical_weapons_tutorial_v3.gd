extends "res://scripts/littoral_drag_tutorial.gd"
## Native predicates own completion. Dragging, closing help or restoring its
## UI checkpoint can never satisfy a weapon, landing or recovery check.
var field_step:Dictionary={"id":"field","text":"先观察岸防，再拖动部队卡安排投送。","from":"deploy_card","to":"landing_zone"}
var intent:String="field"
func _steps()->Array[Dictionary]:return [field_step]
func current_step()->String:return "complete" if _finished else intent
func _set_intent(value:String)->void:
	if intent==value:return
	intent=value;step_changed.emit(value,0)
func notify_event(_kind:String,data:Dictionary={})->void:
	if bool(data.get("accepted",false)) and data.has("focus"):_focus=str(data.focus)
func observe_focus(focus:String)->void:_focus=focus
func observe_state(public_view:Dictionary)->void:
	if not active or _finished:return
	_view=public_view
	var value:Variant=public_view.get("littoral",{}).get("training")
	if not value is Dictionary:return
	var training:Dictionary=value
	if str(public_view.get("island_war",{}).get("version","")) not in ["cas-island-war-v3","cas-island-war-v4","cas-island-war-coastal-v1"] or training.is_empty():return
	_needs_revalidation=false
	var current:Dictionary={}
	for check in training.get("checks",[]):
		if not bool(check.get("done",false)):current=check;break
	if bool(training.get("complete",false)) and _successful_outcome():
		_advance({"source":"public_core","version":str(public_view.island_war.version),"lesson":training.get("lesson",""),"checks":training.get("checks",[]),"tick":public_view.get("tick",0)})
		return
	var groups:Array=public_view.get("littoral",{}).get("groups",[])
	var preferred:String=str(current.get("unit_id",""))
	var recovery:bool=current.is_empty() or str(current.get("id",""))=="recover"
	var candidates:Array=[]
	for group in groups:
		if str(group.get("side","allies"))!="allies":continue
		var stage:String=str(group.get("stage","embarked"))
		if recovery:
			if stage not in ["embarked","recovered","lost"]:candidates.append(group)
		elif preferred.is_empty() or str(group.get("unit_id",""))==preferred:
			if stage not in ["recovered","lost"]:candidates.append(group)
	if not candidates.is_empty():
		if not candidates.any(func(row):return str(row.id)==unit_id):
			unit_id=str(candidates[0].id);step_changed.emit(current_step(),0)
	elif recovery:
		for vehicle in public_view.get("littoral",{}).get("land",{}).get("combat_vehicles",[]):
			if str(vehicle.get("side","axis"))=="allies" and float(vehicle.get("hp",0))>0 and str(vehicle.get("phase","")) not in ["aboard","recovered"]:
				_set_intent("vehicle_recovery");field_step["from"]="";field_step["to"]="sea_minimap" if _focus=="land" else "transport";field_step["text"]="身体已归舰，作战载具仍在实际回收。等车体与机体也安全归队后，再安排舰队返航。";_refresh();return
		_set_intent("return")
		field_step["from"]="" if _focus=="land" else "return_card";field_step["to"]="sea_minimap" if _focus=="land" else "return_zone"
		field_step["text"]="存活部队已归舰，切回海图准备返航。" if _focus=="land" else "把返航卡拖到海上的撤离圈；舰队真正回到圈内后再完成返航。"
		_refresh();return
	var chosen:Dictionary=_group()
	var phase:String=str(chosen.get("stage","embarked"))
	_set_intent("withdraw" if recovery and phase=="ground" else "field")
	var text:String=str(current.get("instruction",current.get("label","清除岸防、发挥各连的武器分工，再把所有存活身体接回船。")))
	if recovery:
		field_step["from"]="withdraw_card" if phase=="ground" else "";field_step["to"]="withdraw_zone" if phase=="ground" else "transport"
		text="把撤收卡拖到这支连队，将存活身体实际接回船；其他连队也要逐一接回。" if phase=="ground" else "正在接回这支连队，等待身体实际登船。"
	elif phase=="embarked":
		field_step["from"]="deploy_card";field_step["to"]="landing_zone"
		text="先拖动部队卡到合法落点；普通登陆艇需要靠岸，空中部队也要避开防空。"
	elif phase=="transit":
		field_step["from"]="";field_step["to"]="transport";text="投送中；艇上乘员仍有各自耐久。可用倍速观察靠岸与卸载。"
	else:
		field_step["from"]="squad_card";field_step["to"]="land_enemy"
		var check_id:String=str(current.get("id",""))
		if check_id in ["vehicle_infantry","disembark","embark","independent_fire"]:
			var vehicle:Dictionary={}
			for row in public_view.get("littoral",{}).get("land",{}).get("combat_vehicles",[]):
				if str(row.get("company_id",""))==unit_id and str(row.get("side",""))=="allies":vehicle=row;break
			if check_id=="embark":
				field_step["to"]="vehicle_zone";text="把身体卡拖到本连载具。身体会实际走近再登载，途中仍可能受伤。"
				if str(vehicle.get("phase",""))=="loading":field_step["from"]="";text="载具正与身体会合。等存活身体实际登载，再安排下一步。"
			elif check_id=="disembark":
				field_step["from"]="vehicle_unload_card";field_step["to"]="vehicle_unload_zone";text="把卸载卡拖向附近陆地。等载具抵达、身体逐一出现，再分别指挥她们。"
				if vehicle.get("passenger_ids",[]).is_empty():field_step["from"]="squad_card";field_step["to"]="vehicle_zone";text="本连身体已在车外。先把身体卡拖到本连载具登载，再练习指定落点卸载。"
			elif check_id=="independent_fire":
				if not vehicle.get("passenger_ids",[]).is_empty():field_step["from"]="vehicle_unload_card";field_step["to"]="vehicle_unload_zone";text="先卸载身体，再让身体和载具分别向敌方开火。车与人的武器、弹匣各自消耗。"
				elif "vehicle_fired" in training.get("evidence",[]):field_step["from"]="squad_card";text="载具已经实际开火。再把身体卡拖向敌方，让步枪手用自己的武器射击。"
				else:field_step["from"]="vehicle_card";text="把载具卡拖向敌方，随后把身体卡也拖向敌方。两种实体要各自实际开火才算完成。"
			else:field_step["from"]="vehicle_card";text="坦克和六名步枪手分别行动。内置协同会随车掩护、侧出射击；拖坦克卡推进，也可直接拖地图上的身体指挥。"
		elif check_id in ["command_network","grenade","deploy_aa_turret","support_designation","demolition_charge","supply_network"]:
			field_step["from"]="ability_card"
			field_step["to"]="friendly_zone" if check_id in ["command_network","supply_network"] else "ability_zone" if check_id=="deploy_aa_turret" else "demolition_target" if check_id=="demolition_charge" else "land_enemy"
			var ability:Dictionary=chosen.get("ability",{})
			if not bool(ability.get("available",false)):
				field_step["from"]=""
				text="专长已下达。观察实际作用；冷却与剩余次数以卡片为准。"
				if check_id=="command_network":
					field_step["from"]="squad_card";field_step["to"]="land_move_zone";text="让增益圈内的部队移动、射击或执行任务；实际获得增益后才会完成这一步。"
				elif check_id=="supply_network":
					field_step["from"]="squad_card";field_step["to"]="land_enemy";text="在保障圈内交战，实际换弹或承受攻击后才会完成。保障只提供增益，不产生弹药。"
			elif check_id=="grenade" and _nearest_threat_distance(public_view,chosen)>float(ability.get("range",0)):
				field_step["from"]="squad_card";field_step["to"]="land_enemy";text="敌人还在手雷距离外。先拖部队卡接近，进入投掷距离后再拖手雷卡。"
			elif check_id=="demolition_charge" and _nearest_fortification_distance(public_view,chosen)>float(ability.get("range",180)):
				field_step["from"]="squad_card";text="工兵先在掩护下接近敌方工事。炸药射程短，进入180米内后再拖爆破卡；不要把炸药丢到空地。"
			if check_id=="support_designation" and _live_designation(public_view):
				field_step["from"]="land_support_card";field_step["to"]="support_zone"
				text="标记已展开，把舰炮卡拖到标记圈内；炮弹仍然需要装填并消耗真实余弹。"
				if not _targets.has("land_support_card"):
					field_step["from"]="";field_step["to"]="sea_minimap";text="先切回海图，把支援战舰的炮火指向标记所在岛屿，再用舰炮卡打进标记圈。"
	if _focus=="sea" and phase=="ground":field_step["from"]="";field_step["to"]="land_minimap";text="点右上小地图切到陆地，查看各连武器与当前目标。"
	if _focus=="sea" and str(current.get("id",""))=="support_designation" and _live_designation(public_view):
		field_step["from"]="gun_badge";field_step["to"]="naval_target";text="将支援战舰的炮火指向标记所在岛屿，再点小地图回陆地拖动舰炮卡。"
	if float(training.get("preparation_remaining_s",0))>0:text="演习准备 %.0f秒 · "%ceil(float(training.preparation_remaining_s))+text
	field_step["text"]=text;_refresh()
func _live_designation(public_view:Dictionary)->bool:
	for effect in public_view.get("littoral",{}).get("land",{}).get("effects",[]):
		if str(effect.get("kind",""))=="support_designation" and str(effect.get("side",""))=="allies" and float(effect.get("remaining_s",0))>0:return true
	return false
func _nearest_threat_distance(public_view:Dictionary,chosen:Dictionary)->float:
	var origin:Dictionary=chosen.get("position",{})
	var at:=Vector2(float(origin.get("x",0)),float(origin.get("y",0)))
	var land:Dictionary=public_view.get("littoral",{}).get("land",{})
	var nearest:float=INF
	for threat in land.get("entities",[])+land.get("buildings",[]):
		if str(threat.get("side","axis"))=="allies" or float(threat.get("hp",0))<=0 or not bool(threat.get("active",true)):continue
		nearest=minf(nearest,at.distance_to(Vector2(float(threat.x),float(threat.y))))
	return nearest
func _nearest_fortification_distance(public_view:Dictionary,chosen:Dictionary)->float:
	var nearest:float=INF
	for body in public_view.get("littoral",{}).get("land",{}).get("entities",[]):
		if str(body.get("company_id",""))!=str(chosen.get("id","")) or float(body.get("hp",0))<=0 or not bool(body.get("active",true)):continue
		for target in public_view.get("littoral",{}).get("land",{}).get("buildings",[]):
			if str(target.get("side","axis"))=="allies" or float(target.get("hp",0))<=0:continue
			nearest=minf(nearest,Vector2(float(body.x),float(body.y)).distance_to(Vector2(float(target.x),float(target.y))))
	return nearest
