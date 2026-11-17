@tool
extends Control
const Design=preload("res://scripts/ui_design.gd")
const Service=preload("res://scripts/tide_event_service.gd")
const Reader=preload("res://scripts/chapter_dialogue_player.gd")
const ActorLayout=preload("res://scripts/story_actor_layout.gd")
@export_group("Presentation")
@export_file("*.json") var content_path:String="res://data/tide-event-v1.json"
## Disable to retain authored theme overrides through preview, binding and reload.
@export var use_default_styles:bool=true
@export var use_content_text:bool=true
@export var use_content_artwork:bool=true
@export var show_cast:bool=true
@export_group("Editor Preview")
@export var preview_ending:bool=false:
	set(value):
		preview_ending=value
		if Engine.is_editor_hint() and is_node_ready():_preview()
@export_range(0,7,1) var preview_line:int=0:
	set(value):
		preview_line=value
		if Engine.is_editor_hint() and is_node_ready():_preview()
var app
var content:Dictionary
var lines:Array=[]
var line_index:=0
var ending:=false
var reader:Node
var layout_revision:=0
func _ready()->void:
	if theme==null:theme=Design.theme()
	content=JSON.parse_string(FileAccess.get_file_as_string(content_path))
	if use_default_styles:
		$Speaker.add_theme_color_override("font_color",Color("efd69b"));$Body.add_theme_color_override("default_color",Color("f0f3ef"))
		Design.apply_overlay_button($Back);Design.apply_overlay_button($Next)
	if Engine.is_editor_hint():_preview()
func _preview()->void:
	ending=preview_ending;lines=content.epilogue if ending else content.intro;line_index=mini(preview_line,lines.size()-1);_line()
func bind(owner)->void:
	app=owner;ending=bool(app.get_meta("tide_story_ending",false));lines=content.epilogue if ending else content.intro
	$Back.pressed.connect(func():app.return_to("tide_event"))
	$Next.pressed.connect(func():reader.continue_reading())
	_line()
func _line()->void:
	var path:String=str(content.ending if ending else content.hero)
	if use_content_artwork and ResourceLoader.exists(path):$Backdrop.texture=load(path)
	var row:Dictionary=lines[line_index]
	if use_content_text:$Speaker.text=str(row.speaker);$Body.text=str(row.text)
	_fit_dialogue(str($Body.get_parsed_text()))
	if $Cast.get_child_count()==0:
		var cards:Dictionary={}
		if app!=null:cards=app.cards
		else:
			for card in JSON.parse_string(FileAccess.get_file_as_string("res://data/ships.json")).get("ships",[]):cards[str(card.id)]=card
		var cast_ids=["IBS-U-USN-FLETCHER","IBS-U-USN-PERKINS"]
		for i in range(cast_ids.size()):
			var card:Dictionary=cards.get(cast_ids[i],{})
			var portrait_path:String=str(card.get("portrait",""))
			if not ResourceLoader.exists(portrait_path):continue
			var actor:=TextureRect.new();actor.texture=ActorLayout.portrait(load(portrait_path),portrait_path);actor.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;actor.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED;actor.mouse_filter=Control.MOUSE_FILTER_IGNORE
			$Cast.add_child(actor);ActorLayout.slot(actor,i,cast_ids.size())
			actor.set_meta("speaker",str(card.get("name","")))
	$Cast.visible=show_cast and str(row.speaker)!="旁白"
	for actor in $Cast.get_children():
		var target:Color=Color.WHITE if str(actor.get_meta("speaker",""))==str(row.speaker) else Color(.68,.72,.78,1.0)
		if app==null or bool(app.get_meta("reduced_motion",false)):actor.modulate=target
		else:create_tween().tween_property(actor,"modulate",target,.18)
	if app==null:return
	if is_instance_valid(reader):remove_child(reader);reader.queue_free()
	reader=Reader.new();reader.app=app;reader.text_label=$Body;reader.advance=_advance;reader.reduced_motion=bool(app.get_meta("reduced_motion",false));reader.text_effect="echo" if line_index==4 and not ending else "none";add_child(reader)
func _fit_dialogue(message:String)->void:
	layout_revision+=1
	var font:Font=$Body.get_theme_font("normal_font")
	var width:float=maxf(1.0,size.x*(.855-.09))
	var long_text:=font.get_multiline_string_size(message,HORIZONTAL_ALIGNMENT_LEFT,width,26).y>size.y*(.915-.835)
	$Cast.anchor_bottom=.905
	$Shade.anchor_top=.70 if long_text else .75
	$Speaker.anchor_top=.74 if long_text else .79;$Speaker.anchor_bottom=.782 if long_text else .832
	$Body.anchor_top=.785 if long_text else .835
	_fit_body_after_layout.call_deferred(layout_revision)
func _fit_body_after_layout(revision:int)->void:
	await get_tree().process_frame
	if revision!=layout_revision:return
	var overflow:float=$Body.get_content_height()-$Body.size.y
	if overflow<=.5:return
	var shift:float=(overflow+8.0)/maxf(1.0,size.y)
	$Body.anchor_top-=shift;$Speaker.anchor_top-=shift;$Speaker.anchor_bottom-=shift
	$Shade.anchor_top-=shift
func _advance()->void:
	line_index+=1
	if line_index>=lines.size():
		app.notify(Service.new(app.economy).read_story(ending));app.return_to("tide_event");return
	_line()
