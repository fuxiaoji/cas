extends SceneTree
const Economy=preload("res://scripts/economy.gd")
const OUTPUT:String="res://../artifacts/home-story/"
const SOURCE:String="res://../artifacts/extraction-stall-20261113/actual-account-refilled.json"
var app
var profile:String=""
var checks:int=0
var failures:Array[String]=[]
var report:Dictionary={}
func _initialize()->void:call_deferred("run")
func check(ok:bool,label:String)->bool:
	checks+=1
	if not ok:failures.append(label);push_error(label)
	return ok
func page():return app.page.find_child("HomeStory",true,false)
func chapter_progress()->Dictionary:
	var result:Dictionary={}
	for key in ["chapter1","chapter2","chapter3"]:
		if app.economy.state.get("progression",{}).has(key):result[key]=app.economy.state.progression[key].duplicate(true)
	return result
func core_identity()->Dictionary:
	var override:String=OS.get_environment("CAS_SIM_PATH")
	if not override.is_empty():return {"path":override,"sha256":FileAccess.get_sha256(override),"default_manifest":false}
	var manifest:Variant=JSON.parse_string(FileAccess.get_file_as_string("res://bin/core-current.json"))
	if manifest is Dictionary:
		var path:String=ProjectSettings.globalize_path("res://bin/"+str(manifest.get("executable","")))
		return {"path":path,"sha256":FileAccess.get_sha256(path),"manifest_sha256":str(manifest.get("sha256","")),"default_manifest":true}
	return {}
func settle_frame()->void:
	await process_frame;await process_frame
func launch()->void:
	var economy=Economy.new(profile);check(economy.load_state().get("ok",false),"load isolated durable account")
	app=load("res://scenes/main.tscn").instantiate();app.boot_to_title=false;app.economy=economy;app.page_motion=false
	root.add_child(app);app.set_process(false);await settle_frame();app.page_motion=false
func close_app()->void:
	app.core.close();app.queue_free();await process_frame
