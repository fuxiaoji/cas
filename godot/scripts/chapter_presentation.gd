extends RefCounted
const Design=preload("res://scripts/ui_design.gd")
const Cinema=preload("res://scripts/cinematic_presentation.gd")
const Content=preload("res://scripts/chapter_story_data.gd")
const DialoguePlayer=preload("res://scripts/chapter_dialogue_player.gd")
const Stage=preload("res://scenes/chapter_stage.tscn")
const Supply=preload("res://scripts/supply_presentation.gd")
const WHITE=Color("f5f8fa")
const ActorLayout=preload("res://scripts/story_actor_layout.gd")

static func refresh(app)->bool:
	if not is_instance_valid(app.page) or not app.page.has_node("ChapterStage"):return false
	render(app)
	return true

static func render(app)->void:
	var saved:Dictionary=app.progression.chapter_status()
	var replay:=str(app.get_meta("chapter_replay_node",""))
	var node:Dictionary=Content.scene(replay if not replay.is_empty() else str(saved.node))
	if node.is_empty():return
	var kind:=str(node.kind)
	var line_index:=int(app.get_meta("chapter_replay_line",0)) if not replay.is_empty() else int(saved.line)
	var lines:Array=node.get("lines",[])
	var line:Dictionary=lines[clampi(line_index,0,lines.size()-1)] if not lines.is_empty() else {}
	var key:=str(node.id)+":"+str(line_index)+":"+replay
	var same_line:bool=str(app.page.get_meta("chapter_line_key",""))==key
	# Keep the actual stage and reader. A line change must not rebuild the sea, cast or window.
	for child in app.page.get_children():
		if child.name=="ChapterStage" or (child.name=="ChapterDialogueReader" and same_line):continue
		app.page.remove_child(child);child.queue_free()
	app.first_button=null;app.toast_label=null
	var night:=str(node.get("background","day")) in ["night","silence","gate"]
	if app.audio!=null:
		app.audio.set_paused(false)
		var cue:String=str(node.get("music_scene","story_tension" if night or kind=="battle" else "story"))
		if cue=="harbor":cue="story_tension" if night or kind=="battle" else "story"
		app.audio.set_scene(cue)
		if app.audio.has_method("set_dialogue_active"):app.audio.set_dialogue_active(kind=="dialogue")
	_background(app,node,line,night,not same_line)
	_chrome(app,node,kind,replay,night)
	app.page.set_meta("chapter_line_key",key)
	if kind=="battle":_battle(app,node,saved);return
	if kind=="guide":_guide(app,node);return
	if kind=="complete":_complete(app,saved);return
	_dialogue(app,node,line,line_index,replay,same_line)

