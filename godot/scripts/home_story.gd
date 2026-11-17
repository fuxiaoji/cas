@tool
extends Control
## A separate, transactional tutorial reader. Only HomeService's verified battle
## settlement can unlock the island or the tactical personality.
const Design=preload("res://scripts/ui_design.gd")
const Reader=preload("res://scripts/chapter_dialogue_player.gd")
const ActorLayout=preload("res://scripts/story_actor_layout.gd")
@export_group("Presentation")
@export_file("*.json") var content_path:String="res://data/home-story-v1.json"
@export var use_default_styles:bool=true
@export var use_content_text:bool=true
@export var use_content_artwork:bool=true
@export var use_cinematic_layout:bool=true
@export var show_cast:bool=true
@export_group("Editor preview")
@export var preview_post:bool=false:
	set(value):
		preview_post=value
		if Engine.is_editor_hint() and is_node_ready():_preview()
@export_range(0,23,1) var preview_line:int=5:
	set(value):
		preview_line=value
		if Engine.is_editor_hint() and is_node_ready():_preview()
@export_tool_button("刷新剧情预览") var refresh_preview:Callable=_preview
var app
var content:Dictionary={}
var lines:Array=[]
var phase:String="pre"
var line_index:int=0
var reader:Node
var layout_revision:int=0
var committing:bool=false
var background_key:String=""
var _highlight:Dictionary={}
var _background_blend:Tween

func _ready()->void:
	if theme==null:theme=Design.theme()
	var parsed:Variant=JSON.parse_string(FileAccess.get_file_as_string(content_path))
	if parsed is Dictionary:content=parsed
	if use_default_styles:
		for button in [$Back,$Home,$Next]:Design.apply_overlay_button(button)
		$Speaker.add_theme_color_override("font_color",Color("efd69b"))
		$Body.add_theme_color_override("default_color",Color("f7f9fa"))
		$Body.add_theme_font_override("normal_font",Design.font(500))
	if Engine.is_editor_hint():_preview()

func _preview()->void:
	if not is_node_ready() or content.is_empty():return
	phase="post" if preview_post else "pre";lines=content.get(phase,[])
	line_index=clampi(preview_line,0,maxi(0,lines.size()-1));_line()

func bind(owner)->void:
	app=owner
	# The ledger, rather than a replay flag or a story index, owns this gate.
	phase="post" if bool(app.home.state().get("tutorial_complete",false)) else "pre"
	lines=content.get(phase,[])
	line_index=clampi(int(progress().get(phase+"_index",0)),0,maxi(0,lines.size()-1))
	$Back.pressed.connect(func():app.go_back("home"))
	$Home.pressed.connect(func():app.go_home())
	$Next.pressed.connect(func():
		if is_instance_valid(reader):reader.continue_reading())
	_line()

func progress()->Dictionary:
	if app==null:return {}
	return app.home.state().get("story",{}).duplicate(true)

func _persist(next_index:int,complete:bool=false)->Dictionary:
	var before:Dictionary=app.economy.state.duplicate(true)
	var story:Dictionary=progress()
	story["version"]="cas-home-story-v1";story["phase"]=phase
	story[phase+"_index"]=next_index
	if complete:story[phase+"_complete"]=true
	app.home.state()["story"]=story
	var saved:Dictionary=app.economy._commit(before,"家园教学进度已保存")
	# _commit rolls back as well; retain this explicit contract for alternate accounts.
	if not saved.get("ok",false):app.economy.state=before
	return saved

func _advance()->void:
	if app==null or committing:return
	committing=true
	var last:bool=line_index>=lines.size()-1
	var saved:Dictionary=_persist(line_index if last else line_index+1,last)
	if not saved.get("ok",false):
		_failure(saved);committing=false;return
	if not last:
		line_index+=1;_line();committing=false;return
	if phase=="post":
		app.show_page("home");return
	var active:Dictionary=app.economy.state.get("active_run",{})
	if not active.is_empty():
		await app.resume_run()
	else:
		# Use this version's registered training loans (the modern lesson needs
		# multiple companies); never reuse a legacy single-unit roster here.
		var prepared:Dictionary=app.home.prepare_littoral("tutorial",int(content.get("seed",42)),[],[],"balanced")
		if prepared.get("ok",false):await app.launch_littoral(prepared.request)
		else:_failure(prepared)
	if is_instance_valid(self) and app.screen=="home_story":
		committing=false
		if is_instance_valid(reader):reader.set_process(true)

func _failure(result:Dictionary)->void:
	$Status.text=str(result.get("message","保存失败，当前页已保留"))
	if app!=null:app.notify(result)
	if is_instance_valid(reader):reader.set_process(true)

func _line()->void:
	if lines.is_empty():$Status.text="剧情内容未就绪";$Next.disabled=true;return
	var row:Dictionary=lines[line_index]
	var cast:Dictionary=content.get("cast",{})
	var speaker:String=str(row.get("speaker",""))
	if use_content_text:
		$Speaker.text=str(cast.get(speaker,{}).get("name","旁白"))
		$Body.text=str(row.get("text","")).replace("[","[lb]")
		$Location.text=str(row.get("location","遗迹救援" if phase=="pre" else "驻岛委托"))
		$Title.text=str(content.get("title",""))
		$Next.text="继续  ›"
		if line_index==lines.size()-1:
			$Next.text="前往家园  ›" if phase=="post" else "前往救援  ›"
			if app!=null and phase=="pre" and not app.economy.state.get("active_run",{}).is_empty():$Next.text="继续行动  ›"
	$Status.text=""
	_fit_dialogue($Body.get_parsed_text())
	_set_background(row)
	_set_cast(row,speaker)
	if app==null:return
	if app.audio!=null:
		app.audio.set_paused(false)
		app.audio.set_scene("story_tension" if phase=="pre" else "story")
		app.audio.set_dialogue_active(true)
	if is_instance_valid(reader):remove_child(reader);reader.queue_free()
	reader=Reader.new();reader.name="DialogueReader";reader.app=app;reader.text_label=$Body
	reader.advance=_advance;reader.reduced_motion=bool(app.get_meta("reduced_motion",false))
	reader.text_effect="none";reader.characters_per_second=34.0;add_child(reader)

