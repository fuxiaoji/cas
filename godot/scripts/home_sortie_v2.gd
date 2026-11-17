extends RefCounted
## A two-step loadout: choose owned actors, inspect the native plan, then launch.
const Design=preload("res://scripts/ui_design.gd")
const Art=preload("res://scripts/character_art.gd")
const Token=preload("res://scripts/tactical_type_token.gd")
var app
var home
var screen:Control
var mode:String="raid"
var units:Array=[]
var ships:Array=[]
var preset:String="balanced"
var target:String=""
var plan:Dictionary={}
var status:Label
var confirm:Button
var rows:VBoxContainer
var ship_window:ScrollContainer
var ship_thumbnails:Array=[]
var unit_window:ScrollContainer
var unit_thumbnails:Array=[]
var thumbnails_queued:bool=false
static func open(owner,selected_mode:String="raid")->void:
	var ui=load("res://scripts/home_sortie_v2.gd").new();ui.app=owner;ui.home=owner.home;ui.mode=selected_mode if selected_mode in ["raid","defense","exercise"] else "raid";ui._seed_selection();ui._build()
func _seed_selection()->void:
	ships=home.state().garrison.duplicate()
	if ships.is_empty():
		for id in app.economy.formation:
			if ships.size()<home.latest_limit("ships_per_side"):ships.append(str(id))
	units=home.state().tactical_garrison.filter(func(id):return home.state().units.has(id) and not home.latest_profile(str(id)).is_empty() and home.condition(str(id))>=10)
	if units.is_empty():
		for id in home.state().units:
			if not home.latest_profile(str(id)).is_empty() and home.condition(str(id))>=10:units.append(str(id));break
	target=str(app.get_meta("home_npc_id",""))
func _label(parent:Node,text:String,font:int=19,color:Color=Design.INK)->Label:
	var result:=Label.new();result.text=text;result.add_theme_font_size_override("font_size",font);result.add_theme_color_override("font_color",color);result.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;parent.add_child(result);return result
