extends RefCounted
## A ship's original CAS reference and its account progression remain distinct.
const Design = preload("res://scripts/ui_design.gd")
const Supply = preload("res://scripts/supply_presentation.gd")
const Art=preload("res://scripts/growth_art.gd")
const Appearance=preload("res://scripts/ship_appearance_service.gd")
const SLOTS := {"equipment":"舰装", "helmsman":"舵手组", "gunnery":"火炮组", "damage_control":"损管组", "command":"指挥组"}
const STATS := {"hp":"耐久", "speed":"航速", "firepower":"火力", "base_hit":"基础炮击命中", "command":"同步机动成功率", "all":"综合强化（耐久 / 航速 / 炮击）", "balanced":"耐久34% / 航速33% / 火力33%预算"}
static var references: Dictionary = {}

static func render(app, ship: Dictionary) -> void:
	if ship.is_empty():
		app.label(app.page,"请先选择一位舰娘",60,200,1200,60,28,Design.INK)
		return
	var id := str(ship.id)
	var appearance=Appearance.new(app.economy)
	var visual:Dictionary=appearance.visual(id)
	var growth: Dictionary = app.economy.growth_profile(id) if app.economy.has_method("growth_profile") else ship
	app.picture(app.page, str(visual.get("portrait",ship.get("portrait", ""))), 45, 115, 510, 655)
	app.panel(app.page,50,638,500,174,Color.WHITE)
	app.label(app.page,str(ship.get("name","舰娘")),77,653,440,58,32,Design.INK)
	app.label(app.page,"%s  /  Lv.%d" % [str(ship.get("class",ship.get("type",""))),int(growth.get("level",1))],80,718,440,40,21,Design.MUTED)
	var repair: Button = app.button(app.page,"维修",74,766,210,43,func():_service(app,id,"repair"))
	var ammo: Button = app.button(app.page,"装载弹药",307,766,218,43,func():_service(app,id,"rearm"))
	repair.tooltip_text="当前耐久 %d%%" % int(ship.get("hp",100))
	ammo.tooltip_text="计划弹药 %d" % int(ship.get("ammo",0))
	var chosen := str(app.get_meta("ship_detail_tab","reference"))
	var tabs:Array[String]=["reference","growth","equipment","crews"]
	var labels:Array[String]=["舰表","成长","舰装","水手"]
	if not appearance.variants(id).is_empty():tabs.append("appearance");labels.append("形象")
	var width:float=948.0/tabs.size()
	for i in tabs.size():
		var key:String=tabs[i]
		var tab: Button=app.button(app.page,labels[i],596+i*width,131,width-17,56,func():app.set_meta("ship_detail_tab",key);app.show_page("ship_detail"))
		Supply.style_tab(tab,chosen==key)
	var body := _body(app)
	match chosen:
		"appearance":_appearances(app,body,id)
		"growth": _growth(app,body,ship,growth)
		"equipment": _loadout(app,body,ship,growth,["equipment"])
		"crews": _loadout(app,body,ship,growth,["helmsman","gunnery","damage_control","command"])
		_: _reference(app,body,ship)

static func _appearances(app,body:Control,identity:String)->void:
	var service=Appearance.new(app.economy)
	_section(body,"同一舰娘 · 两种形象")
	var row:=HBoxContainer.new();row.add_theme_constant_override("separation",20);body.add_child(row)
	for option in service.options(identity):
		var column:=VBoxContainer.new();column.size_flags_horizontal=Control.SIZE_EXPAND_FILL;column.add_theme_constant_override("separation",10);row.add_child(column)
		var portrait:=TextureRect.new();portrait.texture=load(str(option.portrait)) if ResourceLoader.exists(str(option.portrait)) else null
		portrait.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;portrait.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED;portrait.custom_minimum_size=Vector2(270,320);portrait.size_flags_horizontal=Control.SIZE_EXPAND_FILL;column.add_child(portrait)
		var miniature:=TextureRect.new();miniature.name="Miniature_"+str(option.id);miniature.texture=load(str(option.chibi)) if ResourceLoader.exists(str(option.chibi)) else null
		miniature.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;miniature.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED;miniature.mouse_filter=Control.MOUSE_FILTER_IGNORE;portrait.add_child(miniature)
		miniature.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT);miniature.offset_left=-118;miniature.offset_top=-118
		_text(column,str(option.get("name",option.id)),24)
		var is_selected:bool=service.selected(identity)==str(option.id)
		_text(column,"立绘与小人一同更换" if bool(option.unlocked) else "舰娘 Lv.%d 解锁"%int(option.unlock_level),19,Design.MUTED)
		var variant_id:String=str(option.id)
		var equip:Button=_button(app,column,"正在使用" if is_selected else "使用此形象" if bool(option.unlocked) else "尚未解锁",func():
			var response:Dictionary=service.choose(identity,variant_id)
			app.show_page("ship_detail");app.notify(response),true)
		equip.name="Appearance_"+variant_id
		equip.disabled=is_selected or not bool(option.unlocked) or not app.economy.state.get("active_run",{}).is_empty()
		equip.tooltip_text="返航后可更换立绘与小人" if not app.economy.state.get("active_run",{}).is_empty() else "舰娘 Lv.%d 解锁"%int(option.unlock_level) if not bool(option.unlocked) else "正在使用" if is_selected else "同时更换立绘与战斗小人"

