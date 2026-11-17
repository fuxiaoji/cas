extends RefCounted
## Presentation grouping only: every quantity and weapon comes from the native catalogue.
const TARGETS:Dictionary={"unarmored":"无甲","light_armor":"轻甲","heavy_armor":"重甲","aircraft":"固定翼","helicopter":"直升机","parachuting":"下降伞兵"}
const ROLES:Dictionary={"air_assault":"空中突击","marine":"海军陆战","airborne":"伞降","engineer":"工兵","armor":"装甲","amphibious":"两栖装甲","assault":"突击步兵","recon":"侦察","gunship":"武装空突","electronic":"电子战","medic":"医疗","antiarmor":"反装甲","artillery":"自行火炮","transport":"运输","logistics":"保障","sniper":"狙击","airdefense":"防空","riverine":"河口作战","breacher":"攻坚","command":"指挥","rescue":"救援"}
const FAMILIES:Dictionary={"pistol":"手枪","rifle":"制式步枪","carbine":"轻型卡宾枪","smg":"冲锋枪","dmr":"精确射手步枪","lmg":"轻机枪","rocket":"反装甲火箭筒","sniper":"狙击步枪","heavy_sniper":"重型狙击步枪","shotgun":"霰弹枪","stinger":"便携防空导弹","aa_missile":"便携防空导弹","tank_gun":"坦克主炮","autocannon":"两栖战车机炮","howitzer":"自行榴弹炮","helicopter_cannon":"武直机炮","aa_cannon":"防空炮","grenade":"手雷","demolition":"工程炸药","demolition_charge":"工程炸药"}
const FIRE_MODES:Dictionary={"single":"单发点射","burst":"短点射","automatic":"连续射击"}
static func family(weapon:Dictionary)->String:return str(weapon.get("family_id",weapon.get("id","")))
static func cadence(weapon:Dictionary)->String:
	if not weapon.has("magazine_reload_s"):return "旧表未区分射击周期与弹匣换弹"
	var firing:String="%s · 点射间隔%.1f秒"%[str(FIRE_MODES.get(weapon.get("fire_mode",""),weapon.get("fire_mode",""))),float(weapon.get("fire_interval_s",0))]
	if str(weapon.get("fire_mode",""))=="burst":firing="%d连发 · 连射间隔%.1f秒 · 组间停顿%.1f秒"%[int(weapon.get("burst_size",1)),float(weapon.get("fire_interval_s",0)),float(weapon.get("burst_interval_s",0))]
	return firing+"\n弹匣%d发 · 空匣换弹%.1f秒 · 总携弹%d发（含弹匣）"%[int(weapon.get("magazine_capacity",0)),float(weapon.get("magazine_reload_s",0)),int(weapon.get("ammo_capacity",0))]
static func groups(home,id:String)->Array:
	var card:Dictionary=home.latest_profile(id);var by_weapon:Dictionary={}
	for slot in card.get("weapon_composition",[]):
		for source in ["weapon_id","secondary_weapon_id"]:
			if slot.get(source)==null:continue
			var weapon_id:String=str(slot[source]);var key:String=weapon_id+source
			if not by_weapon.has(key):by_weapon[key]={"weapon_id":weapon_id,"weapon":home.latest_weapons().get(weapon_id,{}).duplicate(true),"count":0,"specialists":0,"operators":0,"secondary":source=="secondary_weapon_id"}
			by_weapon[key].count+=1
			if bool(slot.get("specialist",false)):by_weapon[key].specialists+=1
			if slot.get("operator_vehicle")!=null:by_weapon[key].operators+=1
	return by_weapon.values()
static func summary(home,id:String)->String:
	var parts:Array[String]=[]
	for group in groups(home,id):parts.append("%d%s%s%s"%[int(group.count),"名专职" if int(group.specialists)==int(group.count) else "人","副武器" if bool(group.secondary) else "",str(group.weapon.get("name",group.weapon_id))])
	for vehicle in home.latest_profile(id).get("combat_vehicles",[]):parts.append("%d%s%s"%[int(vehicle.get("count_per_company",1)),"架" if str(vehicle.get("kind",""))=="attack_helicopter" else "辆",home.latest_transport_label(str(vehicle.get("kind","")))])
	return "每连 · "+" / ".join(parts)
