extends SceneTree
## Read-only narrative fixtures: no mission completion, rewards or account grants.
const Content=preload("res://scripts/chapter_story_data.gd")
const Chapter=preload("res://scripts/chapter_presentation.gd")
var app
var checks:=0
var failures:Array[String]=[]
var shots:Array[String]=[]
var measurements:Array[Dictionary]=[]
var paragraphs_checked:=0
var legacy_paragraphs_checked:=0
var minimum_text_margin:=100000.0
var output:="res://../artifacts/godot/story-portrait-safety/"
func _initialize()->void:call_deferred("run")
func check(value:bool,title:String)->void:
	checks+=1
	if not value:failures.append(title);push_error(title)
func shot(name:String)->void:
	await create_timer(.6).timeout
	for child in app.page.get_children():
		if child.has_method("continue_reading"):child.elapsed=1000.0;child._process(0.0);child.set_process(false)
	var tide:Node=app.page.get_node_or_null("TideStory")
	if tide!=null and is_instance_valid(tide.reader):tide.reader.elapsed=1000.0;tide.reader._process(0.0);tide.reader.set_process(false)
	await process_frame;await RenderingServer.frame_post_draw
	var path:=ProjectSettings.globalize_path(output+name+".png")
	check(root.get_texture().get_image().save_png(path)==OK,"actual GPU capture "+name);shots.append(path)
func window(dimensions:Vector2i)->void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	root.size=dimensions
	await process_frame;await process_frame
	check(root.size==dimensions,"actual window dimensions "+str(dimensions))
func painted_rect(actor:TextureRect)->Rect2:
	var rect:=actor.get_global_rect()
	var dimensions:Vector2=actor.texture.get_size()
	var factor:=minf(rect.size.x/dimensions.x,rect.size.y/dimensions.y)
	var painted:=dimensions*factor
	return Rect2(rect.position+(rect.size-painted)*.5,painted)

func portrait_frame_safe(actor:TextureRect,title:String)->void:
	check(actor.texture!=null and actor.stretch_mode==TextureRect.STRETCH_KEEP_ASPECT_CENTERED,title+" framed texture keeps its aspect")
	check(actor.mouse_filter==Control.MOUSE_FILTER_IGNORE,title+" portrait does not intercept continue")
	check(is_equal_approx(actor.modulate.a,1.0),title+" non-speaking head and shoulders remain opaque")
	var texture:Texture2D=actor.texture
	check(is_equal_approx(texture.get_size().x,texture.get_size().y),title+" matched square head-and-shoulder composition")
	if texture is AtlasTexture:
		check(Rect2(Vector2.ZERO,texture.atlas.get_size()).encloses(texture.region),title+" camera window stays inside original image")
	check(actor.material is ShaderMaterial and actor.material.shader.resource_path=="res://shaders/story_portrait_fade.gdshader",title+" natural lower-body feather is active")
	if actor.material is ShaderMaterial:
		var region:Vector4=actor.material.get_shader_parameter("frame_region")
		check(region.z>0 and region.w>0 and region.x>=0 and region.y>=0 and region.x+region.z<=1.001 and region.y+region.w<=1.001,title+" feather remains local to this portrait/expression frame")

func actors_safe(cast:Control,_shade:Control,caption:Control,title:String)->void:
	var view:=Rect2(Vector2.ZERO,app.page.size).grow(1)
	var rectangles:Array=[]
	for actor:TextureRect in cast.get_children():
		var rect:=actor.get_global_rect()
		portrait_frame_safe(actor,title+" "+actor.name)
		check(view.encloses(rect),title+" entire character control in visible stage "+actor.name)
		var painted:=painted_rect(actor)
		check(painted.size.y>=app.page.size.y*(.40 if cast.get_child_count()>=3 else .59),title+" close-up occupies the main visual area "+actor.name)
		check(painted.position.y+painted.size.y*.5<caption.get_global_rect().position.y if caption.name=="Speaker" else painted.position.y+painted.size.y*.5<app.page.size.y*.79,title+" head and shoulders stay above the reading zone "+actor.name)
		if actor.has_node("FaceAnimation"):
			var face:Node=actor.get_node("FaceAnimation")
			var original_top:float=actor.anchor_top
			for t in [0.0,1.2,4.65,4.8,9.4]:
				face.elapsed=t;face._process(.01)
				check(view.encloses(actor.get_global_rect()),title+" blink/talk motion remains within cinematic stage "+actor.name)
				check(actor.texture is AtlasTexture and actor.texture.region.size==Vector2(512,512),title+" full authored expression frame retained "+actor.name)
				portrait_frame_safe(actor,title+" animated "+actor.name)
			actor.anchor_top=original_top
		for previous:Rect2 in rectangles:check(not previous.intersects(rect),title+" cast slots do not cover each other")
		rectangles.append(rect)
	measurements.append({"page":title,"cast_count":rectangles.size(),"actor_rects":rectangles.map(func(r:Rect2):return [r.position.x,r.position.y,r.size.x,r.size.y])})

