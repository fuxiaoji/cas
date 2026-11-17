@tool
extends Control
## This same editable scene is used by the game and the editor preview.
const Content=preload("res://scripts/chapter_story_data.gd")
const ActorLayout=preload("res://scripts/story_actor_layout.gd")
@export_group("Editor preview")
@export var preview_scene: String = "waking":
	set(value):preview_scene=value;_queue_preview()
@export_range(0,12,1) var preview_line: int = 0:
	set(value):preview_line=value;_queue_preview()
@export_tool_button("刷新场景预览") var refresh_preview:Callable=_preview
var layout_revision:=0

func layout_dialogue(choosing:bool,message:String)->void:
	layout_revision+=1
	var font:Font=$Body.get_theme_font("normal_font")
	var width:float=maxf(1.0,size.x*(.855-.0525))
	var predicted:float=font.get_multiline_string_size(message,HORIZONTAL_ALIGNMENT_LEFT,width,26).y
	var long_text:bool=predicted>size.y*(.915-.835)
	_apply_dialogue_layout(choosing,long_text)
	_fit_body_after_layout.call_deferred(layout_revision,choosing)

func _apply_dialogue_layout(choosing:bool,long_text:bool)->void:
	var expanded:=choosing or long_text
	$Cast.anchor_bottom=.905
	$DialogueShade.anchor_top=.70 if expanded else .75
	$Speaker.anchor_top=.74 if expanded else .79
	$Speaker.anchor_bottom=.782 if expanded else .832
	$SpeakerAccent.anchor_top=.748 if expanded else .798
	$SpeakerAccent.anchor_bottom=.779 if expanded else .829
	$Body.anchor_top=.785 if expanded else .835
	$Body.anchor_bottom=.915
	set_meta("story_expanded_dialogue",expanded)

func _fit_body_after_layout(revision:int,choosing:bool)->void:
	if not is_inside_tree():return
	await get_tree().process_frame
	if not is_inside_tree() or revision!=layout_revision:return
	var overflow:float=$Body.get_content_height()-$Body.size.y
	if overflow<=.5:return
	# Grow only the exceptional long page, keeping the type size and complete text.
	var extra:=overflow+8.0
	var shift:=extra/maxf(1.0,size.y)
	$Body.anchor_top-=shift
	$Speaker.anchor_top-=shift;$Speaker.anchor_bottom-=shift
	$SpeakerAccent.anchor_top-=shift;$SpeakerAccent.anchor_bottom-=shift
	$DialogueShade.anchor_top-=shift
	set_meta("story_expanded_dialogue",true)

func _ready() -> void:
	if Engine.is_editor_hint():_preview()

func _queue_preview() -> void:
	if Engine.is_editor_hint() and is_inside_tree():_preview.call_deferred()

func dialogue_visible(value:bool) -> void:
	for path in ["DialogueShade","SpeakerAccent","Speaker","Body","Environment"]:get_node(path).visible=value

func _preview() -> void:
	if not Engine.is_editor_hint() or not is_node_ready():return
	Content.cached.clear()
	var node:Dictionary=Content.scene(preview_scene)
	if node.is_empty():return
	var rows:Array=node.get("lines",[])
	var line:Dictionary=rows[clampi(preview_line,0,rows.size()-1)] if not rows.is_empty() else {}
	var asset:=Content.background_path(node)
	$Backdrop.texture=load(asset) if ResourceLoader.exists(asset) else null
	$Body.text=str(line.get("text",node.get("objective",node.get("text",""))))
	layout_dialogue(not node.get("choices",[]).is_empty() and preview_line>=rows.size()-1,$Body.text)
	$Speaker.text=Content.speaker_name(line)
	$Environment.text=str(line.get("caption",""))
	$SpeakerAccent.visible=not $Speaker.text.is_empty()
	for child in $Cast.get_children():child.free()
	if bool(node.get("cg",false)):return
	var cards:Dictionary={}
	var catalog:Variant=JSON.parse_string(FileAccess.get_file_as_string("res://data/ships.json"))
	for card in catalog.get("ships",[]):cards[str(card.id)]=card
	var actors:Array=node.get("actors",[])
	for i in range(actors.size()):
		var key:=str(actors[i]);var cast:Dictionary=Content.data().cast.get(key,{})
		var path:="res://assets/story/chapter1/%s-%s.png"%[key,str(line.get("tone","calm"))]
		if not ResourceLoader.exists(path):path=str(cards.get(str(cast.get("ship_id","")),{}).get("portrait",cast.get("portrait","")))
		if not ResourceLoader.exists(path):continue
		var actor:=TextureRect.new();actor.name="Preview_"+key
		actor.texture=ActorLayout.portrait(load(path),key);actor.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;actor.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED;actor.mouse_filter=Control.MOUSE_FILTER_IGNORE
		$Cast.add_child(actor)
		ActorLayout.slot(actor,i,actors.size())
		actor.modulate=Color.WHITE if key==str(line.get("speaker","")) else Color(.72,.78,.82,1.0)