static func _background(app,node:Dictionary,line:Dictionary,_night:bool,new_line:bool=true)->void:
	var setting:=str(node.get("background","day"))
	var stage:Control=app.page.get_node_or_null("ChapterStage")
	if stage==null:
		stage=Stage.instantiate();app.page.add_child(stage);stage.name="ChapterStage"
		stage.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	stage.dialogue_visible(str(node.kind)=="dialogue")
	var path:=Content.background_path(node)
	var has_cg:bool=bool(node.get("cg",false)) and ResourceLoader.exists(path)
	var near:=str(line.get("shot","wide"))=="near"
	var backdrop:TextureRect=stage.get_node("Backdrop")
	var reduced:bool=bool(app.get_meta("reduced_motion",false))
	var changed:bool=str(backdrop.get_meta("chapter_background",""))!=path
	if changed:
		for child in stage.get_children():
			if str(child.name).begins_with("BackgroundBlend"):
				stage.remove_child(child);child.queue_free()
		if backdrop.texture!=null and not reduced:
			var previous:=TextureRect.new();previous.name="BackgroundBlend";previous.texture=backdrop.texture
			previous.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;previous.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_COVERED;previous.mouse_filter=Control.MOUSE_FILTER_IGNORE
			stage.add_child(previous);stage.move_child(previous,1);previous.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			var cross:Tween=app.create_tween().bind_node(previous)
			cross.tween_property(previous,"modulate:a",0.0,.45).set_trans(Tween.TRANS_SINE)
			cross.tween_callback(previous.queue_free)
		backdrop.texture=load(path)
		backdrop.scale=Vector2.ONE
	if changed or near!=bool(backdrop.get_meta("chapter_near",false)) or reduced:
		_stop_tween(backdrop,"chapter_camera")
		var target:=Vector4(-.03125,-.0278,1.03125,1.0344) if near else Vector4(0,0,1,1)
		if reduced or changed:
			backdrop.anchor_left=target.x;backdrop.anchor_top=target.y;backdrop.anchor_right=target.z;backdrop.anchor_bottom=target.w
		else:
			var camera:Tween=app.create_tween().bind_node(backdrop).set_parallel(true)
			for property in ["anchor_left","anchor_top","anchor_right","anchor_bottom"]:
				camera.tween_property(backdrop,property,target[["anchor_left","anchor_top","anchor_right","anchor_bottom"].find(property)],.4).set_trans(Tween.TRANS_SINE)
			backdrop.set_meta("chapter_camera",camera)
	backdrop.set_meta("chapter_background",path)
	backdrop.set_meta("chapter_near",near)
	var actors:Array=line.get("actors",node.get("actors",[])).duplicate()
	if not has_cg and actors.is_empty():actors=["fletcher","drayton"] if setting=="rescue" else [str(line.get("speaker","fletcher"))]
	var cast:Control=stage.get_node("Cast")
	for actor in cast.get_children():
		if has_cg or not actors.has(str(actor.get_meta("chapter_actor",""))):cast.remove_child(actor);actor.queue_free()
	if not has_cg:
		for i in range(actors.size()):
			var key:=str(actors[i])
			var mood:=str(line.get("actor_tones",{}).get(key,line.get("tone","calm") if key==str(line.get("speaker","")) else "calm"))
			var director_token:=str(node.id)+":"+str(node.get("lines",[]).find(line))+":"+key
			_actor(app,key,i,actors.size(),str(line.get("speaker","")),mood,str(line.get("motion","none")) if new_line else "none",director_token)
	# Signals are conveyed by the caption and finite text echo. No whole-screen white/cyan flash.

static func _stop_tween(node:Node,key:String)->void:
	if not node.has_meta(key):return
	var tween:Variant=node.get_meta(key)
	if tween is Tween and tween.is_valid():tween.kill()
	node.remove_meta(key)

static func portrait_path(app,key:String,tone:String="calm")->String:
	var cast:Dictionary=Content.data().get("cast",{}).get(key,{})
	var expression:="res://assets/story/chapter1/%s-%s.png" % [key,tone]
	if ResourceLoader.exists(expression):return expression
	if cast.has("ship_id"):return str(app.cards.get(str(cast.ship_id),{}).get("portrait",""))
	return str(cast.get("portrait",""))

