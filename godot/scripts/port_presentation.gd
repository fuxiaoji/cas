extends RefCounted
## Harbor presentation only. All ownership, costs and combat decisions stay in their existing services.

const PAPER := Color("182f46")
const GOLD := Color("b18539")
const MUTED := Color("5e7182")
const NAVY := Color("0b2636")
const LINE := Color("426574")
const Design = preload("res://scripts/ui_design.gd")
const Cinema = preload("res://scripts/cinematic_presentation.gd")
const FleetBook = preload("res://scripts/fleet_manager.gd")
const Art = preload("res://scripts/character_art.gd")

static func visual_roster(app) -> Array:
	var rows:Array=[]
	for row:Dictionary in app.economy.roster():rows.append(Art.visual_card(row,app.cards))
	return rows

static func _title(app, text: String, x: float, y: float, w: float, h: float, size := 38, color := PAPER) -> Label:
	var label: Label = app.label(app.page, text, x, y, w, h, mini(size,38), color)
	label.add_theme_font_override("font", Design.font(600))
	return label

static func _rule(app, x: float, y: float, w: float, gold := false) -> void:
	var line := ColorRect.new()
	line.color = GOLD if gold else Color(0.5, 0.68, 0.72, 0.28)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	app.place(line, app.page, x, y, w, 2)

static func _style(button: Button, selected := false, primary := false) -> void:
	Design.apply_button(button,primary)
	if selected:
		var selected_box: StyleBoxFlat = button.get_theme_stylebox("normal").duplicate()
		selected_box.border_color = Design.ACCENT
		selected_box.border_width_bottom = 4
		selected_box.bg_color = Color("e4f1f4")
		button.add_theme_stylebox_override("normal",selected_box)

static func app_style(color: Color, radius: int) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.set_corner_radius_all(radius)
	return box

static func _featured(app) -> Dictionary:
	var rows: Array=visual_roster(app)
	var wanted:=str(app.economy.state.get("harbor",{}).get("secretary",""))
	if wanted.is_empty() and app.economy.state.owned.has("IBS-U-USN-FLETCHER"): wanted="IBS-U-USN-FLETCHER"
	for row in rows:
		if str(row.id)==wanted: return row
	return rows[0] if not rows.is_empty() else {}