func _build()->void:
	plan={};app.set_meta("home_battle_mode",mode);screen=app.open_modal("海陆编成 · "+str({"raid":"人机突袭","defense":"守卫家园","exercise":"自家无损演习"}[mode]));screen.name="HomeSortieV2";screen.set_meta("ui_owner",self)
	for index in range(3):
		var selected:String=["raid","defense","exercise"][index]
		var button:Button=app.button(screen,["人机突袭","守卫家园","自家演习"][index],380+index*195,194,180,54,func():mode=selected;_build(),mode==selected);button.name="IslandMode_"+selected;button.add_theme_font_size_override("font_size",20)
	var procurement:Button=app.button(screen,"载舰采购",975,194,110,54,func():
		app.close_modal();var island:Node=app.page.find_child("HomeIsland",true,false);if island!=null:island._aviation_procurement());procurement.name="OpenAviationProcurement";procurement.add_theme_font_size_override("font_size",18)
	var legacy:Button=app.button(screen,"遗迹搜索",1090,194,110,54,func():
		app.set_meta("home_battle_mode","salvage");app.close_modal();var island:Node=app.page.find_child("HomeIsland",true,false);if island!=null:island._legacy_sortie());legacy.name="OpenLegacySalvage";legacy.add_theme_font_size_override("font_size",19)
	var fleet:=OptionButton.new();fleet.name="SavedDeploymentFleet";fleet.add_item("套用已存舰队 · 也可直接点选下方舰娘");app.place(fleet,screen,380,254,555,44)
	for saved in app.fleets.rows():fleet.add_item(str(saved.name)+" · %d艘"%saved.ships.size());fleet.set_item_metadata(fleet.item_count-1,saved.ships.duplicate())
	fleet.disabled=mode=="defense";fleet.item_selected.connect(func(index:int):
		if index<=0:return
		var ids:Array=fleet.get_item_metadata(index)
		if ids.size()>home.latest_limit("ships_per_side"):app.notify({"ok":false,"message":"本场最多%d艘载舰，请在下方点选。"%home.latest_limit("ships_per_side")});return
		ships=ids.duplicate();_build())
	var target_pick:=OptionButton.new();target_pick.name="NPCIsland";app.place(target_pick,screen,945,254,255,44);target_pick.disabled=mode!="raid"
	var islands:Array=home.latest_island().catalogue()
	for island in islands:
		var id:String=str(island.get("id",island.get("npc_id","")));target_pick.add_item(str(island.get("name",id)));target_pick.set_item_metadata(target_pick.item_count-1,id)
		if id==target:target_pick.select(target_pick.item_count-1)
	if target_pick.item_count>0:
		target=str(target_pick.get_item_metadata(target_pick.selected));target_pick.item_selected.connect(func(index):target=str(target_pick.get_item_metadata(index));_invalidate())
	else:target_pick.add_item("新版海域准备中")
	var ship_scroll:=ScrollContainer.new();ship_scroll.name="DeploymentShips";ship_scroll.vertical_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;app.place(ship_scroll,screen,380,305,820,114);ship_window=ship_scroll;ship_thumbnails=[]
	ship_scroll.get_h_scroll_bar().value_changed.connect(func(_value):_queue_thumbnails())
	var ship_strip:=HBoxContainer.new();ship_strip.add_theme_constant_override("separation",8);ship_scroll.add_child(ship_strip)
	var actual_ships:Array=home.state().garrison if mode=="defense" else ships
	for card in home.naval_roster():
		if not bool(card.get("playable",false)):continue
		var id:String=str(card.id);var button:=Button.new();button.name="Sortie_"+id;button.toggle_mode=true;button.button_pressed=actual_ships.has(id);button.disabled=mode=="defense";button.custom_minimum_size=Vector2(120,108);Design.apply_button(button,button.button_pressed);ship_strip.add_child(button)
		var content:=VBoxContainer.new();content.mouse_filter=Control.MOUSE_FILTER_IGNORE;button.add_child(content);content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);content.offset_top=4;content.offset_bottom=-4
		var art:=TextureRect.new();art.custom_minimum_size=Vector2(112,66);art.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;art.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED;art.mouse_filter=Control.MOUSE_FILTER_IGNORE;content.add_child(art);ship_thumbnails.append({"node":art,"path":str(Art.visual_card(card,app.cards).get("portrait","")),"id":id})
		var title:Label=_label(content,str(card.name),17);title.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;title.mouse_filter=Control.MOUSE_FILTER_IGNORE
		button.tooltip_text=str(card.name)+" · "+str(card.get("type",""))+"\n耐久%d%% / 舰上弹药%d%%"%[int(card.get("hp",100)),int(card.get("ammo",100))]
		button.toggled.connect(func(enabled:bool):
			if enabled and not ships.has(id):
				if ships.size()>=home.latest_limit("ships_per_side"):button.set_pressed_no_signal(false);app.notify({"ok":false,"message":"本场最多%d艘载舰"%home.latest_limit("ships_per_side")});return
				ships.append(id)
			elif not enabled:ships.erase(id)
			Design.apply_button(button,enabled);_invalidate())
	var unit_scroll:=ScrollContainer.new();unit_scroll.name="DeploymentUnitScroll";unit_scroll.vertical_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;app.place(unit_scroll,screen,380,425,820,119);unit_window=unit_scroll;unit_thumbnails=[]
	unit_scroll.get_h_scroll_bar().value_changed.connect(func(_value):_queue_thumbnails())
	var unit_strip:=HBoxContainer.new();unit_strip.name="DeploymentUnits";unit_strip.add_theme_constant_override("separation",8);unit_scroll.add_child(unit_strip)
	var actual_units:Array=home.state().tactical_garrison if mode=="defense" else units
	var unit_cards:Array=home.latest_units();unit_cards.sort_custom(func(a,b):return actual_units.has(str(a.id)) and not actual_units.has(str(b.id)))
	for card in unit_cards:
		var id:String=str(card.id)
		if not home.state().units.has(id):continue
		var button:=Button.new();button.name="Deploy_"+id;button.toggle_mode=true;button.button_pressed=actual_units.has(id);button.disabled=mode=="defense" or home.condition(id)<10;button.custom_minimum_size=Vector2(166,108);Design.apply_button(button,button.button_pressed);unit_strip.add_child(button)
		var box:=VBoxContainer.new();box.add_theme_constant_override("separation",0);box.mouse_filter=Control.MOUSE_FILTER_IGNORE;button.add_child(box);box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);box.offset_left=5;box.offset_right=-5
		var upper:=HBoxContainer.new();upper.mouse_filter=Control.MOUSE_FILTER_IGNORE;box.add_child(upper)
		var token:=Token.new();token.role=str(card.get("nato_type",card.get("role","marine")));token.echelon=str(load("res://scripts/tactical_formation_mark.gd").resolve(card).echelon);token.custom_minimum_size=Vector2(38,37);upper.add_child(token)
		var art:=TextureRect.new();art.custom_minimum_size=Vector2(105,58);art.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;art.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED;art.mouse_filter=Control.MOUSE_FILTER_IGNORE;upper.add_child(art);unit_thumbnails.append({"node":art,"path":str(card.get("portrait","")),"id":id})
		var title:Label=_label(box,str(card.get("codename",card.get("name",id))),18);title.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;title.mouse_filter=Control.MOUSE_FILTER_IGNORE
		var scale:Label=_label(box,"%d连 × %d人"%[int(card.get("company_count",0)),int(card.get("personnel_per_company",0))],15,Design.MUTED);scale.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;scale.mouse_filter=Control.MOUSE_FILTER_IGNORE
		button.tooltip_text=str(card.get("designation",""))+"\n"+_role_description(card)
		button.toggled.connect(func(enabled:bool):
			if enabled and not units.has(id):units.append(id)
			elif not enabled:units.erase(id)
			Design.apply_button(button,enabled);_transport_rows();_invalidate())
	var scroll:=ScrollContainer.new();scroll.name="CompanyTransportScroll";scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;app.place(scroll,screen,380,546,820,83)
	rows=VBoxContainer.new();rows.name="CompanyTransports";rows.size_flags_horizontal=Control.SIZE_EXPAND_FILL;scroll.add_child(rows)
	status=app.label(screen,"",380,634,820,34,17,Design.MUTED);status.name="DeploymentCapacity"
	var supplies:=OptionButton.new();supplies.name="TransportPreset";app.place(supplies,screen,380,678,235,64)
	for text in ["火力优先 · 100%","均衡运输 · 70%","运输优先 · 40%"]:supplies.add_item(text)
	supplies.selected=["combat","balanced","transport"].find(preset);supplies.item_selected.connect(func(index):preset=["combat","balanced","transport"][index];_invalidate())
	var inspect:Button=app.button(screen,"检查计划",625,678,180,64,_inspect);inspect.name="PreviewIslandV2";inspect.add_theme_font_size_override("font_size",20)
	confirm=app.button(screen,"确认出发",815,678,385,64,_launch,true);confirm.name="LaunchLittoral";confirm.disabled=true
	_transport_rows();_invalidate();_queue_thumbnails()
