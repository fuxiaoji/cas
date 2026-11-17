extends RefCounted
## Contextual island management. Every battle and recording is explicitly local NPC simulation.
const Design=preload("res://scripts/ui_design.gd")
const Art=preload("res://scripts/character_art.gd")
const Facility=preload("res://scripts/home_building_art.gd")
var app
var home
var screen:Control
var body:VBoxContainer
static func open(owner,section:String="islands")->void:
	var ui=load("res://scripts/home_conflict_ui.gd").new();ui.app=owner;ui.home=owner.home;ui._build(section)
static func unit(owner,id:String)->void:
	var ui=load("res://scripts/home_conflict_ui.gd").new();ui.app=owner;ui.home=owner.home;ui._unit(id)
func _shell(title:String)->void:
	screen=app.open_modal(title);screen.name="HomeConflictPanel";screen.set_meta("home_conflict_owner",self)
	var margin:=MarginContainer.new();app.place(margin,screen,365,218,865,425)
	var scroll:=ScrollContainer.new();scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;margin.add_child(scroll)
	body=VBoxContainer.new();body.size_flags_horizontal=Control.SIZE_EXPAND_FILL;body.add_theme_constant_override("separation",15);scroll.add_child(body)
func _label(parent:Node,value:String,size:int=22,color:Color=Design.INK)->Label:
	var result:=Label.new();result.text=value;result.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;result.add_theme_font_size_override("font_size",size);result.add_theme_color_override("font_color",color);parent.add_child(result);return result
func _button(parent:Node,title:String,action:Callable,primary:bool=false)->Button:
	var button:=Button.new();button.text=title;button.custom_minimum_size.y=80;Design.apply_button(button,primary);button.pressed.connect(action);parent.add_child(button);return button
func _cost(value:Dictionary)->String:
	var items:Array[String]=[]
	for key in value:items.append("%s %d"%[str(home.RESOURCE_NAMES.get(key,key)),int(value[key])])
	return " · ".join(items)
func _build(section:String)->void:
	_shell("返航灯岛 · 本地岛务")
	var tabs:=HBoxContainer.new();body.add_child(tabs)
	for row in [{"id":"islands","title":"人机海域"},{"id":"defenses","title":"岛屿布防"},{"id":"storage","title":"仓储与扩区"},{"id":"records","title":"攻防录像"}]:
		var key:String=str(row.id);var button:Button=_button(tabs,str(row.title),func():_build(key),key==section);button.name="HomeTab_"+key;button.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	var gallery:Button=_button(tabs,"作战图鉴",func():
		if ResourceLoader.exists("res://scripts/home_cg_gallery.gd"):load("res://scripts/home_cg_gallery.gd").open(app,"",func():_build(section))
		else:app.notify({"ok":false,"message":"作战图鉴准备中"}));gallery.name="HomeCGGallery";gallery.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	_label(body,"本地人机模拟 · 无联网玩家、无自动离线袭击",18,Design.MUTED)
	_button(body,"航空资料馆 · 七舰本人立绘与小人",func():load("res://scripts/home_carrier_archive.gd").open(app,func():_build(section))).name="HomeCarrierArchiveEntry"
	if section=="storage":_storage()
	elif section=="records":_records()
	elif section=="defenses":
		app.close_modal();load("res://scripts/home_defense_v2_ui.gd").open(app);return
	else:_islands()
	app.button(screen,"指挥训练",370,660,270,80,func():
		app.close_modal();var island:Node=app.page.find_child("HomeIsland",true,false)
		if island!=null:island._training_lessons()).name="HomeCommandTraining"
	app.button(screen,"返回海岛",655,660,570,80,func():app.close_modal(),true).name="CloseHomeConflict"