static func secretary_settings(app) -> void:
	var layer:Control=app.open_modal("秘书舰展示")
	var preview_scale:=float(app.economy.state.get("harbor",{}).get("scale",1.0))
	var slider:=HSlider.new()
	slider.min_value=.6; slider.max_value=1.5; slider.step=.05; slider.value=preview_scale
	app.place(slider,layer,500,238,600,37)
	app.label(layer,"立绘大小",375,228,140,50,22)
	var scale_label:Label=app.label(layer,"%d%%"%int(preview_scale*100),1120,228,120,50,22)
	var horizontal:=HSlider.new()
	horizontal.name="SecretaryHorizontal"
	horizontal.min_value=FleetBook.SECRETARY_HORIZONTAL_RANGE.x;horizontal.max_value=FleetBook.SECRETARY_HORIZONTAL_RANGE.y;horizontal.step=5
	horizontal.tooltip_text="向左 / 向右移动秘书舰；随时可重置位置"
	horizontal.value=float(app.economy.state.harbor.get("x",0))
	app.label(layer,"水平",375,284,100,40,20)
	app.place(horizontal,layer,470,291,310,30)
	var vertical:=HSlider.new()
	vertical.name="SecretaryVertical"
	vertical.min_value=FleetBook.SECRETARY_VERTICAL_RANGE.x;vertical.max_value=FleetBook.SECRETARY_VERTICAL_RANGE.y;vertical.step=5
	vertical.tooltip_text="向上 / 向下移动秘书舰；随时可重置位置"
	vertical.value=float(app.economy.state.harbor.get("y",0))
	app.label(layer,"垂直",810,284,100,40,20)
	app.place(vertical,layer,905,291,310,30)
	slider.value_changed.connect(func(value:float):
		scale_label.text="%d%%"%int(value*100)
		_secretary_preview(app,value,Vector2(horizontal.value,vertical.value)))
	horizontal.value_changed.connect(func(_value:float):_secretary_preview(app,slider.value,Vector2(horizontal.value,vertical.value)))
	vertical.value_changed.connect(func(_value:float):_secretary_preview(app,slider.value,Vector2(horizontal.value,vertical.value)))
	var scroll:=ScrollContainer.new()
	scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	app.place(scroll,layer,375,349,850,280)
	var grid:=GridContainer.new();grid.columns=4;grid.add_theme_constant_override("h_separation",14);grid.add_theme_constant_override("v_separation",12);scroll.add_child(grid)
	var selected_id:String=str(_featured(app).get("id",""))
	for row in visual_roster(app):
		var id:String=str(row.id)
		var button:Button=app.button(layer,"",0,0,1,1,func():
			app.notify(app.fleets.secretary(id,float(slider.value),Vector2(horizontal.value,vertical.value)));app.close_modal();app.show_page("harbor"))
		layer.remove_child(button);grid.add_child(button);button.custom_minimum_size=Vector2(200,280)
		button.name="Secretary_"+id
		button.tooltip_text="任命%s为秘书舰"%str(row.name)
		_style(button,id==selected_id)
		app.portrait(button,str(row.get("portrait","")),40,10,1520,700,.52)
		var name:Label=app.label(button,str(row.name),80,735,1440,100,22)
		name.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	app.button(layer,"重置位置",390,660,260,55,func():horizontal.value=0;vertical.value=0)
	app.button(layer,"保存展示",900,660,320,55,func():
		app.notify(app.fleets.secretary(selected_id,float(slider.value),Vector2(horizontal.value,vertical.value)));app.close_modal();app.show_page("harbor"),true)

static func _secretary_preview(app, scale_value:float, position:Vector2) -> void:
	var art:TextureRect=app.page.find_child("SecretaryPortrait",true,false)
	if art!=null: app.place_reposition(art,512-373*scale_value+position.x,818-735*scale_value+position.y,746*scale_value,735*scale_value)

static func _focused(app) -> Dictionary:
	var rows: Array = visual_roster(app)
	var wanted: String = str(app.get_meta("port_focus_id", ""))
	if wanted.is_empty() and not app.economy.formation.is_empty():
		wanted = str(app.economy.formation[0])
	for row in rows:
		if str(row.id) == wanted:
			return row
	return rows[0] if not rows.is_empty() else {}

static func _profile(app, row: Dictionary, formation_mode: bool) -> void:
	app.panel(app.page, 40, 118, 365, 627, Color(0.05, 0.16, 0.23, 0.82))
	if row.is_empty():
		_title(app, "等待新的同行者", 70, 260, 290, 120, 34)
		app.button(app.page, "前往征募", 70, 611, 300, 65, func(): app.show_page("recruit"), true)
		return
	var class_mark: Label = app.label(app.page, str(row.get("type", "")), 271, 135, 117, 95, 62, Color(0.7, 0.82, 0.84, 0.34))
	class_mark.autowrap_mode = TextServer.AUTOWRAP_OFF
	app.picture(app.page, str(row.get("portrait", "")), 50, 128, 345, 455)
	app.panel(app.page, 40, 484, 365, 261, Color(0.045, 0.14, 0.20, 0.96))
	app.label(app.page, "%s · Lv.%d" % [str(row.get("class", row.get("type", ""))), int(row.get("level", 1))], 67, 501, 310, 39, 22, MUTED)
	_title(app, str(row.get("name", "舰娘")), 65, 548, 315, 68, 39)
	app.label(app.page, "耐久 %d%%    计划弹药 %d" % [int(row.get("hp", 100)), int(row.get("ammo", 60))], 67, 618, 315, 36, 21, MUTED)
	var action: Button = app.button(app.page, "查看与整备", 67, 676, 310, 49, func(): app.ship_detail(row))
	_style(action)
	if not formation_mode:
		_rule(app, 65, 657, 312)

