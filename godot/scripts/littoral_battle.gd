extends "res://scripts/legacy_battle.gd"
## Full-screen naval chart plus a linked, public-information landing viewport.
const Sea=preload("res://scripts/littoral_sea.gd")
const AircraftArt=preload("res://scripts/littoral_aircraft_art.gd")
const VehicleControls=preload("res://scripts/tactical_vehicle_controls_v3.gd")
const TacticalFrames=preload("res://scripts/tactical_art_v2.gd")
var ui:Control
var selected_unit:String=""
var selected_vehicle_id:int=0
var support_mode:String=""
var selected_beach:int=1
var insertion:String="landing"
var order_action:String="move"
var roster_signature:String=""
var replay_seconds:float=0
var replay_duration:float=0
var last_pending:Dictionary={}
var last_pending_tick:float=-1

signal interaction_event(kind:String,data:Dictionary)
const DragCard=preload("res://scripts/littoral_drag_card.gd")
const DRAG_VERSIONS:Array[String]=["cas-littoral-v2","cas-littoral-v3","cas-littoral-v4","cas-littoral-coastal-v1"]
var naval_controller
var naval_nodes:Array[CanvasItem]=[]
var naval_visibility:Dictionary={}
var naval_primary:String="sea"
var naval_pause:Button
var primary_map:String="sea"
var drag_layer
var tutorial
var interaction_sequence:int=0
var last_hover_msec:int=0
var hover_preview:Dictionary={}
var tutorial_progress:Dictionary={}
var tutorial_requested:bool=false
var tutorial_dismissed:bool=false
var restoring_ui:bool=false
var ui_save_pending:bool=false
var context_action:String=""
var error_hint_until:int=0
var autonomy_button:Button
var coastal_commands:PanelContainer
var coastal_pending:Dictionary={}
const CarrierDesk=preload("res://scripts/carrier_air_desk.gd")

func build()->void:
	if _world_naval():
		var prior:Array=app.page.get_children()
		naval_controller=load("res://scripts/littoral_naval_controller.gd").new(app);naval_controller.build()
		for node in app.page.get_children():
			if not prior.has(node) and node is CanvasItem and node!=app.sea:naval_nodes.append(node)
		naval_pause=app.pause_button;feedback=naval_controller.feedback
	ui=load("res://scenes/ui/littoral_battle.tscn").instantiate();app.page.add_child(ui)
	if _world_naval():
		autonomy_button=Button.new();autonomy_button.name="CombinedAutonomy"
		ui.add_child(autonomy_button);autonomy_button.custom_minimum_size=Vector2(156,56);autonomy_button.z_index=64
		autonomy_button.text="一键托管";autonomy_button.pressed.connect(_toggle_autonomy)
		Design.apply_button(autonomy_button);autonomy_button.add_theme_font_size_override("font_size",20)
	if _world_naval() and not app.core.view.get("littoral",{}).get("aviation",{}).get("squadrons",[]).is_empty():
		load("res://scripts/carrier_command_desk.gd").install(self)
	if _world_naval():
		# GUI picking follows tree order, not z_index. Keep the full map below
		# the original command desk so its transparent areas cannot swallow buttons.
		app.page.move_child(ui,0)
		var obsolete:Control=ui.get_node("SeaWindow/Map");ui.get_node("SeaWindow").remove_child(obsolete);obsolete.queue_free()
		app.sea.reparent(ui.get_node("SeaWindow"));app.sea.name="Map";app.sea.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		ui.get_node("Top").visible=false;ui.get_node("Objective").visible=false
		ui.get_node("Tray").z_index=20;ui.get_node("Hint").z_index=20
		# Original fleet/route context remains directly above the new tactical tray.
		naval_controller.hud.configure_amphibious_layout()
	else:
		app.sea=ui.get_node("SeaWindow/Map");app.sea.point_selected.connect(move);app.sea.object_selected.connect(select)
	app.sea.cards=app.cards;app.sea.chibis=app.ship_mode;app.sea.drag_requested.connect(_arm)
	ui.get_node("LandWindow/Map").point_selected.connect(_land_click)
	ui.get_node("LandWindow/Map").actor_drag_requested.connect(_arm_map_actor)
	ui.get_node("LandWindow/Map").actor_drag_cancelled.connect(func():drag_layer.cancel())
	ui.get_node("LandWindow/Map").camera_changed.connect(_refresh_focus_label)
	ui.get_node("Top/Pause").pressed.connect(app.toggle_pause);ui.get_node("Top/Menu").pressed.connect(open_pause_menu)
	for multiplier in [1,2,4,8]:
		var speed_button:Button=ui.get_node("Top/Speeds/Speed%d"%multiplier)
		speed_button.pressed.connect(func():set_battle_speed(multiplier));Design.apply_button(speed_button);speed_button.add_theme_font_size_override("font_size",19)
	ui.get_node("MiniMap").pressed.connect(func():set_primary_map("land" if primary_map=="sea" else "sea"))
	ui.get_node("FocusMap").pressed.connect(func():_focus_map())
	ui.get_node("LandWindow/Controls/Focus").pressed.connect(func():ui.get_node("LandWindow/Map").focus_selected())
	# Compatibility actions stay hidden; they are also available in the selected-card menu.
	ui.get_node("Actions/Land").pressed.connect(_deploy)
	ui.get_node("Actions/Retreat").pressed.connect(func():_unit_order("retreat"))
	ui.get_node("Actions/Search").pressed.connect(func():order_action="search";_hint("将部队卡拖向遗迹"))
	ui.get_node("Actions/Repair").pressed.connect(func():order_action="repair";_hint("将工兵卡拖向受损己方设施"))
	ui.get_node("Actions/Naval").pressed.connect(_naval_action)
	ui.get_node("Actions/Helicopter").pressed.connect(func():support_mode="helicopter";_hint("拖动直升机支援卡到落点"))
	ui.get_node("Actions/Extract").pressed.connect(_extract)
	Design.apply_button(ui.get_node("Top/Pause"));Design.apply_button(ui.get_node("Top/Menu"));Design.apply_button(ui.get_node("FocusMap"))
	for path in ["Top/Title","Top/Status","Top/Clock","Objective","Hint","MiniCaption"]:ui.get_node(path).add_theme_color_override("font_color",Color("f0f0db"))
	drag_layer=ui.get_node("DragLayer");drag_layer.started.connect(_drag_started);drag_layer.moved.connect(_drag_hover);drag_layer.dropped.connect(_drag_drop);drag_layer.clicked.connect(_card_clicked);drag_layer.cancelled.connect(_clear_drag)
	drag_layer.map_pinch_requested.connect(_begin_map_pinch)
	drag_layer.scroll_container=ui.get_node("Tray/Scroll")
	if _coastal_controls():
		coastal_commands=load("res://scripts/coastal_command_strip_v1.gd").new();ui.add_child(coastal_commands);coastal_commands.setup(self)
	if not _world_naval():app.pause_button=ui.get_node("Top/Pause");app.battle_status=ui.get_node("Top/Status")
	_layout_maps();update()
	_bind_tutorial()

func _world_naval()->bool:return str(app.core.view.get("littoral",{}).get("version","")) in ["cas-littoral-v4","cas-littoral-coastal-v1"]
func _coastal_controls()->bool:return str(app.core.view.get("island_war",{}).get("version",""))=="cas-island-war-coastal-v1"
func _coastal_ability()->Dictionary:
	var definition:Dictionary=_tactical_card(_identity(selected_unit)).get("ability",{}).duplicate(true)
	definition.merge(_group().get("ability",{}),true);return definition
func _coastal_self_skill()->bool:return str(_coastal_ability().get("id","")) in ["hull_down","rapid_march","supply_network","triage","rescue","air_coordination"] or float(_coastal_ability().get("range",0))<=0

func _hint(text:String)->void:
	if is_instance_valid(ui):ui.get_node("Hint").text=text
func set_battle_speed(multiplier:int)->void:
	if multiplier not in [1,2,4,8]:return
	app.speed=multiplier;update();_emit("speed_changed",{"accepted":true,"speed":multiplier});_save_ui_deferred()
func _error_hint(text:String)->void:
	error_hint_until=Time.get_ticks_msec()+2200;_hint(text)
	ui.get_tree().create_timer(2.25).timeout.connect(_restore_idle_hint)
func _restore_idle_hint()->void:
	if not is_instance_valid(ui) or (drag_layer!=null and drag_layer.dragging) or Time.get_ticks_msec()<error_hint_until:return
	var autonomy:Dictionary=app.core.view.get("littoral",{}).get("autonomy",{})
	if bool(autonomy.get("enabled",false)):
		_hint(str(autonomy.get("status","协同行动中"))+" · 拖动单位即可接管");return
	if tutorial!=null and tutorial.active:_hint("")
	elif _coastal_controls() and primary_map=="land":
		_hint("点击地图确认 · 可取消" if not coastal_pending.is_empty() else "拖动移动 · 拖向敌人攻击 · 点按切换步兵 / 载具")
	else:_hint("拖动部队卡安排岸上行动；二次点卡可撤收" if primary_map=="land" else "将返航卡拖向返航圈" if _return_available() else "拖部队卡到岛上登陆；拖舰艇到岛上调整炮向")
func _emit(kind:String,data:Dictionary={})->void:
	interaction_sequence+=1;data["event_id"]="ui-%d"%interaction_sequence;interaction_event.emit(kind,data)
	if tutorial!=null:tutorial.notify_event(kind,data)
func set_primary_map(value:String)->void:
	if value not in ["sea","land"] or value==primary_map:return
	if _coastal_controls():_coastal_cancel_command(false)
	primary_map=value;roster_signature="";_layout_maps()
	if value=="land" and _has_weapon_lesson() and not replay_mode:
		var ground_map=ui.get_node("LandWindow/Map")
		if ground_map.zoom<=1 and str(_group().get("stage",""))=="ground":ground_map.focus_selected()
	update();_emit("focus_changed",{"focus":value,"accepted":true})
	_save_ui_deferred()
func _layout_maps()->void:
	if not is_instance_valid(ui):return
	for type in ["sea","land"]:
		var window:Control=ui.get_node("SeaWindow" if type=="sea" else "LandWindow")
		window.anchor_left=0 if type==primary_map else .755;window.anchor_top=0 if type==primary_map else .115
		window.anchor_right=1 if type==primary_map else .975;window.anchor_bottom=.79 if type==primary_map else .375
		window.offset_left=0;window.offset_top=0;window.offset_right=0;window.offset_bottom=0
		window.z_index=0 if type==primary_map else 5
	if _world_naval():
		ui.get_node("SeaWindow").z_index=-1 if primary_map=="sea" else 5
		if primary_map=="sea":app.place_reposition(ui.get_node("Hint"),420,562,730,40)
		else:app.place_reposition(ui.get_node("Hint"),40,675,1400,45)
		if _coastal_controls() and primary_map=="land":app.place_reposition(ui.get_node("Hint"),40,554,1100,35)
		for node in naval_nodes:
			if not is_instance_valid(node):continue
			if primary_map=="land":
				if naval_primary!="land":naval_visibility[node.get_instance_id()]=node.visible
				node.visible=false
			else:node.visible=bool(naval_visibility.get(node.get_instance_id(),node.visible))
		naval_primary=primary_map
		ui.get_node("Top").visible=primary_map=="land"
		# Closed drawers stay closed after swapping maps.
		if primary_map=="sea":naval_controller.hud.set_drawer(not naval_controller.collapsed)
	app.sea.miniature=primary_map!="sea";app.sea.queue_redraw()
	ui.get_node("LandWindow/Map").set_miniature(primary_map!="land")
	ui.get_node("MiniMap").z_index=8;ui.get_node("MiniCaption").z_index=9
	ui.get_node("MiniCaption").text="陆地 · 点击切换" if primary_map=="sea" else "海域 · 点击切换"
	_refresh_focus_label()
	_layout_autonomy()
	_update_tutorial_targets.call_deferred()