func _islands()->void:
	var rows:Array=home.latest_island().catalogue()
	if rows.is_empty():_label(body,"人机岛屿目录准备中，尚未产生费用。",22);return
	var grid:=GridContainer.new();grid.columns=2;grid.add_theme_constant_override("h_separation",14);grid.add_theme_constant_override("v_separation",14);body.add_child(grid)
	for island in rows:
		var id:String=str(island.get("id",island.get("npc_id","")))
		var card:=PanelContainer.new();card.custom_minimum_size=Vector2(408,180);card.size_flags_horizontal=Control.SIZE_EXPAND_FILL;card.add_theme_stylebox_override("panel",Design.panel_style());grid.add_child(card)
		var box:=VBoxContainer.new();box.add_theme_constant_override("separation",7);card.add_child(box)
		var heading:=HBoxContainer.new();box.add_child(heading)
		var art:=Facility.new();art.kind="depot" if str(island.get("archetype","")).contains("warehouse") else "hq";art.custom_minimum_size=Vector2(85,75);heading.add_child(art)
		var name:=VBoxContainer.new();name.size_flags_horizontal=Control.SIZE_EXPAND_FILL;heading.add_child(name);_label(name,str(island.get("name",id))+" · Lv%d"%int(island.get("level",1)),25);_label(name,"守舰%d · 驻地%d人 · 建议%d分"%[island.get("garrison",[]).size(),int(island.get("land_personnel",0)),int(island.get("recommended_points",0))],17,Design.MUTED)
		var action:Button=_button(box,"侦察并编队",func():_deploy(id,"raid"),true);action.name="InspectIsland_"+id
	var defense:Button=_button(body,"手动开启防御模拟 · 使用已保存驻防",func():_deploy(str(rows[0].get("id",rows[0].get("npc_id",""))),"defense"));defense.name="StartLocalDefense"
	defense.tooltip_text="会产生真实弹药、本人战损、设施损伤及公示的仓储损失；仅在确认出击后开始。"
	var exercise:Button=_button(body,"自家无损演习 · 自己的攻击队对自己的驻防",func():_deploy("","exercise"),true);exercise.name="StartOwnIslandExercise";exercise.tooltip_text="独立模拟，不扣弹药、不损整备、不损设施、不发奖励；原航次原样保留。"
func _deploy(id:String,mode:String)->void:
	app.set_meta("home_npc_id",id);app.set_meta("home_battle_mode",mode);app.close_modal()
	var island:Node=app.page.find_child("HomeIsland",true,false)
	if island!=null:island._sortie()
func _storage()->void:
	var profile:Dictionary=home.island_profile();var warehouse:Dictionary=home.storage_profile()
	_label(body,"岛屿等级 %d  ·  可建 %d 格"%[int(profile.level),int(profile.buildable_cells)],28)
	_label(body,"升级联络中枢开放更多建造区域。仓库等级提高安全保管量；只有超额部分的20%进入本地防御风险池。",19,Design.MUTED)
	for key in home.RESOURCE_NAMES:
		var line:=HBoxContainer.new();body.add_child(line)
		var icon:=TextureRect.new();icon.texture=Design.icon_texture(str({"scrap":"cargo","alloy":"gear","energy":"sun","protocols":"recruit","credits":"coin"}.get(key,"cargo")));icon.self_modulate=Design.INK;icon.custom_minimum_size=Vector2(38,38);icon.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;icon.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED;line.add_child(icon)
		var text:=VBoxContainer.new();text.size_flags_horizontal=Control.SIZE_EXPAND_FILL;line.add_child(text)
		_label(text,"%s  %d"%[str(home.RESOURCE_NAMES[key]),int(warehouse.resources.get(key,0))],23)
		_label(text,"保底保护 %d  ·  本次最多可掠 %d"%[int(warehouse.protected.get(key,0)),int(warehouse.exposed.get(key,0))],18,Design.MUTED)
	_label(body,"母港基地仓库与当前编队货舱继续独立；这里展示岛屿生产资源。未开启防御模拟不会扣除资源。",18,Design.MUTED)