func _set_background(row:Dictionary)->void:
	if not use_content_artwork:return
	var path:String=str(content.get(phase+"_cg","")) if bool(row.get("cg",false)) else str(content.get(phase+"_background",""))
	if not ResourceLoader.exists(path):path=str(content.get(phase+"_background",""))
	if path==background_key:return
	if ResourceLoader.exists(path):
		if _background_blend!=null and _background_blend.is_valid():_background_blend.kill()
		var blend:TextureRect=$BackgroundBlend
		blend.texture=$Backdrop.texture;blend.modulate.a=1.0
		$Backdrop.texture=load(path)
		blend.visible=blend.texture!=null and app!=null and not bool(app.get_meta("reduced_motion",false))
		if blend.visible:
			_background_blend=create_tween();_background_blend.tween_property(blend,"modulate:a",0.0,.4)
			_background_blend.tween_callback(func():blend.visible=false)
	background_key=path
	$Backdrop.set_meta("story_background",path)

func _cards()->Dictionary:
	if app!=null:return app.cards
	var cards:Dictionary={}
	var data:Variant=JSON.parse_string(FileAccess.get_file_as_string("res://data/ships.json"))
	if data is Dictionary:
		for row in data.get("ships",[]):cards[str(row.id)]=row
	return cards

func _set_cast(row:Dictionary,speaker:String)->void:
	var members:Array=row.get("cast",[])
	$Cast.visible=show_cast and not bool(row.get("cg",false))
	var cards:Dictionary=_cards()
	for key in ["fletcher","reefblade","sanfrancisco"]:
		var actor:TextureRect=$Cast.get_node(key)
		actor.visible=members.has(key)
		if not actor.visible:continue
		var tone:String=str(row.get("tone","calm")) if speaker==key else str(actor.get_meta("home_tone","calm"))
		actor.set_meta("home_tone",tone)
		if use_content_artwork:
			var definition:Dictionary=content.get("cast",{}).get(key,{})
			var path:String=str(definition.get("portrait",cards.get(str(definition.get("ship_id","")),{}).get("portrait","")))
			var expression:String="res://assets/story/chapter1/%s-%s.png"%[key,tone]
			if ResourceLoader.exists(expression):path=expression
			if ResourceLoader.exists(path) and str(actor.get_meta("home_portrait",""))!=path:
				actor.texture=ActorLayout.portrait(load(path),key);ActorLayout.fade(actor);actor.set_meta("home_portrait",path)
		if use_cinematic_layout:ActorLayout.slot(actor,members.find(key),members.size())
		if app!=null and use_content_artwork and ResourceLoader.exists("res://assets/story/expressions-v2/%s-sheet.png"%key):
			var face:Node=actor.get_node_or_null("FaceAnimation")
			if face==null:face=load("res://scripts/chapter_actor_animation.gd").new();face.name="FaceAnimation";actor.add_child(face)
			face.configure(app,actor,key,tone,key==speaker)
		if not use_default_styles:continue
		var color:Color=Color.WHITE if key==speaker or speaker.is_empty() or speaker=="you" else Color(.73,.79,.83,1.0)
		if _highlight.has(key) and is_instance_valid(_highlight[key]):_highlight[key].kill()
		if app==null or bool(app.get_meta("reduced_motion",false)):actor.modulate=color
		else:
			var tween:Tween=create_tween();tween.tween_property(actor,"modulate",color,.18);_highlight[key]=tween

func _fit_dialogue(message:String)->void:
	if not use_cinematic_layout:return
	layout_revision+=1
	var font:Font=$Body.get_theme_font("normal_font")
	var font_size:int=$Body.get_theme_font_size("normal_font_size")
	var predicted:float=font.get_multiline_string_size(message,HORIZONTAL_ALIGNMENT_LEFT,maxf(1.0,size.x*.82),font_size).y
	var expanded:bool=predicted>size.y*.08
	$Body.anchor_top=.78 if expanded else .835;$Body.anchor_bottom=.91
	$Speaker.anchor_top=.735 if expanded else .79;$Speaker.anchor_bottom=.78 if expanded else .832
	$Shade.anchor_top=.68 if expanded else .75
	_fit_after.call_deferred(layout_revision)

func _fit_after(revision:int)->void:
	await get_tree().process_frame
	if revision!=layout_revision:return
	var overflow:float=$Body.get_content_height()-$Body.size.y
	if overflow<=.5:return
	var shift:float=(overflow+8.0)/maxf(1.0,size.y)
	$Body.anchor_top-=shift;$Speaker.anchor_top-=shift;$Speaker.anchor_bottom-=shift;$Shade.anchor_top-=shift

func _exit_tree()->void:
	if is_instance_valid(app) and app.audio!=null:app.audio.set_dialogue_active(false)