static func _actor(app,key:String,index:int,count:int,speaker:String,tone:String,motion:String="none",director_token:String="")->void:
	var active:=key==speaker
	var x:=float(index)*(500.0 if count==3 else 700.0)+25.0
	if count==1:x=510.0
	var path:=portrait_path(app,key,tone)
	if path.is_empty() or not ResourceLoader.exists(path):
		app.icon(app.page,"story",x+160,315,170,170,Color(0.4,0.7,0.8,0.65))
		return
	var cast:Control=app.page.get_node("ChapterStage/Cast")
	var actor:TextureRect=cast.get_node_or_null("Actor_"+key)
	var fresh:bool=actor==null
	if fresh:
		actor=app.picture(cast,path,0,0,1600,900);actor.name="Actor_"+key
	else:
		actor.texture=load(path)
	actor.texture=ActorLayout.portrait(actor.texture,key)
	ActorLayout.fade(actor)
	if str(actor.get_meta("chapter_slot",""))!=str(index)+":"+str(count):
		ActorLayout.slot(actor,index,count)
		actor.set_meta("chapter_slot",str(index)+":"+str(count))
	actor.set_meta("chapter_actor",key)
	actor.set_meta("chapter_expression_asset",path)
	# Keep the entire portrait. A pre-authored expression frame may be a bust, but an
	# ordinary full-length source must never be cropped into a square to match it.
	var sheet_path:="res://assets/story/expressions-v2/%s-sheet.png"%key
	if ResourceLoader.exists(sheet_path):
		var face=actor.get_node_or_null("FaceAnimation")
		if face==null:face=load("res://scripts/chapter_actor_animation.gd").new();face.name="FaceAnimation";actor.add_child(face)
		face.configure(app,actor,key,tone,active)

	var color:=Color.WHITE if active else Color(.72,.78,.82,1.0)
	_stop_tween(actor,"chapter_highlight")
	if fresh or bool(app.get_meta("reduced_motion",false)):actor.modulate=color
	else:
		var highlight:Tween=app.create_tween().bind_node(actor)
		highlight.tween_property(actor,"modulate",color,.18)
		actor.set_meta("chapter_highlight",highlight)
	if bool(app.get_meta("reduced_motion",false)):
		_stop_tween(actor,"chapter_motion");actor.scale=Vector2.ONE;actor.anchor_top=float(actor.get_meta("story_rest_top",.015))
	elif active:
		if motion in ["step","wake"] and str(actor.get_meta("chapter_director_token",""))!=director_token:
			actor.set_meta("chapter_director_token",director_token)
			_stop_tween(actor,"chapter_motion")
			var landing:float=actor.position.x
			actor.position.x-=12.0
			var entrance:Tween=app.create_tween().bind_node(actor)
			entrance.tween_property(actor,"position:x",landing,.32).set_trans(Tween.TRANS_SINE)
			actor.set_meta("chapter_motion",entrance)
			actor.set_meta("chapter_directed_motion_count",int(actor.get_meta("chapter_directed_motion_count",0))+1)

static func _chrome(app,node:Dictionary,kind:String,replay:String,_night:bool)->void:
	Cinema.quiet_button(app,app.page,"‹ 路线",24,10,120,func():_leave(app),true)
	Cinema.quiet_button(app,app.page,"母港",150,10,94,func():app.go_home(),true)
	app.label(app.page,str(Content.data().title)+" / "+str(node.title),260,12,750,38,19,WHITE)
	Cinema.quiet_button(app,app.page,"章节",1040,10,100,func():index(app),true)
	Cinema.quiet_button(app,app.page,"回顾",1155,10,100,func():backlog(app),true)
	if kind=="dialogue":
		Cinema.quiet_button(app,app.page,"自动：开" if bool(app.get_meta("chapter_auto",false)) else "自动",1270,10,116,func():app.set_meta("chapter_auto",not bool(app.get_meta("chapter_auto",false)));app.show_page("chapter"),true)
		Cinema.quiet_button(app,app.page,"跳过本段",1400,10,160,func():_skip(app,node,replay),true)
	var location:=str(node.get("location",""))
	if not location.is_empty() and app.page.get_node("ChapterStage/Environment").text.is_empty():app.label(app.page,location,170,53,810,24,14,Color(.8,.85,.88))
	app.toast_label=app.label(app.page,"",56,97,1470,30,18,WHITE)