func _records()->void:
	var records:Array=home.conflict_records()
	if records.is_empty():_label(body,"还没有本地岛屿战录像。完成一次突袭或手动防御后，记录会保留完整初始化、版本与真实指令。",23);return
	_label(body,"最近8场保留完整录像 · 回看不扣费、不结算奖励",18,Design.MUTED)
	for record in records:
		var id:String=str(record.run_id);var row:=HBoxContainer.new();body.add_child(row)
		var detail:=VBoxContainer.new();detail.size_flags_horizontal=Control.SIZE_EXPAND_FILL;row.add_child(detail)
		_label(detail,str(record.title)+(" · 成功" if bool(record.success) else " · 返航/失守"),23)
		_label(detail,Time.get_datetime_string_from_unix_time(int(record.at)).replace("T"," ")+"  ·  本地人机",17,Design.MUTED)
		if not record.resources.is_empty():_label(detail,"带回  "+_cost(record.resources),17)
		if not record.losses.is_empty():_label(detail,"仓储损失  "+_cost(record.losses),17)
		var watch:Button=_button(row,"观看录像",func():
			if app.has_method("open_home_replay"):app.open_home_replay(id)
			else:app.notify({"ok":false,"message":"录像播放器准备中，原始记录已保存"}),true);watch.name="HomeReplay_"+id;watch.disabled=not bool(record.replay_available)
func _unit(id:String)->void:
	var card:Dictionary=home.latest_unit(id);var stats:Dictionary=home.tactical_profile(id)
	_shell(str(card.get("codename",card.get("name",id)))+" · 战术档案")
	var heading:=HBoxContainer.new();body.add_child(heading)
	var portrait:=TextureRect.new();portrait.custom_minimum_size=Vector2(250,230);portrait.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;portrait.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED;portrait.texture=load("res://scripts/story_actor_layout.gd").portrait(Art.texture(str(card.get("portrait",""))),id);heading.add_child(portrait)
	var detail:=VBoxContainer.new();detail.size_flags_horizontal=Control.SIZE_EXPAND_FILL;heading.add_child(detail)
	_label(detail,str(card.get("designation","")),25);_label(detail,str(card.get("description","")),19,Design.MUTED)
	_label(detail,"Lv.%d / %d  ·  突破 %d"%[int(stats.level),int(stats.level_cap),int(stats.ascension)],27)
	var experience:=ProgressBar.new();experience.custom_minimum_size.y=22;experience.max_value=float(stats.xp_next);experience.value=float(stats.xp);experience.show_percentage=false;detail.add_child(experience)
	_label(detail,"整备 %.1f%%  ·  先遣编制 %d 人"%[float(stats.condition),int(stats.deployed_bodies)],22)
	_label(detail,"设定协议上限 %d；本次先遣身体独立损耗和补员。"%int(stats.protocol_body_cap),16,Design.MUTED)
	if stats.owned:
		var actions:=HBoxContainer.new();actions.add_theme_constant_override("separation",12);body.add_child(actions)
		_button(actions,"训练与突破",func():_train(id),true).name="TacticalTraining"
		_button(actions,"补充身体",func():_replenish(id)).name="TacticalReplenishment"
		_button(actions,"战术专精",func():_specialize(id)).name="TacticalSpecialization"
		if not home.latest_vehicle_profiles(id).is_empty():
			var vehicles:Array=home.latest_vehicle_profiles(id);var states:Array[String]=[]
			for vehicle in vehicles:states.append("%d连 %.0f%%"%[int(vehicle.company),float(vehicle.hp_percent)])
			_label(body,"作战载具："+" · ".join(states),20)
			var repair:Button=_button(body,"维修作战载具",func():_repair_vehicles(id));repair.name="TacticalVehicleRepair";repair.disabled=vehicles.all(func(vehicle):return float(vehicle.hp_percent)>=100)
	app.button(screen,"返回部队",370,660,855,80,func():app.close_modal();var island:Node=app.page.find_child("HomeIsland",true,false);if island!=null:island._units(),true)
	var native:Dictionary=home.latest_profile(id)
	if not native.is_empty():
		_label(body,"编制 %d连 × %d身体"%[int(native.get("company_count",0)),int(native.get("personnel_per_company",0))],24)
		_label(body,load("res://scripts/tactical_codex_v3.gd").summary(home,id),21)
		var ability:Dictionary=native.get("ability",{});var combat:Dictionary=native.get("combat",{})
		_label(body,"投送："+home.latest_transport_label(str(native.get("default_transport",""))),20)
		_label(body,home.latest_combat_label(id),20)
		_label(body,"技能："+str(ability.get("name",""))+" · "+str(ability.get("description","")),20,Design.MUTED)
		var numbers:=VBoxContainer.new();numbers.visible=false
		var toggle:Button=_button(body,"展开战术数据",func():numbers.visible=not numbers.visible);toggle.name="ExpandTacticalData";toggle.custom_minimum_size.y=56;body.add_child(numbers)
		var body_stats:Dictionary=native.get("body_stats",{})
		_label(numbers,"基础身体耐久 %.0f · %s"%[float(body_stats.get("hp",0)),str(load("res://scripts/tactical_codex_v3.gd").TARGETS.get(body_stats.get("armor_class",""),body_stats.get("armor_class","")))],19,Design.MUTED)
		_label(numbers,"身体移动 %.1f米/秒 · 射速与弹药按上方实际武器分组"%float(body_stats.get("speed",0)),19,Design.MUTED)
		_label(numbers,"个人护具承伤倍率 ×%.2f，数值越低承伤越少；身体仍按无装甲目标处理。"%float(body_stats.get("armor_multiplier",1)),18,Design.MUTED)
		_label(numbers,"当前为原创加速模式数值，速度不代表历史实测。",16,Design.MUTED)
		load("res://scripts/tactical_codex_v3.gd").add_details(home,id,numbers,_label)
		_label(numbers,"武器伤害按目标类别倍率和地形掩护裁决；身体类别并不等同旧版护甲数字。",16,Design.MUTED)
		_label(numbers,"技能 %d次  ·  冷却 %.0f秒  ·  范围 %.0f米"%[int(ability.get("charges",0)),float(ability.get("cooldown",0)),float(ability.get("radius",0))],19,Design.MUTED)
	if not stats.owned:_label(body,"尚未同步此人格",23);return
	_label(body,"等级仅在新版岛屿攻防生效，Lv30约+5%耐久/火力。自然每30分钟恢复1%整备，医疗站加速。",18,Design.MUTED)