func run()->void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	var source_hash:String=FileAccess.get_sha256(SOURCE)
	var primary:String="user://cas_port_v1.json";var primary_sha:String=FileAccess.get_sha256(primary);var backup_sha:String=FileAccess.get_sha256(primary+".bak")
	profile=OUTPUT+"isolated-story-%d.json"%OS.get_process_id()
	check(DirAccess.copy_absolute(ProjectSettings.globalize_path(SOURCE),ProjectSettings.globalize_path(profile))==OK,"clone read-only 43-owned account")
	root.content_scale_size=Vector2i(1600,900);root.content_scale_mode=Window.CONTENT_SCALE_MODE_CANVAS_ITEMS;root.size=Vector2i(1280,720)
	await launch()
	if not app.economy.state.active_run.is_empty():check(app.economy.abandon_sortie().get("ok",false),"legally end cloned pre-existing voyage")
	check(app.economy.set_formation(["IBS-U-USN-FLETCHER"]).get("ok",false),"normal formation service selects owned Fletcher")
	var chapters:Dictionary=chapter_progress()
	app.show_page("home_story");await settle_frame()
	check(page()!=null and page().phase=="pre" and page().lines.size()==24,"native full-screen tutorial starts with 24-page prelude")
	check(not app.home.state().tutorial_complete and app.home.state().units.is_empty(),"opening story does not grant island or 034")
	check(app.audio.current_scene=="story_tension" and app.audio._dialogue_active,"prelude has dedicated tension music and dialogue duck")
	var background_id:int=page().get_node("Backdrop").get_instance_id();var actor_id:int=page().get_node("Cast/reefblade").get_instance_id()
	for index in range(7):page()._advance();await settle_frame()
	check(page().line_index==7 and page().progress().pre_index==7,"seven real advances persist the next unread line")
	check(page().get_node("Backdrop").get_instance_id()==background_id and page().get_node("Cast/reefblade").get_instance_id()==actor_id,"line changes retain background and actor nodes")
	check(page().get_node("Cast/reefblade").get_meta("home_portrait","")=="res://assets/tactical/portraits/MCP-034.png","MCP034 uses her own female tactical portrait")
	var disk:String=FileAccess.get_sha256(profile);var before:String=JSON.stringify(app.economy.state)
	var blocker:String=OUTPUT+"blocked-%d"%OS.get_process_id();FileAccess.open(blocker,FileAccess.WRITE).store_string("file, not a directory")
	app.economy.save_path=blocker+"/profile.json";page()._advance()
	check(page().line_index==7 and JSON.stringify(app.economy.state)==before,"failed durable Next retains line and full account")
	check(FileAccess.get_sha256(profile)==disk and not page().get_node("Status").text.is_empty(),"failed save retains disk and shows retry message")
	app.economy.save_path=profile
	await close_app();await launch();app.show_page("home_story");await settle_frame()
	check(page().line_index==7 and page().phase=="pre","complete app restart resumes exact prelude line")
	page().preview_post=true;app.show_page("home_story");await settle_frame()
	check(page().phase=="pre","Inspector preview flag cannot unlock post-story")
	# Test genuine native UI button navigation before consuming the tutorial.
	page().get_node("Home").pressed.emit();await settle_frame();check(app.screen=="harbor","independent Home button returns to harbor")
	app.show_page("home");app.show_page("home_story");await settle_frame();page().get_node("Back").pressed.emit();await settle_frame()
	check(app.screen=="home","Back returns one layer to the island page")
	app.show_page("home_story");await settle_frame()
	while page().line_index<23:page()._advance();await settle_frame()
	check(not app.home.state().tutorial_complete and not app.home.state().unlocked,"all prelude pages leave real victory gate locked")
	page()._advance();await settle_frame()
	if not check(app.screen=="battle" and app.core.view.has("littoral"),"last prelude action launches real prepared native tutorial"):
		await finish(source_hash,primary_sha,backup_sha,chapters);return
	check(app.economy.state.active_run.get("mode","")=="littoral" and app.home.state().story.pre_complete,"real active run and independent prelude completion are saved")
	app.running=false
	var initial:Dictionary=app.core.view.duplicate(true)
	var saved:Dictionary=app.core.request({"op":"save","serialized":true})
	check(app.economy.save_sortie(str(saved.serialized)).get("ok",false),"save actual untouched tutorial starting state")
	await close_app();await launch();app.show_page("home_story");await settle_frame()
	check(page().phase=="pre" and page().line_index==23 and page().get_node("Next").text.contains("继续行动"),"unfinished real sortie offers Continue rather than post-story")
	page()._advance();await settle_frame();app.running=false
	check(app.screen=="battle" and app.home._same(app.core.view.littoral,initial.littoral),"Continue restores same real active native tutorial")
	if not await play_tutorial():
		await finish(source_hash,primary_sha,backup_sha,chapters);return
	app.finish_battle();await settle_frame()
	check(app.screen=="result" and app.last_receipt.get("success",false) and app.audio.current_scene=="victory","real native victory settles through production Main result and victory cue")
	check(app.home.state().tutorial_complete and app.home.state().unlocked and app.home.state().units.has("MCP-034"),"verified settlement grants permanent island and 034")
	var result:Node=app.page.find_child("LittoralResult",true,false)
	if check(result!=null,"real authored result scene is present"):result.get_node("Layout/Return").pressed.emit()
	await settle_frame()
	check(app.screen=="home_story" and page().phase=="post" and page().lines.size()==20,"real victory primary button enters gated 20-page epilogue")
	check(app.audio.current_scene=="story" and app.audio._dialogue_active,"epilogue changes music without losing dialogue duck")
	for index in range(8):page()._advance();await settle_frame()
	await close_app();await launch();app.show_page("home_story");await settle_frame()
	check(page().phase=="post" and page().line_index==8,"complete restart retains exact post-story line")
	for window in [Vector2i(960,540),Vector2i(1280,720),Vector2i(1920,1080),Vector2i(1600,720)]:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED);root.size=window;await settle_frame()
		for sample in [{"phase":"pre","line":0},{"phase":"pre","line":5},{"phase":"post","line":8},{"phase":"post","line":12},{"phase":"post","line":19}]:
			# Read-only view samples; the real transaction cursor is left at eight.
			var line:int=int(sample.line);page().phase=str(sample.phase);page().lines=page().content[page().phase]
			page().line_index=line;page()._line();page().reader.continue_reading();await settle_frame()
			var body:RichTextLabel=page().get_node("Body")
			check(body.get_content_height()<=body.size.y+1.0,"full long dialogue fits at %s %s line%d"%[window,sample.phase,line])
			check(page().get_node("Back").get_global_rect().intersects(page().get_node("Home").get_global_rect())==false,"Back/Home independent safe areas at %s line%d"%[window,line])
			check(page().get_node("Next").get_global_rect().position.y>=body.get_global_rect().end.y,"continue action stays below dialogue at %s line%d"%[window,line])
			if line in [0,5,8,19]:
				await create_timer(.45).timeout
				RenderingServer.force_draw();check(root.get_texture().get_image().save_png(ProjectSettings.globalize_path(OUTPUT+"%s-%dx%d-line%d.png"%[sample.phase,window.x,window.y,line]))==OK,"save settled actual GPU story screenshot")
	page().phase="post";page().lines=page().content.post;page().line_index=8;page()._line()
	while page().line_index<19:page()._advance();await settle_frame()
	page()._advance();await settle_frame()
	check(app.screen=="home" and app.home.state().story.post_complete,"last epilogue transaction enters actual editable island")
	check(app.economy.state.active_run.is_empty(),"story does not fabricate a new battle or leave stale active run")
	var earned:Dictionary=app.home.state().duplicate(true);earned.erase("story")
	await close_app();await launch();app.show_page("home_story");await settle_frame()
	page()._advance();await settle_frame()
	var reread:Dictionary=app.home.state().duplicate(true);reread.erase("story")
	check(app.home._same(earned,reread),"re-reading finished epilogue never grants duplicate resources or units")
	await editability()
	await finish(source_hash,primary_sha,backup_sha,chapters)

