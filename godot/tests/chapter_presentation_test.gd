extends SceneTree
## Presentation fixtures never produce a battle result or a chapter reward.
const Main=preload("res://scenes/main.tscn")
const Economy=preload("res://scripts/economy.gd")
const Chapter=preload("res://scripts/chapter_presentation.gd")
const Content=preload("res://scripts/chapter_story_data.gd")
const Guide=preload("res://scripts/chapter_guide.gd")
const DialoguePlayer=preload("res://scripts/chapter_dialogue_player.gd")
var app
var checks:=0
var failures:Array[String]=[]
var screenshots:Array[String]=[]
var output:="res://../artifacts/godot/chapter-one/"
func _initialize()->void:call_deferred("run")
func check(value:bool,title:String)->void:
	checks+=1
	if not value:failures.append(title);push_error(title)
func shot(name:String)->void:
	await process_frame
	if DisplayServer.get_name()=="headless":return
	for player in app.page.get_children():
		if player.has_method("continue_reading"):player.elapsed=1000.0
	await create_timer(.8).timeout
	await RenderingServer.frame_post_draw
	var path:=ProjectSettings.globalize_path(output+name+".png")
	check(root.get_texture().get_image().save_png(path)==OK,"screenshot "+name);screenshots.append(path)
func run()->void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	var path:="user://tests/chapter-presentation-%d.json" % OS.get_process_id()
	app=Main.instantiate();app.boot_to_title=false;app.economy=Economy.new(path);root.add_child(app);app.set_process(false)
	await process_frame
	var old_story:Dictionary=app.progression.data().story.duplicate(true)
	var wallet:Dictionary=app.economy.wallet().duplicate(true)
	var commander:Dictionary=app.economy.state.commander.duplicate(true)
	var saved:Dictionary=app.progression.chapter_status()
	check(saved.node=="rescue" and saved.cleared.is_empty(),"new chapter starts independently at rescue")
	check(not app.progression.chapter_prepare("c1-boss").ok,"locked boss cannot be launched")
	check(app.progression.chapter_move("skip").ok and app.progression.chapter_status().node=="rescue","dialogue skip stops at explicit choice")
	check(not app.progression.chapter_move("choice","unknown").ok,"unknown dialogue choice rejected")
	check(app.progression.chapter_move("choice","crew").ok and app.progression.chapter_status().choices.rescue=="crew","explicit short choice persisted")
	check(app.progression.chapter_move("skip").ok and app.progression.chapter_move("next").ok,"reading can advance to first actual task")
	check(app.progression.chapter_status().node=="breakout" and not app.progression.chapter_move("next").ok and not app.progression.chapter_move("skip").ok,"text next and skip cannot bypass battle gate")
	var prepared:Dictionary=app.progression.chapter_prepare("c1-breakout")
	check(prepared.ok and prepared.request.op=="new_chapter" and prepared.context.mode=="story_chapter","first gate generates actual native chapter contract")
	check(app.progression.data().story==old_story and app.economy.wallet()==wallet,"reading changes neither old prologue nor wallet")
	for node in Content.data().scenes:
		var visual:Resource=load("res://data/chapter-scenes/%s.tres"%str(node.id))
		check(visual!=null and visual.has_method("presentation") and str(visual.scene_id)==str(node.id),"editable visual resource "+str(node.id))
		check(not visual.presentation().keys().any(func(key):return key in ["kind","stage","next","rewards","choices"]),"visual edits cannot override mission or reward "+str(node.id))
		app.economy.state.progression.chapter1.node=str(node.id);app.economy.state.progression.chapter1.line=0
		app.show_page("chapter");await process_frame
		check(app.page.get_child_count()>4,"chapter scene renders "+str(node.id))
		check(app.page.get_node("ChapterStage").scene_file_path=="res://scenes/chapter_stage.tscn" and app.page.get_node("ChapterStage/Body") is RichTextLabel,"actual editable scene used "+str(node.id))
		if str(node.id) in ["waking","supplies","archive"]:
			check(app.page.get_node("ChapterStage/Backdrop").get_meta("chapter_background")==str(node.background_asset),"new authored scene background loaded "+str(node.id))
		if str(node.id) in ["rescue","waking","silence","hearing","portguide","supplies","salvage","archive","message","boss","afterboss","promise","complete"]:await shot(str(node.id))
	app.economy.state.progression.chapter1.node="supplies";app.economy.state.progression.chapter1.line=Content.scene("supplies").lines.size()-1
	app.show_page("chapter");await process_frame
	check(app.page.get_node("ChapterStage/Speaker").text=="旁白" and not app.page.get_node("ChapterStage/Environment").text.is_empty(),"narrator and environmental caption have distinct visible slots")
	var face:Font=app.page.get_node("ChapterStage/Body").get_theme_font("normal_font")
	check(face is FontVariation and float(face.variation_opentype.get(TextServerManager.get_primary_interface().name_to_tag("wght"),0))==400.0,"actual dialogue uses readable regular font weight")
	await shot("drydock-narration")
	await motion_checks()
	for example in [{"node":"waking","line":1,"cast":"fletcher","tone":"concern"},{"node":"waking","line":3,"cast":"drayton","tone":"concern"},{"node":"message","line":1,"cast":"fletcher","tone":"resolve"}]:
		app.economy.state.progression.chapter1.node=example.node;app.economy.state.progression.chapter1.line=example.line
		app.show_page("chapter");await process_frame
		var expected:="res://assets/story/chapter1/%s-%s.png" % [example.cast,example.tone]
		check(Chapter.portrait_path(app,example.cast,example.tone)==expected and ResourceLoader.exists(expected),"generated expression selected "+example.cast+"-"+example.tone)
		await shot(example.cast+"-"+example.tone)
	app.economy.state.progression.chapter1.node="portguide"
	check(app.progression.chapter_move("tour").ok,"optional harbour tour starts")
	check(app.progression.chapter_status().node=="supplies" and app.progression.chapter_status().guide_active,"tour cannot gate later story behind transactions")
	for step in Content.data().guide:
		app.show_page(str(step.route))
		# Main calls the helper when integrated. Render explicitly only if absent.
		var exists:=false
		for control in app.find_children("*","Button",true,false):
			if bool(control.get_meta("chapter_guide_next",false)) and control.is_visible_in_tree():exists=true
		if not exists:Guide.render(app)
		await process_frame
		var found:=false
		for control in app.find_children("*","Button",true,false):
			if bool(control.get_meta("chapter_guide_next",false)) and control.is_visible_in_tree():found=true
		check(found,"dismissible optional tour card "+str(step.route))
		if str(step.route) in ["harbor","mail"]:await shot("guide-"+str(step.route))
		if str(step.route)=="harbor":
			Guide._collapse(app,true);await process_frame
			var expanded:=false
			for control in app.find_children("*","Button",true,false):
				if bool(control.get_meta("chapter_guide_expand",false)) and control.is_visible_in_tree():expanded=true
			check(expanded and app.progression.chapter_status().guide_active and app.economy.wallet()==wallet,"guide collapses without stopping progression or forcing a transaction")
			await shot("guide-collapsed")
			Guide._collapse(app,false)
		check(app.progression.chapter_move("guide_next").ok,"tour records view without purchase "+str(step.route))
	check(not app.progression.chapter_status().guide_active and app.economy.wallet()==wallet,"tour ends with no transaction or resource change")
	check(app.progression.chapter_move("tour").ok and app.progression.chapter_move("guide_end").ok,"tour can be reopened and dismissed")
	check(app.progression.chapter_status().cleared.is_empty() and app.progression.chapter_status().claimed.is_empty(),"all presentation fixtures grant no false clear or rewards")
	check(app.economy.state.commander==commander,"viewing, reading and tour grant no commander experience")
	app.audio.shutdown();app.core.close();app.queue_free();await process_frame
	for suffix in ["",".bak",".tmp"]:
		if FileAccess.file_exists(path+suffix):DirAccess.remove_absolute(ProjectSettings.globalize_path(path+suffix))
	var report:={"checks":checks,"passed":checks-failures.size(),"failures":failures,"screenshots":screenshots,"scope":"isolated narrative/presentation fixtures; task gates and optional tour transactions; native battles checked separately"}
	var file:=FileAccess.open(output+"presentation-receipt.json",FileAccess.WRITE);file.store_string(JSON.stringify(report,"\t"));file.close()
	print(JSON.stringify(report));quit(0 if failures.is_empty() else 1)