static func render_harbor(app) -> void:
	var scene=load("res://scenes/ui/harbor.tscn").instantiate()
	app.page.add_child(scene)
	scene.bind(app)

static func _toggle_formation(app, id: String) -> void:
	var ids: Array = app.economy.formation.duplicate()
	if ids.has(id):
		ids.erase(id)
	else:
		ids.append(id)
	var result: Dictionary = app.economy.set_formation(ids)
	app.set_meta("port_focus_id", id)
	app.show_page("formation")
	app.notify(result)

static func _relative(node: Control, parent: Control, left: float, top: float, right: float, bottom: float) -> void:
	parent.add_child(node)
	node.anchor_left = left
	node.anchor_top = top
	node.anchor_right = right
	node.anchor_bottom = bottom
	node.offset_left = 0
	node.offset_top = 0
	node.offset_right = 0
	node.offset_bottom = 0

static func _ship_card(app, row: Dictionary, width: float, height: float, editing: bool) -> Button:
	var id: String = str(row.id)
	var selected: bool = app.economy.formation.has(id)
	var card: Button = app.button(app.page,"",0,0,1,1,func():
		if editing: _toggle_formation(app,id)
		else: app.ship_detail(row))
	app.page.remove_child(card)
	card.custom_minimum_size=Vector2(width,height)
	_style(card,selected)
	var portrait: TextureRect = app.portrait(card,str(row.get("portrait","")),40,16,1520,690,0.54)
	portrait.clip_contents = true
	var name_label: Label = app.label(card,str(row.get("name","")),90,721,1400,87,28,PAPER)
	name_label.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
	name_label.autowrap_mode=TextServer.AUTOWRAP_OFF
	app.label(card,"%s  ·  Lv.%d" % [str(row.get("type","")),int(row.get("level",1))],90,820,1350,64,18,MUTED)
	if selected:
		var tag: Label = app.label(card,"✓",1240,26,280,100,24,Color("267c9e"))
		tag.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	card.tooltip_text="查看%s"%str(row.get("name","舰娘"))
	card.set_meta("search",str(row.get("name",""))+str(row.get("type","")))
	return card

static func render_roster(app) -> void:
	var rows: Array = visual_roster(app)
	app.label(app.page,"舰娘名册",57,119,700,49,27,PAPER)
	app.label(app.page,"已结识 %d 位"%rows.size(),1281,126,260,36,21,MUTED)
	var search := LineEdit.new()
	search.name="RosterSearch"
	search.placeholder_text="寻找舰娘"
	search.text=str(app.get_meta("search",""))
	app.place(search,app.page,59,184,442,49)
	app.button(app.page,"一键维修",550,184,280,49,func():app.bulk_service("repair"))
	app.button(app.page,"一键补给",850,184,280,49,func():app.bulk_service("ammo"))
	app.button(app.page,"一键整备",1150,184,390,49,func():app.bulk_service("both"),true)
	var scroll := ScrollContainer.new()
	scroll.name="RosterScroll"
	scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	app.place(scroll,app.page,58,257,1484,550)
	var grid := GridContainer.new()
	grid.columns=5
	grid.add_theme_constant_override("h_separation",18)
	grid.add_theme_constant_override("v_separation",22)
	scroll.add_child(grid)
	for row in rows:
		var card:Button=_ship_card(app,row,277,350,false)
		card.name="RosterShip_"+str(row.id)
		grid.add_child(card)
		card.visible=search.text.strip_edges().is_empty() or str(card.get_meta("search","")).to_lower().contains(search.text.to_lower())
	search.text_changed.connect(func(value:String):
		app.set_meta("search",value)
		for card in grid.get_children(): card.visible=value.strip_edges().is_empty() or str(card.get_meta("search","")).to_lower().contains(value.to_lower()))
	if rows.is_empty():
		app.label(app.page,"新的同行者，正在海的另一边等你。",60,350,1200,70,29,MUTED)
		app.button(app.page,"前往征募",60,460,330,65,func():app.show_page("recruit"),true)