static func _dialogue(app,node:Dictionary,line:Dictionary,line_index:int,replay:String,same_line:bool=false)->void:
	var key:=str(line.get("speaker",""))
	var speaker:=Content.speaker_name(line)
	var message:=_spoken_text(app,str(node.id),line_index,line)
	_remember(app,str(node.id),line_index,speaker,message)
	var stage=app.page.get_node("ChapterStage")
	stage.get_node("Speaker").text=speaker
	stage.get_node("Environment").text=str(line.get("caption",""))
	var text:RichTextLabel=stage.get_node("Body")
	var player=app.page.get_node_or_null("ChapterDialogueReader")
	if not same_line or player==null:text.text=message.replace("[","[lb]")
	text.set_meta("chapter_text",true)
	var choosing:bool=not node.get("choices",[]).is_empty() and line_index>=node.get("lines",[]).size()-1
	stage.layout_dialogue(choosing,message)
	if choosing:
		for i in range(node.choices.size()):
			var answer:Dictionary=node.choices[i]
			var reply:Button=app.button(app.page,str(answer.text),145+i*665,834,645,48,func():_choose(app,str(answer.id),replay))
			reply.set_meta("chapter_choice",str(answer.id))
		return
	if player==null:
		player=DialoguePlayer.new();player.name="ChapterDialogueReader"
		player.app=app;player.text_label=text;player.advance=func():_next(app,node,replay)
		player.characters_per_second=float(line.get("characters_per_second",28.0 if key.is_empty() else 34.0))
		player.text_effect=str(line.get("text_effect","none"))
		player.reduced_motion=bool(app.get_meta("reduced_motion",false))
		app.page.add_child(player)
	player.automatic=bool(app.get_meta("chapter_auto",false))
	if bool(app.get_meta("reduced_motion",false)):
		player.reduced_motion=true;player._settle();text.set_meta("chapter_text_effect","none")
	var next:Button=Cinema.quiet_button(app,app.page,"继续  ›",1390,824,165,player.continue_reading,true)
	next.set_meta("chapter_continue",true)
	app.label(app.page,"空格 / Enter",1400,875,160,18,12,Color(0.69,0.79,0.83))

static func _spoken_text(app,node:String,line_index:int,line:Dictionary)->String:
	var saved:Dictionary=app.progression.chapter_status()
	# Authored revision owns its beat-specific evidence wording, instead of old
	# positional substitutions that would now overwrite an unrelated spoken line.
	if str(Content.data().get("narrative_revision","")).begins_with("cas-longform"):
		return str(line.get("text",""))
	if not bool(saved.evidence.get("aversion_spared_flagship",false)):
		if node=="silence" and line_index==0:return "那具憎恶的炮口……\n我没看清。把接触记录先留下来。"
		if node=="silence" and line_index==1:return "别急着下结论。我们还不知道，\n她在什么情况下会选择目标。"
		if node=="hearing" and line_index==0:return "从憎恶出没的海上捡来，没有舰历？\n这不是小事。这是必须解释的事。"
	if node=="waking" and line_index==0 and str(saved.choices.get("rescue","lost"))=="crew":return "先担心别人……你和弗莱彻倒很像。\n不过现在，有东西在追我们。"
	if node=="message" and line_index==0 and str(saved.choices.get("archive","share"))=="protect":return "旧金山藏不住神的记忆。\n第五队，把那份档案放回海里。"
	if node=="c2-lifeline" and line_index==3 and str(saved.choices.get("c2-rations","borrow"))=="earn":return "你还没有一个能证明过去的名字。\n但这条航线上，每一艘平安返航的船，都替你写下了现在。"
	if node=="c3-after" and line_index==0 and str(saved.choices.get("c3-choice","refuse"))=="together":return "最后一段铭环熄灭，潮门缓缓合拢。\n答案还在海图之外。这一次，你不用一个人去找。"
	return str(line.get("text",""))

static func _next(app,node:Dictionary,replay:String)->void:
	if not replay.is_empty():
		var at:=int(app.get_meta("chapter_replay_line",0))+1
		if at>=node.get("lines",[]).size():app.remove_meta("chapter_replay_node");app.remove_meta("chapter_replay_line")
		else:app.set_meta("chapter_replay_line",at)
		app.show_page("chapter");return
	_apply(app,app.progression.chapter_move("next"))

static func _skip(app,node:Dictionary,replay:String)->void:
	if not replay.is_empty():
		app.remove_meta("chapter_replay_node");app.remove_meta("chapter_replay_line");app.show_page("chapter");return
	var state:Dictionary=app.progression.chapter_status()
	for i in range(int(state.line),node.get("lines",[]).size()):
		var line:Dictionary=node.lines[i]
		_remember(app,str(node.id),i,Content.speaker_name(line),_spoken_text(app,str(node.id),i,line))
	var result:Dictionary=app.progression.chapter_move("skip")
	if result.get("ok",false) and str(app.progression.chapter_status().node)==str(node.id) and node.get("choices",[]).is_empty():result=app.progression.chapter_move("next")
	_apply(app,result)

