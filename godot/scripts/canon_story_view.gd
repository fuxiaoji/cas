@tool
extends "res://scripts/chapter_stage.gd"
## Reuses the editable cinematic stage, while keeping v2 script/progress separate.
const CanonData=preload("res://scripts/canon_story_data.gd")
const Service=preload("res://scripts/canon_story_service.gd")
const Actions=preload("res://scripts/canon_story_actions.gd")
const Reader=preload("res://scripts/chapter_dialogue_player.gd")
@export_enum("chapter-01","chapter-02","chapter-03") var preview_chapter:String="chapter-01"
var app
var service
var reader:Node
var controls:Control
var committing:bool=false
func bind(owner)->void:
	app=owner;service=Service.new(app.economy)
	if not service.enabled():
		var response:Dictionary=service.select("chapter-01")
		if not response.get("ok",false):app.notify(response);return
	_render()
func _preview()->void:
	if not is_node_ready():return
	CanonData.cache.clear();var data:Dictionary=CanonData.chapter(preview_chapter)
	var current:Dictionary=CanonData.scene(preview_chapter,preview_scene if not CanonData.scene(preview_chapter,preview_scene).is_empty() else str(data.get("entry","")))
	if current.is_empty():return
	var lines:Array=current.get("lines",[]);var line:Dictionary=lines[clampi(preview_line,0,maxi(0,lines.size()-1))] if not lines.is_empty() else {}
	var path:String=CanonData.background(current,line)
	$Backdrop.texture=load(path) if ResourceLoader.exists(path) else null
	$Speaker.text=str(line.get("name",data.get("cast",{}).get(str(line.get("speaker","")),{}).get("name","旁白")))
	$Body.text=str(line.get("text",current.get("objective","")))
	layout_dialogue(false,$Body.text)
func _render()->void:
	if not is_instance_valid(app):return
	if is_instance_valid(reader):remove_child(reader);reader.queue_free();reader=null
	if is_instance_valid(controls):remove_child(controls);controls.queue_free()
	controls=Control.new();controls.name="StoryControls";controls.mouse_filter=Control.MOUSE_FILTER_IGNORE;add_child(controls);controls.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var current:Dictionary=service.node();var saved:Dictionary=service.chapter();var data:Dictionary=CanonData.chapter(str(service.state().selected))
	var lines:Array=service.visible_lines(current);var index:int=clampi(int(saved.get("line",0)),0,maxi(0,lines.size()-1));var line:Dictionary=lines[index] if not lines.is_empty() else {}
	var path:String=CanonData.background(current,line)
	if str($Backdrop.get_meta("asset",""))!=path:
		$Backdrop.texture=load(path) if ResourceLoader.exists(path) else null;$Backdrop.set_meta("asset",path)
	_render_cast(data,current,line)
	app.button(controls,"‹ 章节",24,10,138,48,func():app.show_page("canon_catalog"))
	app.button(controls,"母港",170,10,100,48,app.go_home)
	app.label(controls,str(data.get("title","航海日志"))+" / "+str(current.get("title","")),295,16,980,42,21,Color("ecf3f0"))
	var kind:String=str(current.get("kind","dialogue"))
	if app.audio!=null:app.audio.set_dialogue_active(kind=="dialogue");app.audio.set_scene(str(current.get("music_scene","story_tension" if str(current.get("background","")) in ["night","storm","court"] else "story")))
	if kind=="dialogue":
		var key:String=str(line.get("speaker",""));var row:Dictionary=data.get("cast",{}).get(key,{})
		$Speaker.text=str(line.get("name",row.get("name","旁白" if key.is_empty() else key)))
		$Body.text=str(line.get("text",""));$Environment.text=str(line.get("caption",current.get("location","")))
		var choices:Array=current.get("choices",[]) if index>=lines.size()-1 else []
		layout_dialogue(not choices.is_empty(),$Body.text)
		if choices.is_empty():
			var next:Button=app.button(controls,"继续  ›",1370,759,180,55,func():
				if reader!=null:reader.continue_reading())
			next.name="ContinueStory"
		else:
			for i in choices.size():
				var choice:Dictionary=choices[i]
				var answer:Button=app.button(controls,str(choice.get("text",choice.get("label","回答"))),835,480+i*72,700,62,func():_move("choice",str(choice.id)))
				answer.name="Choice_"+str(choice.id)
		var skip:Button=app.button(controls,"跳过本段",1392,12,170,45,func():_move("skip"));skip.name="SkipDialogue"
		reader=Reader.new()
		reader.name="CanonDialogueReader"
		reader.app=app
		reader.text_label=$Body
		reader.advance=func():_move("next")
		reader.reduced_motion=bool(app.get_meta("reduced_motion",false))
		reader.text_effect=str(line.get("text_effect","none"))
		reader.characters_per_second=float(line.get("characters_per_second",34.0))
		reader.automatic=false
		add_child(reader)
	elif kind=="complete":
		$Speaker.text="航海日志";$Body.text=str(current.get("text","这一程已经安全记下。"));$Environment.text="";layout_dialogue(false,$Body.text)
		service.move("complete")
		app.button(controls,"下一章 / 章节目录",1115,742,420,65,func():app.show_page("canon_catalog"),true)
	else:
		$Speaker.text=str(current.get("title","一起试一次"));$Body.text=CanonData.objective(current);$Environment.text="";layout_dialogue(false,$Body.text)
		$DialogueShade.anchor_top=.43;$Speaker.anchor_top=.49;$Speaker.anchor_bottom=.55
		$SpeakerAccent.anchor_top=.50;$SpeakerAccent.anchor_bottom=.54;$Body.anchor_top=.59;$Body.anchor_bottom=.70
		var action:String=CanonData.action(current)
		var pending:Dictionary=service.state().pending
		var has_receipt:bool=not pending.is_empty() and app.economy.state.active_run.is_empty() and app.economy.state.get("settled",{}).has(str(pending.get("run_id","")))
		var launch:Button=app.button(controls,"完成迎敌 · 继续故事" if has_receipt and action=="island_defense" else "核对战报 · 继续故事" if has_receipt else "同步协议" if action=="fixed_recruit" else "前往 / 继续行动",1030,690,505,65,_check if has_receipt else _launch,true);launch.name="LaunchCanonAction"
		if action in ["harbor_tour","growth","home_build","home_garrison"]:
			var verify:Button=app.button(controls,"已完成 · 继续故事",1030,768,505,56,_check);verify.name="CheckCanonAction"
		if bool(current.get("optional",false)):app.button(controls,"稍后再学，继续故事",57,744,450,54,func():_move("defer"))
	app.toast_label=app.label(controls,"",72,845,1450,36,19,Color("eef4f3"))
	_style_cinematic_controls()

