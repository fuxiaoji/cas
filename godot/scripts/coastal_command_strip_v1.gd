extends PanelContainer
## One selected company, one short row. No extra vehicle/ability portrait cards.
const Chip=preload("res://scripts/coastal_action_chip_v1.gd")
const Vehicles=preload("res://scripts/tactical_vehicle_controls_v3.gd")
var controller
var heading:Label
var chips:HBoxContainer
var cancel_button:Button
var signature:String=""
var body_texture:Texture2D
var vehicle_texture:Texture2D
func setup(owner_controller)->void:
	controller=owner_controller;name="CoastalCommands";mouse_filter=Control.MOUSE_FILTER_STOP;z_index=50
	anchor_left=.025;anchor_right=.73;anchor_top=.665;anchor_bottom=.787
	var skin:=StyleBoxFlat.new();skin.bg_color=Color(.035,.09,.12,.94);skin.set_corner_radius_all(8);skin.content_margin_left=10;skin.content_margin_right=10;skin.content_margin_top=5;skin.content_margin_bottom=5;add_theme_stylebox_override("panel",skin)
	var stack:=VBoxContainer.new();stack.add_theme_constant_override("separation",4);add_child(stack)
	var top:=HBoxContainer.new();stack.add_child(top)
	heading=Label.new();heading.add_theme_font_size_override("font_size",17);heading.add_theme_color_override("font_color",Color("e9efd9"));heading.size_flags_horizontal=Control.SIZE_EXPAND_FILL;top.add_child(heading)
	cancel_button=Button.new();cancel_button.name="CancelCommand";cancel_button.text="取消";cancel_button.custom_minimum_size=Vector2(66,30);cancel_button.pressed.connect(func():controller._coastal_cancel_command());top.add_child(cancel_button)
	var scroll:=ScrollContainer.new();scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_AUTO;scroll.vertical_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;scroll.size_flags_horizontal=Control.SIZE_EXPAND_FILL;stack.add_child(scroll)
	chips=HBoxContainer.new();chips.add_theme_constant_override("separation",6);scroll.add_child(chips)
	set_process_unhandled_key_input(true)
func _unhandled_key_input(event:InputEvent)->void:
	if visible and event is InputEventKey and event.pressed and event.keycode==KEY_ESCAPE and not controller.coastal_pending.is_empty():controller._coastal_cancel_command();get_viewport().set_input_as_handled()