static func add_details(home,id:String,parent:Node,label:Callable)->void:
	var card:Dictionary=home.latest_profile(id)
	label.call(parent,summary(home,id),23)
	for group in groups(home,id):
		var weapon:Dictionary=group.weapon
		var text_parent:Node=parent;var icon:Texture2D=weapon_icon(str(group.weapon_id),family(weapon))
		if icon!=null:
			var line:=HBoxContainer.new();line.add_theme_constant_override("separation",12);parent.add_child(line)
			var picture:=TextureRect.new();picture.texture=icon;picture.custom_minimum_size=Vector2(70,62);picture.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;picture.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED;line.add_child(picture)
			var text:=VBoxContainer.new();text.size_flags_horizontal=Control.SIZE_EXPAND_FILL;line.add_child(text);text_parent=text
		label.call(text_parent,"%s%s × %d · %s\n单发 %.1f · 最大射程 %.0f米"%["副武器 " if bool(group.secondary) else "",str(weapon.get("name",group.weapon_id)),int(group.count),str(FAMILIES.get(family(weapon),family(weapon))),float(weapon.get("damage",0)),float(weapon.get("range_m",0))],19)
		label.call(text_parent,cadence(weapon),17)
		if weapon.has("mean_fire_interval_s"):label.call(text_parent,"理论满匣循环均值 %.3f秒/发（含换弹）；实际移动或失去目标会中断射击。"%float(weapon.mean_fire_interval_s),15)
		if icon!=null:label.call(text_parent,"图标表示武器类别，型号数值分别裁决。",14)
		var multiplier:Dictionary=weapon.get("multipliers",{});var comparisons:Array[String]=[]
		for target in TARGETS:comparisons.append("%s ×%s"%[TARGETS[target],str(multiplier.get(target,0))])
		label.call(text_parent," · ".join(comparisons),16)
		var accuracy_value:Variant=weapon.get("accuracy");var accuracy:Dictionary=accuracy_value if accuracy_value is Dictionary else {}
		if not accuracy.is_empty():
			label.call(text_parent,("散布品质基准系数" if str(accuracy.get("application",""))=="indirect_spread" else "静止基准命中")+" %.1f%% · 移动×%.2f · 近身×%.2f→1（%.0f米）"%[float(accuracy.get("base_hit",0))*100,float(accuracy.get("moving_multiplier",1)),float(accuracy.get("close_multiplier",1)),float(accuracy.get("close_range_m",0))],17)
			if str(accuracy.get("application",""))=="indirect_spread":label.call(text_parent,"范围武器按距离精度改变真实散布，此系数不等于直接命中概率。",16)
		if int(group.operators)>0:label.call(text_parent,"其中%d名配属作战载具；乘坐时不在车旁复制步兵，离车后使用自身武器。"%int(group.operators),17)
	for vehicle in card.get("combat_vehicles",[]):
		var weapon:Dictionary=home.latest_weapons().get(str(vehicle.get("weapon_id","")),{})
		var text_parent:Node=parent;var icon:Texture2D=vehicle_icon(str(vehicle.get("kind","")))
		if icon!=null:
			var line:=HBoxContainer.new();line.add_theme_constant_override("separation",12);parent.add_child(line)
			var picture:=TextureRect.new();picture.texture=icon;picture.custom_minimum_size=Vector2(112,105);picture.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;picture.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED;line.add_child(picture)
			var text:=VBoxContainer.new();text.size_flags_horizontal=Control.SIZE_EXPAND_FILL;line.add_child(text);text_parent=text
		label.call(text_parent,"%s · 每连%d%s · 独立耐久%.0f · %s · %.0f米/秒"%[home.latest_transport_label(str(vehicle.get("kind",""))),int(vehicle.get("count_per_company",1)),"架" if str(vehicle.get("kind",""))=="attack_helicopter" else "辆",float(vehicle.get("hp",0)),str(TARGETS.get(vehicle.get("armor_class",""),vehicle.get("armor_class",""))),float(vehicle.get("speed",0))],20)
		label.call(text_parent,"载具由人格共同意识操控；无乘员座位，步兵始终在车外独立协同。" if int(vehicle.get("passenger_seats",vehicle.get("capacity",0)))==0 else "载具由人格共同意识操控；%d个座位，身体可上下车。乘坐时不复制步兵，离车后独立作战。"%int(vehicle.get("passenger_seats",vehicle.get("capacity",0))),16)
		label.call(text_parent,"%s · 单发%.1f · 最大射程%.0f米"%[str(weapon.get("name","")),float(weapon.get("damage",0)),float(weapon.get("range_m",0))],18)
		label.call(text_parent,cadence(weapon),17)
	var skill:Dictionary=card.get("ability",{});var skill_weapon:String=str(skill.get("weapon_id",""));var used:Dictionary={}
	for group in groups(home,id):used[str(group.weapon_id)]=true
	for vehicle in card.get("combat_vehicles",[]):used[str(vehicle.get("weapon_id",""))]=true
	if not skill_weapon.is_empty() and not used.has(skill_weapon):
		var weapon:Dictionary=home.latest_weapons().get(skill_weapon,{})
		label.call(parent,"技能装备 · "+str(weapon.get("name",skill_weapon)),20)
		if str(skill.get("ammo_pool",""))=="company_throwables":label.call(parent,"本连独立投掷物库存%d枚 · 技能冷却%.1f秒；消耗同一份技能次数，不是弹匣持续开火。"%[int(skill.get("charges",0)),float(skill.get("cooldown",0))],17)
		else:label.call(parent,"可部署%d次，装备各有独立有限弹药池。"%int(skill.get("charges",0)),17);label.call(parent,cadence(weapon),17)
		label.call(parent,"单次基础伤害%.1f · 最大射程%.0f米 · 范围半径%.0f米"%[float(weapon.get("damage",0)),float(weapon.get("range_m",0)),float(weapon.get("blast_radius_m",0))],17)