static func _choose(app,answer:String,replay:String)->void:
	if not replay.is_empty():
		app.remove_meta("chapter_replay_node");app.remove_meta("chapter_replay_line");app.show_page("chapter");return
	_apply(app,app.progression.chapter_move("choice",answer))

static func _apply(app,response:Dictionary)->void:
	app.show_page("chapter")
	if not response.get("ok",false):app.notify(response)

static func _leave(app)->void:
	app.remove_meta("chapter_replay_node");app.remove_meta("chapter_replay_line")
	app.set_meta("story_route_node",str(app.progression.chapter_status().node))
	app.go_back("story_route")

static func _battle(app,node:Dictionary,saved:Dictionary)->void:
	Cinema.gradient(app,app.page,Rect2(0,350,1600,550),Color(0.025,0.07,0.11,0),Color(0.025,0.07,0.11,0.97))
	app.label(app.page,str(node.objective),92,548,1210,83,30,WHITE)
	app.label(app.page,str(node.hint),96,657,1180,68,23,Color("bad2d7"))
	var cleared:bool=saved.cleared.has(str(node.stage))
	var completed_revisit:bool=bool(node.get("longform_extra",false)) and str(Content.scene(str(saved.node)).get("kind",""))=="complete"
	app.label(app.page,"第五小队借用出航 · 不消耗个人物资",96,748,1075,37,20,WHITE)
	app.label(app.page,"已完章回访 · 保留原进度，本次不重复发放奖励" if completed_revisit else "首次通关  "+Supply.rewards_text(node.get("rewards",{}))+" / 指挥官经验 ×150" if not cleared else "本关已完成 · 再战不重复领取首次奖励",96,799,1050,37,19,Design.GOLD)
	var active:bool=not app.economy.state.get("active_run",{}).is_empty()
	var launch:Button=app.button(app.page,"继续海上行动" if active else "再次出击" if cleared else "进入作战",1170,782,350,68,func():app.resume_run() if active else launch_stage(app,str(node.stage)),true)
	launch.set_meta("chapter_launch",str(node.stage))
	if active:app.label(app.page,"先完成或结束已有航次，再开始这一关。",96,851,1100,30,18,Color("bad2d7"))

static func launch_stage(app,id:String)->void:
	var prepared:Dictionary=app.progression.chapter_prepare(id)
	if not prepared.get("ok",false):app.notify(prepared);return
	app.remove_meta("chapter_replay_node");app.remove_meta("chapter_replay_line")
	app.start_local_mode(prepared.request,prepared.context)

static func _guide(app,node:Dictionary)->void:
	Cinema.gradient(app,app.page,Rect2(0,500,1600,400),Color(0.025,0.07,0.11,0),Color(0.025,0.07,0.11,0.96))
	app.label(app.page,"这次，让我带路。",96,600,1200,70,32,WHITE)
	app.label(app.page,str(node.text),100,693,1200,100,24,WHITE)
	app.button(app.page,"带我看看",1000,811,430,60,func():start_tour(app),true)
	Cinema.quiet_button(app,app.page,"我先自己逛逛",98,815,380,func():_apply(app,app.progression.chapter_move("guide_skip")),true)

static func start_tour(app)->void:
	var response:Dictionary=app.progression.chapter_move("tour")
	if response.get("ok",false):app.set_meta("chapter_guide_collapsed",false);app.show_page("harbor")
	else:app.notify(response)

