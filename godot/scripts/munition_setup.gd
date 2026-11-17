@tool
extends Control
const Service=preload("res://scripts/cargo_service.gd")
const Design=preload("res://scripts/ui_design.gd")
const SHELL_NAMES=["均衡弹","穿甲弹","高爆弹"]
const TORP_NAMES=["标准鱼雷","疾行鱼雷","重型鱼雷"]
var app
var draft:Dictionary={}
static func open(owner)->void:
	var layer:Control=owner.open_modal("弹药与备雷")
	layer.tree_exited.connect(func():
		if not is_instance_valid(owner) or owner.screen!="formation":return
		var summary:Label=owner.page.find_child("SortieCargoSummary",true,false)
		if summary!=null:
			var budget:Dictionary=owner.economy.cargo_budget();var fleet:Dictionary=owner.economy.formation_preview()
			summary.text="货舱  %d 格 · %.1f 吨\n搜索  %d 秒\n弹药  %d 份"%[int(budget.cells),float(budget.max_kg)/1000.0,int(budget.search_seconds),int(fleet.ammo_required)])
	var view:Control=load("res://scenes/ui/munition_setup.tscn").instantiate()
	view.app=owner;layer.add_child(view);view.position=Vector2(370,222);view.build()
func build()->void:
	theme=Design.theme()
	var service:=Service.new(app.economy)
	draft=service.expedition_config(app.economy.roster()).munitions
	for ship in app.economy.cargo_budget().ships:
		var row:Control=load("res://scenes/ui/munition_row.tscn").instantiate();$Scroll/Ships.add_child(row)
		row.add_theme_stylebox_override("panel",Design.box(Color("e8f1f2"),3))
		row.get_node("Margin/Body/Name").text=str(ship.name)
		var id:String=str(ship.id);var config:Dictionary=draft[id]
		row.set_meta("ship_identity",id)
		var shell:OptionButton=row.get_node("Margin/Body/Choices/Shell")
		var torp:OptionButton=row.get_node("Margin/Body/Choices/Torpedo")
		var reserve:HSlider=row.get_node("Margin/Body/Choices/Reserve")
		for i in range(3):
			shell.add_icon_item(load("res://assets/items/expedition/shell_"+Service.SHELLS[i]+".svg"),SHELL_NAMES[i])
			torp.add_icon_item(load("res://assets/items/expedition/torpedo_"+Service.TORPEDOES[i]+".svg"),TORP_NAMES[i])
		shell.select(Service.SHELLS.find(str(config.shell)));torp.select(Service.TORPEDOES.find(str(config.torpedo)));reserve.value=int(config.reserve_reloads)
		for button in [shell,torp]:
			Design.apply_button(button);button.add_theme_font_size_override("font_size",17);button.add_theme_constant_override("icon_max_width",28)
			button.get_popup().add_theme_font_size_override("font_size",18)
			button.disabled=not app.economy.state.get("active_run",{}).is_empty()
		torp.disabled=torp.disabled or not bool(ship.has_torpedoes) or not bool(ship.torpedoes)
		reserve.editable=not torp.disabled
		reserve.tooltip_text="拖动调整备雷：0–2轮，每轮占2格"
		shell.item_selected.connect(func(i:int):draft[id].shell=Service.SHELLS[i];_hint(row,id,ship))
		torp.item_selected.connect(func(i:int):draft[id].torpedo=Service.TORPEDOES[i];_hint(row,id,ship))
		reserve.value_changed.connect(func(value:float):draft[id].reserve_reloads=int(value);_hint(row,id,ship))
		_hint(row,id,ship)
	Design.apply_button($Done,true);$Done.pressed.connect(_save)
	$Done.disabled=not app.economy.state.get("active_run",{}).is_empty()
	_capacity()
func _hint(row:Control,id:String,ship:Dictionary)->void:
	var config:Dictionary=draft[id]
	var text:String="穿甲：重甲伤害+35%，软体-20%" if config.shell=="ap" else "高爆：软体伤害+30%，重甲-35%" if config.shell=="he" else "均衡弹：适应混合目标"
	if not bool(ship.has_torpedoes):text+=" · 本舰无鱼雷"
	elif not bool(ship.torpedoes):text+=" · 已卸下鱼雷，备雷不占格"
	else:text+=" · "+("30秒装填" if config.torpedo=="heavy" else "20秒装填")+" · 备雷%d轮 / %d格"%[int(config.reserve_reloads),int(config.reserve_reloads)*2]
	row.get_node("Margin/Body/Hint").text=text
	_capacity()
func _capacity()->void:
	var budget:Dictionary=app.economy.cargo_budget();var cells:int=budget.cells
	var old:Dictionary=Service.new(app.economy).expedition_config(app.economy.roster()).munitions
	for ship in budget.ships:
		if bool(ship.has_torpedoes) and bool(ship.torpedoes):cells+=2*(int(old[str(ship.id)].reserve_reloads)-int(draft[str(ship.id)].reserve_reloads))
	$Capacity.text="载货预算 %d 格  ·  %d kg"%[cells,cells*55]
func _save()->void:
	var result:Dictionary=Service.new(app.economy).set_expedition_options({"munitions":draft})
	app.notify(result)
	if bool(result.get("ok",false)):app.close_modal()