static func _body(app) -> VBoxContainer:
	var scroll:=ScrollContainer.new()
	app.place(scroll,app.page,602,221,936,582)
	scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	var body:=VBoxContainer.new()
	body.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation",15)
	scroll.add_child(body)
	return body

static func _text(parent: Control, text: String, size:=21, color:=Design.INK) -> Label:
	var label:=Label.new()
	label.text=text
	label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	label.add_theme_font_override("font",Design.font(600 if size>=24 else 400))
	label.add_theme_font_size_override("font_size",size)
	label.add_theme_color_override("font_color",color)
	parent.add_child(label)
	return label

static func _section(parent: Control, title: String) -> void:
	_text(parent,title,24)
	parent.add_child(HSeparator.new())

static func _row(parent: Control, title: String, value: String) -> void:
	var line:=HBoxContainer.new()
	line.add_theme_constant_override("separation",24)
	parent.add_child(line)
	var caption:=_text(line,title,20,Design.MUTED)
	caption.custom_minimum_size.x=220
	caption.size_flags_horizontal=Control.SIZE_SHRINK_BEGIN
	_text(line,value,21)

static func _button(app,parent: Control,title: String,callback: Callable,primary:=false) -> Button:
	var button: Button=app.button(app.page,title,0,0,1,1,callback,primary)
	app.page.remove_child(button)
	parent.add_child(button)
	button.custom_minimum_size.y=49
	return button

static func sheet_reference(id: String) -> Dictionary:
	if references.is_empty():
		var value: Variant=JSON.parse_string(FileAccess.get_file_as_string("res://data/ship-reference.json"))
		if value is Dictionary: references=value.get("ships",{})
	return references.get(id,{})

static func _series(values: Array, unit: String="") -> String:
	var parts:PackedStringArray=[]
	for value in values:parts.append(_value(value))
	return " / ".join(parts)+(" "+unit if not unit.is_empty() else "")

static func _value(value: Variant) -> String:
	if value==null:return "—"
	if value is float and is_equal_approx(value,round(value)):return str(int(value))
	return str(value)

