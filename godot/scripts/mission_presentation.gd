extends RefCounted
## Entry cards launch through the application's authoritative owned-fleet transaction.
const Design=preload("res://scripts/ui_design.gd")
const Supply=preload("res://scripts/supply_presentation.gd")

static func render(app,kind: String) -> void:
	var ladder:=kind=="ladder"
	var missions: Array=app.economy.mission_catalog(kind) if app.economy.has_method("mission_catalog") else []
	app.label(app.page,"每周抽卡补给 · 真实舰队挑战" if ladder else "选择本次需要的物资",60,120,1200,47,24,Design.INK)
	if not ladder:
		var tier:=int(app.get_meta("resource_tier",1))
		for i in range(3):
			var selected:=i+1
			var tab:Button=app.button(app.page,["基础海域","进阶海域 · Lv.3","深层海域 · Lv.6"][i],60+i*325,174,307,48,func():app.set_meta("resource_tier",selected);app.show_page("resources"))
			Supply.style_tab(tab,tier==selected)
		missions=missions.filter(func(row):return int(row.get("tier",1))==tier)
		missions.sort_custom(func(a,b):return ["silver","training","equipment","crew"].find(str(a.id).get_slice("-",0))<["silver","training","equipment","crew"].find(str(b.id).get_slice("-",0)))
	var scroll:=ScrollContainer.new()
	app.place(scroll,app.page,60,240 if not ladder else 215,1480,530)
	scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	var grid:=GridContainer.new()
	grid.columns=4
	grid.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation",20)
	grid.add_theme_constant_override("v_separation",20)
	scroll.add_child(grid)
	for value in missions:
		var row:Dictionary=value
		var card:=Control.new()
		card.custom_minimum_size=Vector2(350,450)
		card.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		grid.add_child(card)
		app.panel(card,0,0,1600,900,Color(1,1,1,0.86))
		var art:=str(row.get("art",""))
		if art.is_empty():art="res://assets/items/command.png" if str(row.id).contains("crew") else "res://assets/items/equipment.png" if str(row.id).contains("equipment") else "res://assets/items/alloy.png"
		if str(row.id).begins_with("training"):
			var material:="materials" if int(row.get("tier",1))==1 else "training_t%d"%int(row.tier)
			art="res://assets/growth/icons/%s.tres"%material
		if ladder:
			app.icon(card,"trophy",570,60,460,250,Design.ACCENT)
		else:app.picture(card,art,400,30,800,280)
		app.label(card,str(row.get("name","海上行动")),90,320,1420,95,28,Design.INK)
		app.label(card,"歼灭敌舰 · 可重复挑战" if ladder else "搜索物资 → 装载撤离"+("\n渊喉出没" if int(row.get("tier",1))==3 else "\n警戒海怪群" if int(row.get("tier",1))==2 else "\n近海补给航线"),95,435,1410,112,19,Design.MUTED)
		if ladder:app.label(card,"%d  对  %d" % [int(row.get("player_budget",0)),int(row.get("enemy_budget",0))],95,565,1410,70,24,Design.ACCENT)
		var rewards:Dictionary=row.get("rewards",{}).duplicate(true)
		if ladder and int(row.get("remaining",0))==0:rewards["origins"]=0
		if ladder:app.label(card,_reward_text(rewards),95,635,1410,112,19,Design.INK)
		else:
			var prize:=_prize(row)
			app.label(card,str(prize[0]),95,555,1410,55,21,Design.INK)
			app.label(card,str(prize[1]),95,615,1410,55,18,Design.MUTED)
			app.button(card,"查看掉落",90,682,1420,58,func():_details(app,row))
		var cost:=int(row.get("cost_stamina",0))
		var limit:=int(row.get("limit",0))
		var remaining:=int(row.get("remaining",limit))
		var caption:="体力 %d" % cost
		if limit>0:caption+="  /  本周奖励 %d/%d" % [remaining,limit]
		app.label(card,caption,95,755,1410,45,18,Design.MUTED)
		var unlocked:=bool(row.get("unlocked",true))
		var caption_start:="继续挑战" if ladder and remaining==0 else "出击"
		if not unlocked:caption_start="指挥官 Lv.%d 解锁"%int(row.get("player_level",1))
		var start:Button=app.button(card,caption_start,90,815,1420,70,func():app.launch_mission(kind,str(row.id)),true)
		start.disabled=not unlocked or int(app.economy.wallet().get("stamina",0))<cost or not app.economy.state.get("active_run",{}).is_empty()
		start.tooltip_text="选择自有舰队出航，结算后领取实际战利品。"
	if missions.is_empty():app.label(app.page,"暂无可出航任务",70,260,1200,60,25,Design.MUTED)
	app.button(app.page,"舰队编成",61,795,290,54,func():app.show_page("formation"))
	app.button(app.page,"打捞远征",1235,795,300,54,func():app.show_page("formation"),true)
	if not ladder:app.button(app.page,"指挥官档案 / 材料合成",565,795,450,54,func():app.show_page("player"))

static func _reward_text(rewards:Dictionary) -> String:
	var ordinary:=rewards.duplicate(true)
	var extra:PackedStringArray=[]
	var names:={"training_t2":"进阶记录","training_t3":"精研记录","core_t1":"锈蚀核心","core_t2":"精密核心","core_t3":"共鸣核心"}
	for key in names:
		if int(ordinary.get(key,0))>0:extra.append("%s ×%d"%[names[key],int(ordinary[key])]);ordinary.erase(key)
	var baseline:=Supply.rewards_text(ordinary)
	return baseline+("\n"+" · ".join(extra) if not extra.is_empty() else "")

static func _prize(row:Dictionary) -> Array:
	var id:=str(row.id);var tier:=int(row.get("tier",1));var reward:Dictionary=row.rewards
	if id.begins_with("silver"):return ["银币 ×%d"%int(reward.credits),"元词 ×%d"%int(reward.origins)]
	if id.begins_with("training"):
		var names:=["基础记录","进阶记录","精研记录"]
		var material:="materials" if tier==1 else "training_t%d"%tier
		return ["%s ×%d"%[names[tier-1],int(reward.get(material,0))],"%s核心 ×%d"%[["锈蚀","精密","共鸣"][tier-1],int(reward.get("core_t%d"%tier,0))]]
	return [("舰装" if id.begins_with("equipment") else "水手组")+" · 至少"+["制式","改良","精良"][tier-1],"五类舰装，可选择改装方向" if id.begins_with("equipment") else "四类岗位 · 主副词条"]
static func _details(app,row:Dictionary) -> void:
	var layer:Control=app.open_modal(str(row.name)+" · 行动详情")
	app.label(layer,"成功撤离且实际带回物资后结算。\n"+str(row.get("description","")),390,240,820,100,22,Design.INK)
	var scroll:=ScrollContainer.new();scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	app.place(scroll,layer,390,350,820,202)
	var rewards:=Label.new();rewards.text="固定奖励\n"+_reward_text(row.rewards)+"\n指挥官经验 ×%d"%int(row.get("commander_xp",60))
	rewards.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;rewards.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	rewards.add_theme_font_override("font",Design.font());rewards.add_theme_font_size_override("font_size",22);rewards.add_theme_color_override("font_color",Design.INK);scroll.add_child(rewards)
	app.label(layer,"出航消耗体力 %d · 失败无固定奖励"%int(row.cost_stamina),390,560,820,50,20,Design.MUTED)
	app.button(layer,"查看材料仓 / 养成解锁",390,635,820,55,func():app.close_modal();app.show_page("player"))