static func _complete(app,saved:Dictionary)->void:
	Cinema.gradient(app,app.page,Rect2(0,300,1600,600),Color(0.025,0.07,0.11,0),Color(0.025,0.07,0.11,0.96))
	app.label(app.page,str(Content.data().title)+"。",92,540,1160,90,40,WHITE)
	app.label(app.page,str(Content.scene(str(saved.node)).get("ending","港口重新亮起返航灯。新的问题，留到下一次出航。")),98,652,1220,69,25,WHITE)
	var total:int=Content.data().scenes.filter(func(row):return str(row.kind)=="battle").size()
	app.label(app.page,"已完成 %d / %d 场真实行动" % [saved.cleared.size(),total],98,737,750,40,21,Design.GOLD)
	app.button(app.page,"返回章节路线",1125,799,385,65,func():_leave(app),true)
	Cinema.quiet_button(app,app.page,"重看章节",90,809,255,func():index(app),true)
	var next_id:=str(Content.scene(str(saved.node)).get("next_chapter","chapter-02" if Content.selected_chapter=="chapter-01" else ""))
	if not next_id.is_empty():Cinema.quiet_button(app,app.page,"下一章  ›",360,809,255,func():app.progression.chapter_select(next_id);app.set_meta("story_route_node",str(app.progression.chapter_status().node));app.show_page("story_route"),true)

static func _remember(app,node:String,line:int,speaker:String,text:String)->void:
	var log:Array=app.get_meta("chapter_backlog",[])
	var key:=node+":"+str(line)
	if not log.any(func(row):return str(row.get("key",""))==key):log.append({"key":key,"speaker":speaker,"text":text})
	app.set_meta("chapter_backlog",log)

static func backlog(app)->void:
	var layer:Control=app.open_modal(str(Content.data().title)+" · 对白回顾")
	# Reconstruct read lines after a restart from persistent scene/line progress.
	var saved:Dictionary=app.progression.chapter_status()
	for node in Content.data().scenes:
		if str(node.kind)!="dialogue":continue
		var visited:bool=saved.seen.has(str(node.id))
		if not visited and str(saved.node)!=str(node.id):continue
		var limit:int=node.lines.size() if visited else mini(node.lines.size(),int(saved.line)+1)
		for i in range(limit):
			var line:Dictionary=node.lines[i]
			var speaker:=Content.speaker_name(line)
			_remember(app,str(node.id),i,speaker,_spoken_text(app,str(node.id),i,line))
		for choice in node.get("choices",[]):
			if str(saved.choices.get(str(node.id),""))==str(choice.id):_remember(app,str(node.id),node.lines.size(),"你",str(choice.text))
	var scroll:=ScrollContainer.new();app.place(scroll,layer,382,230,836,455)
	var list:=VBoxContainer.new();list.size_flags_horizontal=Control.SIZE_EXPAND_FILL;list.add_theme_constant_override("separation",21);scroll.add_child(list)
	var log:Array=app.get_meta("chapter_backlog",[])
	log.sort_custom(func(a:Dictionary,b:Dictionary):return _log_position(str(a.key))<_log_position(str(b.key)))
	for row in log:
		var label:=Label.new();label.text=str(row.speaker)+"\n"+str(row.text);label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;label.custom_minimum_size.x=740;label.add_theme_font_override("font",Design.font());label.add_theme_font_size_override("font_size",22);label.add_theme_color_override("font_color",Design.INK);list.add_child(label)

static func _log_position(key:String)->int:
	var nodes:Array=Content.data().scenes
	for i in range(nodes.size()):
		if str(nodes[i].id)==key.get_slice(":",0):return i*10000+int(key.get_slice(":",1))
	return 99999

static func index(app)->void:
	app.set_meta("story_chapter_id",Content.selected_chapter)
	app.set_meta("story_route_node",str(app.progression.chapter_status().node))
	app.go_back("story_route")

static func _open_node(app,id:String)->void:
	app.close_modal()
	if id==str(app.progression.chapter_status().node):_leave_replay(app)
	else:app.set_meta("chapter_replay_node",id);app.set_meta("chapter_replay_line",0)
	app.show_page("chapter")

static func _leave_replay(app)->void:
	app.remove_meta("chapter_replay_node");app.remove_meta("chapter_replay_line")