func _layout_autonomy()->void:
	if not is_instance_valid(autonomy_button):return
	# A raised z_index does not fix GUI picking through the naval desk. Place
	# this real input control in the active header, after the map siblings.
	var parent:Control=ui.get_node("Top") if primary_map=="land" else app.page
	if autonomy_button.get_parent()!=parent:autonomy_button.reparent(parent,false)
	if primary_map=="land":
		autonomy_button.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
		parent.move_child(autonomy_button,3)
	else:
		app.place_reposition(autonomy_button,1040,24,156,56)
		# HBoxContainer wrote pixel offsets while the land header owned it.
		# Anchors alone would add those offsets again after returning to sea.
		autonomy_button.offset_left=0;autonomy_button.offset_top=0;autonomy_button.offset_right=0;autonomy_button.offset_bottom=0
		parent.move_child(autonomy_button,parent.get_child_count()-1)
func _focus_map()->void:
	if primary_map=="land":ui.get_node("LandWindow/Map").focus_selected()
	else:app.sea.zoom=1 if app.sea.zoom>1 else 1.8;app.sea.queue_redraw()
func _refresh_focus_label()->void:
	if not is_instance_valid(ui):return
	var land=ui.get_node("LandWindow/Map");var label:String="概览" if land.zoom>1 else "街区"
	ui.get_node("FocusMap").text=label if primary_map=="land" and _world_naval() else "⊕"
	ui.get_node("FocusMap").tooltip_text="聚焦所选部队到约700米街区；再次点击返回全岛概览" if primary_map=="land" and _world_naval() else "调整地图视野"
func serialize_ui_state()->Dictionary:
	var progress:Dictionary=tutorial.snapshot_progress() if tutorial!=null else tutorial_progress.duplicate(true)
	progress["dismissed"]=tutorial_dismissed;progress["completed"]=str(progress.get("step_id",""))=="complete"
	var result:Dictionary={"primary_map":primary_map,"selected_unit":selected_unit,"selected_vehicle_id":selected_vehicle_id,"selected_ship":_selected_naval_id(),"speed":app.speed,"context_action":context_action,"drag_tutorial":progress}
	var ground_map=ui.get_node("LandWindow/Map")
	result["land_view"]={"zoom":ground_map.zoom,"center":{"x":ground_map.camera_center.x,"y":ground_map.camera_center.y}}
	if naval_controller!=null:result["naval"]={"fleet_id":naval_controller.fleet_id,"ship_id":naval_controller.ship_id,"target_id":naval_controller.target_id,"route_mode":naval_controller.route_mode,"cruise":naval_controller.cruise,"tab":naval_controller.tab,"collapsed":naval_controller.collapsed,"torpedo":naval_controller.torpedo.duplicate(true),"ranges_visible":app.sea.ranges_visible}
	return result
func restore_ui_state(value:Dictionary)->void:
	restoring_ui=true
	primary_map=str(value.get("primary_map","sea"));selected_unit=str(value.get("selected_unit",""));selected_vehicle_id=int(value.get("selected_vehicle_id",0));tutorial_progress=value.get("drag_tutorial",{}).duplicate(true)
	app.sea.selected_ship=int(value.get("selected_ship",0));context_action=str(value.get("context_action",""))
	var ground_map=ui.get_node("LandWindow/Map");var ground_view:Dictionary=value.get("land_view",{})
	ground_map.zoom=clampf(float(ground_view.get("zoom",1)),1,12 if _world_naval() else 4)
	var ground_center:Dictionary=ground_view.get("center",{})
	ground_map.camera_center=Vector2(float(ground_center.get("x",0)),float(ground_center.get("y",0)))
	ground_map._resize_visuals()
	if naval_controller!=null:
		for key in value.get("naval",{}):
			if key in ["fleet_id","ship_id","target_id","route_mode","cruise","tab","collapsed"]:naval_controller.set(key,value.naval[key])
		app.sea.ranges_visible=bool(value.get("naval",{}).get("ranges_visible",true))
		naval_controller.torpedo.clear()
		for key in value.get("naval",{}).get("torpedo",{}):naval_controller.torpedo[int(str(key))]=value.naval.torpedo[key].duplicate(true)
	tutorial_dismissed=bool(tutorial_progress.get("dismissed",false))
	var saved_speed:int=int(value.get("speed",1));app.speed=saved_speed if saved_speed in [1,2,4,8] else 1
	if primary_map not in ["sea","land"]:primary_map="sea"
	_layout_maps();roster_signature="";update()
	_apply_tutorial();restoring_ui=false
func _save_ui_deferred()->void:
	if restoring_ui or replay_mode or ui_save_pending or app.run.is_empty():return
	ui_save_pending=true;_save_ui.call_deferred()
func _save_ui()->void:
	ui_save_pending=false
	if replay_mode or not is_instance_valid(ui) or app.battle_controller!=self or app.run.is_empty():return
	if not app.checkpoint():app.running=false
func tutorial_targets()->Dictionary:
	return {"main_map":ui.get_node("SeaWindow/Map" if primary_map=="sea" else "LandWindow/Map"),"mini_map":ui.get_node("LandWindow/Map" if primary_map=="sea" else "SeaWindow/Map"),"tray":ui.get_node("Tray"),"swap":ui.get_node("MiniMap"),"pause":ui.get_node("Top/Pause"),"menu":ui.get_node("Top/Menu")}
func _update_tutorial_targets()->void:
	if tutorial==null:return
	var targets:Dictionary={};var nodes:Dictionary=tutorial_targets()
	for key in nodes:targets[key]=nodes[key].get_global_rect()
	var sea:Control=ui.get_node("SeaWindow/Map");var land:Control=ui.get_node("LandWindow/Map")
	var map:Control=sea if primary_map=="sea" else land
	var data:Dictionary=app.core.view.get("littoral",{});var group:Dictionary=_group()
	var lesson_unit:String=str(tutorial.unit_id) if tutorial.active else ""
	for card in ui.get_node("Tray/Scroll/Cards").get_children():
		var payload:Dictionary=card.payload;var kind:String=str(payload.kind)
		if kind=="unit":
			if _payload_company(payload)==selected_unit:targets["squad_card"]=card.get_global_rect()
			if not targets.has("deploy_card"):
				for row in data.get("groups",[]):
					if str(row.id)==_payload_company(payload) and str(row.get("stage",""))=="embarked" and (lesson_unit.is_empty() or _payload_company(payload)==lesson_unit):targets["deploy_card"]=card.get_global_rect()
		elif kind=="naval":targets["land_support_card"]=card.get_global_rect()
		elif kind=="withdraw":targets["withdraw_card"]=card.get_global_rect()
		elif kind=="ability":targets["ability_card"]=card.get_global_rect()
		elif kind=="return":targets["return_card"]=card.get_global_rect()
		elif kind=="vehicle":targets["vehicle_card"]=card.get_global_rect()
		elif kind=="vehicle_unload":targets["vehicle_unload_card"]=card.get_global_rect()
	if primary_map=="sea":targets["land_minimap"]=ui.get_node("MiniMap").get_global_rect()
	else:targets["sea_minimap"]=ui.get_node("MiniMap").get_global_rect()
	var beaches:Array=data.get("beaches",[])
	if str(data.get("version","")) in DRAG_VERSIONS and str(data.get("mode",""))=="tutorial" and beaches.size()>1:beaches=[beaches[1]]
	for beach in beaches:
		var point:Dictionary=beach.get("land",{})
		if not point.is_empty():targets["landing_zone"]=_world_rect(map,Vector2(float(point.x),float(point.y)),42);break
	for transport in data.get("transports",[]):
		if _row_company(transport)==selected_unit:targets["transport"]=_world_rect(map,Vector2(float(transport.x),float(transport.y)),32);break
	if primary_map=="sea":
		var exit:Dictionary=data.get("exit",{})
		if not exit.is_empty():targets["return_zone"]=_world_rect(sea,Vector2(float(exit.x),float(exit.y)),40)
		var tutorial_ship:int=_selected_naval_id()
		var training:Variant=data.get("training")
		if training is Dictionary and str(training.get("lesson",""))=="sea_control":
			var caliber:float=-1
			for ship in app.core.view.get("ships",[]):
				if float(ship.get("hp",0))>0 and _has_naval_gun(ship) and float(ship.get("mainCaliberMm",0))>caliber:caliber=float(ship.get("mainCaliberMm",0));tutorial_ship=int(ship.id)
		for ship in app.core.view.get("ships",[]):
			if int(ship.id)==tutorial_ship:
				targets["naval_support_card"]=_world_rect(sea,Vector2(float(ship.x),float(ship.y)),38)
				var badge:Vector2=sea.get_global_transform()*(sea.project(Vector2(float(ship.x),float(ship.y)))+Vector2(-24,-48))
				targets["gun_badge"]=Rect2(badge-Vector2(17,17),Vector2(34,34));break
		for enemy in app.core.view.get("contacts",[]):
			if float(enemy.get("health",1))>0:targets["sea_enemy"]=_world_rect(sea,Vector2(float(enemy.x),float(enemy.y)),32);break
	var move_origin:Vector2=Vector2.ZERO
	for body in data.get("land",{}).get("entities",[]):
		var point:Vector2=Vector2(float(body.x),float(body.y))
		if str(body.get("side","axis"))=="allies" and _row_company(body)==selected_unit:
			move_origin=point
			if primary_map=="land":targets["withdraw_zone"]=_entity_rect(land,body,30)
		elif primary_map=="land" and not targets.has("land_enemy") and str(body.get("side","axis"))!="allies" and float(body.get("hp",0))>0:targets["land_enemy"]=_entity_rect(land,body,23)
	if primary_map=="land" and move_origin!=Vector2.ZERO:
		targets["friendly_zone"]=_world_rect(land,move_origin,30)
		for offset in [Vector2(650,-400),Vector2(-650,-400),Vector2(800,0),Vector2(-800,0)]:
			var candidate:Vector2=move_origin+offset
			if _island_contains(candidate) and not _ground_blocked(candidate) and land.target_at(land.project(candidate)).is_empty():targets["land_move_zone"]=_world_rect(land,candidate,25);break
		# Deployable skills share the selected company's actual reach. Avoid
		# pointing a short-range turret/grenade skill at a distant move waypoint.
		for offset in [Vector2(100,-80),Vector2(-100,-80),Vector2(100,0),Vector2(-100,0),Vector2.ZERO]:
			var candidate:Vector2=move_origin+offset
			if _island_contains(candidate) and not _ground_blocked(candidate):targets["ability_zone"]=_world_rect(land,candidate,25);break
	for ruin in data.get("land",{}).get("ruins",[]):
		if not bool(ruin.get("searched",false)) and primary_map=="land":targets["search_zone"]=_world_rect(land,Vector2(float(ruin.x),float(ruin.y)),32);break
	for building in data.get("land",{}).get("buildings",[]):
		if str(building.get("side","axis"))!="allies" and float(building.get("hp",0))>0:
			var target:Rect2=_world_rect(map,Vector2(float(building.x),float(building.y)),36)
			if primary_map=="land" and not targets.has("land_enemy"):targets["land_enemy"]=target
			targets["naval_target" if primary_map=="sea" else "support_zone"]=target;break
	if primary_map=="land" and move_origin!=Vector2.ZERO:
		var fortification:Dictionary={};var fortification_gap:float=INF
		for building in data.get("land",{}).get("buildings",[]):
			if str(building.get("side","axis"))=="allies" or float(building.get("hp",0))<=0:continue
			var gap:float=move_origin.distance_to(Vector2(float(building.x),float(building.y)))
			if gap<fortification_gap:fortification_gap=gap;fortification=building
		if not fortification.is_empty():targets["demolition_target"]=_world_rect(land,Vector2(float(fortification.x),float(fortification.y)),30)
	if primary_map=="land" and _has_weapon_lesson() and move_origin!=Vector2.ZERO:
		var nearest:Dictionary={};var distance:float=INF
		var threats:Array=data.get("land",{}).get("entities",[])+data.get("land",{}).get("buildings",[])
		for threat in threats:
			if str(threat.get("side","axis"))=="allies" or float(threat.get("hp",0))<=0 or not bool(threat.get("active",true)):continue
			var gap:float=move_origin.distance_to(Vector2(float(threat.x),float(threat.y)))
			if gap<distance:distance=gap;nearest=threat
		if not nearest.is_empty():targets["land_enemy"]=_world_rect(land,Vector2(float(nearest.x),float(nearest.y)),26)
	# A legal empty shore point remains a meaningful live-fire lesson after the
	# actual squad has already cleared the last hostile. The shot is still real.
	var support_key:String="naval_target" if primary_map=="sea" else "support_zone"
	if not targets.has(support_key) and targets.has("landing_zone"):targets[support_key]=targets.landing_zone
	if str(app.core.view.get("island_war",{}).get("version","")) in ["cas-island-war-v3","cas-island-war-v4","cas-island-war-coastal-v1"]:
		for effect in data.get("land",{}).get("effects",[]):
			if str(effect.get("kind",""))=="support_designation" and str(effect.get("side",""))=="allies" and float(effect.get("remaining_s",0))>0:
				targets[support_key]=_world_rect(map,Vector2(float(effect.x),float(effect.y)),32);break
		if primary_map=="land":
			var vehicle:Dictionary=VehicleControls.own(self,selected_unit)
			if not vehicle.is_empty():
				targets["vehicle_zone"]=_entity_rect(land,vehicle,26)
				var origin:=Vector2(float(vehicle.x),float(vehicle.y))
				for offset in [Vector2(45,0),Vector2(-45,0),Vector2(0,45),Vector2(0,-45),Vector2.ZERO]:
					var point:Vector2=origin+offset
					if _island_contains(point) and not _ground_blocked(point):targets["vehicle_unload_zone"]=_world_rect(land,point,25);break
	tutorial.set_targets(targets)
