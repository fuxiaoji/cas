extends RefCounted
static var styles:Dictionary={}
static func engagement_hint(card:Dictionary)->String:
	var weapons:Array=[]
	for body in card.get("weapon_composition",[]):
		var weapon:String=family(body)
		if not weapons.has(weapon):weapons.append(weapon)
	if not card.get("combat_vehicles",[]).is_empty():
		if str(card.get("id",""))=="MCP-022":return "坦克与六名步枪手分别行动，车打硬目标、步兵清近处；重型登陆艇负责投送与撤收。"
		return "载具与身体独立作战。身体卡拖向本连载具登载，卸载卡拖向地面下车。"
	if str(card.get("id",""))=="MCP-009":return "步枪掩护接近工事，再拖炸药卡爆破；注意与爆炸范围保持距离。"
	if str(card.get("id",""))=="MCP-116":return "靠近友军展开保障，改善换弹与防护；增益不会生成弹药。"
	if weapons.has("shotgun") or weapons.has("smg"):return "贴近交火：霰弹与冲锋枪的远距离精度下降快。"
	if weapons.has("heavy_sniper") or weapons.has("sniper"):return "保持距离、停稳射击；狙击武器移动与近身精度较低。"
	if weapons.has("dmr"):return "射手步枪以点射保持中远程精度；弹匣打空后需要换弹。"
	if weapons.has("aa_missile"):return "防空弹留给空中威胁；地面自卫由手枪和步枪承担。"
	if weapons.has("rocket"):return "火箭筒手负责装甲目标，其他身体用轻武器掩护。"
	if weapons.has("pistol"):return "手枪仅供近距自卫，优先让友军掩护这支支援连。"
	return "接近有效交战距离再开火；最大射程内仍会有精度衰减。"
static func family(row:Dictionary)->String:
	var weapon:Dictionary=row.get("weapon",{}) if row.get("weapon",{}) is Dictionary else {}
	return str(row.get("weapon_family_id",weapon.get("family_id",row.get("weapon_id",weapon.get("id",""))))).to_lower()
## Small contextual weapon marks come from each actual body's loadout.
## They never select targets, change damage, or add people to the company.
static func caption(row:Dictionary)->String:
	var id:String=family(row)
	if id=="demolition_charge":return "爆破"
	if "aa" in id:return "防空"
	if "rocket" in id or "rpg" in id or "missile" in id:return "反甲"
	if "sniper" in id:return "狙击"
	if "shotgun" in id:return "霰弹"
	if "dmr" in id:return "射手"
	if "pistol" in id:return "手枪"
	if "howitzer" in id or "artillery" in id:return "炮兵"
	if id=="tank_gun":return "主炮"
	if id=="helicopter_cannon":return "机炮"
	if "smg" in id or "carbine" in id:return "轻装"
	if "autocannon" in id:return "机炮"
	return "步枪"
static func paint(canvas:CanvasItem,row:Dictionary,height:float,selected:bool,lift:float)->void:
	if str(row.get("equipment_version","")) not in ["tactical-vehicles-v3","tactical-vehicles-v4"] or float(row.get("hp",0))<=0:return
	if not selected and not bool(row.get("specialist",false)):return
	if height<22 or str(row.get("phase",""))=="parachuting":return
	var reloading:bool=float(row.get("reloading_in",0))>0
	var text:String="换弹" if reloading else caption(row)
	var width:float=29
	var rect:=Rect2(Vector2(height*.25,-height*.63-lift),Vector2(width,15))
	canvas.draw_style_box(_style(bool(row.get("specialist",false))),rect)
	canvas.draw_string(ThemeDB.fallback_font,rect.position+Vector2(2,11),text,HORIZONTAL_ALIGNMENT_CENTER,width-4,10,Color("f4f3e8"))
static func reload_status(data:Dictionary)->Dictionary:
	var states:Dictionary={}
	for body in data.get("land",{}).get("entities",[]):
		if str(body.get("equipment_version","")) not in ["tactical-vehicles-v3","tactical-vehicles-v4"] or float(body.get("hp",0))<=0 or not bool(body.get("active",true)):continue
		var company:String=str(body.get("company_id",""))
		if company.is_empty():continue
		if not states.has(company):states[company]={"members":0,"reloading":0}
		states[company].members+=1
		if float(body.get("reloading_in",0))>0:states[company].reloading+=1
	var result:Dictionary={}
	for company in states:
		var status:Dictionary=states[company]
		if int(status.reloading)>0:result[company]="换弹中 · 需要掩护" if int(status.reloading)==int(status.members) else "部分成员换弹"
	return result
static func _style(specialist:bool)->StyleBoxFlat:
	if styles.has(specialist):return styles[specialist]
	var style:=StyleBoxFlat.new();style.bg_color=Color("795732") if specialist else Color("25494a")
	style.set_corner_radius_all(3);styles[specialist]=style;return style