func readable_legacy(title:String)->void:
	var body:Label=null
	var speaker:Label=null
	for child in app.page.get_children():
		if bool(child.get_meta("story_dialogue_body",false)):body=child
		if bool(child.get_meta("story_dialogue_speaker",false)):speaker=child
	if body==null:return
	var font:Font=body.get_theme_font("font")
	var height:float=font.get_multiline_string_size(body.text,HORIZONTAL_ALIGNMENT_LEFT,body.size.x,26).y
	check(body.size.y>=height,title+" complete legacy paragraph fits")
	check(body.get_theme_font_size("font_size")==26,title+" legacy text remains readable without shrinking")
	check(speaker!=null and not speaker.get_global_rect().intersects(body.get_global_rect()),title+" legacy speaker and paragraph remain separated")
	for button:Button in app.page.find_children("*","Button",true,false):
		if button.is_visible_in_tree():check(not body.get_global_rect().intersects(button.get_global_rect()),title+" legacy text and action remain separated "+button.text)
	legacy_paragraphs_checked+=1

func readable_body(body:RichTextLabel,speaker:Control,title:String)->void:
	var margin:float=body.size.y-body.get_content_height()
	minimum_text_margin=minf(minimum_text_margin,margin)
	check(margin>=-.5,title+" complete paragraph fits at readable type size; margin="+str(margin))
	check(body.get_theme_font_size("normal_font_size")==26,title+" dialogue font size remains 26 without shrinking")
	check(not body.get_global_rect().intersects(speaker.get_global_rect()),title+" speaker and paragraph do not overlap")
	for button:Button in app.page.find_children("*","Button",true,false):
		if not button.is_visible_in_tree():continue
		check(not body.get_global_rect().intersects(button.get_global_rect()),title+" paragraph and action do not overlap "+button.text)
	paragraphs_checked+=1

func all_paragraphs()->void:
	for dimensions in [Vector2i(960,540),Vector2i(1280,720),Vector2i(1600,900),Vector2i(1600,720)]:
		await window(dimensions)
		for chapter_id in ["chapter-01","chapter-02","chapter-03"]:
			for node in Content.data(chapter_id).scenes:
				if str(node.kind)!="dialogue":continue
				for line in range(node.lines.size()):
					app.set_meta("chapter_replay_node",str(node.id));app.set_meta("chapter_replay_line",line);app.show_page("chapter")
					await process_frame;await process_frame;await process_frame
					var stage:Control=app.page.get_node("ChapterStage")
					readable_body(stage.get_node("Body"),stage.get_node("Speaker"),str(node.id)+":"+str(line)+" "+str(dimensions))
					var message:String=Chapter._spoken_text(app,str(node.id),line,node.lines[line])
					check(stage.get_node("Body").get_parsed_text()==message,"full authored/branch text retained "+str(node.id)+":"+str(line))
		app.remove_meta("chapter_replay_node");app.remove_meta("chapter_replay_line")
		for ending in [false,true]:
			app.set_meta("tide_story_ending",ending);app.show_page("tide_story")
			var story:Control=app.page.get_node("TideStory")
			for line in range(story.lines.size()):
				story.line_index=line;story._line();await process_frame;await process_frame;await process_frame
				readable_body(story.get_node("Body"),story.get_node("Speaker"),"tide "+str(ending)+":"+str(line)+" "+str(dimensions))
				check(story.get_node("Body").get_parsed_text()==str(story.lines[line].text),"full event text retained "+str(ending)+":"+str(line))
		for step in range(1,30):
			if step in [5,11,22,28]:continue
			app.economy.state.progression.story.step=step
			var rows:Array=app.progression.story_lines()
			for line in range(maxi(1,rows.size())):
				app.economy.state.progression.story.line=line;app.show_page("story");await process_frame;await process_frame
				readable_legacy("legacy "+str(step)+":"+str(line)+" "+str(dimensions))
func chapter(node:Dictionary,dimensions:Vector2i,capture:bool)->void:
	app.set_meta("chapter_replay_node",str(node.id));app.set_meta("chapter_replay_line",0)
	app.show_page("chapter");await window(dimensions)
	var stage:Control=app.page.get_node("ChapterStage")
	if not bool(node.get("cg",false)):
		actors_safe(stage.get_node("Cast"),stage.get_node("DialogueShade"),stage.get_node("Environment"),str(node.id)+" "+str(dimensions))
		var before:Dictionary={}
		for actor in stage.get_node("Cast").get_children():before[actor.get_instance_id()]=true
		app.set_meta("chapter_replay_line",mini(1,node.lines.size()-1));app.show_page("chapter");await process_frame
		check(app.page.get_node("ChapterStage")==stage,"line advance preserves stable stage "+str(node.id))
		check(stage.get_node("Cast").get_children().all(func(actor):return before.has(actor.get_instance_id())),"line advance preserves stable cast "+str(node.id))
	if capture:await shot("%dx%d-%s"%[dimensions.x,dimensions.y,str(node.id)])