func _world_rect(map:Control,point:Vector2,radius:float)->Rect2:
	var center:Vector2=map.get_global_transform()*map.project(point)
	return Rect2(center-Vector2.ONE*radius,Vector2.ONE*radius*2)
func _entity_rect(map:Control,row:Dictionary,radius:float)->Rect2:
	var key:int=int(row.get("id",0));var local:Vector2=map.actor_hit_point(key) if map.actors.has(key) else map.project(Vector2(float(row.x),float(row.y)))
	var center:Vector2=map.get_global_transform()*local
	return Rect2(center-Vector2.ONE*radius,Vector2.ONE*radius*2)

func _has_weapon_lesson()->bool:
	var value:Variant=app.core.view.get("littoral",{}).get("training")
	return str(app.core.view.get("island_war",{}).get("version","")) in ["cas-island-war-v3","cas-island-war-v4","cas-island-war-coastal-v1"] and value is Dictionary and not value.is_empty()
func _bind_tutorial()->void:
	var path:String="res://scenes/ui/littoral_drag_tutorial.tscn"
	if not ResourceLoader.exists(path):return
	var progressive:String="res://scripts/littoral_progressive_tutorial.gd"
	var weapon_lesson:bool=_has_weapon_lesson()
	tutorial=load("res://scripts/tactical_weapons_tutorial_v3.gd").new() if weapon_lesson else load(progressive).new() if str(app.core.view.get("littoral",{}).get("version","")) in ["cas-littoral-v3","cas-littoral-v4","cas-littoral-coastal-v1"] and ResourceLoader.exists(progressive) else load(path).instantiate();ui.add_child(tutorial)
	if tutorial is CanvasItem:tutorial.z_index=2000
	if tutorial.has_signal("progress_changed"):tutorial.progress_changed.connect(func(value):tutorial_progress=value.duplicate(true);_save_ui_deferred())
	if tutorial.has_signal("help_closed"):tutorial.help_closed.connect(func():tutorial_dismissed=true;_save_ui_deferred())
	if tutorial.has_signal("step_changed"):tutorial.step_changed.connect(func(_id,_index):roster_signature="";_refresh_context.call_deferred())
	tutorial_requested=bool(app.get_meta("littoral_drag_help",false))
	if app.has_meta("littoral_drag_help"):app.remove_meta("littoral_drag_help")
	_apply_tutorial()
	_update_tutorial_targets.call_deferred()
func _apply_tutorial()->void:
	if tutorial==null:return
	var data:Dictionary=app.core.view.get("littoral",{})
	var v2:bool=str(app.core.view.get("littoral",{}).get("version","")) in DRAG_VERSIONS
	if _has_weapon_lesson():v2=true
	var fresh_lesson:bool=v2 and str(data.get("mode",""))=="tutorial" and tutorial_progress.is_empty()
	if _has_weapon_lesson():fresh_lesson=tutorial_progress.is_empty()
	var saved_help:bool=bool(tutorial_progress.get("help_open",false)) and not bool(tutorial_progress.get("completed",false))
	if not replay_mode and v2 and (tutorial_requested or saved_help or (fresh_lesson and not tutorial_dismissed)):
		tutorial.start_tutorial(tutorial_progress);tutorial.observe_state(app.core.view)
	else:tutorial.active=false;tutorial.hide();tutorial.set_process(false)
func _refresh_context()->void:
	if not is_instance_valid(ui):return
	_follow_tutorial_unit()
	_roster(app.core.view.get("littoral",{}));_refresh_cards(app.core.view.get("littoral",{}));_update_tutorial_targets()
func _follow_tutorial_unit()->void:
	if tutorial==null or not tutorial.active or str(app.core.view.get("littoral",{}).get("version","")) not in ["cas-littoral-v3","cas-littoral-v4","cas-littoral-coastal-v1"]:return
	var id:String=str(tutorial.unit_id)
	if id.is_empty() or selected_unit==id:return
	for row in app.core.view.get("littoral",{}).get("groups",[]):
		if str(row.id)==id:selected_unit=id;context_action="";roster_signature="";return

func update()->void:
	if not is_instance_valid(ui):return
	var view:Dictionary=app.core.view;var data:Dictionary=view.get("littoral",{})
	if is_instance_valid(autonomy_button):
		var autonomy:Dictionary=data.get("autonomy",{})
		autonomy_button.text=("接管指挥" if app.running else "开始托管" if float(view.get("tick",0))<.001 else "继续托管") if bool(autonomy.get("enabled",false)) else "一键托管"
		autonomy_button.disabled=replay_mode or view.get("result")!=null
		autonomy_button.tooltip_text=str(autonomy.get("status","指挥各连投送、搜索、战斗与撤收，并调度舰载机和有限舰炮；拖动单位随时接管"))
	if naval_controller!=null:
		naval_controller.replay_mode=replay_mode;naval_controller.update();ship_id=naval_controller.ship_id;fleet_id=naval_controller.fleet_id
		if primary_map=="land":
			for node in naval_nodes:
				if is_instance_valid(node):node.visible=false
	_follow_tutorial_unit()
	app.sea.playback_rate=float(app.speed);app.sea.playing=app.running;app.sea.observe(view);app.sea.motion_strength=app.battle_motion_strength
	var land_view:Dictionary=data.get("land",{}).duplicate();land_view["shells"]=view.get("shells",[]);land_view["impacts"]=data.get("impacts",[]);land_view["tick"]=view.get("tick",0);land_view["groups"]=data.get("groups",[]);land_view["shots"]=data.get("shots",[]);land_view["transports"]=data.get("transports",[])
	if _world_naval():land_view["corpses"]=data.get("corpses",[]);land_view["persistent_corpses"]=true;land_view["seed"]=data.get("seed",view.get("seed",0))
	land_view["projectiles"]=data.get("projectiles",[])
	if str(view.get("island_war",{}).get("version","")) in ["cas-island-war-v2","cas-island-war-v3","cas-island-war-v4","cas-island-war-coastal-v1"]:
		land_view["art_version"]="tactical-art-v2";land_view["deployables"]=view.get("island_war",{}).get("deployables",[])
		land_view["weather"]=view.get("weather",{}) if view.get("weather",{}) is Dictionary else {}
		land_view.weather=land_view.weather.duplicate(true)
		if not land_view.weather.has("night_amount"):land_view.weather["night_amount"]=.88 if str(view.get("environment",{}).get("light","day"))=="night" else 0.0
		if str(view.island_war.version) in ["cas-island-war-v3","cas-island-war-v4","cas-island-war-coastal-v1"]:land_view["equipment_version"]="tactical-vehicles-v4" if str(view.island_war.version) in ["cas-island-war-v4","cas-island-war-coastal-v1"] else "tactical-vehicles-v3"
	land_view["transports"]=data.get("transports",[])
	var land=ui.get_node("LandWindow/Map");land.actor_commands_enabled=not replay_mode;land.selected_unit=selected_unit;land.playback_rate=float(app.speed);land.motion_strength=app.battle_motion_strength;land.observe(land_view,app.running)
	ui.get_node("Top/Clock").text="%02d:%02d"%[int(view.get("tick",0))/60,int(view.get("tick",0))%60]
	ui.get_node("Top/Status").text=("已暂停" if not app.running else str({"embarked":"运输编队待命","landing":"部队正在投送","ground":"岸上行动","extracting":"撤收与返航","finished":"行动结束"}.get(str(data.get("phase","")),"海陆协同")))+" · %d×"%app.speed
	ui.get_node("Top/Pause").text="暂停" if app.running else "继续"
	for multiplier in [1,2,4,8]:ui.get_node("Top/Speeds/Speed%d"%multiplier).set_pressed_no_signal(app.speed==multiplier)
	var signature:String=str(hash([primary_map,selected_unit,_selected_naval_id(),context_action,_return_available(),data.get("groups",[]).map(func(row):return {"id":row.id,"stage":row.get("stage","")}),data.get("support",{}).get("naval",[]).map(func(row):return [row.ship,row.get("aim_target")!=null]),_legacy_helicopters(data).map(func(row):return [row.unit_id,row.get("available",false)]),view.get("ships",[]).map(func(row):return row.id)]))
	signature+=str(hash(CarrierDesk.signature(self)))
	signature+=str(hash(VehicleControls.signature(self)))
	if signature!=roster_signature:_roster(data);roster_signature=signature
	_refresh_cards(data)
	if is_instance_valid(coastal_commands):coastal_commands.refresh()
	CarrierDesk.Simple.update(self)
	if has_meta("carrier_training"):get_meta("carrier_training").observe(view)
	var objectives:Array[String]=[]
	for objective in data.get("objectives",[]):
		if not bool(objective.get("complete",false)):objectives.append(str(objective.get("name",{"capture_hq":"占领敌方指挥部","hold_hq":"守住联络中枢","search_ruin":"搜索遗迹"}.get(str(objective.get("kind","")),"完成当前目标"))))
	ui.get_node("Objective").text=" / ".join(objectives.slice(0,1)) if not objectives.is_empty() else "部队回舰后驶入返航水域"
	var group:Dictionary=_group();ui.get_node("Selected").text=str(group.get("name",selected_unit))
	var support:Dictionary=_naval_support(_selected_naval_id());ui.get_node("Actions/Naval").text="取消炮援" if support.get("pending_target")!=null else "近岸炮援"
	_update_tutorial_targets()
	if tutorial!=null and not restoring_ui:
		if tutorial.has_method("observe_focus"):tutorial.observe_focus(primary_map)
		tutorial.observe_state(view)
	_restore_idle_hint()
	if bool(view.get("island_war",{}).get("exercise",false)) and not ui.get_node("Hint").text.begins_with("无损演习"):
		ui.get_node("Hint").text="无损演习 · "+ui.get_node("Hint").text
	if app.audio!=null:app.audio.ingest_events(view.get("events",[]),view.get("ships",[]),view.get("contacts",[]),not replay_mode,int(view.get("tick",0)))