func _queue_thumbnails()->void:
	if thumbnails_queued:return
	thumbnails_queued=true;_refresh_thumbnails.call_deferred()
func _refresh_thumbnails()->void:
	await app.get_tree().process_frame
	thumbnails_queued=false
	if not is_instance_valid(screen) or not is_instance_valid(ship_window):return
	_load_visible(ship_window,ship_thumbnails)
	if is_instance_valid(unit_window):_load_visible(unit_window,unit_thumbnails)
func _load_visible(window:ScrollContainer,entries:Array)->void:
	var visible_area:Rect2=window.get_global_rect().grow_individual(180,0,180,0)
	for entry in entries:
		var node:TextureRect=entry.node
		if not is_instance_valid(node):continue
		if node.get_global_rect().intersects(visible_area):
			if node.texture==null:node.texture=load("res://scripts/story_actor_layout.gd").portrait(Art.texture(str(entry.path)),str(entry.id))
		else:node.texture=null
func _role_description(card:Dictionary)->String:
	return "投送："+home.latest_transport_label(str(card.get("default_transport","")))+"\n"+home.latest_combat_label(str(card.get("id","")))+"\n"+load("res://scripts/tactical_codex_v3.gd").summary(home,str(card.get("id","")))
func _choices(ids:Array)->Array:
	var result:Array=[]
	for identity in ids:
		var id:String=str(identity);var option:Dictionary=home.latest_transport_option(id)
		if not option.is_empty():result.append({"id":id,"kind":str(option.kind)})
	return result