func motion_checks()->void:
	# Exercise the reader's timing and input, without replacing progression or battle data.
	for child in app.page.get_children():
		if child.has_method("continue_reading"):child.set_process(false)
	var label:=RichTextLabel.new();label.bbcode_enabled=true;label.text="海。风";app.page.add_child(label)
	var calls:={"count":0}
	var reader=DialoguePlayer.new();reader.app=app;reader.text_label=label;reader.characters_per_second=20.0;reader.text_effect="tremble";reader.advance=func():calls.count+=1
	app.page.add_child(reader);reader.set_process(false)
	check("[wave" in label.text and label.get_meta("chapter_text_effect")=="tremble","selected cold/alarm line receives a gentle wave")
	reader.elapsed=.22
	check(reader._visible_count()==2,"full stop inserts a readable pause before the next character")
	reader.continue_reading()
	check(calls.count==0 and label.get_parsed_text()=="海。风" and "[wave" not in label.text,"first click reveals and settles without skipping the line")
	reader.continue_reading()
	check(calls.count==1,"second click advances exactly once")
	reader.free();label.free()
	label=RichTextLabel.new();label.bbcode_enabled=true;label.text="不要着急。";app.page.add_child(label)
	reader=DialoguePlayer.new();reader.app=app;reader.text_label=label;reader.text_effect="echo";reader.advance=func():calls.count+=1
	app.page.add_child(reader);reader.set_process(false);reader.elapsed=1000.0;reader._process(.4)
	check("[wave" not in label.text and bool(label.get_meta("chapter_effect_settled",false)),"voice echo finishes its movement after reveal")
	var elapsed:float=reader.elapsed
	app.open_modal("暂停阅读");reader._process(5.0)
	check(reader.elapsed==elapsed,"modal inspection pauses dialogue timing")
	app.close_modal();reader.free();label.free()
	label=RichTextLabel.new();label.bbcode_enabled=true;label.text="保持安静。";app.page.add_child(label)
	reader=DialoguePlayer.new();reader.app=app;reader.text_label=label;reader.text_effect="tremble";reader.reduced_motion=true;reader.advance=func():calls.count+=1
	app.page.add_child(reader);reader.set_process(false)
	check("[wave" not in label.text and label.get_meta("chapter_text_effect")=="none","reduced motion renders the same text completely still")
	reader.free();label.free()