static func _reference(app,body: Control,ship: Dictionary) -> void:
	var record:=sheet_reference(str(ship.id))
	if record.is_empty():
		_text(body,"该舰的 CAS 舰表尚未核验。",24)
		return
	var base: Dictionary=record.get("base",{})
	_section(body,"舰体与航行")
	_row(body,"耐久 / 最高航速","%s DP  /  %s 节" % [_value(base.get("dp","—")),_value(base.get("max_knots","—"))])
	_row(body,"舷侧 / 甲板装甲","%s / %s" % [_value(base.get("armor_belt","—")),_value(base.get("armor_deck","—"))])
	_row(body,"舰型 / 转向尺度","%s / %s" % [_value(base.get("size","—")),_value(base.get("turn_size","—"))])
	_row(body,"转向推进 / 失速","%s 码 / %s 节" % [_value(base.get("turn_advance_yards","—")),_value(base.get("speed_loss_knots","—"))])
	_row(body,"加速 / 高速加速 / 减速","%s / %s / %s 节每回合" % [_value(base.get("accel_knots_per_turn","—")),_value(base.get("accel_high_knots_per_turn","—")),_value(base.get("brake_knots_per_turn","—"))])
	if base.has("torpedo_protection_dp"):_row(body,"水下防护",str(base.torpedo_protection_dp)+" DP")
	var gun: Dictionary=base.get("gun",{})
	_section(body,"主炮")
	_row(body,_value(gun.get("name","主炮")),"%s mm × %s" % [_value(gun.get("caliber_mm","—")),_value(gun.get("barrels","—"))])
	_row(body,"近 / 中 / 远 / 极远射程",_series(gun.get("range_yd",[]),"码"))
	_row(body,"对应伤害",_series(gun.get("damage",[])))
	_row(body,"舷侧 / 甲板穿深",_series(gun.get("pen_belt",[]))+"\n"+_series(gun.get("pen_deck",[])))
	_row(body,"炮术标准 / 炮座数","%s / %d" % [_value(gun.get("gs","—")),gun.get("mounts",[]).size()])
	var secondary:Variant=base.get("secondary")
	if secondary is Dictionary and not secondary.is_empty():
		_section(body,"副炮")
		_row(body,_value(secondary.get("name","副炮")),"%s mm × %s" % [_value(secondary.get("caliber_mm","—")),_value(secondary.get("barrels","—"))])
		_row(body,"近 / 中 / 远 / 极远射程",_series(secondary.get("range_yd",[]),"码"))
		_row(body,"对应伤害",_series(secondary.get("damage",[])))
	_section(body,"鱼雷")
	var torpedo: Variant=base.get("torpedo")
	if torpedo is Dictionary:
		_row(body,_value(torpedo.get("name","鱼雷")),"%s 管 / 战斗部 %s" % [_value(torpedo.get("tubes","—")),_value(torpedo.get("warhead","—"))])
		var settings: PackedStringArray=[]
		for option in torpedo.get("speed_options",[]):settings.append("%s 节 · %s 码" % [_value(option.get("speed_knots","—")),_value(option.get("range_yd","—"))])
		_row(body,"航速与射程","\n".join(settings) if not settings.is_empty() else "%s 节 · %s 码" % [_value(torpedo.get("speed_knots","—")),_value(torpedo.get("range_yd","—"))])
	else:_text(body,"本舰未装鱼雷。",20,Design.MUTED)
	_section(body,"损伤航速")
	var damage: PackedStringArray=[]
	for row in base.get("damage_speed",[]):damage.append("%s DP → %s 节" % [_value(row.get("damage","—")),_value(row.get("knots","—"))])
	_text(body,"  /  ".join(damage),20,Design.MUTED)
	_text(body,"CAS 原始舰表；自有舰成长在「成长」页另列。",19,Design.MUTED)
	if str(record.get("source_kind",""))=="same_class":_text(body,"本舰采用已核验的同级舰表。",19,Design.MUTED)
	_button(app,body,"查看舰表来源",func():
		var layer: Control=app.open_modal("舰表来源")
		app.label(layer,str(record.get("source",""))+"\n\n配置："+_value(base.get("period_label",base.get("configuration_year","—")))+"\n\n数据源："+str(record.get("source_file","")),390,242,820,400,22,Design.INK))

static func _progress(parent: Control, value: float, maximum: float) -> void:
	var bar:=ProgressBar.new()
	bar.show_percentage=false
	bar.max_value=maxf(1,maximum)
	bar.value=value
	bar.custom_minimum_size.y=12
	bar.add_theme_stylebox_override("background",Design.box(Color("dde6eb"),2))
	bar.add_theme_stylebox_override("fill",Design.box(Design.ACCENT,2))
	parent.add_child(bar)

