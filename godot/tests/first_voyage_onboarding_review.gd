extends SceneTree
## Isolated fresh/legacy account boundaries and actual Boot/Reader behavior.
## No battle outcome, progress completion or elapsed chapter duration is faked.
const Economy=preload("res://scripts/economy.gd")
const Entry=preload("res://scripts/first_voyage_onboarding.gd")
const Story=preload("res://scripts/canon_story_service.gd")
const Data=preload("res://scripts/canon_story_data.gd")
var checks:int=0
var failures:Array=[]
var records:Array=[]
var directory:String="res://../artifacts/story-onboarding-20261114/review-%d/"%OS.get_process_id()
var boot
class GuideSeaFixture extends Control:
	var planned:Array[Vector2]=[]
	var gesture:Dictionary={}
	var pan:Vector2=Vector2.ZERO
	var combat_offset:Vector2=Vector2.ZERO
	func project(point:Vector2)->Vector2:return point*.01
	func pos(row:Dictionary)->Vector2:return Vector2(float(row.get("x",0)),float(row.get("y",0)))
class GuideControllerFixture extends RefCounted:
	var fleet_id:int=1
	var cruise:float=25.0
	var preview:Dictionary={}
	var reform:Dictionary={}
	var tab:String="fleet"
	var hud=null
	var preview_refreshed:bool=false
	func select(_kind:String,row:Dictionary)->void:fleet_id=int(row.get("fleet",fleet_id))
	func refresh_preview()->void:preview_refreshed=true
	func choose_route(_mode:String)->void:pass
	func rebuild()->void:pass
	func preview_reform()->void:reform={"valid":true}
func _initialize()->void:
	root.position=Vector2i(-10000,-10000)
	call_deferred("run")
func check(ok:bool,label:String)->bool:
	checks+=1
	if not ok:failures.append(label);push_error(label)
	return ok
func new_account(name:String):
	var account=Economy.new(directory+name+".json")
	check(account.load_state().get("ok",false),"actual economy creates isolated account "+name)
	return account