static func _pick_slot(app, _slot: int=0) -> void:
	var layer:Control=app.open_modal("编队成员 · 点选加入或移出")
	var scroll:=ScrollContainer.new();scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	app.place(scroll,layer,372,228,852,415)
	var grid:=GridContainer.new();grid.columns=4;grid.add_theme_constant_override("h_separation",13);grid.add_theme_constant_override("v_separation",16);scroll.add_child(grid)
	var members:Array=app.fleets.active().get("ships",[])
	for row in visual_roster(app):
		var id:String=str(row.id)
		var selected:bool=members.has(id)
		var b:Button=app.button(layer,"",0,0,1,1,func():
			var result:Dictionary=app.fleets.toggle_member(id)
			app.close_modal();app.show_page("formation");_pick_slot(app);app.notify(result))
		layer.remove_child(b);grid.add_child(b);b.custom_minimum_size=Vector2(200,275);_style(b,selected)
		b.name="FleetMember_"+id
		b.tooltip_text=("移出 " if selected else "编入 ")+str(row.name)
		app.portrait(b,str(row.get("portrait","")),40,10,1520,710,.54)
		app.label(b,("✓ " if selected else "")+str(row.name),80,735,1440,100,22)
	app.button(layer,"完成编队",900,668,320,52,func():app.close_modal();app.show_page("formation"),true)

static func _fleet_name(app, creating:bool) -> void:
	var layer:Control=app.open_modal("新建编队" if creating else "舰队名称")
	var field:=LineEdit.new();field.placeholder_text="舰队名称";field.max_length=32
	field.text="" if creating else str(app.fleets.active().get("name",""))
	app.place(field,layer,390,285,800,65)
	app.label(layer,"每个编队可自由添加已拥有舰娘，出航时可勾选多个编队。",390,385,800,90,22,MUTED)
	app.button(layer,"保存",840,595,350,65,func():
		var result:Dictionary=app.fleets.create(field.text) if creating else app.fleets.rename(str(app.fleets.active().id),field.text)
		app.close_modal();app.show_page("formation");app.notify(result),true)

