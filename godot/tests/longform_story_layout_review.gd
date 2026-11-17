extends "res://tests/story_portrait_safety_review.gd"
## Read-only story fixtures, plus an explicitly labelled old-complete compatibility fixture.
var page_total:int=0
var cast_swaps:int=0
func run()->void:
	output="res://../artifacts/godot/story-longform-layout/"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	root.gui_embed_subwindows=true;root.content_scale_size=Vector2i(1600,900)
	app=load("res://scenes/main.tscn").instantiate();app.boot_to_title=false
	app.economy=load("res://scripts/economy.gd").new("user://tests/longform-layout-%d.json"%OS.get_process_id())
	root.add_child(app);app.set_process(false);await process_frame;await process_frame
	app.page_motion=false
	if "--copy-review" in OS.get_cmdline_user_args():
		await changed_copy()
		FileAccess.open(output+"copy-review-receipt.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"passed":checks-failures.size(),"failures":failures,"scope":"last two natural-dialogue wording corrections, actual GPU body and Resource checks"},"\t"))
		app.audio.shutdown();app.core.close();app.queue_free();await process_frame
		print("COPY_REVIEW ",checks," ",failures);quit(0 if failures.is_empty() else 1);return
	await paragraphs()
	await director_cues()
	await compatibility()
	var report:Dictionary={"checks":checks,"passed":checks-failures.size(),"failures":failures,"pages_checked":page_total,"stable_cast_swaps":cast_swaps,"minimum_text_margin":minimum_text_margin,"shots":shots,"scope":"all compiled dialogue pages at two real GPU aspect ratios; directed expressions/motions; legacy save compatibility fixtures explicitly separate from the real 18-mission playthrough"}
	FileAccess.open(output+"receipt.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	app.audio.shutdown();app.core.close();app.queue_free();await process_frame
	print(JSON.stringify(report));quit(0 if failures.is_empty() else 1)

func changed_copy()->void:
	for dimensions in [Vector2i(960,540),Vector2i(1600,720)]:
		await window(dimensions)
		for id in ["waking","c2-unposted-letter"]:
			app.economy.state.progression.story_chapter_id=Content.chapter_for_node(id)
			var node:Dictionary=Content.scene(id)
			for i in range(node.lines.size()):
				var text:=str(node.lines[i].text)
				if not (text.begins_with("右边的响声近了") or text.begins_with("这封信不归我们个人")):continue
				app.set_meta("chapter_replay_node",id);app.set_meta("chapter_replay_line",i);app.show_page("chapter");await process_frame;await process_frame
				var stage:Control=app.page.get_node("ChapterStage")
				readable_body(stage.get_node("Body"),stage.get_node("Speaker"),id+" final copy")
				check(stage.get_node("Body").get_parsed_text()==text,"final natural wording is actual resource text")

func paragraphs()->void:
	for dimensions in [Vector2i(1600,900),Vector2i(1600,720)]:
		await window(dimensions)
		for chapter_id in ["chapter-01","chapter-02","chapter-03"]:
			app.economy.state.progression.story_chapter_id=chapter_id
			for node in Content.data(chapter_id).scenes:
				if str(node.kind)!="dialogue":continue
				var previous:Dictionary={}
				for i in range(node.lines.size()):
					app.set_meta("chapter_replay_node",str(node.id));app.set_meta("chapter_replay_line",i);app.show_page("chapter")
					await process_frame;await process_frame
					var stage:Control=app.page.get_node("ChapterStage")
					var body:RichTextLabel=stage.get_node("Body")
					readable_body(body,stage.get_node("Speaker"),str(node.id)+":"+str(i)+" "+str(dimensions))
					check(body.get_parsed_text()==str(node.lines[i].text),"runtime Resource retains authored body "+str(node.id)+":"+str(i))
					var actors:Array=node.lines[i].get("actors",node.get("actors",[]))
					var speaker:=str(node.lines[i].speaker)
					if not bool(node.get("cg",false)):
						var cast:Control=stage.get_node("Cast")
						check(cast.get_child_count()<=3,"at most three authored portraits")
						if Content.data(chapter_id).cast.has(speaker):check(cast.has_node("Actor_"+speaker),"actual speaking portrait "+speaker)
						var now:Dictionary={}
						for actor in cast.get_children():
							var key:=str(actor.get_meta("chapter_actor",""));now[key]=actor.get_instance_id()
							if previous.has(key):check(previous[key]==actor.get_instance_id(),"unchanged actor instance stays stable "+key)
						if not previous.is_empty() and now.keys()!=previous.keys():cast_swaps+=1
						previous=now
					page_total+=1
				if str(node.id) in ["c1-supp-game","c2-market","c3-tideborn-account"]:await shot(str(node.id)+"-%dx%d"%[dimensions.x,dimensions.y])
	app.remove_meta("chapter_replay_node");app.remove_meta("chapter_replay_line")

func director_cues()->void:
	await window(Vector2i(960,540))
	var directives:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/story-longform/direction-overrides.json"))
	for chapter_id in directives.chapters:
		app.economy.state.progression.story_chapter_id=chapter_id
		for cue in directives.chapters[chapter_id]:
			var node:Dictionary=Content.scene(str(cue.scene_id));var index:int=-1
			for i in range(node.lines.size()):
				if str(node.lines[i].text).contains(str(cue.text_contains)):index=i;break
			check(index>=0,"director cue uniquely exists")
			app.set_meta("chapter_replay_node",str(node.id));app.set_meta("chapter_replay_line",index);app.show_page("chapter");await process_frame
			var key:=str(node.lines[index].speaker)
			var actor:TextureRect=app.page.get_node("ChapterStage/Cast/Actor_"+key)
			var face:Node=actor.get_node_or_null("FaceAnimation")
			check(face!=null and str(face.expression)==str(cue.tone),"actual directed expression "+str(cue.scene_id))
			var instance:int=actor.get_instance_id()
			if str(cue.get("motion","none"))=="step":
				var count:int=int(actor.get_meta("chapter_directed_motion_count",0))
				check(count>0,"late directed step runs without replacing the actor")
				Chapter.refresh(app);await process_frame
				check(actor.get_instance_id()==instance and int(actor.get_meta("chapter_directed_motion_count",0))==count,"same-line refresh does not restart directed motion")
				await shot(str(cue.scene_id)+"-directed-step")
			if index+1<node.lines.size() and node.lines[index+1].get("actors",[]).has(key):
				app.set_meta("chapter_replay_line",index+1);app.show_page("chapter");await process_frame
				var next:TextureRect=app.page.get_node("ChapterStage/Cast/Actor_"+key)
				check(next.get_instance_id()==instance,"expression and dialogue retain same actor")
	app.remove_meta("chapter_replay_node");app.remove_meta("chapter_replay_line")

func compatibility()->void:
	app.economy.state.progression.story_chapter_id="chapter-01"
	app.progression.chapter_status()
	var saved:Dictionary=app.economy.state.progression.chapter1
	saved.node="hearing";saved.line=99999
	var clamped:Dictionary=app.progression.chapter_status()
	check(int(clamped.line)==Content.scene("hearing").lines.size()-1,"old out-of-range line safely clamps")
	saved.node="complete";saved.line=0;saved.seen=["rescue","waking","hearing"];saved.cleared={"c1-breakout":true,"c1-salvage":true,"c1-boss":true};saved.claimed=saved.cleared.duplicate()
	app.set_meta("story_route_node","c1-rear-escort");app.show_page("story_route");await process_frame
	var route:Control=app.page.get_node("StoryRoute")
	check(not route.get_node("Detail/Open").disabled,"old completed save opens new actual mission briefing")
	var graph:Control=route.get_node("Graph")
	check(graph.available.get("c1-rear-escort",false),"new inserted nodes are visible to completed legacy save")
	var prepare:Dictionary=app.progression.chapter_prepare("c1-rear-escort")
	check(prepare.get("ok",false) and str(prepare.request.id)=="c1-breakout","old completed save can really launch new native-mapped action")
	var tamper:Dictionary=prepare.context.duplicate(true);tamper.native_stage="c1-boss"
	var core=preload("res://scripts/core_bridge.gd").new()
	var original:Dictionary=core.request(prepare.request)
	check(original.get("ok",false),"compatibility mission starts in actual default core")
	var frozen:Dictionary=core.request({"op":"save","serialized":true})
	var chapter=preload("res://scripts/chapter_progression.gd").new(app.economy,"chapter-01")
	check(not chapter.validate_start(tamper,JSON.parse_string(str(frozen.serialized))).is_empty(),"wrong native mapping rejected at start")
	core.close()
	var wallet:Dictionary=app.economy.wallet().duplicate(true)
	var commander:Dictionary=app.economy.state.commander.duplicate(true)
	app.start_local_mode(prepare.request,prepare.context)
	await preload("res://tests/transition_settle.gd").wait_for_route(self,app)
	check(app.screen=="battle","completed legacy account actually starts inserted native action")
	check(app.issue({"op":"route","fleet":1,"mode":"follow","speed":20,"points":[{"x":7400,"y":1200},{"x":7400,"y":2200}]}).get("ok",false),"legacy revisit uses real route command")
	check(app.issue({"op":"step","seconds":80}).get("ok",false),"legacy revisit advances real simulation")
	check(app.issue({"op":"salvage_extract","exit":0}).get("ok",false),"legacy revisit actually extracts")
	app.issue({"op":"step","seconds":12})
	check(app.core.view.get("chapter",{}).get("status")=="won","completed old-save revisit reaches real native victory")
	var terminal:Dictionary=app.core.request({"op":"save","serialized":true})
	var terminal_view:Dictionary=app.core.view.duplicate(true)
	app.finish_battle()
	check(app.last_receipt.get("success",false) and app.last_receipt.rewards.is_empty(),"inserted replay after legacy completion grants no extra first-clear reward")
	check(app.economy.wallet()==wallet and app.economy.state.commander==commander,"legacy replay changes neither wallet nor commander experience")
	check(app.progression.chapter_status().node=="complete" and app.progression.chapter_status().cleared.has("c1-rear-escort"),"legacy completion remains complete while additional real win is recorded")
	var duplicate:Dictionary=app.progression.finish_mode(terminal_view,str(terminal.serialized))
	check(duplicate.get("duplicate",false) and app.economy.wallet()==wallet and app.economy.state.commander==commander,"legacy inserted replay settlement remains idempotent")
	var before:Dictionary=app.economy.state.duplicate(true)
	app.set_meta("chapter_replay_node","c1-supp-morning");app.set_meta("chapter_replay_line",0);app.show_page("chapter");await process_frame
	check(not Content.scene("c1-supp-morning").is_empty(),"newly inserted legacy story exists in final build")
	if not Content.scene("c1-supp-morning").is_empty():check(app.page.get_node("ChapterStage/Body").get_parsed_text()==str(Content.scene("c1-supp-morning").lines[0].text),"old completed account reads actual new scene text")
	check(app.economy.state==before,"new story replay does not reset old complete or grant resources")
	await shot("legacy-complete-new-story")