func run()->void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	var normal:Dictionary={"main":FileAccess.get_sha256("user://cas_port_v1.json"),"backup":FileAccess.get_sha256("user://cas_port_v1.json.bak")}
	var account=new_account("future-fresh")
	check(Entry.pending(account),"actual new_profile opts in with an explicit marker")
	var result:Dictionary=Entry.prepare_route(account,"title")
	check(result.get("ok",false) and result.get("route")=="canon_story","fresh account enters chapter one without a harbor detour")
	var story=Story.new(account)
	check(story.state().selected=="chapter-01" and story.node().id=="v2c1-drifting","new story begins at first-person drifting node")
	check(Data.chapter("chapter-01").scenes[0].get("perspective")=="first_person","authored entry uses first-person perspective")
	var warnings:Array=story.visible_lines(story.node()).filter(func(line):return line.get("speaker")=="warning_voice")
	check(warnings.size()>=3 and warnings[0].get("text_effect")=="echo","unknown warning recurs with authored brief echo treatment")
	check(Data.chapter("chapter-01").cast.warning_voice.name=="……" and Data.chapter("chapter-01").cast.warning_voice!=Data.chapter("chapter-01").cast.fsm_ai,"hallucination does not impersonate the later state-machine assistant")
	check(story.move("next").get("ok",false),"reading first line saves an actual reading position")
	var position:int=int(story.chapter().line)
	var resumed=Economy.new(account.save_path)
	check(resumed.load_state().ok and Entry.prepare_route(resumed,"title").route=="canon_story","reload resumes initial voyage directly")
	check(int(Story.new(resumed).chapter().line)==position,"restart preserves the read line and never resets to zero")
	# Explicit state fixtures below test branches only, not simulated gameplay.
	var old=new_account("legacy-fixture")
	old.state.progression.erase(Entry.KEY)
	old.state.progression["chapter1"]={"scene":"legacy-open","cleared":{"one":true}}
	check(old.save_state().ok,"legacy fixture stored without future-profile marker")
	var bytes:String=FileAccess.get_sha256(old.save_path)
	var before:Dictionary=old.state.duplicate(true)
	check(Entry.prepare_route(old,"title").route=="title" and old.state==before,"existing zero-sortie and v1 progress are not inferred to be new")
	check(bytes==FileAccess.get_sha256(old.save_path) and not Story.new(old).enabled(),"legacy entry decision performs no story migration or save write")
	resumed.state.active_run={"run_id":"boundary-fixture-existing-voyage","mode":"salvage"}
	before=resumed.state.duplicate(true)
	check(Entry.prepare_route(resumed,"title").route=="title" and resumed.state==before,"existing voyage owns resume; onboarding cannot redirect or clear it")
	resumed.state.active_run={}
	var gate=Story.new(resumed)
	gate.chapter().node="v2c1-salvage";gate.chapter().line=0
	check(not gate.move("skip").ok and gate.node().id=="v2c1-salvage","skipping dialogue cannot complete an actual salvage/cargo action")
	gate.chapter().complete=true
	check(Entry.prepare_route(resumed,"title").route=="title" and not Entry.pending(resumed),"completed first chapter releases automatic entry without resetting progress")
	var imported=new_account("imported-marker-fixture")
	var imported_story=Story.new(imported);imported_story.ensure();imported_story.state().selected="chapter-03"
	check(Entry.prepare_route(imported,"harbor").route=="harbor" and imported_story.state().selected=="chapter-03","an imported later chapter cannot be forcibly selected back to chapter one")
	var journal=new_account("journal-failure-fixture")
	before=journal.state.duplicate(true);journal.save_path="res://tests/first_voyage_onboarding_review.gd/impossible.json"
	check(not Entry.prepare_route(journal,"title").ok and journal.state==before,"failed opening journal commit rolls back progress and marker together")
	await actual_boot()
	check(records.any(func(record):return record.has("fixture_scope")),"guide review reaches its final checkpoint without an interrupted script")
	var after:Dictionary={"main":FileAccess.get_sha256("user://cas_port_v1.json"),"backup":FileAccess.get_sha256("user://cas_port_v1.json.bak")}
	check(normal==after,"normal account and backup bytes unchanged")
	var report:Dictionary={"checks":checks,"passed":failures.is_empty(),"failures":failures,"records":records,"scope":"actual isolated new_profile/load/Boot/Reader plus explicit boundary fixtures; no full chapter playthrough or claimed human duration"}
	FileAccess.open(directory+"receipt.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("FIRST_VOYAGE "+JSON.stringify(report))
	if is_instance_valid(boot):boot.app.core.close();boot.queue_free()
	await process_frame
	await process_frame
	quit(0 if failures.is_empty() else 1)
func actual_boot()->void:
	root.content_scale_size=Vector2i(1600,900);root.size=Vector2i(1280,720)
	var results:Array=[]
	boot=load("res://scenes/boot.tscn").instantiate()
	boot.profile_override=ProjectSettings.globalize_path(directory+"boot-fresh.json")
	boot.boot_completed.connect(func(value):results.append(value))
	root.add_child(boot)
	var deadline:int=Time.get_ticks_msec()+60000
	while results.is_empty() and Time.get_ticks_msec()<deadline:
		# Off-screen test viewport only. Suppress this isolated app's OS full-screen
		# switch before page startup; never move or capture a user's game window.
		if is_instance_valid(boot.app):boot.app.fullscreen_story=true
		await process_frame
	if not check(not results.is_empty() and results[0].get("ok",false),"normal async Boot loads a newly-created isolated profile"):return
	var app=boot.app;app.set_process(false);app.page_motion=false
	check(app.screen=="canon_story","normal cold boot first visible page is the chapter story")
	check(app.page.get_node_or_null("CanonStory")!=null,"editable cinematic scene instantiates through normal page preparation")
	var stage=app.page.get_node_or_null("CanonStory")
	if stage==null:return
	check(stage.reader!=null and stage.reader.is_processing(),"first paragraph has a live reader, not a frozen empty text panel")
	var service=Story.new(app.economy)
	while int(service.chapter().line)<1:stage.reader.continue_reading();await process_frame
	check(stage.get_node("Speaker").text=="……","warning voice uses an unknown identity nameplate")
	check(stage.reader.text_effect=="echo","normal scene applies the authored transient warning effect")
	check(not app.page.has_node("CanonActionGuide"),"opening keeps harbor tutorial panel off cinematic canvas")
	if DisplayServer.get_name()!="headless":
		stage.reader.elapsed=1000.0;stage.reader.text_label.visible_characters=-1
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(directory+"opening-warning.png")
	records.append({"normal_boot_page":app.screen,"node":service.node().id,"line":service.chapter().line,"reader_live":stage.reader.is_processing(),"opening_harbor_detour":false})
	await guide_contract(app)

func guide_contract(app)->void:
	# Public-view fixtures verify presentation only. They are never submitted to
	# the native engine, committed as receipts, or used to finish a story action.
	var view:Dictionary=app.core.view.duplicate(true)
	var fixture:Dictionary={"result":null,"chapter":{"missionProfile":"canon-missions-v3","title":"礼物坐标","tutorialSteps":[],"tutorial":{"completeSteps":0,"totalSteps":6}},"salvage":{}}
	app.core.view=fixture
	var guide=load("res://scenes/ui/chapter_battle_guide.tscn").instantiate();guide.app=app;guide.stage_id="c1-salvage";app.page.add_child(guide);guide.bind()
	for kind in ["move","search","cargo_place","rally","extract","focus_fire","boss_phase","victory"]:
		fixture.chapter.tutorialSteps=[{"id":"native-"+kind,"action":kind,"label":"当前目标","done":false,"point":null}]
		app.core.view=fixture
		guide._observe()
		check(guide.get_meta("canon_native_action")==kind and guide.step_id=="canon_native-"+kind,"new guide reads current native action "+kind)
		check(not fixture.chapter.tutorialSteps[0].done,"rendering a guide never completes native step "+kind)
		if kind=="cargo_place":check(guide.get_node("Card/Body").text.contains("拖入空格") and guide.get_node("Card/Action").text=="打开航次货舱","cargo lesson points to the real grid, never auto-stows loot")
		if kind=="rally":check(guide.get_node("Card/Body").text.contains("神通") and guide.get_node("Card/Body").text.contains("避难船"),"rally includes the light cruiser and human escort fleet")
	fixture.chapter.tutorialSteps=[{"id":"already-done","action":"search","done":true},{"id":"still-required","action":"cargo_place","done":false}]
	app.core.view=fixture;guide._observe()
	check(guide.get_meta("canon_native_step")=="still-required","native done flags, rather than dismissed prompts, select the next step")
	check(service_record_unchanged(app),"guide view fixtures do not advance the story or its real-action receipts")
	for row in [{"id":"move","action":"route","expect":"move"},{"id":"escort","action":"route","expect":"escort"},{"id":"rally","action":"route","expect":"rally"},{"id":"search","action":"search_salvage","expect":"search"},{"id":"boss","action":"gun","expect":"focus_fire"},{"id":"extract","action":"salvage_extract","expect":"extract"}]:
		fixture.chapter.tutorialSteps=[{"id":row.id,"action":row.action,"done":false}]
		app.core.view=fixture;guide._observe()
		check(guide.get_meta("canon_native_action")==row.expect,"production command name resolves guide semantics "+row.action+"/"+row.id)
	var sea_before=app.sea;var controller_before=app.battle_controller;var selected_before:Dictionary=app.selected.duplicate(true);var kind_before:String=app.selection_kind
	var fake_sea=GuideSeaFixture.new();fake_sea.size=Vector2(1000,700);app.page.add_child(fake_sea);app.sea=fake_sea
	var fake_control=GuideControllerFixture.new();app.battle_controller=fake_control
	fixture.ships=[{"id":7,"fleet":3,"hp":220,"x":1000,"y":3200,"systems":{"maxSpeed":3.0}}]
	fixture.fleets=[{"id":3,"name":"人类避难船","leader":7,"maxSpeed":3.0}]
	fixture.chapter.tutorialSteps=[{"id":"escort","action":"route","done":false,"ship_id":7,"fleet_id":3,"point":{"x":1000,"y":3200}}]
	app.core.view=fixture;guide._locate_canon_step(fixture.chapter.tutorialSteps[0])
	check(app.selection_kind=="ship" and int(app.selected.id)==7 and fake_control.fleet_id==3,"production route action locates and selects the actual escort fleet")
	fixture.fleets[0].notice="因航行危险停止；请重新下达航路。";app.running=true;guide._observe()
	check(guide.step_id=="canon_danger_stop","a real hazard-stop notice takes priority over an old advance-time prompt")
	guide.action.call()
	check(not app.running and fake_control.fleet_id==3,"recovery hint button pauses and selects stopped escort without issuing movement")
	fixture.fleets[0].erase("notice")
	fake_sea.planned.append(Vector2(100,100));fake_control.preview={"valid":false,"error":"航速超过当前可用上限"}
	guide._observe();check(guide.step_id=="canon_route_detach","sub-four-knot fleet is guided to damage inspection rather than an illegal three-knot route")
	guide.action.call()
	check(fake_control.tab=="ship" and int(app.selected.id)==7 and fake_control.cruise==25.0,"damage hint selects actual damaged ship and exposes manual detach without silently issuing it")
	fixture.fleets[0].maxSpeed=12.0;fixture.ships[0].systems.maxSpeed=12.0
	guide._observe();check(guide.step_id=="canon_route_speed","valid damaged-speed range gets an actionable preview repair")
	guide.action.call();check(fake_control.cruise==12.0 and fake_control.preview_refreshed,"preview repair lowers cruise to the actual legal damaged maximum")
	fake_control.preview={"valid":false,"error":"领舰尾随需要纵队；先点重整纵队"};guide._observe()
	check(guide.step_id=="canon_reform_preview","a broken column requires real reformation rather than distant waypoints")
	guide.action.call();guide._observe()
	check(fake_control.reform.get("valid",false) and guide.step_id=="canon_reform_commit","reformation preview opens the current real command drawer and asks for explicit commit")
	fake_control.reform={"valid":false,"error":"请先完成转向"};guide._observe()
	check(guide.step_id=="canon_reform_unavailable" and guide.get_node("Card/Body").text.contains("脱队"),"unavailable reformation teaches manual detach and separate all-ship recovery")
	fake_sea.planned.clear();fake_control.preview={};fake_sea.gesture={"weapon":"torpedo","aim":{"friendly":true}};guide._observe()
	check(guide.step_id=="canon_torpedo_safety","active torpedo drag prioritizes friendly-fire safety warning")
	fake_sea.gesture={"weapon":"torpedo","aim":{}};guide._observe();check(guide.step_id=="canon_torpedo_aim","manual torpedo drag teaches the actual short hover-aim step")
	fake_sea.gesture={"weapon":"torpedo","anchor":Vector2.ZERO,"aim":{"valid":true}};guide._observe();check(guide.step_id=="canon_torpedo_release","only an anchored aim shows release instructions")
	app.sea=sea_before;app.battle_controller=controller_before;app.selected=selected_before;app.selection_kind=kind_before;fake_sea.queue_free()
	guide.queue_free();app.core.view=view
	records.append({"fixture_scope":"guide presentation only","native_commands_sent":0,"native_actions_falsely_completed":0})

func service_record_unchanged(app)->bool:
	var service=Story.new(app.economy)
	return service.node().id=="v2c1-drifting" and int(service.chapter().line)==1 and service.state().pending.is_empty() and app.economy.state.settled.is_empty()