static func render_formation(app) -> void:
	var current:Dictionary=app.fleets.active()
	app.label(app.page,"保存的舰队",48,116,250,50,26)
	app.button(app.page,"＋ 新建",48,175,245,50,func():_fleet_name(app,true))
	var fleet_scroll:=ScrollContainer.new();fleet_scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	app.place(fleet_scroll,app.page,48,246,245,490)
	var fleet_list:=VBoxContainer.new();fleet_list.size_flags_horizontal=Control.SIZE_EXPAND_FILL;fleet_list.add_theme_constant_override("separation",12);fleet_scroll.add_child(fleet_list)
	for row in app.fleets.rows():
		var id:String=str(row.id)
		var item:=VBoxContainer.new();fleet_list.add_child(item)
		var b:Button=app.button(app.page,str(row.name),0,0,1,1,func():app.fleets.activate(id);app.show_page("formation"))
		app.page.remove_child(b);item.add_child(b);b.custom_minimum_size=Vector2(225,52);_style(b,str(current.get("id",""))==id)
		var check:=CheckBox.new();check.text="随队出航 · %d 艘"%row.ships.size();check.button_pressed=app.fleets.selected(id);check.disabled=row.ships.is_empty()
		check.toggled.connect(func(on:bool):var result:Dictionary=app.fleets.select(id,on);app.show_page("formation");app.notify(result))
		item.add_child(check)
	app.label(app.page,str(current.get("name","舰队")),332,116,530,48,28)
	app.button(app.page,"改名",904,118,86,43,func():_fleet_name(app,false))
	app.button(app.page,"移除",1000,118,86,43,func():app.confirm_action("移除此编队？舰娘会保留在舰库。",func():app.notify(app.fleets.erase(str(current.id)));app.show_page("formation")))
	app.label(app.page,"%d 艘已编入"%current.get("ships",[]).size(),334,177,470,40,21,MUTED)
	var members:Button=app.button(app.page,"＋ 管理成员",850,177,238,46,func():_pick_slot(app))
	members.name="AddFleetMember"
	var scroll:=ScrollContainer.new();scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	app.place(scroll,app.page,332,246,756,512)
	var grid:=GridContainer.new();grid.columns=3;grid.add_theme_constant_override("h_separation",15);grid.add_theme_constant_override("v_separation",18);scroll.add_child(grid)
	var roster:Dictionary={}
	for row in visual_roster(app):roster[str(row.id)]=row
	var index:=0
	for identity in current.get("ships",[]):
		var id:String=str(identity);var row:Dictionary=roster.get(id,{})
		var card:Button=app.button(app.page,"",0,0,1,1,func():app.ship_detail(row));app.page.remove_child(card);grid.add_child(card)
		card.name="FleetSlot%d"%index;index+=1;card.custom_minimum_size=Vector2(235,350);_style(card)
		app.portrait(card,str(row.get("portrait","")),20,10,1560,690,.55)
		app.label(card,str(row.get("name","")),90,720,1400,100,24)
		app.label(card,str(row.get("type","")),90,825,1400,55,19,MUTED)
	var add:Button=app.button(app.page,"＋ 添加舰娘",0,0,1,1,func():_pick_slot(app));app.page.remove_child(add);grid.add_child(add);add.custom_minimum_size=Vector2(235,140)
	add.name="MoreFleetMembers"
	app.panel(app.page,1121,246,421,514)
	app.label(app.page,"本次出航",1152,269,355,52,28)
	var groups:Array=app.fleets.groups()
	app.label(app.page,"%d 个编队 · %d 艘舰娘"%[groups.size(),app.economy.formation.size()],1152,330,355,50,22)
	var preview:Dictionary=app.economy.formation_preview()
	var budget:Dictionary=app.economy.cargo_budget()
	var summary:Label=app.label(app.page,"货舱  %d 格 · %.1f 吨\n搜索  %d 秒\n弹药  %d 份"%[int(budget.cells),float(budget.max_kg)/1000.0,int(budget.search_seconds),int(preview.ammo_required)],1152,397,350,145,23,MUTED)
	summary.name="SortieCargoSummary"
	var loadout:Button=app.button(app.page,"装载与货舱",1152,558,355,52,func():load("res://scripts/cargo_presentation.gd").open_loadout(app))
	loadout.name="SortieLoadout"
	var munitions:Button=app.button(app.page,"弹种与备雷",1152,617,355,48,func():load("res://scripts/munition_setup.gd").open(app))
	munitions.name="SortieMunitions"
	var launch:Button=app.button(app.page,"确认出航",1152,684,355,70,func():app.launch(false),true)
	launch.disabled=groups.is_empty() or app.economy.formation.is_empty()
	app.button(app.page,"基础打捞 · 借用舰",1141,778,392,46,func():app.launch(true))