func play_tutorial()->bool:
	var deployed:bool=false;var searched:bool=false;var retreat:bool=false;var exiting:bool=false
	var beach:Dictionary=app.core.view.littoral.beaches[1]
	check(app.core.request({"op":"route","fleet":1,"speed":35,"points":[beach.sea]}).get("ok",false),"normal native route to actual beach")
	for second in range(500):
		var view:Dictionary=app.core.view;var group:Dictionary=view.littoral.groups[0]
		if view.get("result")!=null:break
		if not deployed and Vector2(float(view.ships[0].x),float(view.ships[0].y)).distance_to(Vector2(float(beach.sea.x),float(beach.sea.y)))<800:
			deployed=app.core.request({"op":"littoral_deploy","unit_id":"MCP-034","beach":2,"insertion":"landing"}).get("ok",false)
		if str(group.stage)=="ground" and not searched:searched=app.core.request({"op":"littoral_order","unit_id":"MCP-034","action":"search","target":1}).get("ok",false)
		if bool(view.littoral.land.ruins[0].searched) and not retreat:retreat=app.core.request({"op":"littoral_order","unit_id":"MCP-034","action":"retreat"}).get("ok",false)
		if str(group.stage)=="recovered" and not exiting:exiting=app.core.request({"op":"route","fleet":1,"speed":35,"points":[{"x":5500,"y":13500}]}).get("ok",false)
		if exiting:app.core.request({"op":"littoral_extract"})
		if app.core.view.get("result")!=null:break
		var step:Dictionary=app.core.request({"op":"step","seconds":1})
		if not step.get("ok",false):check(false,"real native tutorial advance "+str(step.get("error","")));return false
		if second%60==0:await process_frame
	report["tutorial"]={"deployed":deployed,"searched":searched,"retreat":retreat,"exiting":exiting,"tick":app.core.view.get("tick"),"outcome":app.core.view.littoral.get("outcome")}
	return check(app.core.view.get("result")!=null and app.core.view.littoral.get("outcome",{}).get("success",false),"transport, actual search, return and safe extraction produce real victory")

func editability()->void:
	var view=load("res://scenes/ui/home_story.tscn").instantiate()
	view.use_default_styles=false;view.use_content_text=false;view.use_content_artwork=false;view.use_cinematic_layout=false
	var custom_font:FontVariation=FontVariation.new();custom_font.base_font=load("res://assets/fonts/NotoSansSC.ttf")
	view.get_node("Body").add_theme_font_override("normal_font",custom_font)
	view.get_node("Body").add_theme_font_size_override("normal_font_size",31)
	view.get_node("Body").text="编辑器自定义对白";view.get_node("Body").anchor_top=.72
	var texture:GradientTexture2D=GradientTexture2D.new();texture.gradient=Gradient.new();view.get_node("Backdrop").texture=texture
	root.add_child(view);await settle_frame();view.bind(app);await settle_frame()
	check(view.get_node("Body").get_theme_font("normal_font")==custom_font and view.get_node("Body").get_theme_font_size("normal_font_size")==31,"Inspector font and size survive runtime binding")
	check(view.get_node("Body").get_parsed_text()=="编辑器自定义对白" and is_equal_approx(view.get_node("Body").anchor_top,.72),"Inspector text and authored layout survive disabled content/layout policies")
	check(view.get_node("Backdrop").texture==texture,"Inspector artwork survives disabled content art policy")
	view.queue_free();await process_frame

func finish(source_sha:String,primary_sha:String,backup_sha:String,chapters:Variant)->void:
	if is_instance_valid(app):
		check(app.home._same(chapters,chapter_progress()),"independent home story preserves existing three chapter progression")
		await close_app()
	check(FileAccess.get_sha256(SOURCE)==source_sha,"read-only source clone bytes unchanged")
	check(FileAccess.get_sha256("user://cas_port_v1.json")==primary_sha,"normal primary account bytes unchanged")
	check(FileAccess.get_sha256("user://cas_port_v1.json.bak")==backup_sha,"normal account backup unchanged")
	report.merge({"checks":checks,"failures":failures,"passed":failures.is_empty(),"profile":ProjectSettings.globalize_path(profile),"core_override":OS.get_environment("CAS_SIM_PATH"),"core_identity":core_identity(),"gpu":true,"source_sha256":source_sha,"primary_sha256":primary_sha,"backup_sha256":backup_sha},true)
	FileAccess.open(OUTPUT+"receipt.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	print("HOME_STORY_REVIEW ",JSON.stringify(report));quit(0 if failures.is_empty() else 1)