func _slider(minimum:int,maximum:int,value:int,name:String)->HSlider:
	var slider:=HSlider.new();slider.name=name;slider.min_value=minimum;slider.max_value=maxi(minimum,maximum);slider.step=1;slider.value=value;slider.custom_minimum_size.y=60;body.add_child(slider);return slider
func _transaction(response:Dictionary,id:String)->void:
	app.notify(response)
	if response.get("ok",false):_unit(id)
func _replenish(id:String)->void:
	_shell("补员预览 · 确认后单次扣费")
	var stats:Dictionary=home.tactical_profile(id);_label(body,"当前整备 %.1f%%  ·  有限先遣编制 %d 人"%[float(stats.condition),int(stats.deployed_bodies)],25)
	var slider:HSlider=_slider(mini(100,int(floor(float(stats.condition)))+1),100,100,"ReplenishmentTarget")
	var status:Label=_label(body,"",23);var cost:Label=_label(body,"",21,Design.MUTED);var quote:Dictionary={}
	var confirm:Button=_button(body,"确认补员",func():_transaction(home.development().replenish(id,int(slider.value),"replenish-%s-%d"%[id,Time.get_ticks_usec()],quote.get("cost",{})),id),true);confirm.name="ConfirmTacticalReplenishment"
	var update:Callable=func():
		quote.merge(home.development().replenishment_preview(id,int(slider.value)),true);status.text="目标整备 %d%% · 恢复约 %.1f 人份整备"%[int(slider.value),float(quote.get("body_equivalent",0))];cost.text="费用："+_cost(quote.get("cost",{}));confirm.disabled=not quote.get("ready",false)
	slider.value_changed.connect(func(_value):update.call());update.call()
	_label(body,"不会扩充编制或产生额外储备身体；行动期间不能补员。取消不产生费用。",19,Design.MUTED)
	_button(body,"取消",func():_unit(id)).name="CancelTacticalReplenishment"