static func _chart(app, region: String) -> Control:
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/campaign-chart.json"))
	var chart: Dictionary = raw.get("charts", {}).get(region, raw.get("charts", {}).get("overview", {})) if raw is Dictionary else {}
	var frame := Control.new()
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	app.place(frame, app.page, 45, 193, 1009, 547)
	var image_key := "war-chart:" + region
	if not app.texture_cache.has(image_key) and not chart.is_empty():
		var grid := ""
		for x in range(0, 961, 96):
			grid += '<path d="M%d 0V540"/>' % x
		for y in range(0, 541, 90):
			grid += '<path d="M0 %dH960"/>' % y
		var svg := '<svg xmlns="http://www.w3.org/2000/svg" width="1008" height="567" viewBox="0 0 960 540"><rect width="960" height="540" fill="#96d7d9"/><g stroke="#b4e6e3" stroke-width="0.65" fill="none">%s</g><path d="%s" fill="#739e7c" fill-rule="evenodd" stroke="#edf0d0" stroke-width="1"/></svg>' % [grid, str(chart.get("coast", ""))]
		var image := Image.new()
		if image.load_svg_from_string(svg) == OK:
			app.texture_cache[image_key] = ImageTexture.create_from_image(image)
	var picture := TextureRect.new()
	picture.texture = app.texture_cache.get(image_key)
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_SCALE
	picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_relative(picture, frame, 0, 0, 1, 1)
	var bounds: Array = chart.get("bounds", [-24, 180, -57, 73])
	for place in chart.get("labels", []):
		var x: float = (float(place[1]) - float(bounds[0])) / (float(bounds[1]) - float(bounds[0]))
		var y: float = (float(bounds[3]) - float(place[2])) / (float(bounds[3]) - float(bounds[2]))
		app.label(frame, str(place[0]), x * 1600 - 90, y * 900 - 20, 250, 50, 20, PAPER)
	app.label(frame, "海岸线 Natural Earth", 23, 823, 1400, 57, 18, MUTED)
	var lng := 159.83
	var lat := -9.23
	if region == "north":
		lng = 154.73
		lat = -6.26
	elif region == "central":
		lng = 157.1
		lat = -7.79
	var px: float = (lng - float(bounds[0])) / (float(bounds[1]) - float(bounds[0]))
	var py: float = (float(bounds[3]) - lat) / (float(bounds[3]) - float(bounds[2]))
	if px >= 0 and px <= 1 and py >= 0 and py <= 1:
		var pin := Label.new()
		pin.text = "◇"
		pin.add_theme_font_size_override("font_size", 72)
		pin.add_theme_color_override("font_color", GOLD)
		pin.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_relative(pin, frame, px - 0.037, py - 0.068, px + 0.060, py + 0.10)
		app.label(frame, "所罗门战区" if region == "overview" else str(chart.get("label", "")), px * 1600 - 350, py * 900 - 25, 325, 55, 22, GOLD)
	return frame

static func _campaign_launch(app, row: Dictionary) -> void:
	if not app.economy.state.get("active_run", {}).is_empty():
		app.notify({"ok": false, "message": "请先继续或结束当前海上航次。"})
		return
	if not row.get("playable", false):
		app.notify({"ok": false, "message": "该战役仍在核验，暂不可出航。"})
		return
	var stage := ""
	var side := str(app.get_meta("campaign_side", "allies"))
	var difficulty := str(app.get_meta("campaign_difficulty", "standard"))
	for id in row.get("stage_ids", []):
		if str(id).begins_with("CAMP-" + side.to_upper() + "-"):
			stage = str(id)
	if stage.is_empty():
		app.notify({"ok": false, "message": "该战役缺少可用的本席编队。"})
		return
	if difficulty == "story":
		load("res://scripts/campaign_deployment.gd").open(app, row)
		return
	app.start_local_mode({"op": "new_campaign", "id": stage, "difficulty": difficulty, "seed": 6106, "profile": app.progression.selected_profile()}, {"mode": "campaign", "id": stage, "difficulty": difficulty, "title": str(row.get("ibs_title", stage)), "side": side})

