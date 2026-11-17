@tool
extends Control
const Design=preload("res://scripts/ui_design.gd")
@export_group("Presentation")
## Disable to preserve scene-authored fonts, panel colors and bar styles.
@export var use_default_styles:bool=true
@export var show_control_hint:bool=true
@export_group("Editor Preview")
@export var preview_show_upgrades:bool=false:
	set(value):
		preview_show_upgrades=value
		if Engine.is_editor_hint() and is_node_ready():_preview_upgrades()
@export var preview_choices:Array[String]=["舰炮共鸣", "潮汐装甲", "回响引力"]:
	set(value):
		preview_choices=value
		if Engine.is_editor_hint() and is_node_ready():_preview_upgrades()
var owner_ref:WeakRef
var controller:
	get:return owner_ref.get_ref() if owner_ref!=null else null
var move_clock:=0.0
var _was_moving:=false
var _team_signature:String=""
var _toast_time:=0.0
func _ready()->void:
	if theme==null:theme=Design.theme()
	$Hint.visible=show_control_hint
	if Engine.is_editor_hint():_preview_upgrades()
	if not use_default_styles:return
	$Status.add_theme_stylebox_override("panel",Design.box(Color("f0f3e8"),6))
	$JoinToast.add_theme_stylebox_override("panel",Design.box(Color(.025,.12,.16,.94),6))
	$JoinToast/Name.add_theme_color_override("font_color",Color("e5fff1"))
	for label in [$Status/Body/Wave,$Status/Body/Level]:label.add_theme_color_override("font_color",Design.INK)
	for label in [$Clock,$Hint,$Upgrades/Title]:label.add_theme_color_override("font_color",Color("fff7df"))
	for button in [$Pause,$Menu]:Design.apply_button(button)
	for bar in [$Status/Body/Hp,$Status/Body/Xp]:
		bar.add_theme_stylebox_override("background",Design.box(Color("cbd6cf"),3))
		bar.add_theme_stylebox_override("fill",Design.box(Color("348c8a") if bar.name=="Hp" else Color("d1a250"),3))
func _preview_upgrades()->void:
	$Upgrades.visible=preview_show_upgrades
	for child in $Upgrades/Choices.get_children():
		if child.has_meta("editor_preview"):$Upgrades/Choices.remove_child(child);child.queue_free()
	if $Upgrades/Choices.get_child_count()>0:return
	for title in preview_choices:
		var choice:=Button.new();choice.text=title;choice.size_flags_horizontal=Control.SIZE_EXPAND_FILL;choice.disabled=true;choice.set_meta("editor_preview",true)
		if use_default_styles:Design.apply_button(choice,true)
		$Upgrades/Choices.add_child(choice)
func bind(value)->void:
	owner_ref=weakref(value)
	$Pause.pressed.connect(controller.app.toggle_pause)
	$Menu.pressed.connect(controller.open_pause_menu)
func sync_team(ships:Array,cards:Dictionary,joined:Array)->void:
	var signature:String=str(ships.map(func(ship):return str(ship.get("characterId",""))))
	if signature!=_team_signature:
		_team_signature=signature
		for child in $Team.get_children():$Team.remove_child(child);child.queue_free()
		for ship in ships:
			var identity:String=str(ship.get("characterId",""));var card:Dictionary=cards.get(identity,{})
			var avatar:=TextureRect.new();avatar.name="Member_"+str(int(ship.id));avatar.custom_minimum_size=Vector2(60,72);avatar.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;avatar.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED;avatar.mouse_filter=Control.MOUSE_FILTER_IGNORE;avatar.tooltip_text=str(card.get("name",identity));avatar.set_meta("character_id",identity)
			var source:Texture2D=load("res://scripts/character_art.gd").texture(str(card.get("portrait","")))
			if source!=null:avatar.texture=load("res://scripts/story_actor_layout.gd").portrait(source,identity)
			$Team.add_child(avatar)
	for member in joined:
		var card:Dictionary=cards.get(str(member.get("character_id","")),{})
		$JoinToast/Name.text=str(card.get("name","援军"))+"  抵达";$JoinToast.visible=true;_toast_time=2.2
		var avatar:Control=$Team.get_node_or_null("Member_"+str(int(member.get("ship_id",0))))
		if avatar!=null:
			avatar.modulate.a=.2;var tween:=create_tween();tween.tween_property(avatar,"modulate:a",1.0,.4)
func _process(delta:float)->void:
	if controller==null or not is_instance_valid(controller.app.sea):return
	_toast_time=maxf(0,_toast_time-delta);$JoinToast.visible=_toast_time>0
	controller.app.sea.presentation_running=controller.app.running
	if controller.replay_mode or not controller.app.running or $Upgrades.visible or is_instance_valid(controller.app.modal):return
	move_clock+=delta
	var direction:=Vector2(float(Input.is_physical_key_pressed(KEY_D))-float(Input.is_physical_key_pressed(KEY_A)),float(Input.is_physical_key_pressed(KEY_W))-float(Input.is_physical_key_pressed(KEY_S)))
	var v2:bool=str(controller.app.core.view.get("tide",{}).get("version",""))=="cas-event-tide-v2"
	if direction.length_squared()>.1 and move_clock>(.1 if v2 else .35):
		move_clock=0
		var ship:Dictionary=controller.app.core.view.ships[0]
		controller.move(Vector2(float(ship.x),float(ship.y))+direction.normalized()*1100)
		_was_moving=true
	elif direction.length_squared()<.1 and _was_moving:
		_was_moving=false
		if v2:controller.app.issue({"op":"speed","fleet":1,"speed":0})
func _draw()->void:
	pass