func _repair_vehicles(id:String)->void:
	_shell("作战载具维修 · 确认后扣费")
	var profiles:Array=home.latest_vehicle_profiles(id)
	var states:Array[String]=[];var lowest:float=100
	for vehicle in profiles:
		states.append("%d连 %s %.0f%%"%[int(vehicle.company),home.latest_transport_label(str(vehicle.kind)),float(vehicle.hp_percent)])
		lowest=minf(lowest,float(vehicle.hp_percent))
	_label(body," · ".join(states),23)
	var slider:HSlider=_slider(mini(100,int(floor(lowest))+1),100,100,"VehicleRepairTarget")
	var status:Label=_label(body,"",23);var cost:Label=_label(body,"",21,Design.MUTED);var quote:Dictionary={}
	var confirm:Button=_button(body,"确认维修载具",func():_transaction(home.development(true).repair_vehicles(id,int(slider.value),0,"vehicle-repair-%s-%d"%[id,Time.get_ticks_usec()],quote.get("cost",{})),id),true);confirm.name="ConfirmTacticalVehicleRepair"
	var update:Callable=func():
		quote.clear();quote.merge(home.development(true).vehicle_repair_preview(id,int(slider.value)),true)
		status.text="各连载具至少修至 %d%% · 不降低已有耐久"%int(slider.value)
		cost.text="费用："+_cost(quote.get("cost",{})) if quote.get("ok",false) else str(quote.get("message","维修价格准备中"))
		confirm.disabled=not quote.get("ready",false)
	slider.value_changed.connect(func(_value):update.call());update.call()
	_label(body,"载具与身体分别整备；未撤收载具须重新维修，0%时不能出击。取消不产生费用。",19,Design.MUTED)
	_button(body,"取消",func():_unit(id)).name="CancelTacticalVehicleRepair"
func _train(id:String)->void:
	_shell("战术训练 · 突破")
	var stats:Dictionary=home.tactical_profile(id);_label(body,"Lv.%d / %d · 经验 %d / %d"%[int(stats.level),int(stats.level_cap),int(stats.xp),int(stats.xp_next)],26)
	var slider:HSlider=_slider(1,10,1,"TacticalTrainingAmount");var cost:Label=_label(body,"",22)
	var train:Button=_button(body,"确认训练",func():_transaction(home.development().train(id,int(slider.value),"tactical-train-%d"%Time.get_ticks_usec()),id),true)
	var update:Callable=func():var quote:Dictionary=home.development().training_preview(id,int(slider.value));cost.text="%d份 · 经验+%d · %s"%[int(slider.value),int(quote.get("xp",0)),_cost(quote.get("cost",{}))];train.disabled=not quote.get("ready",false)
	slider.value_changed.connect(func(_v):update.call());update.call()
	var ascend:Dictionary=home.development().ascent_preview(id)
	if not ascend.get("maxed",false):
		_label(body,"突破至上限%d · 指挥官Lv%d · %s"%[int(ascend.next_cap),int(ascend.commander),_cost(ascend.cost)],19,Design.MUTED)
		var button:Button=_button(body,"确认突破",func():_transaction(home.development().ascend(id,"tactical-ascend-%d"%Time.get_ticks_usec()),id));button.disabled=not ascend.ready
	_button(body,"返回档案",func():_unit(id))
func _specialize(id:String)->void:
	_shell("战术专精 · Lv15开放")
	var stats:Dictionary=home.tactical_profile(id)
	_label(body,"专精只作用于新版岛屿行动，属于小幅功能取向；不改变历史舰表。",20,Design.MUTED)
	for key in stats.specializations:
		var kind:String=str(key);var quote:Dictionary=home.development().specialization_preview(id,kind)
		var button:Button=_button(body,str(stats.specializations[key])+(" · 当前" if str(stats.specialization)==kind else " · "+_cost(quote.cost)),func():_transaction(home.development().specialize(id,kind,"tactical-spec-%d"%Time.get_ticks_usec()),id),str(stats.specialization)==kind);button.disabled=not quote.ready
	_button(body,"返回档案",func():_unit(id))