static func _growth(app,body: Control,ship: Dictionary,growth: Dictionary) -> void:
	_section(body,"舰历成长")
	var level_cap:=int(growth.get("level_cap",10))
	_row(body,"等级","Lv.%d / %d" % [int(growth.get("level",0)),level_cap])
	_progress(body,float(growth.get("xp",0)),float(growth.get("xp_next",1)))
	_text(body,"经验 %d / %d" % [int(growth.get("xp",0)),int(growth.get("xp_next",1))],20,Design.MUTED)
	var actions:=HBoxContainer.new();actions.add_theme_constant_override("separation",14);body.add_child(actions)
	var mats:Array=app.economy.material_catalog()
	for i in range(3):
		var mat:Dictionary=mats[i]
		var tier:=i+1
		var col:=VBoxContainer.new();col.size_flags_horizontal=Control.SIZE_EXPAND_FILL;actions.add_child(col)
		var art:=Art.icon(col,str(mat.id),66);art.size_flags_horizontal=Control.SIZE_SHRINK_CENTER
		var caption:=_text(col,"×%d"%int(mat.owned),19,Design.MUTED);caption.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
		var train:=_button(app,col,"+%d EXP"%int(mat.xp),func():_train(app,str(ship.id),tier),true)
		train.add_theme_font_size_override("font_size",20)
		train.tooltip_text="%s ×1 / 银币 %d"%[str(mat.name),int(mat.xp)*5/4]
		train.disabled=int(mat.owned)<1 or int(app.economy.wallet().credits)<int(mat.xp)*5/4 or int(growth.level)>=level_cap or not app.economy.state.active_run.is_empty()
	var ascent:Dictionary=app.economy.ascend_preview(str(ship.id))
	if not bool(ascent.get("maxed",false)):
		_text(body,"突破至 Lv.%d · 指挥官 Lv.%d"%[int(ascent.next_cap),int(ascent.required_player_level)],22)
		var costs:=HBoxContainer.new();costs.add_theme_constant_override("separation",12);body.add_child(costs)
		for key in ascent.materials:
			Art.icon(costs,str(key),42)
			_text(costs,"%d / %d"%[int(app.economy.wallet().get(key,0)),int(ascent.materials[key])],20,Design.MUTED)
		_text(costs,"银币 %d"%int(ascent.credits),20,Design.MUTED)
		var advance:=_button(app,body,"等级突破",func():_ascend(app,str(ship.id)),true)
		advance.disabled=not bool(ascent.ready)
		advance.tooltip_text="达到当前等级上限，满足指挥官等级与材料条件后突破。上限处的超额经验会保留。"
	_section(body,"实战熟练度")
	_progress(body,float(growth.get("mastery",0)),float(growth.get("mastery_max",1000)))
	_text(body,"%d / %d · 随真实出航积累" % [int(growth.get("mastery",0)),int(growth.get("mastery_max",1000))],20,Design.MUTED)
	_mastery_rewards(app,body,str(ship.id))
	_section(body,"当前自有舰加成")
	var bonuses: Dictionary=growth.get("bonuses",{})
	for key in ["hp","speed","firepower","base_hit"]:
		_row(body,str(STATS[key]),"+%.2f%%" % ((float(bonuses.get(key,1))-1.0)*100.0))
	_row(body,str(STATS.command),"%.2f%%（含基础成功率）" % (float(bonuses.get("command",0))*100.0))
	_text(body,"同步机动概率用于打捞；战役沿用原控制。",19,Design.MUTED)
	_text(body,str(growth.get("scope","仅自有舰 PvE；历史借用舰保持原始舰表。")),19,Design.MUTED)

static func _mastery_rewards(app,body: Control,id: String) -> void:
	var rewards: Array=app.economy.mastery_rewards(id)
	if rewards.is_empty():return
	_text(body,"熟练纪念 · 每档 "+Supply.rewards_text(rewards[0].get("grants",{})),20,Design.MUTED)
	var row:=HBoxContainer.new()
	row.add_theme_constant_override("separation",12)
	body.add_child(row)
	for reward in rewards:
		var threshold:=int(reward.threshold)
		var status: String={"locked":"未达成","ready":"领取","claimed":"已领取"}.get(str(reward.status),"未达成")
		var claim:=_button(app,row,"%d · %s" % [threshold,status],func():_claim_mastery(app,id,threshold),bool(reward.available))
		claim.add_theme_font_size_override("font_size",20)
		claim.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		claim.disabled=not bool(reward.available) or not app.economy.state.get("active_run",{}).is_empty()
		claim.tooltip_text=Supply.rewards_text(reward.get("grants",{}))+" · 每舰每档限领一次"
		claim.set_meta("mastery_threshold",threshold)

static func _claim_mastery(app,id: String,threshold: int) -> void:
	var response: Dictionary=app.economy.claim_mastery_reward(id,threshold)
	app.show_page("ship_detail");app.notify(response)

static func affix(affix_data: Dictionary) -> String:
	if affix_data.is_empty():return "无词条"
	if int(affix_data.get("bp",0))==0:return "无附加效果"
	var stat:=str(affix_data.get("stat",""))
	return "%s +%.2f%%" % [str(STATS.get(stat,stat)),float(affix_data.get("bp",0))/100.0]