func _transport_rows()->void:
	for child in rows.get_children():rows.remove_child(child);child.queue_free()
	var ids:Array=home.state().tactical_garrison if mode=="defense" else units
	for identity in ids:
		var id:String=str(identity);var card:Dictionary=home.latest_unit(id);var data:Dictionary=home.latest_profile(id)
		var row:=HBoxContainer.new();row.custom_minimum_size.y=68;rows.add_child(row)
		var title:Label=_label(row,str(card.get("codename",card.get("name",id)))+"\n"+str(card.get("designation","")),16);title.custom_minimum_size.x=250;title.size_flags_vertical=Control.SIZE_SHRINK_CENTER
		var selected:Dictionary=home.latest_transport_option(id)
		var picture_kind:String=str(selected.get("kind",""))
		if picture_kind=="amphibious_vehicle" and not data.get("combat_vehicles",[]).is_empty():picture_kind=str(data.combat_vehicles[0].kind)
		var picture:=TextureRect.new();picture.custom_minimum_size=Vector2(55,52);picture.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;picture.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED;picture.texture=_vehicle_icon(picture_kind);row.add_child(picture)
		var description:Label=_label(row,"固定投送 · "+home.latest_transport_label(str(selected.get("kind","")))+"\n"+home.latest_combat_label(id),17);description.name="CompanyTransport_"+id;description.size_flags_horizontal=Control.SIZE_EXPAND_FILL;description.size_flags_vertical=Control.SIZE_SHRINK_CENTER;description.tooltip_text=_role_description(data)

func _vehicle_icon(kind:String)->Texture2D:
	var path:String="res://data/tactical-vehicles-v3.json"
	var raw:Variant=JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else null
	if not raw is Dictionary:return null
	if FileAccess.file_exists("res://data/tactical-vehicles-v4.json"):
		var extra:Variant=JSON.parse_string(FileAccess.get_file_as_string("res://data/tactical-vehicles-v4.json"))
		if extra is Dictionary:raw.get_or_add("vehicles",{}).merge(extra.get("vehicles",{}),true)
	var key:String="transport_aircraft" if kind=="parachute_aircraft" else kind
	var row:Dictionary=raw.get("vehicles",{}).get(key,{})
	var frame:Dictionary=row.get("frames",{}).get("N",{})
	var rect:Array=frame.get("region",[]);var source:String=str(row.get("atlas",""))
	if rect.size()!=4 or source.is_empty() or not ResourceLoader.exists(source):return null
	var icon:=AtlasTexture.new();icon.atlas=load(source);icon.region=Rect2(float(rect[0]),float(rect[1]),float(rect[2]),float(rect[3]));return icon
func _invalidate()->void:
	plan={}
	if not is_instance_valid(confirm):return
	confirm.disabled=true;confirm.text="检查后出发" if mode!="exercise" else "检查后开始演习"
	var ids:Array=home.state().tactical_garrison if mode=="defense" else units;var companies:int=0;var people:int=0
	for id in ids:
		var card:Dictionary=home.latest_profile(str(id));companies+=int(card.get("company_count",0));people+=int(card.get("company_count",0))*int(card.get("personnel_per_company",0))
	status.text="已选 %d人格 / %d连 / %d人 · 检查投送与整备"%[ids.size(),companies,people]
	if mode=="exercise":status.text+=" · 自己攻打自己，无损无奖励"
	elif mode=="defense":status.text+=" · 使用已保存驻防，产生真实损耗"
func _inspect()->void:
	var ids:Array=home.state().tactical_garrison if mode=="defense" else units;var naval:Array=home.state().garrison if mode=="defense" else ships
	plan=home.prepare_latest_exercise(ids,naval,preset,_choices(ids)) if mode=="exercise" else home.prepare_latest_island(mode,target,ids,naval,preset,_choices(ids))
	if not plan.get("ok",false):status.text=str(plan.get("message","计划尚未通过"));status.add_theme_color_override("font_color",Color("b5533c"));confirm.disabled=true;return
	status.add_theme_color_override("font_color",Design.MUTED);confirm.disabled=false
	if mode=="exercise":
		status.text="攻方%d舰 / %d人格，守方为自己的%d舰 / %d人格 · 全程无损"%[plan.request.ships.size(),plan.request.roster.size(),plan.request.defender.ships.size(),plan.request.defender.roster.size()];confirm.text="开始自家无损演习"
	else:status.text="投送检查通过 · 出航扣弹药%d · 本人及设施实际战损生效"%int(plan.loaded_ammo);confirm.text="确认出发"
func _launch()->void:
	if not plan.get("ok",false):return
	var request:Dictionary=plan.request.duplicate(true);app.set_meta("home_npc_id",target)
	if mode=="exercise":
		if app.has_method("launch_home_exercise"):app.launch_home_exercise(request)
		else:app.notify({"ok":false,"message":"演习会话正在接线，账号未产生费用"})
	else:app.launch_littoral(request)