static func weapon_icon(id:String,family_id:String="")->Texture2D:
	var manifest:String="res://data/tactical-weapons-art-v3.json"
	var raw:Variant=JSON.parse_string(FileAccess.get_file_as_string(manifest)) if FileAccess.file_exists(manifest) else null
	if not raw is Dictionary:return null
	var row:Dictionary=raw.get("weapons",{}).get(id,raw.get("weapons",{}).get(family_id,{}))
	var source:String=str(row.get("source",""));var region:Array=row.get("region",[])
	if source.is_empty() or region.size()!=4 or not ResourceLoader.exists(source):return null
	var result:=AtlasTexture.new();result.atlas=load(source);result.region=Rect2(float(region[0]),float(region[1]),float(region[2]),float(region[3]));return result
static func vehicle_icon(kind:String)->Texture2D:
	var manifest:String="res://data/tactical-vehicles-v3.json"
	var raw:Variant=JSON.parse_string(FileAccess.get_file_as_string(manifest)) if FileAccess.file_exists(manifest) else null
	if not raw is Dictionary:return null
	var row:Dictionary=raw.get("vehicles",{}).get(kind,{})
	var extra:String="res://data/tactical-vehicles-v4.json"
	if FileAccess.file_exists(extra):
		var newest:Variant=JSON.parse_string(FileAccess.get_file_as_string(extra))
		if newest is Dictionary and newest.get("vehicles",{}).has(kind):row=newest.vehicles[kind]
	var source:String=str(row.get("atlas",""));var region:Array=row.get("frames",{}).get("N",{}).get("region",[])
	if source.is_empty() or region.size()!=4 or not ResourceLoader.exists(source):return null
	var result:=AtlasTexture.new();result.atlas=load(source);result.region=Rect2(float(region[0]),float(region[1]),float(region[2]),float(region[3]));return result