func _portrait(id:String,card:Dictionary)->Texture2D:
	var cell:Dictionary=TacticalFrames.frame(id,"idle",0) if TacticalFrames.available(id) else {}
	if not cell.is_empty():
		var source:Texture2D=TacticalFrames.texture(str(cell.get("source","")))
		if source!=null:
			var region:Array=cell.rect;var sprite:=AtlasTexture.new();sprite.atlas=source;sprite.region=Rect2(float(region[0]),float(region[1]),float(region[2]),float(region[3]));sprite.filter_clip=true;return sprite
	var sheet:String=str(card.get("sprite_sheet",""))
	if not sheet.is_empty() and ResourceLoader.exists(sheet):
		var texture:Texture2D=load(sheet);var atlas:=AtlasTexture.new();atlas.atlas=texture;atlas.region=Rect2(0,0,texture.get_width()/4,texture.get_height()/3);atlas.filter_clip=true;return atlas
	return load("res://scripts/story_actor_layout.gd").portrait(Art.texture(str(card.get("portrait",""))),id)
func _tactical_card(id:String)->Dictionary:
	if app.get("home")==null:return {}
	if str(app.core.view.get("island_war",{}).get("version","")) in ["cas-island-war-v4","cas-island-war-coastal-v1"] and app.home.has_method("v4_unit"):return app.home.v4_unit(id)
	if str(app.core.view.get("island_war",{}).get("version",""))=="cas-island-war-v3" and app.home.has_method("v3_unit"):return app.home.v3_unit(id)
	if str(app.core.view.get("island_war",{}).get("version",""))=="cas-island-war-v2" and app.home.has_method("v2_unit"):return app.home.v2_unit(id)
	return app.home.unit(id)
func _roster(data:Dictionary)->void:
	var row:HBoxContainer=ui.get_node("Tray/Scroll/Cards")
	for node in row.get_children():row.remove_child(node);node.queue_free()
	for group in data.get("groups",[]):
		var id:String=str(group.id)
		if selected_unit.is_empty():selected_unit=id
		var identity:String=str(group.get("unit_id",id));var card:Dictionary=_tactical_card(identity)
		var payload:Dictionary={"kind":"unit","unit_id":identity,"role":str(card.get("role","infantry")),"designation":str(card.get("designation","")),"formation_echelon":str(card.get("formation_echelon","")),"selected":selected_unit==id,"name":str(card.get("codename",group.get("name",id))),"texture":_portrait(identity,card)}
		if str(data.get("company_layout",""))=="multi-company-v1":
			var sisters:Array=data.get("groups",[]).filter(func(other):return str(other.get("unit_id",other.id))==identity);var ordinal:int=sisters.find(group)
			payload["company_id"]=id;payload["company_name"]=str(group.get("company_name",""));payload["company_caption"]="%s连 %d/%d · %d人"%[["一","二","三","四","五"][clampi(ordinal,0,4)],ordinal+1,sisters.size(),int(group.get("personnel_count",0))]
		var surviving_vehicle:Dictionary=VehicleControls.orphan(self,id)
		if not surviving_vehicle.is_empty():
			payload["kind"]="vehicle";payload["vehicle_id"]=int(surviving_vehicle.id);payload["texture"]=VehicleControls.icon(surviving_vehicle)
			payload["name"]=str(card.get("codename",group.get("name",id)))+" · "+str(VehicleControls.NAMES.get(str(surviving_vehicle.get("vehicle_kind","")),"载具"))
			payload["company_caption"]=str(group.get("company_name",""))+" · 步兵全损"
		_add_card(payload,row)
	if _world_naval() and CarrierDesk.active(self):CarrierDesk.cards(self,row)
	elif _world_naval():
		for squadron in data.get("aviation",{}).get("squadrons",[]):
			var identity:String=str(squadron.get("carrier_identity",""));var card:Dictionary=app.cards.get(identity,{})
			_add_card({"kind":"squadron","unit_id":str(squadron.id),"squadron_id":str(squadron.id),"air_role":str(squadron.get("role","")),"name":_carrier_caption(squadron)+" · "+AircraftArt.display_name(str(squadron.get("visual_type",squadron.get("name","航空中队")))),"texture":_portrait(identity,card)},row)
	if primary_map=="sea" and _return_available():
		var identity:String=_identity(selected_unit);var card:Dictionary=_tactical_card(identity);_add_card({"kind":"return","unit_id":selected_unit,"name":"全队返航","texture":_portrait(identity,card)},row)
	if primary_map=="land":
		for ship in app.core.view.get("ships",[]):
			if int(ship.id)!=_selected_naval_id() or not _has_naval_gun(ship):continue
			if str(data.get("version","")) in DRAG_VERSIONS and _naval_support(int(ship.id)).get("aim_target")==null:continue
			var card:Dictionary=app.cards.get(str(ship.get("characterId","")),{})
			_add_card({"kind":"naval","ship":int(ship.id),"name":"舰炮 · "+str(ship.get("name","支援")),"texture":_portrait(str(ship.get("characterId","")),card)},row)
		var group:Dictionary=_group();var identity:String=_identity(selected_unit);var card:Dictionary=_tactical_card(identity)
		if str(group.get("stage",""))=="ground" and not _coastal_controls():
			var withdrawal:bool=context_action=="withdraw" or (tutorial!=null and tutorial.active and tutorial.current_step()=="withdraw")
			var air_available:bool=false
			for air in _legacy_helicopters(data):
				if _row_company(air)==selected_unit and bool(air.get("available",false)):air_available=true;break
			var context:Dictionary=_company_fields(selected_unit);context["texture"]=_portrait(identity,card)
			if group.get("ability") is Dictionary and not withdrawal and context_action!="air":context["kind"]="ability";context["name"]=str(group.ability.get("name","战术专长"))
			elif air_available and not withdrawal:context["kind"]="air";context["name"]="旋翼支援"
			else:context["kind"]="withdraw";context["name"]="撤收 · "+str(card.get("codename",identity))
			_add_card(context,row)
	VehicleControls.cards(self,row)
func _legacy_helicopters(data:Dictionary)->Array:
	var value:Variant=data.get("support",{}).get("helicopter",[])
	return value if value is Array else []
func _add_card(payload:Dictionary,row:HBoxContainer)->void:
	var card=PanelContainer.new();card.set_script(DragCard);card.name=("Unit_"+_payload_company(payload)) if payload.kind=="unit" else ("Naval_%d"%int(payload.ship)) if payload.kind=="naval" else str(payload.kind).capitalize()+"_"+_payload_company(payload)
	card.custom_minimum_size=Vector2(188 if payload.kind in ["unit","vehicle"] and not str(payload.get("designation","")).is_empty() else 132,140);row.add_child(card);card.configure(payload,"待命");card.armed.connect(_arm)
func _refresh_cards(data:Dictionary)->void:
	var reload_states:Dictionary=load("res://scripts/tactical_weapon_badge_v3.gd").reload_status(data)
	for card in ui.get_node("Tray/Scroll/Cards").get_children():
		var p:Dictionary=card.payload;var status:String="待命";var allowed:bool=true
		if str(p.kind)=="unit":
			var group:Dictionary={}
			for candidate in data.get("groups",[]):
				if str(candidate.id)==_payload_company(p):group=candidate;break
			var stage:String=str(group.get("stage",""));status=str({"embarked":"拖向岛屿登陆","transit":"实际运输中","ground":"拖动下达指令","returning":"返回载舰","recovered":"已安全归队","lost":"身体已失去战力"}.get(stage,"待命"));allowed=stage in ["embarked","ground"]
			if p.has("company_id"):status=str({"embarked":"待登陆","transit":"投送中","ground":"岸上待命","returning":"撤回中","recovered":"已归队","lost":"失去战力"}.get(stage,"待命"))
			if group.get("pending_deploy") is Dictionary:status="载舰正在接近";allowed=true
			elif stage=="ground" and reload_states.has(_payload_company(p)):status=str(reload_states[_payload_company(p)])
			if stage=="ground":
				var seated:String=VehicleControls.unit_status(self,_payload_company(p))
				if not seated.is_empty():status=seated
		elif str(p.kind)=="naval":
			var support:Dictionary=_naval_support(int(p.ship));status=str({"turning":"实际调整炮位","ready":"炮位已就绪","out_of_range":"超出真实炮程","no_ammo":"炮弹已用尽"}.get(str(support.get("aim_state","")),"拖向落点炮援"));allowed=bool(support.get("alive",false)) and float(support.get("ammo",0))>0
			if float(support.get("ready_in",0))>0:status="装填 %.0f秒"%ceil(float(support.ready_in))
		elif str(p.kind)=="air":status="拖向落点支援"
		elif str(p.kind)=="squadron":
			for squadron in data.get("aviation",{}).get("squadrons",[]):
				if str(squadron.id)!=str(p.squadron_id):continue
				status="可出击 %d · 在空 %d"%[int(squadron.get("available",0)),int(squadron.get("airborne",0))];allowed=int(squadron.get("available",0))>0
				if not allowed:status=str(squadron.get("reason","甲板整备中"))
				if data.has("carrier_ops"):
					allowed=int(squadron.get("total",0))>int(squadron.get("lost",0))
					if squadron.get("reason")!=null:status=str(squadron.reason)+" · 可排队/召回"
					for order in data.get("carrier_ops",{}).get("queue",[]):
						if str(order.get("squadron_id",""))==str(squadron.id):status="已待命 · 拖动修改/召回";break
		elif str(p.kind)=="withdraw":status="拖回本人所在位置"
		elif str(p.kind)=="return":status="拖到返航圈结束" if _inside_exit() else "拖向返航圈 · 全队回港"
		elif str(p.kind)=="ability":
			var ability:Dictionary=_group().get("ability",{});status="拖向落点 · 余%d次"%int(ability.get("charges",0));allowed=bool(ability.get("available",false))
			if float(ability.get("ready_in",0))>0:status="冷却 %.0f秒"%ceil(float(ability.ready_in))
			elif int(ability.get("charges",0))<=0:status="本次行动次数已用尽"
		if CarrierDesk.active(self) and str(p.kind) in ["wing","flight","squadron","aviation_support"]:
			var aviation_status:Dictionary=CarrierDesk.status(self,p)
			if not aviation_status.is_empty():status=str(aviation_status.text);allowed=bool(aviation_status.allowed)
		var vehicle_status:Dictionary=VehicleControls.status(self,p)
		if not vehicle_status.is_empty():status=str(vehicle_status.text);allowed=bool(vehicle_status.allowed)
		p["reason"]=status;card.configure(p,status,allowed and not replay_mode)

func _arm(payload:Dictionary,point:Vector2,pointer:int=-1)->void:
	if replay_mode:_hint("回放只读 · 可切换海陆视角");return
	drag_layer.arm(payload,point,pointer)
func _arm_map_actor(body:Dictionary,point:Vector2,pointer:int)->void:
	if replay_mode:return
	if _coastal_controls() and not coastal_pending.is_empty():
		var confirmation:Dictionary=coastal_pending.duplicate();confirmation["confirm_point"]=point
		drag_layer.arm(confirmation,point,pointer);return
	var company:String=_row_company(body);var identity:String=str(body.get("unit_id",_identity(company)))
	var card:Dictionary=_tactical_card(identity);var payload:Dictionary=_company_fields(company)
	payload["kind"]="vehicle" if not str(body.get("vehicle_kind","")).is_empty() else "unit"
	payload["name"]=str(card.get("codename",card.get("name",identity)))
	payload["texture"]=VehicleControls.icon(body) if payload.kind=="vehicle" else _portrait(identity,card)
	payload["map_origin"]=true
	if payload.kind=="vehicle":payload["vehicle_id"]=int(body.id)
	drag_layer.arm(payload,point,pointer)
