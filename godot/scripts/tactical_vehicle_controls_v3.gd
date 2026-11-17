extends RefCounted
## Drag gestures only translate public intent. Native previews never move a
## passenger, and only the committed vehicle command can change a seat.
const Art=preload("res://scripts/tactical_transport_art.gd")
const NAMES:Dictionary={"tank":"坦克","amphibious_vehicle":"两栖战车","self_propelled_gun":"自行火炮","attack_helicopter":"武装直升机"}
static func active(controller)->bool:return str(controller.app.core.view.get("island_war",{}).get("version","")) in ["cas-island-war-v3","cas-island-war-v4","cas-island-war-coastal-v1"]
static func rows(controller)->Array:return controller.app.core.view.get("littoral",{}).get("land",{}).get("combat_vehicles",[])
static func company(controller,vehicle:Dictionary)->String:return controller._row_company(vehicle)
static func find(controller,id:int)->Dictionary:
	for vehicle in rows(controller):
		if int(vehicle.get("id",-1))==id:return vehicle
	return {}
static func own(controller,id:String)->Dictionary:
	for vehicle in rows(controller):
		if company(controller,vehicle)==id and str(vehicle.get("side","axis"))=="allies":return vehicle
	return {}
static func orphan(controller,id:String)->Dictionary:
	if not active(controller):return {}
	var vehicle:Dictionary=own(controller,id)
	if vehicle.is_empty() or float(vehicle.get("hp",0))<=0 or str(vehicle.get("phase","")) not in ["active","loading","unloading"]:return {}
	var living:Array=controller.app.core.view.get("littoral",{}).get("land",{}).get("entities",[]).filter(func(body):return company(controller,body)==id and not body.has("vehicle_kind") and float(body.get("hp",0))>0)
	for group in controller.app.core.view.get("littoral",{}).get("groups",[]):
		if str(group.id)==id and living.is_empty():return vehicle
	return {}
static func signature(controller)->Array:
	if not active(controller):return []
	return rows(controller).map(func(v):return [v.get("id"),v.get("phase"),v.get("passenger_ids",[]),float(v.get("hp",0))>0])
static func icon(vehicle:Dictionary)->Texture2D:
	var row:Dictionary=vehicle.duplicate();row["kind"]=str(vehicle.get("vehicle_kind",""));row["equipment_version"]="tactical-vehicles-v3"
	var spec:Dictionary=Art.specification_v3(row,0)
	if spec.is_empty() or not ResourceLoader.exists(str(spec.path)):return null
	var texture:=AtlasTexture.new();texture.atlas=load(str(spec.path));var region:Array=spec.frame.region
	texture.region=Rect2(float(region[0]),float(region[1]),float(region[2]),float(region[3]));texture.filter_clip=true;return texture
static func cards(controller,parent:HBoxContainer)->void:
	if not active(controller) or controller.primary_map!="land":return
	if controller.has_method("_coastal_controls") and controller._coastal_controls():return
	var vehicle:Dictionary=own(controller,controller.selected_unit)
	if vehicle.is_empty() or float(vehicle.get("hp",0))<=0 or str(vehicle.get("phase","")) in ["aboard","inserting","returning","recovered","dead"]:return
	if not orphan(controller,controller.selected_unit).is_empty():return # Already in this company's primary tray slot.
	var base:Dictionary=controller._company_fields(controller.selected_unit)
	base["vehicle_id"]=int(vehicle.id);base["texture"]=icon(vehicle);base["kind"]="vehicle";base["name"]=str(NAMES.get(str(vehicle.vehicle_kind),"作战载具"))
	controller._add_card(base,parent)
	if int(vehicle.get("capacity",0))>0 and not vehicle.get("passenger_ids",[]).is_empty():
		var unload:Dictionary=base.duplicate();unload["kind"]="vehicle_unload";unload["name"]="卸载本连身体";controller._add_card(unload,parent)
static func status(controller,payload:Dictionary)->Dictionary:
	if not active(controller) or str(payload.get("kind","")) not in ["vehicle","vehicle_unload"]:return {}
	var vehicle:Dictionary=find(controller,int(payload.get("vehicle_id",-1)))
	if vehicle.is_empty():return {"text":"载具已不可用","allowed":false}
	var phase:String=str(vehicle.get("phase",""));var available:bool=float(vehicle.get("hp",0))>0 and phase in ["active","loading","unloading"]
	var text:String="拖向落点卸载" if str(payload.kind)=="vehicle_unload" else "拖动独立移动 / 攻击"
	if phase=="loading":text="身体正靠近登载"
	elif phase=="unloading":text="正在实际卸载"
	elif float(vehicle.get("reloading_in",0))>0:text="载具武器换弹中"
	return {"text":text,"allowed":available}
