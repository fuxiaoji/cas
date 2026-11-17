extends RefCounted
## Read-only drafting. Saving changes transport choices; only launch charges.
const Design=preload("res://scripts/ui_design.gd")
const Art=preload("res://scripts/character_art.gd")
const TypeToken=preload("res://scripts/tactical_type_token.gd")
var app
var service
var layer:Control
var unit_list:VBoxContainer
var company_list:VBoxContainer
var summary:Label
var save:Button
var drafts:Dictionary={}
var selected_unit:String=""
var fleet:Array=[]
var callback:Callable
static func open(owner,completed:Callable=Callable())->void:
	var screen=load("res://scripts/army_loadout.gd").new();screen.app=owner;screen.callback=completed;screen.build()
func build()->void:
	service=load("res://scripts/amphibious_expedition_service.gd").new(app.economy)
	for row in app.economy.roster():
		if app.economy.formation.has(str(row.id)):fleet.append(row)
	for draft in service.choices():
		if draft.has("company_id"):drafts[str(draft.company_id)]=draft.duplicate(true)
	layer=app.open_modal("陆军搭载 · 逐连随舰");layer.set_meta("loadout_owner",self)
	var left:=ScrollContainer.new();left.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;app.place(left,layer,360,220,280,398);unit_list=VBoxContainer.new();unit_list.size_flags_horizontal=Control.SIZE_EXPAND_FILL;unit_list.add_theme_constant_override("separation",8);left.add_child(unit_list)
	var right:=ScrollContainer.new();right.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;app.place(right,layer,660,220,560,398);company_list=VBoxContainer.new();company_list.size_flags_horizontal=Control.SIZE_EXPAND_FILL;company_list.add_theme_constant_override("separation",12);right.add_child(company_list)
	for unit in service.home.catalogue:
		var identity:String=str(unit.id)
		if not service.home.state().units.has(identity):continue
		if selected_unit.is_empty():selected_unit=identity
		var choice:=Button.new();choice.name="ArmyUnit_"+identity;choice.text=str(unit.get("codename",unit.get("name",identity)))+"\n"+str(unit.get("designation",""));choice.custom_minimum_size=Vector2(260,86);choice.add_theme_font_size_override("font_size",17);choice.icon=load("res://scripts/story_actor_layout.gd").portrait(Art.texture(str(unit.get("portrait",""))),identity);choice.expand_icon=true;choice.add_theme_constant_override("icon_max_width",54);Design.apply_button(choice);unit_list.add_child(choice);choice.pressed.connect(func():selected_unit=identity;render_companies())
	summary=app.label(layer,"",370,625,850,52,18,Design.INK);summary.name="ArmyLoadoutValidation";summary.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	app.button(layer,"清空携行",370,691,240,58,func():drafts.clear();render_companies()).name="ClearArmyPlan"
	save=app.button(layer,"保存搭载计划",850,691,370,58,_save,true);save.name="SaveArmyLoadout"
	render_companies()
