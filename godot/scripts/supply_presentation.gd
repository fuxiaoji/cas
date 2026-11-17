extends RefCounted
## Store views read the account catalogue; transactions remain in the account service.
const Design = preload("res://scripts/ui_design.gd")
const Cinema = preload("res://scripts/cinematic_presentation.gd")
const CURRENCIES := {"credits":"银币", "origins":"元词", "tickets":"常驻券", "up_tickets":"UP券", "medals":"勋章", "stamina":"体力", "materials":"基础航海记录", "ammo_stock":"弹药", "training_t2":"进阶航海记录", "training_t3":"精研航海记录", "core_t1":"锈蚀突破核心", "core_t2":"精密突破核心", "core_t3":"共鸣突破核心", "commander_xp":"指挥官经验"}
const CATEGORIES := ["ships", "supply", "bundles", "exchange", "tactics", "simulation"]
const CATEGORY_NAMES := ["舰娘", "补给", "礼包", "兑换", "舰队战术", "模拟充值"]

static func render(app) -> void:
	var selected := str(app.get_meta("supply_category", "supply"))
	for i in range(CATEGORIES.size()):
		var key: String = CATEGORIES[i]
		var tab: Button = app.button(app.page, CATEGORY_NAMES[i], 50+i*249, 125, 231, 54, func():app.set_meta("supply_category",key);app.show_page("shop"))
		style_tab(tab, selected == key)
	if selected == "simulation":
		var scene=load("res://scenes/ui/simulated_recharge.tscn").instantiate()
		app.page.add_child(scene)
		scene.bind(app)
		return
	if selected == "tactics":
		tactics(app)
		return
	var catalogue: Array = app.economy.supply_catalog() if app.economy.has_method("supply_catalog") else []
	var scroll := ScrollContainer.new()
	app.place(scroll, app.page, 50, 212, 1495, 580)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var grid := GridContainer.new()
	grid.columns = 3
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 18)
	grid.add_theme_constant_override("v_separation", 18)
	scroll.add_child(grid)
	for entry in catalogue:
		var row: Dictionary = entry
		if str(row.get("category", "supply")) != selected: continue
		product(app, grid, row)
	if grid.get_child_count() == 0:
		app.label(app.page, "暂无可采购物资", 65, 265, 900, 60, 24, Design.MUTED)
	var hint := "直接邀请舰娘入港" if selected == "ships" else "元词可兑换征募券与养成物资" if selected == "exchange" else "交易成功后物资自动入库"
	app.label(app.page, hint, 60, 805, 760, 37, 20, Design.MUTED)
	if selected=="exchange":
		var obtain:Button=app.button(app.page,"获取元词",860,800,250,48,func():origins_sources(app))
		Design.apply_button(obtain,false,true)
	var store: Button = app.button(app.page, "物资仓库", 1250, 800, 285, 48, func():app.show_page("warehouse"))
	Design.apply_button(store, false, true)

static func origins_sources(app) -> void:
	var layer:Control=app.open_modal("元词补给")
	app.label(layer,"完成作战，带回新的补给。",390,233,800,58,26,Design.INK)
	app.button(layer,"物资海域",390,330,380,65,func():app.close_modal();app.show_page("resources"),true)
	app.button(layer,"每周天梯",810,330,380,65,func():app.close_modal();app.show_page("ladder"),true)
	app.label(layer,"战役与剧情的资源奖励，会随实际通关到账。",390,428,800,88,22,Design.MUTED)
	var pvp:Button=app.button(layer,"多人奖励 · 未开放",390,560,380,62,func():pass)
	pvp.disabled=true
	app.button(layer,"模拟充值 · 不扣真钱",810,560,380,62,func():app.close_modal();app.set_meta("supply_category","simulation");app.show_page("shop"))