static func unit_status(controller,id:String)->String:
	if not active(controller):return ""
	var vehicle:Dictionary=own(controller,id)
	if vehicle.is_empty() or vehicle.get("passenger_ids",[]).is_empty():return ""
	if str(vehicle.get("phase","")) in ["active","loading","unloading"]:return "搭乘中 · 拖向地面卸载"
	return ""
static func plan(controller,payload:Dictionary,location:Dictionary)->Dictionary:
	if not active(controller):return {}
	var kind:String=str(payload.get("kind",""))
	if kind not in ["unit","vehicle","vehicle_unload"]:return {}
	var vehicle:Dictionary=own(controller,controller._payload_company(payload)) if kind=="unit" else find(controller,int(payload.get("vehicle_id",-1)))
	if vehicle.is_empty():return {}
	var action:String=""
	var hit:Dictionary=location.get("hit",{});var target:Dictionary=hit.get("row",{})
	if kind=="vehicle_unload":action="disembark"
	elif kind=="vehicle":
		action=str(payload.get("vehicle_action",""))
		if action.is_empty():
			var coastal:bool=controller.has_method("_coastal_controls") and controller._coastal_controls()
			action="attack" if str(target.get("side","allies"))!="allies" and float(target.get("hp",0))>0 else "face" if not coastal and bool(payload.get("map_origin",false)) and str(controller.app.core.view.get("island_war",{}).get("version","")) in ["cas-island-war-v4","cas-island-war-coastal-v1"] else "move"
	else:
		var group:Dictionary={}
		for row in controller.app.core.view.littoral.get("groups",[]):
			if str(row.id)==controller._payload_company(payload):group=row;break
		if str(group.get("stage",""))!="ground":return {}
		if target.has("vehicle_kind") and str(target.get("side","axis"))=="allies" and int(target.get("id",-1))!=int(vehicle.id):return {"invalid_reason":"请把身体卡拖到本连自己的载具"}
		if target.has("vehicle_kind") and str(target.get("side","axis"))=="allies" and int(target.get("id",-1))==int(vehicle.id):action="embark"
		elif not vehicle.get("passenger_ids",[]).is_empty():action="disembark"
		else:return {}
	var world:Vector2=location.get("world",Vector2.ZERO)
	if action in ["attack","fire_at"] and str(target.get("side","allies"))!="allies" and float(target.get("hp",0))>0:world=Vector2(float(target.get("x",world.x)),float(target.get("y",world.y)))
	return {"command":{"op":"littoral_vehicle_order","vehicle_id":int(vehicle.id),"action":action,"x":world.x,"y":world.y},"event":"vehicle_"+action+"_ordered"}
static func preview(controller,payload:Dictionary,location:Dictionary)->Dictionary:
	var proposed:Dictionary=plan(controller,payload,location)
	if proposed.is_empty():return {}
	if proposed.has("invalid_reason"):return {"valid":false,"reason":str(proposed.invalid_reason)}
	if not bool(location.get("valid",false)):return {"valid":false,"reason":str(location.get("reason","请拖到主地图"))}
	if controller.primary_map!="land":return {"valid":false,"reason":"先切换陆图，再指挥载具和上下车"}
	var command:Dictionary=proposed.command.duplicate();command["op"]="littoral_vehicle_preview"
	var response:Dictionary=controller.app.core.request(command)
	if not response.get("ok",false):return {"valid":false,"reason":str(response.get("error","载具当前无法执行"))}
	var result:Dictionary=response.get("data",{})
	if bool(result.get("valid",false)):result["reason"]=str({"embark":"松手登载 · 身体实际走到本连载具","disembark":"松手指定卸载点 · 载具抵达后逐一卸载","move":"松手令载具独立移动 · 下车身体保持原任务","face":"松手指定火力方向 · 原地转向警戒","attack":"松手令载具向目标推进并交战 · 消耗自身弹药","fire_at":"松手原地开火 · 需要实际射程、视线和弹药"}.get(str(command.action),"松手下达载具命令"))
	return result