func _card_clicked(payload:Dictionary)->void:
	if _coastal_controls() and payload.get("confirm_point") is Vector2:_drag_drop(payload,payload.confirm_point);update();return
	if _coastal_controls() and payload.has("context"):_coastal_context_click(payload);return
	if bool(payload.get("map_origin",false)):
		selected_unit=_payload_company(payload);selected_vehicle_id=int(payload.get("vehicle_id",0));context_action="";coastal_pending.clear();roster_signature="";update();_save_ui_deferred();return
	if CarrierDesk.clicked(self,payload):return
	if str(payload.get("kind","")) in ["vehicle","vehicle_unload"]:
		selected_unit=_payload_company(payload)
		selected_vehicle_id=int(payload.get("vehicle_id",0))
		var vehicle:Dictionary=VehicleControls.find(self,int(payload.get("vehicle_id",-1)))
		roster_signature="";update();_save_ui_deferred()
		_hint("载具独立存活，可继续拖动移动或攻击。" if not VehicleControls.orphan(self,selected_unit).is_empty() else "坦克与步枪手分别拖动，可以协同移动或攻击。" if int(vehicle.get("capacity",0))<=0 else "拖动载具卡独立移动或攻击；拖动身体卡到本连载具可以登载。");return
	if str(payload.get("kind",""))=="unit":
		selected_vehicle_id=0
		var id:String=_payload_company(payload)
		if _coastal_controls():selected_unit=id;coastal_pending.clear();context_action="";roster_signature="";update();_save_ui_deferred()
		elif selected_unit==id:open_unit_menu(id)
		else:selected_unit=id;context_action="";update();_hint("拖动这张部队卡下达指令 · 再点一次查看情境操作");_save_ui_deferred()
	elif str(payload.get("kind",""))=="naval":open_naval_menu()
	elif str(payload.get("kind",""))=="squadron":open_squadron_menu(str(payload.squadron_id))
	elif payload.has("ship"):ship_id=int(payload.ship);app.sea.selected_ship=ship_id;update()
func _drag_started(payload:Dictionary,point:Vector2)->void:
	coastal_pending.clear()
	selected_vehicle_id=int(payload.get("vehicle_id",0))
	if payload.has("unit_id") and str(payload.get("kind","")) not in ["squadron","flight","wing","aviation_support"]:selected_unit=_payload_company(payload)
	if naval_controller!=null and payload.has("ship"):
		for ship in app.core.view.get("ships",[]):
			if int(ship.id)==int(payload.ship):naval_controller.select("ship",ship);break
	last_hover_msec=0;_drag_hover(payload,point)
func _coastal_cancel_command(announce:bool=true)->void:
	coastal_pending.clear()
	if drag_layer!=null and not drag_layer.payload.is_empty():drag_layer.cancel()
	if is_instance_valid(coastal_commands):coastal_commands.refresh()
	if announce:_hint("已取消 · 没有发出指令");_emit("command_cancelled",{"accepted":true})
func _coastal_context_click(payload:Dictionary)->void:
	var context:String=str(payload.get("context",""));var vehicle:Dictionary=VehicleControls.find(self,int(payload.get("vehicle_id",0)))
	coastal_pending.clear()
	if context in ["select_body","select_vehicle"]:
		selected_vehicle_id=int(payload.get("vehicle_id",0)) if context=="select_vehicle" else 0
		roster_signature="";update();_save_ui_deferred();return
	if context=="more":
		var layer:Control=app.open_modal("所选连队")
		app.button(layer,"原地待命",420,300,760,64,func():app.close_modal();_coastal_hold())
		app.button(layer,"撤回载舰",420,390,760,64,func():app.close_modal();_coastal_withdraw())
		app.button(layer,"继续指挥",420,500,760,64,app.close_modal);return
	if context=="embark":
		_coastal_immediate(payload,Vector2(float(vehicle.get("x",0)),float(vehicle.get("y",0))));return
	if context=="ability" and _coastal_self_skill():
		var position:Dictionary=_group().get("position",{})
		_coastal_immediate(payload,Vector2(float(position.get("x",0)),float(position.get("y",0))));return
	coastal_pending=payload.duplicate();update();_hint(str(payload.get("name","操作"))+" · 点击地图确认，或拖动按钮到落点；可随时取消")
func _coastal_immediate(payload:Dictionary,point:Vector2)->void:
	var preview:Dictionary=_preview(payload,{"valid":true,"world":point,"hit":{}})
	if not bool(preview.get("valid",false)):_error_hint(str(preview.get("reason","当前无法使用")));return
	var plan:Dictionary=VehicleControls.plan(self,payload,{"world":point,"hit":{}})
	var command:Dictionary=plan.get("command",{})
	if str(payload.get("kind",""))=="ability":command=_scope_command({"op":"littoral_ability","x":point.x,"y":point.y},_payload_company(payload))
	if command.is_empty():return
	var response:Dictionary=app.issue(command)
	if bool(response.get("ok",false)):
		app.running=true;_hint(str(preview.get("reason","指令已接收")));_emit(str(plan.get("event","ability_ordered")),{"accepted":true,"command":command,"response":response})
	else:_error_hint(str(response.get("error","指令未被接受")))
	update();_save_ui_deferred()
func _coastal_hold()->void:
	var vehicle:Dictionary=VehicleControls.find(self,selected_vehicle_id)
	if not vehicle.is_empty():
		var payload:Dictionary=_company_fields(selected_unit);payload.merge({"kind":"vehicle","vehicle_id":selected_vehicle_id,"vehicle_action":"move"},true)
		_coastal_immediate(payload,Vector2(float(vehicle.x),float(vehicle.y)))
	else:_unit_order("hold");update()
func _coastal_withdraw()->void:
	var response:Dictionary=app.issue(_scope_command({"op":"littoral_order","action":"retreat"},selected_unit))
	if bool(response.get("ok",false)):app.running=true;_hint("连队与独立载具开始真实撤收");_emit("withdraw_ordered",{"accepted":true,"company_id":selected_unit})
	else:_error_hint(str(response.get("error","当前无法撤收")))
	update();_save_ui_deferred()
func _begin_map_pinch(first_pointer:int,first_point:Vector2,second_pointer:int,second_point:Vector2)->void:
	var map=ui.get_node("LandWindow/Map")
	var inverse:Transform2D=map.get_global_transform().affine_inverse()
	var first:Vector2=inverse*first_point;var second:Vector2=inverse*second_point
	map.actor_pointer_armed=false
	map.camera_touch_points={first_pointer:first,second_pointer:second}
	map.camera_gesture=true;map.camera_pointer_dragged=true
	map.camera_pinch_distance=first.distance_to(second);map.camera_pinch_center=(first+second)*.5
func _drop_location(point:Vector2)->Dictionary:
	if ui.get_node("MiniMap").get_global_rect().has_point(point):return {"valid":false,"reason":"先点小地图切换，再把卡拖到主图"}
	var map:Control=ui.get_node("SeaWindow/Map" if primary_map=="sea" else "LandWindow/Map")
	if not map.get_global_rect().has_point(point):return {"valid":false,"reason":"拖到主地图上，松手下达指令"}
	var local:Vector2=map.get_global_transform().affine_inverse()*point
	var world:Vector2=map.unproject(local)
	var hit:Dictionary=map.target_at(local) if primary_map=="land" or _world_naval() else {}
	# Visual body spacing and a tall SD's head are not authoritative terrain.
	# A hit on a public target always orders its actual observed position.
	var observed:Dictionary=hit.get("row",{})
	if observed.has("x") and observed.has("y"):world=Vector2(float(observed.x),float(observed.y))
	return {"valid":true,"world":world,"hit":hit,"map":map}
func _island_contains(world:Vector2)->bool:
	for island in app.core.view.get("islands",[]):
		var raw:Variant=island.get("polygon",[]) if island is Dictionary else island
		var polygon:PackedVector2Array=[]
		for point in raw:
			if point is Dictionary:polygon.append(Vector2(float(point.x),float(point.y)))
		if polygon.size()>2 and Geometry2D.is_point_in_polygon(world,polygon):return true
	return false
func _ground_blocked(world:Vector2)->bool:
	for obstacle in app.core.view.get("littoral",{}).get("land",{}).get("obstacles",[]):
		var raw:Variant=obstacle.get("polygon",[]) if obstacle is Dictionary else obstacle
		var polygon:PackedVector2Array=[]
		for point in raw:
			if point is Dictionary:polygon.append(Vector2(float(point.get("x",0)),float(point.get("y",0))))
		if polygon.size()>2 and Geometry2D.is_point_in_polygon(world,polygon):return true
	return false