static func render_campaign(app) -> void:
	var response: Dictionary = app.core.request({"op": "campaign"})
	var rows: Array = response.get("data", {}).get("scenarios", []) if response.get("ok", false) else []
	var selected_id: String = str(app.get_meta("campaign_focus_id", "IBS-S-01"))
	var selected: Dictionary = rows[0] if not rows.is_empty() else {}
	for row in rows:
		if str(row.get("ibs_id", "")) == selected_id:
			selected = row
	var region: String = str(app.get_meta("campaign_region", "overview"))
	var regions := ["overview", "iron", "central", "north"]
	var titles := ["战区总览", "铁底湾", "中所罗门", "北所罗门"]
	for i in range(regions.size()):
		var key: String = regions[i]
		var tab: Button = app.button(app.page, titles[i], 45 + i * 253, 121, 243, 56, func(): app.set_meta("campaign_region", key); app.show_page("campaign"))
		_style(tab, region == key)
	_chart(app, region)
	app.panel(app.page, 1081, 120, 474, 624, Color(0.97, 0.97, 0.93, 0.98))
	_title(app, "历史战役", 1105, 132, 421, 51, 32)
	app.label(app.page, "%d 份战役档案" % rows.size(), 1108, 189, 419, 33, 20, MUTED)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	app.place(scroll, app.page, 1100, 231, 437, 228)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 4)
	scroll.add_child(list)
	for row in rows:
		var entry: Dictionary = row
		var title: String = str(entry.get("ibs_title", "战役"))
		var item: Button = app.button(app.page, title + "\n" + str(entry.get("ibs_date", "")), 0, 0, 1, 1, func(): app.set_meta("campaign_focus_id", str(entry.get("ibs_id", ""))); app.show_page("campaign"))
		app.page.remove_child(item)
		list.add_child(item)
		item.custom_minimum_size = Vector2(415, 75)
		item.alignment = HORIZONTAL_ALIGNMENT_LEFT
		item.add_theme_font_size_override("font_size", 22)
		_style(item, str(entry.get("ibs_id", "")) == str(selected.get("ibs_id", "")))
	_rule(app, 1105, 476, 425)
	_title(app, str(selected.get("ibs_title", "档案暂未载入")), 1106, 492, 422, 51, 28)
	var side_menu := OptionButton.new()
	for name in ["同盟战线", "轴心战线"]: side_menu.add_item(name)
	side_menu.selected = 1 if str(app.get_meta("campaign_side", "allies")) == "axis" else 0
	app.place(side_menu, app.page, 1106, 551, 199, 43)
	side_menu.item_selected.connect(func(index: int): app.set_meta("campaign_side", "axis" if index==1 else "allies"))
	var difficulty_menu := OptionButton.new()
	for name in ["故事", "标准", "挑战"]: difficulty_menu.add_item(name)
	difficulty_menu.selected = ["story", "standard", "challenge"].find(str(app.get_meta("campaign_difficulty", "standard")))
	app.place(difficulty_menu, app.page, 1323, 551, 205, 43)
	difficulty_menu.item_selected.connect(func(index: int): app.set_meta("campaign_difficulty", ["story", "standard", "challenge"][index]))
	var brief: Button = app.button(app.page, "作战简报", 1106, 608, 423, 33, func(): _campaign_brief(app, selected))
	brief.add_theme_font_size_override("font_size", 20)
	_style(brief)
	var launch: Button = app.button(app.page, "出航", 1105, 652, 426, 63, func(): _campaign_launch(app, selected), true)
	_style(launch, false, true)
	launch.disabled = not bool(selected.get("playable", false))


static func _campaign_brief(app, row: Dictionary) -> void:
	var layer: Control = app.open_modal(str(row.get("ibs_title", "作战简报")))
	var text := "日期：%s\n\n%s\n\n使用独立的历史编队，不扣个人舰队弹药，不发放港口经济奖励。" % [str(row.get("ibs_date", "")), str(row.get("note", "按原核配置、环境与双方目标进行本地指挥。"))]
	app.label(layer, text, 393, 245, 802, 333, 25, PAPER)
	app.label(layer, "本地试玩中的资料与未实现机制仍以项目核验记录为准。", 394, 606, 790, 55, 20, MUTED)