static func style_tab(button: Button, selected: bool) -> void:
	Design.apply_button(button, false, true)
	button.add_theme_font_override("font", Design.font(600 if selected else 400))
	var style := Design.box(Color(1,1,1,0), 0)
	style.border_width_bottom = 3 if selected else 0
	style.border_color = Design.ACCENT
	button.add_theme_stylebox_override("normal", style)

static func currency_name(key: String) -> String:
	if key=="standard_tickets":return "常驻券"
	return str(CURRENCIES.get(key, key))

static func rewards_text(rewards: Dictionary) -> String:
	var parts: PackedStringArray = []
	for key in rewards:
		if rewards[key] is int or rewards[key] is float:
			if int(rewards[key]) > 0: parts.append("%s ×%d" % [currency_name(str(key)), int(rewards[key])])
	return "  /  ".join(parts)

static func item_art(app, parent: Control, row: Dictionary, rect: Rect2) -> void:
	var identities: Array=row.get("ship_ids",[])
	if identities.size()>1:
		for i in range(mini(identities.size(),3)):
			var ship:Dictionary=app.cards.get(str(identities[i]),{})
			var portrait_path:=str(ship.get("portrait",""))
			if not ResourceLoader.exists(portrait_path):continue
			var portrait:=TextureRect.new()
			portrait.texture=Design.crop(load(portrait_path),0.62)
			portrait.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
			portrait.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			portrait.mouse_filter=Control.MOUSE_FILTER_IGNORE
			app.place(portrait,parent,rect.position.x+i*rect.size.x*0.23,rect.position.y,rect.size.x*0.55,rect.size.y)
		return
	var asset := str(row.get("art", row.get("image", "")))
	var identity := str(row.get("ship_id", ""))
	if not identity.is_empty():
		var card: Dictionary = app.cards.get(identity, {})
		asset = str(card.get("portrait", ""))
	if asset.is_empty():
		var id := str(row.get("id", ""))
		if id.contains("ammo"):
			asset = "res://assets/items/ammo-crate-v1.png" if ResourceLoader.exists("res://assets/items/ammo-crate-v1.png") else ""
		elif id.contains("crew") or id.contains("command"): asset = "res://assets/items/command.png"
		elif id.contains("equipment") or id.contains("gear"): asset = "res://assets/items/equipment.png"
		elif id.contains("material"): asset = "res://assets/items/alloy.png"
	if not asset.is_empty() and ResourceLoader.exists(asset):
		app.picture(parent, asset, rect.position.x, rect.position.y, rect.size.x, rect.size.y)
	else:
		var key := "ammo" if str(row.get("id", "")).contains("ammo") else "ticket" if str(row.get("id", "")).contains("ticket") else "supply" if str(row.get("category", "")) == "bundles" else "recruit" if str(row.get("currency", "")) == "origins" else "cargo"
		app.icon(parent, key, rect.position.x+rect.size.x*0.27, rect.position.y+rect.size.y*0.2, rect.size.x*0.46, rect.size.y*0.6, Design.ACCENT)