func _preview(payload:Dictionary,location:Dictionary)->Dictionary:
	if not bool(location.get("valid",false)):return {"valid":false,"reason":str(location.reason)}
	if _coastal_controls() and str(payload.get("context",""))=="more":return {"valid":false,"reason":"点按更多，选择待命或撤收"}
	var world:Vector2=location.world;var kind:String=str(payload.get("kind",""))
	var vehicle_preview:Dictionary=VehicleControls.preview(self,payload,location)
	if not vehicle_preview.is_empty():return vehicle_preview
	if kind=="aviation_support":
		var response:Dictionary=app.core.request(CarrierDesk.request(self,payload,location,true))
		return response.get("data",{}) if bool(response.get("ok",false)) else {"valid":false,"reason":str(response.get("error","目标不可用"))}
	if kind=="squadron":
		var response:Dictionary=app.core.request(_air_order(payload,location,true))
		var result:Dictionary=response.get("data",{})
		if not response.get("ok",false):return {"valid":false,"reason":str(response.get("error","航空落点不可用"))}
		if bool(result.get("valid",false)):
			result["reason"]="松手下达航空任务 · 实际起飞、飞行和返航"
			if CarrierDesk.active(self):result["reason"]="松手取消待命并召回 · 等待实际返舰" if str(_air_order(payload,location,false).action)=="return" else "松手安排下一波 · 甲板或飞机忙时等待；改当前任务请拖在空卡"
		return result
	if kind in ["flight","wing"]:
		var response:Dictionary=app.core.request(CarrierDesk.request(self,payload,location,true));var result:Dictionary=response.get("data",{})
		if not bool(response.get("ok",false)):return {"valid":false,"reason":str(response.get("error","航空落点不可用"))}
		if bool(result.get("valid",false)):result["reason"]="松手召回联队 · 等待实际返舰" if kind=="wing" else "松手改变当前在空任务 · 燃油和武器不重置"
		return result
	if kind=="unit":
		var group:Dictionary={}
		for row in app.core.view.littoral.get("groups",[]):
			if str(row.id)==_payload_company(payload):group=row;break
		var stage:String=str(group.get("stage",""))
		if stage=="embarked":
			if not _island_contains(world):return {"valid":false,"reason":"将部队拖到岛上；载舰会驶近合法滩头"}
			if str(app.core.view.get("littoral",{}).get("version","")) in DRAG_VERSIONS:
				var response:Dictionary=app.core.request(_scope_command({"op":"littoral_preview","kind":"deploy","x":world.x,"y":world.y,"insertion":"landing"},_payload_company(payload)))
				var value:Dictionary=response.get("data",{});return value if response.get("ok",false) else {"valid":false,"reason":str(response.get("error","无法选择滩头"))}
			return {"valid":false,"reason":"旧航次保留原规则 · 点部队卡后选择就近登陆"}
		if stage!="ground":return {"valid":false,"reason":str({"transit":"仍在真实投送途中","returning":"正在返回载舰","recovered":"这支部队已安全归队","lost":"身体已失去战力"}.get(stage,"部队尚未就绪"))}
		if primary_map!="land":return {"valid":false,"reason":"点击右上陆图，再拖动部队安排岸上行动"}
		if not _island_contains(world):return {"valid":false,"reason":"落点必须在真实陆地范围内"}
		if location.get("hit",{}).is_empty() and _ground_blocked(world):return {"valid":false,"reason":"这里是实际楼体或岩石 · 请拖到道路、坡道或空地"}
		return {"valid":true,"reason":"松手攻击这个位置的敌人" if str(payload.get("unit_action",""))=="attack" else "松手移动到这里" if str(payload.get("unit_action",""))=="move" else _order_description(location.get("hit",{}))}
	if kind in ["ship","naval"]:
		if not _island_contains(world):
			if kind=="ship" and str(app.core.view.get("littoral",{}).get("version","")) in ["cas-littoral-v3","cas-littoral-v4","cas-littoral-coastal-v1"]:
				var movement:Dictionary=app.core.request({"op":"littoral_preview","kind":"ship_move","ship":int(payload.ship),"x":world.x,"y":world.y})
				var route:Dictionary=movement.get("data",{})
				if not movement.get("ok",false):return {"valid":false,"reason":str(movement.get("error","当前航路不可用"))}
				if bool(route.get("valid",false)):route["reason"]="松手沿实际水路驶近 · 进入交战距离"
				return route
			return {"valid":false,"reason":"将舰艇或舰炮卡拖到岛上落点"}
		if str(app.core.view.get("littoral",{}).get("version","")) in DRAG_VERSIONS:
			var response:Dictionary=app.core.request({"op":"littoral_preview","kind":"aim_land","ship":int(payload.ship),"x":world.x,"y":world.y})
			if not response.get("ok",false):return {"valid":false,"reason":str(response.get("error","当前无法支援"))}
			var value:Dictionary=response.get("data",{});value["reason"]="松手指定炮向 · 实际转向到射界" if bool(value.get("valid",false)) and kind=="ship" else "松手排定炮援 · 等待真实转向和装填" if bool(value.get("valid",false)) else str(value.get("reason","无法支援"));return value
		if kind=="ship":return {"valid":false,"reason":"旧航次保留原炮向规则 · 请切陆图使用舰炮支援卡"}
		var support:Dictionary=_naval_support(int(payload.ship));var ship:Dictionary={}
		for row in app.core.view.ships:
			if int(row.id)==int(payload.ship):ship=row;break
		if not bool(support.get("alive",false)) or float(support.get("ammo",0))<=0:return {"valid":false,"reason":"这艘舰艇已无法提供炮援"}
		if Vector2(float(ship.get("x",0)),float(ship.get("y",0))).distance_to(world)>float(support.get("range",0)):return {"valid":false,"reason":"超出真实炮程 · 请先在海图驶近"}
		return {"valid":true,"reason":"松手指定炮向 · 转到射界后可支援" if kind=="ship" else "松手排定炮援 · 实际转向并等待装填"}
	if kind=="air":return {"valid":primary_map=="land","reason":"松手发出真实直升机支援" if primary_map=="land" else "请切换陆图指定支援落点"}
	if kind=="withdraw":
		if primary_map!="land":return {"valid":false,"reason":"先切换陆图，再把撤收卡拖回本人位置"}
		var hit:Dictionary=location.get("hit",{});var same_unit:bool=_row_company(hit.get("row",{}))==_payload_company(payload)
		for row in app.core.view.littoral.get("groups",[]):
			if str(row.id)!=_payload_company(payload) or str(row.get("stage",""))!="ground":continue
			var point:Dictionary=row.get("position",{})
			if same_unit or (not point.is_empty() and world.distance_to(Vector2(float(point.x),float(point.y)))<550):return {"valid":true,"reason":"松手撤回载舰 · 部队真实返回登船"}
		return {"valid":false,"reason":"将撤收卡拖回这支部队本人所在位置"}
	if kind=="ability":
		var group:Dictionary=_group();var ability:Dictionary=group.get("ability",{})
		if primary_map!="land" or str(group.get("stage",""))!="ground":return {"valid":false,"reason":"部队上岸后，在陆图使用专长"}
		if VehicleControls.active(self):
			var command:Dictionary=_scope_command({"op":"littoral_ability_preview","x":world.x,"y":world.y},_payload_company(payload))
			var response:Dictionary=app.core.request(command)
			if not response.get("ok",false):return {"valid":false,"reason":str(response.get("error","专长落点当前不可用"))}
			var native_preview:Dictionary=response.get("data",{}).duplicate()
			if bool(native_preview.get("valid",false)):native_preview["reason"]="松手使用 · "+str(ability.get("name","战术专长"))
			return native_preview
		if not bool(ability.get("available",false)):return {"valid":false,"reason":"专长尚在冷却" if float(ability.get("ready_in",0))>0 else "本次行动的专长次数已用尽"}
		if not _island_contains(world):return {"valid":false,"reason":"将专长拖到真实陆地落点"}
		var p:Dictionary=group.get("position",{});var range:float=float(ability.get("range",0))
		if range>0 and Vector2(float(p.get("x",0)),float(p.get("y",0))).distance_to(world)>range:return {"valid":false,"reason":"超出这支部队专长的真实作用距离"}
		return {"valid":true,"reason":"松手使用 · "+str(ability.get("name","战术专长"))+("（强化本人）" if range<=0 else "")}
	if kind=="return":
		if primary_map!="sea" or not _return_available():return {"valid":false,"reason":"岸上部队实际回舰后，切回海图安排返航"}
		var exit:Dictionary=app.core.view.littoral.get("exit",{})
		if world.distance_to(Vector2(float(exit.get("x",0)),float(exit.get("y",0))))>float(exit.get("radius",0)):return {"valid":false,"reason":"将返航卡拖进海图的返航圈"}
		return {"valid":true,"reason":"松手完成真实撤离" if _inside_exit() else "松手驶往返航圈 · 抵达后可撤离"}
	return {"valid":false,"reason":"未知拖动指令"}
func _order_description(hit:Dictionary)->String:
	if str(hit.get("kind",""))=="ruins":return "松手搜索这处遗迹"
	if str(hit.get("kind","")) in ["entities","buildings"] and str(hit.get("row",{}).get("side","axis"))!="allies":return "松手攻击这个真实目标"
	if str(hit.get("kind",""))=="buildings":return "松手接近己方设施" if VehicleControls.active(self) else "松手接近己方设施 · 工兵可维修"
	return "松手移动到这里"
func _drag_hover(payload:Dictionary,point:Vector2)->void:
	if bool(payload.get("map_origin",false)) and primary_map=="land" and drag_layer.pointer>=0:
		var map=ui.get_node("LandWindow/Map")
		if map.actor_pointer_armed:map.camera_touch_points[drag_layer.pointer]=map.get_global_transform().affine_inverse()*point
	var now:int=Time.get_ticks_msec()
	if now-last_hover_msec<90:return
	last_hover_msec=now;var location:Dictionary=_drop_location(point);hover_preview=_preview(payload,location)
	_hint(str(hover_preview.get("reason","松手确认")))
	if not bool(location.get("valid",false)):return
	var world:Vector2=location.world;app.sea.show_drag_target=primary_map=="sea";app.sea.drag_point=world;app.sea.drag_preview=hover_preview;app.sea.queue_redraw()
	var land=ui.get_node("LandWindow/Map");land.show_drag_target=primary_map=="land";land.drag_point=world;land.drag_valid=bool(hover_preview.get("valid",false));land.queue_redraw()
func _clear_drag()->void:
	app.sea.show_drag_target=false;app.sea.queue_redraw()
	if is_instance_valid(ui):
		var map=ui.get_node("LandWindow/Map")
		if map.actor_pointer_armed:map.camera_touch_points.clear()
		map.show_drag_target=false;map.actor_pointer_armed=false;map.camera_pointer_down=false;map.queue_redraw()
	if is_instance_valid(coastal_commands):coastal_commands.refresh()
	_restore_idle_hint()
func _drag_drop(payload:Dictionary,point:Vector2)->void:
	var location:Dictionary=_drop_location(point);var preview:Dictionary=_preview(payload,location)
	if not bool(preview.get("valid",false)):
		_error_hint(str(preview.get("reason","无法在这里下达指令")));_emit("drag_rejected",{"accepted":false,"reason":str(preview.get("reason",""))});return
	var world:Vector2=location.world;var kind:String=str(payload.get("kind",""));var command:Dictionary={};var event:String=""
	var vehicle_plan:Dictionary=VehicleControls.plan(self,payload,location)
	if not vehicle_plan.is_empty():command=vehicle_plan.command;event=str(vehicle_plan.event)
	elif kind=="squadron":command=_air_order(payload,location,false);event="squadron_ordered"
	elif kind in ["flight","wing","aviation_support"]:command=CarrierDesk.request(self,payload,location,false);event="carrier_flight_ordered"
	elif kind=="unit":
		selected_unit=_payload_company(payload);var group:Dictionary=_group()
		if str(group.get("stage",""))=="embarked":command={"op":"littoral_deploy","unit_id":selected_unit,"x":world.x,"y":world.y,"insertion":"landing","queue":true};event="deploy_queued"
		else:
			var hit:Dictionary=location.get("hit",{});var action:String=str(payload.get("unit_action",""))
			if action.is_empty():
				action="move"
				if str(hit.get("kind",""))=="ruins":action="search"
				elif str(hit.get("kind","")) in ["entities","buildings"] and str(hit.get("row",{}).get("side","axis"))!="allies":action="attack"
				elif str(hit.get("kind",""))=="buildings" and str(_tactical_card(_identity(selected_unit)).get("role",""))=="engineer" and not VehicleControls.active(self):action="repair"
			if action in ["attack","search","repair"] and hit.get("row") is Dictionary:world=Vector2(float(hit.row.get("x",world.x)),float(hit.row.get("y",world.y)))
			command={"op":"littoral_order","unit_id":selected_unit,"action":action}
			if action in ["move","attack","defend"]:command["x"]=world.x;command["y"]=world.y
			if hit.has("id"):command["target"]=hit.id
			event="unit_ordered"
	elif kind=="ship":
		var action:String="aim_land" if _island_contains(world) else "move"
		command={"op":"littoral_ship_order","ship":int(payload.ship),"action":action,"x":world.x,"y":world.y};event="naval_aimed" if action=="aim_land" else "ship_moved"
		if action=="move":command["speed"]=25
	elif kind=="naval":
		if str(app.core.view.get("littoral",{}).get("version","")) not in DRAG_VERSIONS:_queue_naval(world);return
		ship_id=int(payload.ship);app.sea.selected_ship=ship_id
		if naval_controller!=null:naval_controller.ship_id=ship_id
		var aimed:Dictionary=app.issue({"op":"littoral_ship_order","ship":ship_id,"action":"aim_land","x":world.x,"y":world.y})
		if not aimed.get("ok",false):_hint(str(aimed.get("error","无法调整炮向")));return
		command={"op":"littoral_support","kind":"naval","ship":ship_id,"x":world.x,"y":world.y,"queue":true};event="naval_support_queued"
	elif kind=="air":command={"op":"littoral_support","kind":"helicopter","unit_id":str(payload.unit_id),"x":world.x,"y":world.y};event="air_support_fired"
	elif kind=="withdraw":command={"op":"littoral_order","unit_id":str(payload.unit_id),"action":"retreat"};event="withdraw_ordered"
	elif kind=="ability":command={"op":"littoral_ability","unit_id":str(payload.unit_id),"x":world.x,"y":world.y};event="ability_ordered"
	elif kind=="return":
		if _inside_exit():command={"op":"littoral_extract"};event="extract_ordered"
		else:
			# Separate carriers can have different live offsets after queued landings.
			# A real per-ship course avoids applying an old fleet offset onto land.
			var exit:Dictionary=app.core.view.littoral.exit;var center:=Vector2(float(exit.x),float(exit.y));var target:Vector2=center+(world-center).limit_length(maxf(0,float(exit.radius)-600))
			var ordered:Array=[];var index:int=0
			for ship in app.core.view.get("ships",[]):
				if float(ship.get("hp",0))<=0:continue
				var at:Vector2=target+Vector2((index%3-1)*180,(index/3)*180);index+=1
				var response:Dictionary=app.issue({"op":"littoral_ship_order","ship":int(ship.id),"action":"move","x":at.x,"y":at.y,"speed":25})
				if not response.get("ok",false):_hint(str(response.get("error","这艘载舰暂时无法返航")));return
				ordered.append(int(ship.id))
			app.running=true;_hint("全队正在真实驶往返航圈 · 抵达后拖卡撤离");_emit("return_ordered",{"accepted":true,"ships":ordered,"world":{"x":target.x,"y":target.y},"unit_id":selected_unit});_save_ui_deferred();return
	if command.is_empty():return
	if kind in ["unit","air","withdraw","ability"]:command=_scope_command(command,_payload_company(payload))
	var response:Dictionary=app.issue(command)
	if response.get("ok",false):
		if _coastal_controls():coastal_pending.clear()
		app.running=true;_hint(str(preview.get("reason","指令已接收")));_emit(event,{"accepted":true,"op":command.op,"action":str(command.get("action","")),"unit_id":str(payload.get("unit_id","")),"company_id":str(payload.get("company_id","")),"ship":int(command.get("ship",0)),"target_id":command.get("target",0),"world":{"x":world.x,"y":world.y},"response":response,"command":command})
		if has_meta("carrier_training"):get_meta("carrier_training").accepted(command)
		if app.core.view.get("result")!=null:app.finish_battle()
	else:_error_hint(str(response.get("error","指令未被接受")));_emit("drag_rejected",{"accepted":false,"reason":str(response.get("error",""))})