func render_companies()->void:
	for child in company_list.get_children():company_list.remove_child(child);child.queue_free()
	for button in unit_list.get_children():Design.apply_button(button,button.name=="ArmyUnit_"+selected_unit)
	if selected_unit.is_empty():summary.text="先在家园教学或协议招募中获得战术部队。";save.disabled=true;return
	var unit:Dictionary=service.home.unit(selected_unit);var profile:Dictionary=service.multi_profiles.get(selected_unit,{})
	var heading:=HBoxContainer.new();company_list.add_child(heading)
	var token:=TypeToken.new();token.role=str(profile.get("nato_type",profile.get("role","marine")));token.echelon=str(load("res://scripts/tactical_formation_mark.gd").resolve(unit).echelon);token.custom_minimum_size=Vector2(48,48);heading.add_child(token)
	var title:=Label.new();title.text=str(unit.get("designation",""))+"\n"+str(unit.get("name",""));title.add_theme_font_size_override("font_size",20);heading.add_child(title)
	for company in service.layout(selected_unit).get("companies",[]):
		var key:String=str(company.company_id);var box:=VBoxContainer.new();company_list.add_child(box)
		var check:=CheckBox.new();check.name="Embark_"+key;check.text=str(company.company_name)+" · %d人"%int(company.personnel_count);check.custom_minimum_size.y=44;check.button_pressed=drafts.has(key);check.disabled=not app.economy.state.get("active_run",{}).is_empty();box.add_child(check)
		Design.apply_button(check);check.add_theme_font_size_override("font_size",20)
		# The checked button uses the light selected surface, including pointer hover.
		check.add_theme_color_override("font_pressed_color",Design.INK);check.add_theme_color_override("font_hover_pressed_color",Design.INK)
		check.add_theme_constant_override("h_separation",16)
		var row:=HBoxContainer.new();box.add_child(row)
		var kind:=OptionButton.new();kind.name="Vehicle_"+key;kind.custom_minimum_size=Vector2(235,52);kind.size_flags_horizontal=Control.SIZE_EXPAND_FILL;row.add_child(kind)
		for transport in profile.get("transport_options",[]):
			kind.add_item(str(transport.get("vehicle_name",{"landing_craft":"登陆艇","amphibious_vehicle":"两栖车","helicopter":"直升机"}.get(str(transport.kind),str(transport.kind)))));kind.set_item_metadata(kind.item_count-1,str(transport.kind))
			if str(drafts.get(key,{}).get("transport_kind",profile.get("default_transport","landing_craft")))==str(transport.kind):kind.selected=kind.item_count-1
		var carrier:=OptionButton.new();carrier.name="Carrier_"+key;carrier.custom_minimum_size=Vector2(235,52);carrier.size_flags_horizontal=Control.SIZE_EXPAND_FILL;row.add_child(carrier)
		_fill_carriers(carrier,profile,str(kind.get_selected_metadata()),str(drafts.get(key,{}).get("carrier_identity","")))
		Design.apply_button(kind);Design.apply_button(carrier)
		var update:Callable=func():
			if check.button_pressed:
				drafts[key]={"unit_id":selected_unit,"company_id":key,"transport_kind":str(kind.get_selected_metadata()),"carrier_identity":str(carrier.get_selected_metadata()) if carrier.selected>=0 else ""}
			else:drafts.erase(key)
			_refresh_summary()
		check.toggled.connect(func(_on:bool):update.call());carrier.item_selected.connect(func(_index:int):update.call());kind.item_selected.connect(func(_index:int):_fill_carriers(carrier,profile,str(kind.get_selected_metadata()),"");update.call())
	_refresh_summary()
func _fill_carriers(option:OptionButton,profile:Dictionary,kind:String,wanted:String)->void:
	option.clear();var air:bool=kind=="helicopter" or str(profile.get("role","")) in ["air_assault","airborne","gunship"];var armor:bool=kind=="amphibious_vehicle" or str(profile.get("role","")) in ["armor","transport"]
	var found:bool=false
	for ship in fleet:
		var type:String=str(ship.get("type","DD"))
		if air and type not in ["CV","LHA"]:continue
		if armor and type not in ["APV","CV","LHA"]:continue
		option.add_item(str(ship.name)+" · "+type);option.set_item_metadata(option.item_count-1,str(ship.id))
		if str(ship.id)==wanted:option.selected=option.item_count-1;found=true
	if option.item_count==0:option.add_item("当前随行舰无合格载舰");option.set_item_metadata(0,"")
	elif not wanted.is_empty() and not found:option.add_item("请重新选择合格载舰");option.set_item_metadata(option.item_count-1,wanted);option.selected=option.item_count-1
func _refresh_summary()->void:
	var selected:Array=drafts.values();var plan:Dictionary=service.prepare_plan(fleet,selected,true)
	var used:int=0;var capacity:int=0;var details:Array[String]=[]
	for row in plan.get("transport_capacity",[]):
		used+=int(row.used);capacity+=int(row.capacity);details.append("%s：%d / %d舱"%[str(app.cards.get(str(row.carrier_identity),{}).get("name",row.carrier_identity)),int(row.used),int(row.capacity)])
	summary.text=("未携带陆军 · 可以直接出航" if selected.is_empty() else "%d 连 · %d 人 · 舱位 %d / %d"%[selected.size(),int(plan.get("personnel",0)),used,capacity]) if plan.get("ok",false) else str(plan.get("message","请安排搭载舰"));summary.tooltip_text="\n".join(details)
	summary.add_theme_color_override("font_color",Design.MUTED if plan.get("ok",false) else Color("a94f3b"));save.disabled=not plan.get("ok",false) or not app.economy.state.get("active_run",{}).is_empty()
func _save()->void:
	var plan:Dictionary=service.prepare_plan(fleet,drafts.values(),true)
	if not plan.get("ok",false):app.notify(plan);return
	var response:Dictionary=service.set_choices(drafts.values(),true)
	if response.get("ok",false):app.close_modal();if callback.is_valid():callback.call()
	else:app.notify(response)
