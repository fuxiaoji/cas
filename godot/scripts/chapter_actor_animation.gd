@tool
extends Node
const ActorLayout=preload("res://scripts/story_actor_layout.gd")
## Facial changes are local to a persistent actor, never a scene/page rebuild.
@export var character_id:String="fletcher"
@export var expression:String="calm"
var actor:TextureRect
var app
var speaking:bool=false
var elapsed:float=0.0
var last_visible:int=-1
var talk_until:float=0.0
@export var face_library:SpriteFrames
var frames:Array[AtlasTexture]=[]
var base_top:float=0.0
var blink_count:int=0
var talk_count:int=0
var frame_index:int=-1
func configure(owner,portrait:TextureRect,key:String,tone:String,active:bool)->void:
	app=owner;actor=portrait;character_id=key;expression=tone;speaking=active
	ActorLayout.composition(actor,true)
	base_top=float(actor.get_meta("story_rest_top",actor.anchor_top))
	if frames.is_empty():
		var path:="res://assets/story/expressions-v2/%s-sheet.png"%key
		if not ResourceLoader.exists(path):set_process(false);return
		face_library=load("res://assets/story/expressions-v2/%s-faces.tres"%key)
		for face in ["neutral","resolve","concern","talk","blink","hurt"]:frames.append(face_library.get_frame_texture(face,0) as AtlasTexture)
	_apply(_tone_frame())
func _tone_frame()->int:
	return 5 if expression=="hurt" else 2 if expression in ["concern","alert"] else 1 if expression in ["resolve","bright"] else 0
func _apply(index:int)->void:
	# A dialogue refresh can restore the base portrait before reconfiguring this
	# persistent actor. Reapply the same face instead of waiting for the next blink.
	if frames.is_empty() or (index==frame_index and actor.texture==frames[index]):return
	frame_index=index;actor.texture=frames[index]
	ActorLayout.fade(actor)
	actor.set_meta("chapter_face_frame",index)
	if index==4:blink_count+=1
	if index==3:talk_count+=1
func _process(delta:float)->void:
	if not is_instance_valid(actor) or frames.is_empty():return
	elapsed+=delta
	var reduced:bool=app!=null and bool(app.get_meta("reduced_motion",false))
	if reduced:_apply(_tone_frame());return
	var reader:Node=app.page.get_node_or_null("ChapterDialogueReader") if app!=null else null
	if reader==null and app!=null:reader=app.page.get_node_or_null("CanonStory/CanonDialogueReader")
	if speaking and reader!=null and is_instance_valid(reader.text_label):
		var count:int=reader.text_label.visible_characters
		if count!=last_visible and count>=0 and count<reader.text_label.get_total_character_count():talk_until=elapsed+.16
		last_visible=count
	var phase:=fmod(elapsed+float(abs(character_id.hash())%31)*.1,4.8)
	if phase>4.60 and phase<4.76:_apply(4)
	elif speaking and elapsed<talk_until and fmod(elapsed,.30)<.15:_apply(3)
	else:_apply(_tone_frame())
	# Breath stays below two virtual pixels and never changes the dialogue panel.
	actor.anchor_top=base_top+sin(elapsed*1.65+float(character_id.length()))*.0011