static func product(app, grid: GridContainer, row: Dictionary) -> void:
	var card := Control.new()
	card.custom_minimum_size = Vector2(475, 268)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_child(card)
	app.panel(card, 0, 0, 1600, 900, Color(1,1,1,0.82))
	item_art(app, card, row, Rect2(40,65,535,620))
	app.label(card, str(row.get("name", "物资")), 630, 75, 910, 150, 25, Design.INK).add_theme_font_override("font",Design.font(600))
	var description := str(row.get("description", ""))
	var identity:=str(row.get("ship_id",""))
	if not identity.is_empty():
		var ship:Dictionary=app.cards.get(identity,{})
		description=str(ship.get("class",ship.get("type","")))
	elif row.get("ship_ids",[]).size()>1:
		var names:PackedStringArray=[]
		for ship_id in row.ship_ids:names.append(str(app.cards.get(str(ship_id),{}).get("name",ship_id)))
		description="\n".join(names)
	app.label(card, description, 635, 285, 875, 275, 19, Design.MUTED)
	var price := int(row.get("cost", 0))
	var currency := str(row.get("currency", "credits"))
	app.label(card, "%d %s" % [price, currency_name(currency)], 635, 590, 900, 105, 22, Design.INK)
	var owned: bool = row.get("owned", false)
	var remaining := int(row.get("limit_remaining", row.get("remaining", -1)))
	var buy: Button = app.button(card, "已入港" if owned else "已领取" if remaining == 0 else "采购", 630, 735, 880, 120, func():
		var response: Dictionary = app.economy.purchase(str(row.id))
		app.show_page("shop");app.notify(response), true)
	buy.set_meta("product_id",str(row.id))
	buy.disabled = owned or remaining == 0 or int(app.economy.wallet().get(currency, 0)) < price or not app.economy.state.get("active_run", {}).is_empty()
	var shortfall:=maxi(0,price-int(app.economy.wallet().get(currency,0)))
	buy.tooltip_text = "航次进行中，返港后可采购" if not app.economy.state.get("active_run", {}).is_empty() else "还差%d%s" % [shortfall,currency_name(currency)] if shortfall>0 else description

static func tactics(app) -> void:
	var scroll := ScrollContainer.new()
	app.place(scroll, app.page, 60, 210, 1480, 570)
	scroll.name="TacticalAIInventory"
	scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	var grid:=GridContainer.new()
	grid.columns=3;grid.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation",18);grid.add_theme_constant_override("v_separation",18)
	scroll.add_child(grid)
	for entry in app.progression.ai_options():
		var row: Dictionary = entry
		var identity:Dictionary=preload("res://scripts/ai_character_art.gd").lookup(str(row.id))
		var card:Control=load("res://scenes/ui/tactical_ai_card.tscn").instantiate()
		card.name="AI_"+str(row.id).replace("-","_");grid.add_child(card)
		var body:Control=card.get_node("Body")
		body.get_node("Name").text=str(identity.get("name",row.name))
		body.get_node("Doctrine").text=str(row.name)+(" · 当前预设" if app.progression.selected_profile()==str(row.id) else "")
		var path:=str(identity.get("portrait",""))
		if ResourceLoader.exists(path):body.get_node("Portrait").texture=Design.crop(load(path),0.70)
		card.set_meta("profile_id",str(row.id));card.set_meta("character_id",str(identity.get("id","")))
		var stage:=str(row.get("stage",""))
		var unlocked:bool=stage.is_empty() or int(app.progression.data().campaign.get(stage,{}).get("stars",0))>0
		var cost := "已拥有" if row.owned else "%d 常驻券" % int(row.cost) if row.has("cost") else "6 舰队勋章" if row.id == "gunnery" else "挑战解锁"
		body.get_node("Price").text=cost
		body.get_node("Status").text="已拥有" if row.owned else "首次通过挑战解锁" if row.id=="torpedo" else "通关「%s」解锁"%str(row.get("stageName",stage)) if not unlocked else "可获取"
		var action:Button=body.get_node("Action")
		action.text="当前预设" if app.progression.selected_profile()==str(row.id) else "设为预设" if row.owned else "未解锁" if not unlocked else "挑战解锁" if row.id=="torpedo" else "获取战术"
		var active:bool=not app.economy.state.get("active_run",{}).is_empty()
		var affordable:bool=int(app.economy.wallet().get("medals",0))>=6 if row.id=="gunnery" else int(app.economy.wallet().get("tickets",0))>=int(row.get("cost",0))
		action.disabled=active or (not row.owned and (not unlocked or not affordable or row.id=="torpedo"))
		action.set_meta("ai_profile",str(row.id))
		action.pressed.connect(func():
			var response: Dictionary = app.progression.set_profile(str(row.id)) if row.owned else app.progression.buy_profile(str(row.id))
			app.show_page("shop");app.notify(response))
		card.tooltip_text=str(row.get("description","均衡协同指挥"))+ ("\n返港后可调整战术" if active else "")