func _style_cinematic_controls()->void:
	# A story page keeps its controls subordinate to the cast and image. The
	# shared port buttons are bright cards, which otherwise dominate this canvas.
	for control in controls.find_children("*","Button",true,false):
		for status in ["normal","hover","pressed","focus","disabled"]:
			var style:=StyleBoxFlat.new()
			style.bg_color=Color(.025,.08,.12,.12 if status in ["normal","disabled"] else .7)
			style.border_color=Color(.78,.84,.84,.18 if status=="normal" else .6)
			style.set_border_width_all(1 if status in ["hover","focus","pressed"] else 0)
			style.set_corner_radius_all(3)
			control.add_theme_stylebox_override(status,style)
		control.add_theme_color_override("font_color",Color("dfebe9"))
		control.add_theme_color_override("font_hover_color",Color("fff1cf"))
		control.add_theme_color_override("font_pressed_color",Color("f3d493"))
		control.add_theme_font_override("font",app.Design.font(400))
		control.add_theme_font_size_override("font_size",19 if not str(control.name).begins_with("Choice_") else 22)
func _render_cast(data:Dictionary,current:Dictionary,line:Dictionary)->void:
	var actors:Array=line.get("actors",current.get("actors",[]))
	if bool(current.get("cg",false)) and ResourceLoader.exists(str(line.get("cg_asset",current.get("background_asset",current.get("cg_asset",""))))):actors=[]
	var keep:Array=[]
	for i in actors.size():
		var key:String=str(actors[i]);var row:Dictionary=data.get("cast",{}).get(key,{})
		var portrait:String=str(row.get("portrait",""));var hidden:bool=bool(row.get("hidden_identity",false)) or bool(row.get("silhouette",false)) or key.contains("shadow") or key.contains("silhouette")
		if hidden:portrait="res://assets/story/canon-v2/shinano-hologram.png"
		elif portrait.is_empty():portrait=str(app.cards.get(str(row.get("ship_id","")),{}).get("portrait",""))
		if portrait.is_empty() and not str(row.get("unit_id","")).is_empty():portrait=str(app.home.unit(str(row.unit_id)).get("portrait",""))
		var active:bool=str(line.get("speaker",""))==key
		var tone:String=str(line.get("actor_tones",{}).get(key,line.get("tone","calm") if active else "calm"))
		var expression:String="res://assets/story/chapter1/%s-%s.png"%[key,tone]
		if not hidden and key!="missouri" and ResourceLoader.exists(expression):portrait=expression
		if portrait.is_empty() or not ResourceLoader.exists(portrait):continue
		var actor:TextureRect=$Cast.get_node_or_null("Actor_"+key)
		if actor==null:
			actor=TextureRect.new();actor.name="Actor_"+key;$Cast.add_child(actor)
		if str(actor.get_meta("asset",""))!=portrait:actor.texture=ActorLayout.portrait(load(portrait),key);actor.set_meta("asset",portrait)
		ActorLayout.slot(actor,i,actors.size());actor.visible=true
		if not hidden and key!="missouri" and ResourceLoader.exists("res://assets/story/expressions-v2/%s-sheet.png"%key):
			var face=actor.get_node_or_null("FaceAnimation")
			if face==null:face=load("res://scripts/chapter_actor_animation.gd").new();face.name="FaceAnimation";actor.add_child(face)
			face.configure(app,actor,key,tone,active)
		actor.modulate=Color.WHITE if active else Color(.76,.82,.86,1)
		# The authored hologram already conceals her face. Preserve its readable rim
		# light instead of multiplying the entire silhouette into near-black.
		if hidden:actor.modulate=Color.WHITE
		keep.append(str(actor.name))
	for child in $Cast.get_children():child.visible=keep.has(str(child.name))
func _move(kind:String,value:String="")->void:
	if committing:return
	committing=true;var result:Dictionary=service.move(kind,value);committing=false
	if not result.get("ok",false):app.notify(result);return
	_render()
func _launch()->void:
	if committing:return
	committing=true
	var result:Dictionary=await Actions.launch(app)
	if not is_instance_valid(self):return
	committing=false
	if app.screen=="canon_story":
		if not result.get("ok",false):app.notify(result)
		else:_render()
func _check()->void:
	if committing:return
	var result:Dictionary=service.check_action(app.home)
	if not result.get("ok",false):app.notify(result);return
	_render()
