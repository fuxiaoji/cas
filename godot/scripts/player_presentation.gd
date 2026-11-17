extends RefCounted
## Compact commander record and six illustrated material bins.
const Design=preload("res://scripts/ui_design.gd")
const Detail=preload("res://scripts/ship_detail_presentation.gd")
const Art=preload("res://scripts/growth_art.gd")
static func render(app) -> void:
	var profile:Dictionary=app.economy.player_profile()
	app.label(app.page,"航海履历",64,130,760,68,36,Design.INK)
	app.label(app.page,"Lv.%d"%int(profile.level),65,217,470,85,60,Design.ACCENT)
	var bar:=ProgressBar.new();bar.show_percentage=false
	bar.max_value=maxi(1,int(profile.xp_next));bar.value=int(profile.xp)
	app.place(bar,app.page,67,316,480,13)
	app.label(app.page,"最高等级" if int(profile.level)==int(profile.max_level) else "%d / %d EXP"%[int(profile.xp),int(profile.xp_next)],67,342,500,40,20,Design.MUTED)
	app.label(app.page,"完成实战与首次剧情战斗，解锁更深海域。",65,398,490,72,21,Design.MUTED)
	app.button(app.page,"前往资源海域",65,501,480,60,func():app.show_page("resources"),true)
	app.button(app.page,"舰队与养成",65,580,480,60,func():app.show_page("formation"))
	app.label(app.page,"材料仓",620,135,900,50,29,Design.INK)
	var grid:=GridContainer.new();grid.columns=3;grid.add_theme_constant_override("h_separation",20);grid.add_theme_constant_override("v_separation",22)
	app.place(grid,app.page,620,210,915,455)
	for raw in app.economy.material_catalog():
		var row:Dictionary=raw
		var panel:=PanelContainer.new();panel.custom_minimum_size=Vector2(290,208)
		panel.add_theme_stylebox_override("panel",Design.box(Color(1,1,1,.82),8));grid.add_child(panel)
		var content:=VBoxContainer.new();content.alignment=BoxContainer.ALIGNMENT_CENTER;content.add_theme_constant_override("separation",7);panel.add_child(content)
		var art:=Art.icon(content,str(row.id),78);art.size_flags_horizontal=Control.SIZE_SHRINK_CENTER
		var title:=Detail._text(content,str(row.name),20);title.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
		var number:=Detail._text(content,"× %d"%int(row.owned),24,Design.ACCENT);number.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
		if str(row.id) in ["materials","training_t2","core_t1","core_t2"]:
			var key:=str(row.id)
			var button:=Detail._button(app,content,"3 → 1 合成",func():_fuse(app,key))
			button.custom_minimum_size.y=36;button.add_theme_font_size_override("font_size",17)
			button.disabled=int(row.owned)<3 or not app.economy.state.active_run.is_empty()
	var unlocks:=HBoxContainer.new();unlocks.add_theme_constant_override("separation",18)
	app.place(unlocks,app.page,620,710,915,86)
	for unlock in profile.unlocks:
		var caption:=Detail._text(unlocks,"Lv.%d\n%s"%[int(unlock.level),str(unlock.name)],18,Design.ACCENT if bool(unlock.open) else Design.MUTED)
		caption.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;caption.size_flags_horizontal=Control.SIZE_EXPAND_FILL
static func _fuse(app,id:String) -> void:
	var response:Dictionary=app.economy.fuse_material(id)
	app.show_page("player");app.notify(response)