func _air_order(payload:Dictionary,location:Dictionary,preview:bool)->Dictionary:
	var world:Vector2=location.get("world",Vector2.ZERO);var hit:Dictionary=location.get("hit",{})
	if CarrierDesk.active(self) and str(hit.get("kind",""))=="aircraft" and str(hit.get("row",{}).get("side",""))=="allies":hit={}
	var request:Dictionary={"op":"littoral_preview" if preview else "littoral_air_order","squadron_id":str(payload.get("squadron_id","")),"action":"strike","x":world.x,"y":world.y}
	if hit.is_empty() and not _island_contains(world):request["action"]="patrol"
	if app.core.view.get("littoral",{}).has("carrier_ops"):
		request["queue"]=true
		var squadron:Dictionary={}
		for row in app.core.view.get("littoral",{}).get("aviation",{}).get("squadrons",[]):
			if str(row.id)==str(payload.get("squadron_id","")):squadron=row;break
		if str(hit.get("kind",""))=="ship" and str(hit.get("id",""))==str(squadron.get("carrier",-1)):
			request["action"]="return";request.erase("queue")
		for ship in app.core.view.get("ships",[]):
			if int(ship.id)==int(squadron.get("carrier",-1)) and world.distance_to(Vector2(float(ship.x),float(ship.y)))<=600:
				request["action"]="return";request.erase("queue");break
	if preview:request["kind"]="air"
	if CarrierDesk.active(self):request["queue"]=true
	if str(hit.get("kind","")) in ["ship","aircraft"]:request["target_kind"]=str(hit.kind);request["target_id"]=int(hit.get("id",0)) if str(hit.kind)=="aircraft" else str(hit.get("id",""))
	elif str(hit.get("kind","")) in ["entities","buildings"]:request["target_kind"]="land";request["target_id"]=hit.get("id")
	return request
func open_unit_menu(id:String)->void:
	selected_unit=id;var group:Dictionary=_group();var layer:Control=app.open_modal(str(group.get("name",id)))
	app.button(layer,"继续 · 拖动这张卡安排任务",420,250,760,62,app.close_modal,true)
	if str(group.get("stage",""))=="ground":
		app.button(layer,"显示撤收卡 · 拖回本人撤收",420,330,760,62,func():app.close_modal();context_action="withdraw";roster_signature="";update())
		app.button(layer,"原地待命",420,410,760,62,func():app.close_modal();_unit_order("hold"))
		if not VehicleControls.active(self):app.button(layer,"显示本人专长 / 旋翼支援卡",420,485,760,62,func():app.close_modal();context_action="" if context_action!="" else "air";roster_signature="";update())
		elif context_action=="withdraw":app.button(layer,"显示本人专长卡",420,485,760,62,func():app.close_modal();context_action="";roster_signature="";update())
	elif str(group.get("stage",""))=="embarked" and not VehicleControls.active(self):
		app.button(layer,"就近滩头登陆（旧航次 / 精确滩头）",420,330,760,62,func():app.close_modal();_deploy())
	if str(app.core.view.get("island_war",{}).get("version","")) in ["cas-island-war-v3","cas-island-war-v4","cas-island-war-coastal-v1"]:
		app.label(layer,load("res://scripts/tactical_weapon_badge_v3.gd").engagement_hint(_tactical_card(_identity(id))),420,555,760,50,20)
	app.button(layer,"关闭",420,620,760,62,app.close_modal)

func _return_available()->bool:
	var data:Dictionary=app.core.view.get("littoral",{});var searched:bool=false
	var returned:bool=false
	for group in data.get("groups",[]):
		if str(group.get("stage","")) in ["ground","transit","returning"] or group.get("pending_deploy") is Dictionary:return false
		if str(app.core.view.get("island_war",{}).get("version","")) in ["cas-island-war-v3","cas-island-war-v4","cas-island-war-coastal-v1"] and str(group.get("stage","")) not in ["embarked","recovered","lost"]:return false
		returned=returned or str(group.get("stage","")) in ["recovered","lost"]
	# New island missions need no salvage-ruin prerequisite. The native extract
	# command still decides success, losses and whether recovery is complete.
	if str(app.core.view.get("island_war",{}).get("version","")) in ["cas-island-war-v3","cas-island-war-v4","cas-island-war-coastal-v1"]:
		for vehicle in data.get("land",{}).get("combat_vehicles",[]):
			if str(vehicle.get("side","axis"))=="allies" and float(vehicle.get("hp",0))>0 and str(vehicle.get("phase","")) not in ["aboard","recovered"]:return false
		return returned and app.core.view.get("result")==null
	for ruin in data.get("land",{}).get("ruins",[]):searched=searched or bool(ruin.get("searched",false))
	var training:Variant=data.get("training")
	var sea_lesson:bool=str(data.get("version","")) in ["cas-littoral-v3","cas-littoral-v4","cas-littoral-coastal-v1"] and training is Dictionary and str(training.get("lesson",""))=="sea_control" and bool(training.get("complete",false))
	return (searched or sea_lesson) and app.core.view.get("result")==null
func _inside_exit()->bool:
	var exit:Dictionary=app.core.view.get("littoral",{}).get("exit",{})
	if exit.is_empty():return false
	var alive:int=0
	for ship in app.core.view.get("ships",[]):
		if float(ship.get("hp",0))<=0:continue
		alive+=1
		if Vector2(float(ship.x),float(ship.y)).distance_to(Vector2(float(exit.x),float(exit.y)))>float(exit.get("radius",0)):return false
	return alive>0
func open_naval_menu()->void:
	var layer:Control=app.open_modal("选择实际炮援舰")
	var index:int=0
	for ship in app.core.view.get("ships",[]):
		if not _has_naval_gun(ship):continue
		var id:int=int(ship.id);var support:Dictionary=_naval_support(id)
		app.button(layer,str(ship.name)+(" · 炮弹已尽" if float(support.get("ammo",0))<=0 else ""),420,245+index*76,760,62,func():app.close_modal();ship_id=id;app.sea.selected_ship=id;roster_signature="";update();_save_ui_deferred(),id==_selected_naval_id());index+=1
	app.button(layer,"返回",420,minf(760,245+index*76),760,62,app.close_modal)
func _has_naval_gun(ship:Dictionary)->bool:
	if not _world_naval():return bool(ship.get("gun",false))
	return ship.get("systems",{}).get("guns",[]).any(func(row):return not bool(row.get("destroyed",false)))
func open_squadron_menu(id:String)->void:
	if CarrierDesk.active(self):CarrierDesk.squadron_menu(self,id);return
	var squadron:Dictionary={}
	for row in app.core.view.get("littoral",{}).get("aviation",{}).get("squadrons",[]):
		if str(row.id)==id:squadron=row;break
	if squadron.is_empty():return
	var layer:Control=app.open_modal(AircraftArt.display_name(str(squadron.get("visual_type",squadron.get("name","航空中队")))))
	app.label(layer,"可出击 %d / %d · 在空 %d · 损失 %d"%[int(squadron.get("available",0)),int(squadron.get("total",0)),int(squadron.get("airborne",0)),int(squadron.get("lost",0))],420,255,760,60,24)
	app.label(layer,"拖中队卡到敌舰、陆地或空中目标；射程、弹药与返航由实际飞行裁决。",420,330,760,90,22)
	app.button(layer,"召回实际在空飞机",420,455,760,64,func():app.close_modal();app.issue({"op":"littoral_air_order","squadron_id":id,"action":"return"})).disabled=replay_mode or int(squadron.get("airborne",0))<=0
	app.button(layer,"返回",420,565,760,64,app.close_modal)

func _group()->Dictionary:
	for group in app.core.view.get("littoral",{}).get("groups",[]):
		if str(group.id)==selected_unit:return group
	return {}
func _row_company(row:Dictionary)->String:return str(row.get("company_id",row.get("unit_id","")))
func _payload_company(payload:Dictionary)->String:return str(payload.get("company_id",payload.get("unit_id","")))
func _identity(id:String)->String:
	for group in app.core.view.get("littoral",{}).get("groups",[]):
		if str(group.id)==id:return str(group.get("unit_id",id))
	return id
func _company_fields(id:String)->Dictionary:
	var data:Dictionary=app.core.view.get("littoral",{})
	for group in data.get("groups",[]):
		if str(group.id)==id:
			return {"unit_id":str(group.get("unit_id",id)),"company_id":id} if str(data.get("company_layout",""))=="multi-company-v1" else {"unit_id":id}
	return {"unit_id":id}
func _scope_command(command:Dictionary,id:String)->Dictionary:
	command.merge(_company_fields(id),true);return command

func _fleet()->Dictionary:
	if naval_controller!=null:return naval_controller._fleet()
	var fleets:Array=app.core.view.get("fleets",[])
	return fleets[0] if not fleets.is_empty() else {}

func move(point:Vector2)->void:
	if replay_mode:return
	_cancel_naval_support()
	var response:Dictionary=app.issue({"op":"route","fleet":1,"mode":"follow","speed":25,"points":[{"x":point.x,"y":point.y}]})
	if response.get("ok",false):app.running=true

func select(kind:String,object:Dictionary)->void:
	if naval_controller!=null:
		naval_controller.select(kind,object);ship_id=naval_controller.ship_id;fleet_id=naval_controller.fleet_id;update();return
	if kind=="ship":app.sea.selected_ship=int(object.get("id",0));ship_id=app.sea.selected_ship;update()

func _deploy()->void:
	if selected_unit.is_empty() or replay_mode:return
	var response:Dictionary=app.issue(_scope_command({"op":"littoral_deploy","beach":selected_beach,"insertion":insertion},selected_unit))
	if response.get("ok",false):app.running=true

func _extract()->void:
	if replay_mode:return
	var response:Dictionary=app.issue({"op":"littoral_extract"})
	if response.get("ok",false) and app.core.view.get("result")!=null:app.finish_battle()