func refresh()->void:
	var group:Dictionary=controller._group();var vehicle:Dictionary=Vehicles.own(controller,controller.selected_unit)
	var usable:bool=not vehicle.is_empty() and float(vehicle.get("hp",0))>0 and str(vehicle.get("phase","")) in ["active","loading","unloading"]
	visible=controller.primary_map=="land" and not group.is_empty() and (str(group.get("stage",""))=="ground" or usable)
	if not visible:return
	var orphan:bool=not Vehicles.orphan(controller,controller.selected_unit).is_empty()
	if orphan and usable:controller.selected_vehicle_id=int(vehicle.id)
	var selected:bool=usable and controller.selected_vehicle_id==int(vehicle.id)
	var ability:Dictionary=controller._coastal_ability() if group.get("ability") is Dictionary and not orphan else {}
	var mode:String=str(controller.coastal_pending.get("name",""))
	var actor_name:String=str(Vehicles.NAMES.get(str(vehicle.get("vehicle_kind","")),"载具")) if selected else "步兵"
	var equipment:String=""
	if selected:
		var ready:float=float(vehicle.get("reloading_in",0))
		equipment=" · 换弹 %.1f秒"%ready if ready>0 else " · 待发 %.1f秒"%float(vehicle.get("ready_in",0)) if float(vehicle.get("ready_in",0))>0 else " · 弹药 %d"%int(vehicle.get("ammo",0))
		equipment+=" · 射程 %.0f米"%float(vehicle.get("range",0))
		var state:String=str(vehicle.get("fire_status",""))
		if state in ["not_deployed","no_ammo","no_target_or_los"]:equipment+=" · "+str({"not_deployed":"尚在投送","no_ammo":"弹药耗尽","no_target_or_los":"自动警戒"}[state])
	heading.text=str(group.get("company_name",group.get("name","所选连队")))+" · "+actor_name+equipment+(" · "+mode+"：点击地图 / 拖动" if not mode.is_empty() else "")
	cancel_button.visible=not controller.coastal_pending.is_empty() or not controller.drag_layer.payload.is_empty()
	var key:String=str([controller.selected_unit,selected,usable,orphan,str(group.get("stage","")),not ability.is_empty(),not vehicle.get("passenger_ids",[]).is_empty(),int(vehicle.get("capacity",0))>0])
	if key!=signature:
		signature=key
		body_texture=controller._portrait(controller._identity(controller.selected_unit),controller._tactical_card(controller._identity(controller.selected_unit)))
		vehicle_texture=Vehicles.icon(vehicle) if usable else null
		for child in chips.get_children():chips.remove_child(child);child.queue_free()
		if usable and not orphan:_chip("body","步兵","点选 / 拖动",{"context":"select_body","kind":"unit"})
		if usable:_chip("vehicle",actor_name if selected else str(Vehicles.NAMES.get(str(vehicle.get("vehicle_kind","")),"载具")),"点选 / 拖动",{"context":"select_vehicle","kind":"vehicle"})
		if str(group.get("stage",""))=="ground" or usable:
			_chip("move","移动","拖向目的地",{"context":"target","vehicle_action":"move","unit_action":"move"})
			_chip("attack","攻击","拖向敌人",{"context":"target","vehicle_action":"attack","unit_action":"attack"})
			if selected:
				_chip("fire","开火","原地射击",{"context":"target","vehicle_action":"fire_at"})
				_chip("face","炮向","拖出方向",{"context":"target","vehicle_action":"face"})
			if usable and int(vehicle.get("capacity",0))>0:
				if not vehicle.get("passenger_ids",[]).is_empty():_chip("unload","下车","拖到陆地",{"context":"target","vehicle_action":"disembark","force_vehicle":true})
				elif not orphan:_chip("load","上车","集合登载",{"context":"embark","vehicle_action":"embark","force_vehicle":true})
			if not ability.is_empty():_chip("ability",str(ability.get("name","专长")),"",{"context":"ability","kind":"ability"})
			_chip("more","更多","待命 / 撤收",{"context":"more"})
	for child in chips.get_children():
		var p:Dictionary=controller._company_fields(controller.selected_unit);p.merge(child.get_meta("spec"),true)
		p["kind"]=str(p.get("kind","vehicle" if selected or bool(p.get("force_vehicle",false)) else "unit"));p["vehicle_id"]=int(vehicle.get("id",0));p["texture"]=vehicle_texture if str(p.kind)=="vehicle" else body_texture
		p["name"]=str(child.get_meta("title"));p["selected"]=(str(p.context)=="select_vehicle" and selected) or (str(p.context)=="select_body" and not selected) or (not mode.is_empty() and str(controller.coastal_pending.get("name",""))==str(p.name))
		var subtitle:String=str(child.get_meta("subtitle"));var allowed:bool=not controller.replay_mode
		if str(p.context)=="ability":
			var ready:float=float(ability.get("ready_in",0));allowed=allowed and bool(ability.get("available",false))
			subtitle="冷却 %.0f秒 · 余%d次"%[ceil(ready),int(ability.get("charges",0))] if ready>0 else "余%d次 · %s"%[int(ability.get("charges",0)),"点按" if controller._coastal_self_skill() else "拖动"]
			p["reason"]=str(ability.get("description",subtitle))
		child.configure(p,str(p.name),subtitle,allowed)
	queue_redraw()
func _draw()->void:
	if not visible or controller==null:return
	var payload:Dictionary=controller.drag_layer.payload if controller.drag_layer.dragging else controller.coastal_pending
	if payload.is_empty():return
	var land:Control=controller.ui.get_node("LandWindow/Map")
	var center:Vector2;var radius:float=0
	if str(payload.get("kind",""))=="ability":
		var group:Dictionary=controller._group();var p:Dictionary=group.get("position",{})
		center=Vector2(float(p.get("x",0)),float(p.get("y",0)));radius=float(controller._coastal_ability().get("range",0))
	elif str(payload.get("kind",""))=="vehicle" and str(payload.get("vehicle_action","")) in ["fire_at","face","attack"]:
		var vehicle:Dictionary=Vehicles.find(controller,int(payload.get("vehicle_id",0)))
		center=Vector2(float(vehicle.get("x",0)),float(vehicle.get("y",0)));radius=float(vehicle.get("range",0))
	if radius<=0:return
	var points:=PackedVector2Array()
	for index:int in range(65):points.append(get_global_transform().affine_inverse()*(land.get_global_transform()*land.project(center+Vector2.from_angle(index*TAU/64)*radius)))
	draw_polyline(points,Color(.95,.83,.51,.5),1.5,true)
func _chip(id:String,title:String,subtitle:String,spec:Dictionary)->void:
	var chip=Chip.new();chip.name="Command_"+id;chip.set_meta("spec",spec);chip.set_meta("title",title);chip.set_meta("subtitle",subtitle);chips.add_child(chip);chip.armed.connect(controller._arm)