static func _loadout(app,body: Control,ship: Dictionary,growth: Dictionary,slots: Array) -> void:
	for slot_value in slots:
		var slot:=str(slot_value)
		var item: Dictionary=growth.get("equipment",{}) if slot=="equipment" else growth.get("crews",{}).get(slot,{})
		_section(body,str(SLOTS[slot]))
		var line:=HBoxContainer.new()
		line.add_theme_constant_override("separation",22)
		body.add_child(line)
		var icon:=TextureRect.new()
		var asset:="res://assets/items/equipment.png" if slot=="equipment" else "res://assets/items/crew-%s-v1.png" % slot
		if slot=="equipment" and not str(item.get("gear_type","")).is_empty():icon.texture=Art.texture(str(item.gear_type),true)
		elif ResourceLoader.exists(asset):icon.texture=load(asset)
		else:
			icon.texture=Design.icon_texture({"helmsman":"compass","gunnery":"ammo","damage_control":"repair","command":"fleet"}.get(slot,"gear"))
			icon.modulate=Design.ACCENT
		icon.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.custom_minimum_size=Vector2(115,115)
		line.add_child(icon)
		var info:=VBoxContainer.new()
		info.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		line.add_child(info)
		_text(info,str(item.get("name","未装配"))+("  ·  "+str(item.get("rarity_name","品级 %d" % int(item.get("quality",1)))) if not item.is_empty() else ""),23)
		if not item.is_empty():
			_text(info,"主词条  "+affix(item.get("main",{})),20,Design.MUTED)
			_text(info,"副词条  "+affix(item.get("sub",{})),20,Design.MUTED)
		else:_text(info,"可从物资副本与搜打撤获得。",20,Design.MUTED)
		var actions:=HBoxContainer.new()
		actions.add_theme_constant_override("separation",15)
		body.add_child(actions)
		_button(app,actions,"选择"+str(SLOTS[slot]),func():_picker(app,str(ship.id),slot),true).size_flags_horizontal=Control.SIZE_EXPAND_FILL
		if not item.is_empty():_button(app,actions,"卸下",func():_assign(app,str(ship.id),slot,"")).size_flags_horizontal=Control.SIZE_EXPAND_FILL
		if slot=="equipment" and not item.is_empty():_button(app,actions,"改装类型",func():_refit_picker(app,str(item.id))).size_flags_horizontal=Control.SIZE_EXPAND_FILL
	_text(body,"词条以当前物件为准，装卸后立即更新成长页。",19,Design.MUTED)

static func _picker(app,id: String,slot: String) -> void:
	var layer: Control=app.open_modal("选择"+str(SLOTS[slot]))
	var scroll:=ScrollContainer.new()
	app.place(scroll,layer,390,240,820,425)
	var column:=VBoxContainer.new()
	column.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation",14)
	scroll.add_child(column)
	var inventory: Array=app.economy.gear_inventory(id,slot)
	for value in inventory:
		var item: Dictionary=value
		var location:=str(item.get("location","warehouse"))
		var title:=str(item.get("name","物件"))+"\n"+affix(item.get("main",{}))+" / "+affix(item.get("sub",{}))
		var button:=_button(app,column,title,func():_assign(app,id,slot,str(item.id)))
		button.set_meta("gear_instance_id",str(item.id))
		button.custom_minimum_size.y=84
		button.add_theme_font_size_override("font_size",20)
		button.disabled=location!="warehouse" and location!=id
		if button.disabled:button.tooltip_text="已装配到其他舰娘"
	if inventory.is_empty():_text(column,"仓库暂无可装配物件。前往资源副本或打捞远征获取。",22,Design.MUTED)

static func _assign(app,id: String,slot: String,item: String) -> void:
	var response: Dictionary=app.economy.assign_item(id,slot,item)
	app.close_modal();app.show_page("ship_detail");app.notify(response)

static func _service(app,id: String,method: String) -> void:
	var response: Dictionary=app.economy.call(method,id)
	app.show_page("ship_detail");app.notify(response)

static func _train(app,id:String,tier:int) -> void:
	var response:Dictionary=app.economy.train_material(id,tier)
	app.show_page("ship_detail");app.notify(response)
static func _ascend(app,id:String) -> void:
	var response:Dictionary=app.economy.ascend_ship(id)
	app.show_page("ship_detail");app.notify(response)
static func _refit_picker(app,instance_id:String) -> void:
	var costs:Dictionary=app.economy.refit_cost()
	var layer:Control=app.open_modal("舰装改装 · %d银币 / 基础核心×%d"%[int(costs.credits),int(costs.core_t1)])
	var column:=VBoxContainer.new();column.add_theme_constant_override("separation",10)
	app.place(column,layer,390,229,820,460)
	for raw in app.economy.gear_types():
		var row:Dictionary=raw
		var type:=str(row.id)
		var line:=HBoxContainer.new();column.add_child(line)
		Art.icon(line,type,70,true)
		var button:=_button(app,line,str(row.name)+" · "+str(STATS.get(str(row.stat),str(row.stat))),func():
			var response:Dictionary=app.economy.refit_equipment(instance_id,type)
			app.close_modal();app.show_page("ship_detail");app.notify(response))
		button.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		button.add_theme_font_size_override("font_size",20)
	_text(column,"保留原品级，重新分配现有强化预算。每艘仅装1件舰装，总预算不超过1%。",18,Design.MUTED)