func _toggle_autonomy()->void:
	if replay_mode or not _world_naval():return
	# A new battle opens paused. If native autonomy is already enabled, the
	# first click should start that plan, not silently disable it while paused.
	if bool(app.core.view.get("littoral",{}).get("autonomy",{}).get("enabled",false)) and not app.running:
		app.running=true;_emit("autonomy_changed",{"accepted":true,"enabled":true,"resumed":true});update();_save_ui_deferred();return
	var enabled:bool=not bool(app.core.view.get("littoral",{}).get("autonomy",{}).get("enabled",false))
	var island_version:String=str(app.core.view.get("island_war",{}).get("version",""))
	var command:Dictionary={"op":"island_autonomy","version":island_version,"enabled":enabled} if island_version in ["cas-island-war-v2","cas-island-war-v3","cas-island-war-v4","cas-island-war-coastal-v1"] else {"op":"littoral_autonomy","version":"combined-autonomy-v1","enabled":enabled}
	var response:Dictionary=app.issue(command)
	if not bool(response.get("ok",false)):return
	if enabled:app.running=true
	_emit("autonomy_changed",{"accepted":true,"enabled":enabled});update();_save_ui_deferred()

func _unit_order(action:String,point:Vector2=Vector2.ZERO,target:Variant=0)->void:
	if selected_unit.is_empty() or replay_mode:return
	var vehicle:Dictionary=VehicleControls.find(self,selected_vehicle_id) if selected_vehicle_id>0 else VehicleControls.orphan(self,selected_unit)
	if not vehicle.is_empty() and float(vehicle.get("hp",0))<=0:vehicle={};selected_vehicle_id=0
	if not vehicle.is_empty() and action in ["move","attack","hold","retreat"]:
		var vehicle_command:Dictionary={"op":"littoral_vehicle_order","vehicle_id":int(vehicle.id),"action":action,"x":point.x,"y":point.y}
		var vehicle_response:Dictionary=app.issue(vehicle_command)
		if vehicle_response.get("ok",false):app.running=true
		return
	var command:Dictionary={"op":"littoral_order","unit_id":selected_unit,"action":action}
	if action in ["move","attack","defend"]:command["x"]=point.x;command["y"]=point.y
	if target!=0:command["target"]=target
	var response:Dictionary=app.issue(_scope_command(command,selected_unit))
	if response.get("ok",false):app.running=true

func _land_click(point:Vector2,target:Variant,kind:String)->void:
	if replay_mode:return
	if _coastal_controls() and not coastal_pending.is_empty():
		var map=ui.get_node("LandWindow/Map");_drag_drop(coastal_pending.duplicate(),map.get_global_transform()*map.project(point));update();return
	if kind=="entities" and str(app.core.view.get("littoral",{}).get("version","")) in ["cas-littoral-v3","cas-littoral-v4","cas-littoral-coastal-v1"]:
		for body in app.core.view.littoral.land.get("entities",[]):
			if int(body.id)==int(target) and str(body.get("side","axis"))=="allies":selected_unit=_row_company(body);selected_vehicle_id=int(body.id) if body.has("vehicle_kind") else 0;roster_signature="";context_action="";update();_save_ui_deferred();return
	if not support_mode.is_empty():
		if support_mode=="naval":_queue_naval(point);return
		var command:Dictionary={"op":"littoral_support","kind":support_mode,"x":point.x,"y":point.y}
		if support_mode=="naval":
			var ships:Array=app.core.view.get("ships",[]);command["ship"]=app.sea.selected_ship if app.sea.selected_ship!=0 else int(ships[0].id) if not ships.is_empty() else 0
		else:command=_scope_command(command,selected_unit)
		var response:Dictionary=app.issue(command)
		if response.get("ok",false):app.running=true;support_mode="";_hint("支援已接令 · 弹药与射程按真实战况核验")
		return
	var action:String=order_action
	if kind=="ruins" and target!=0:action="search"
	_unit_order(action,point,target)

func _selected_naval_id()->int:
	var ships:Array=app.core.view.get("ships",[])
	return app.sea.selected_ship if app.sea.selected_ship!=0 else int(ships[0].id) if not ships.is_empty() else 0

func _naval_support(id:int)->Dictionary:
	for row in app.core.view.get("littoral",{}).get("support",{}).get("naval",[]):
		if int(row.ship)==id:return row
	return {}

func _cancel_naval_support()->void:
	if replay_mode:return
	var id:int=_selected_naval_id()
	if _naval_support(id).get("pending_target")!=null:app.issue({"op":"littoral_ship_order","ship":id,"action":"cancel_support"})

func _naval_action()->void:
	if replay_mode:return
	if _naval_support(_selected_naval_id()).get("pending_target")!=null:
		_cancel_naval_support();support_mode="";_hint("已取消待发炮援");return
	support_mode="naval";_hint("选择海上支援舰，再点击陆图落点；自动调整真实炮位")

func _queue_naval(point:Vector2)->void:
	var id:int=_selected_naval_id();var support:Dictionary=_naval_support(id);var ship:Dictionary={}
	for row in app.core.view.get("ships",[]):
		if int(row.id)==id:ship=row;break
	if ship.is_empty() or not bool(support.get("alive",false)):app.notify({"ok":false,"message":"请选择存活的支援舰"});return
	var origin:Vector2=Vector2(float(ship.x),float(ship.y))
	if origin.distance_to(point)>float(support.get("range",0)):app.notify({"ok":false,"message":"落点超出真实炮程，请先在海图靠近"});return
	var bearing:float=fposmod(rad_to_deg(atan2(point.x-origin.x,point.y-origin.y)),360)
	var heading:float=float(ship.get("heading",0));var closest:float=INF;var target_heading:float=heading
	for raw in support.get("arcs",[]):
		var width:float=float(raw[1])-float(raw[0]);var mid:float=float(raw[0])+fposmod(width,360)*.5
		if absf(width)>=359.9:mid=fposmod(bearing-heading,360)
		var candidate:float=fposmod(bearing-mid,360);var turn:float=absf(wrapf(candidate-heading,-180,180))
		if turn<closest:closest=turn;target_heading=candidate
	var aligned:Dictionary=app.issue({"op":"littoral_ship_order","ship":id,"action":"face","heading":target_heading})
	if not aligned.get("ok",false):return
	var queued:Dictionary=app.issue({"op":"littoral_support","kind":"naval","ship":id,"x":point.x,"y":point.y,"queue":true})
	if queued.get("ok",false):support_mode="";app.running=true;_hint("炮援已排定 · 正在真实转向与装填，可取消")

func cancel_draft(_announce:bool=true)->void:
	if naval_controller!=null:naval_controller.cancel_draft();return
	app.sea.planned.clear();support_mode="";_cancel_naval_support()
func refresh_preview()->void:
	if naval_controller!=null:naval_controller.refresh_preview()
	else:super.refresh_preview()
func commit_route()->void:
	if naval_controller!=null:naval_controller.commit_route()
	else:super.commit_route()
func record_signal(value:String)->void:
	if naval_controller!=null:naval_controller.record_signal(value)
func begin_replay()->void:
	if replay_mode:return
	if not app.checkpoint():app.running=false;return
	var saved:Dictionary=app.core.request({"op":"save","serialized":true})
	if not saved.get("ok",false):app.notify(saved);return
	replay_save=str(saved.serialized);last_live_view=app.core.view.duplicate(true)
	replay_duration=float(JSON.parse_string(replay_save).get("tick",0));replay_limit=int(ceil(replay_duration));replay_seconds=0
	replay_back_running=app.running;app.running=false;replay_mode=true;seek_littoral(0)
func seek(tick:int)->void:seek_littoral(float(tick))
func advance_littoral_replay(seconds:float)->void:
	seek_littoral(replay_seconds+seconds,true)
	if replay_seconds>=replay_duration-.000001:app.running=false
func seek_littoral(seconds:float,continuous:bool=false)->void:
	if not replay_mode:return
	if replay_duration<=0:
		var saved:Variant=JSON.parse_string(replay_save)
		if saved is Dictionary:replay_duration=float(saved.get("tick",0))
	var target:float=clampf(snappedf(seconds,.1),0,replay_duration)
	if not continuous and is_instance_valid(ui):ui.get_node("LandWindow/Map").prime_visuals()
	var response:Dictionary=app.core.request({"op":"replay","serialized":replay_save,"tick":target})
	if response.get("ok",false):replay_seconds=target;replay_tick=int(target);update()
	else:app.notify(response)
func end_replay()->void:
	if not replay_mode:return
	if app.home_replay_session!=null and app.home_replay_session.active:app.close_home_replay();return
	app.running=false
	if archive_replay:
		replay_mode=false;app.show_page("archives");return
	var restored:Dictionary=app.core.request({"op":"load","serialized":replay_save})
	if not restored.get("ok",false):app.notify(restored);return
	replay_mode=false;app.sea.cancel_pending();ui.get_node("LandWindow/Map").prime_visuals();update()
func open_pause_menu()->void:
	app.running=false
	if drag_layer!=null:drag_layer.cancel()
	_save_ui_deferred()
	if app.home_exercise_session!=null and app.home_exercise_session.active:
		var exercise_layer:Control=app.open_modal("自家攻防演习 · 暂停")
		app.label(exercise_layer,"演习不消耗资源与整备，设施保持完好。",400,230,790,70,24)
		app.button(exercise_layer,"继续演习",400,350,790,65,func():app.close_modal();app.running=true;update(),true)
		app.button(exercise_layer,"结束演习 · 返回海岛",400,450,790,65,app.close_home_exercise)
		return
	if replay_mode:
		var replay_layer:Control=app.open_modal("海陆协同 · 只读复盘")
		var slider:=HSlider.new();slider.name="LittoralReplaySeek";slider.min_value=0;slider.max_value=replay_duration;slider.step=.1;slider.value=replay_seconds;app.place(slider,replay_layer,400,280,790,48)
		slider.drag_ended.connect(func(_changed:bool):seek_littoral(slider.value))
		slider.gui_input.connect(func(event:InputEvent):
			if event is InputEventKey and event.pressed and event.keycode in [KEY_LEFT,KEY_RIGHT,KEY_HOME,KEY_END]:_seek_replay_slider.call_deferred(slider))
		app.button(replay_layer,"播放 / 暂停",400,390,790,65,func():app.close_modal();app.running=not app.running;update(),true)
		app.button(replay_layer,"返回档案" if archive_replay else "返回当前指挥",400,500,790,65,func():app.close_modal();end_replay())
		return
	var layer:Control=app.open_modal("海陆协同 · 暂停")
	app.button(layer,"继续指挥",400,240,790,60,func():app.close_modal();app.running=true;update(),true)
	app.button(layer,"拖动指挥帮助",400,320,790,60,func():app.close_modal();_open_drag_help())
	app.button(layer,"保存暂离",400,400,790,60,func():app.close_modal();app.save_leave())
	app.button(layer,"结束行动 · 保留真实损耗",400,480,790,60,func():app.close_modal();app.abandon())
	app.button(layer,"保存并返回母港",400,560,790,60,app.go_home)
	app.button(layer,"只读复盘",400,640,790,52,func():app.close_modal();begin_replay())
func _seek_replay_slider(slider:Range)->void:
	if is_instance_valid(slider):seek_littoral(slider.value)
func _open_drag_help()->void:
	if tutorial==null:return
	tutorial_dismissed=false;tutorial.start_tutorial({"review_only":true});tutorial.observe_state(app.core.view);roster_signature="";update();_save_ui_deferred()


func _carrier_caption(squadron:Dictionary)->String:
	for ship in app.core.view.get("ships",[]):
		if int(ship.id)==int(squadron.get("carrier",-1)):return str(ship.name)
	return "母舰"+str(squadron.get("carrier",""))