func run()->void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	root.gui_embed_subwindows=true
	root.content_scale_size=Vector2i(1600,900)
	app=load("res://scenes/main.tscn").instantiate();app.boot_to_title=false
	app.economy=load("res://scripts/economy.gd").new("user://tests/portrait-safety-%d.json"%OS.get_process_id())
	root.add_child(app);app.set_process(false);await process_frame;await process_frame
	app.page_motion=false
	if "--design-preview" in OS.get_cmdline_user_args():
		await design_previews();app.audio.shutdown();app.core.close();app.queue_free();await process_frame;quit();return
	if "--prologue-edge-review" in OS.get_cmdline_user_args():
		await prologue_edge_review()
		var edge_report:Dictionary={"checks":checks,"failures":failures,"passed":failures.is_empty(),"screenshots":shots,"legacy_paragraphs_checked":legacy_paragraphs_checked,"scope":"Baixi lower side feather only; unchanged close-up geometry; GPU face/edge pixel comparison and legacy dialogue regression"}
		FileAccess.open(output+"prologue-edge-receipt.json",FileAccess.WRITE).store_string(JSON.stringify(edge_report,"  "))
		app.audio.shutdown();app.core.close();app.queue_free();await process_frame
		print("STORY_PROLOGUE_EDGE ",JSON.stringify(edge_report));quit(0 if failures.is_empty() else 1);return
	var state_before:Dictionary=app.economy.state.duplicate(true)
	for chapter_id in ["chapter-01","chapter-02","chapter-03"]:
		for node in Content.data(chapter_id).scenes:
			if str(node.kind)=="dialogue":await chapter(node,Vector2i(1600,900),str(node.id) in ["waking","return","hearing","message","c2-rations","c3-lighthouse"])
	for dimensions in [Vector2i(960,540),Vector2i(1280,720),Vector2i(1600,720)]:
		for id in ["return","message","c2-rations","c3-lighthouse"]:await chapter(Content.scene(id),dimensions,true)
	app.remove_meta("chapter_replay_node");app.remove_meta("chapter_replay_line")
	check(app.economy.state==state_before,"viewing chapters does not complete missions, alter progression or grant rewards")
	for dimensions in [Vector2i(960,540),Vector2i(1280,720),Vector2i(1600,900),Vector2i(1600,720)]:
		app.set_meta("tide_story_ending",false);app.show_page("tide_story");await window(dimensions)
		var tide:Control=app.page.get_node("TideStory")
		# First spoken page; narration intentionally shows only its CG.
		tide.line_index=1;tide._line();await process_frame
		check(tide.get_node("Cast").get_child_count()==2,"two original event portraits "+str(dimensions))
		actors_safe(tide.get_node("Cast"),tide.get_node("Shade"),tide.get_node("Speaker"),"tide "+str(dimensions))
		await shot("%dx%d-tide"%[dimensions.x,dimensions.y])
		for step in [1,3,6]:
			app.economy.state.progression.story.step=step;app.economy.state.progression.story.line=0
			app.show_page("story");await window(dimensions)
			var count:=0
			var shade:Control=null
			for child in app.page.get_children():
				if bool(child.get_meta("story_dialogue_shade",false)):shade=child
			check(shade!=null,"legacy dialogue shade identified "+str(step))
			for child in app.page.get_children():
				if not bool(child.get_meta("story_actor",false)):continue
				count+=1
				portrait_frame_safe(child,"legacy "+str(step)+" "+str(dimensions))
				check(painted_rect(child).size.y>=app.page.size.y*.59,"legacy close-up remains large "+str(step))
			check(count==1,"legacy spoken page contains one portrait "+str(step))
			readable_legacy("legacy fixture "+str(step)+" "+str(dimensions))
			if step==3:await shot("%dx%d-prologue"%[dimensions.x,dimensions.y])
	await all_paragraphs()
	var report:Dictionary={"checks":checks,"failures":failures,"passed":failures.is_empty(),"screenshots":shots,"layouts":measurements,"paragraphs_checked":paragraphs_checked,"legacy_paragraphs_checked":legacy_paragraphs_checked,"minimum_text_margin":minimum_text_margin,"scope":"isolated read-only narrative fixtures; cinematic close-up framing, feathered lower body, cast, animation and all chapter/event/prologue text safety; no mission results"}
	FileAccess.open(output+"receipt.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	app.audio.shutdown();app.core.close();app.queue_free();await process_frame
	print("STORY_PORTRAIT_SAFETY ",JSON.stringify({"checks":checks,"failures":failures,"screenshots":shots.size(),"paragraphs_checked":paragraphs_checked,"legacy_paragraphs_checked":legacy_paragraphs_checked,"minimum_text_margin":minimum_text_margin}));quit(0 if failures.is_empty() else 1)

func design_previews()->void:
	for dimensions in [Vector2i(960,540),Vector2i(1280,720)]:
		for id in ["return","c3-lighthouse"]:
			app.set_meta("chapter_replay_node",id);app.set_meta("chapter_replay_line",1);app.show_page("chapter");await window(dimensions)
			await shot("large-%dx%d-%s"%[dimensions.x,dimensions.y,id])
		app.remove_meta("chapter_replay_node");app.remove_meta("chapter_replay_line")
		app.show_page("tide_story");await window(dimensions)
		var tide:Control=app.page.get_node("TideStory");tide.line_index=1;tide._line();await process_frame
		await shot("large-%dx%d-tide"%[dimensions.x,dimensions.y])
		app.economy.state.progression.story.step=3;app.economy.state.progression.story.line=0;app.show_page("story");await window(dimensions)
		await shot("large-%dx%d-prologue"%[dimensions.x,dimensions.y])

func changed_pixels(before:Image,after:Image,area:Rect2)->int:
	var scale:=Vector2(float(before.get_width())/app.page.size.x,float(before.get_height())/app.page.size.y)
	var first:=Vector2i(area.position*scale)
	var last:=Vector2i(area.end*scale)
	var changed:=0
	for y in range(maxi(0,first.y),mini(before.get_height(),last.y)):
		for x in range(maxi(0,first.x),mini(before.get_width(),last.x)):
			if before.get_pixel(x,y)!=after.get_pixel(x,y):changed+=1
	return changed

func prologue_edge_review()->void:
	for dimensions in [Vector2i(960,540),Vector2i(1280,720),Vector2i(1600,900),Vector2i(1600,720)]:
		app.economy.state.progression.story.step=3;app.economy.state.progression.story.line=0;app.show_page("story");await window(dimensions)
		var actor:TextureRect=null
		for child in app.page.get_children():
			if bool(child.get_meta("story_actor",false)):actor=child
		check(actor!=null,"Baixi portrait is present "+str(dimensions))
		if actor==null:continue
		portrait_frame_safe(actor,"Baixi edge "+str(dimensions))
		check(is_equal_approx(actor.anchor_left,700.0/1600.0) and is_equal_approx(actor.anchor_top,126.0/900.0) and is_equal_approx(actor.anchor_right,1480.0/1600.0) and is_equal_approx(actor.anchor_bottom,816.0/900.0),"portrait size and position unchanged "+str(dimensions))
		var material:ShaderMaterial=actor.material
		check(is_equal_approx(float(material.get_shader_parameter("side_feather")),.035),"only narrow 3.5 percent side feather enabled "+str(dimensions))
		material.set_shader_parameter("side_feather",0.0);await process_frame;await RenderingServer.frame_post_draw
		var before:Image=root.get_texture().get_image()
		material.set_shader_parameter("side_feather",.035);await process_frame;await RenderingServer.frame_post_draw
		var after:Image=root.get_texture().get_image()
		var rect:=painted_rect(actor)
		var face:=Rect2(rect.position+rect.size*Vector2(.32,.08),rect.size*Vector2(.42,.34))
		var edge:=Rect2(rect.position+rect.size*Vector2(0,.48),rect.size*Vector2(.035,.18))
		check(changed_pixels(before,after,face)==0,"actual GPU face/crown pixels unchanged "+str(dimensions))
		check(changed_pixels(before,after,edge)>10,"actual GPU lower crop boundary is softened "+str(dimensions))
		await shot("%dx%d-prologue"%[dimensions.x,dimensions.y])
		for step in range(1,30):
			if step in [5,11,22,28]:continue
			app.economy.state.progression.story.step=step
			var rows:Array=app.progression.story_lines()
			for line in range(maxi(1,rows.size())):
				app.economy.state.progression.story.line=line;app.show_page("story");await process_frame;await process_frame
				readable_legacy("legacy edge "+str(step)+":"+str(line)+" "+str(dimensions))
			for child in app.page.get_children():
				if not bool(child.get_meta("story_actor",false)):continue
				var source:Texture2D=child.texture.atlas if child.texture is AtlasTexture else child.texture
				if not source.resource_path.contains("baixi"):
					check(float(child.material.get_shader_parameter("side_feather"))==0.0,"non-Baixi portraits retain original side opacity "+str(step))
