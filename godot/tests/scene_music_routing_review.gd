extends SceneTree
## Tests production routing rather than directly selecting AudioDirector cues.
const Economy=preload("res://scripts/economy.gd")
const OUTPUT:String="res://../artifacts/scene-music-routing/"
var app
var checks:int=0
var failures:Array[String]=[]
var routes:Array=[]
func _initialize()->void:call_deferred("run")
func check(ok:bool,label:String)->bool:
	checks+=1
	if not ok:failures.append(label);push_error(label)
	return ok
func frames()->void:await process_frame;await process_frame
func cue(expected:String,dialogue:bool,label:String)->void:
	await frames()
	check(app.audio.current_scene==expected,label+" selects actual "+expected+" cue")
	check(app.audio.current_music_path=="res://assets/audio/original/"+expected+".ogg",label+" uses original scene master")
	check(app.audio._dialogue_active==dialogue,label+" dialogue duck state is correct")
	check(app.audio._music.playing and app.audio._music.stream is AudioStreamOggVorbis,label+" has a real active Vorbis decoder")
	routes.append({"route":label,"scene":app.audio.current_scene,"path":app.audio.current_music_path,"duck":app.audio._dialogue_active})
func run()->void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	var primary:String="user://cas_port_v1.json";var primary_sha:String=FileAccess.get_sha256(primary);var backup_sha:String=FileAccess.get_sha256(primary+".bak")
	var audio_settings:String="user://cas_audio_v1.json";var settings_sha:String=FileAccess.get_sha256(audio_settings)
	var source:String="res://../artifacts/extraction-stall-20261113/actual-account-refilled.json";var source_sha:String=FileAccess.get_sha256(source)
	var profile:String=OUTPUT+"isolated-routing-%d.json"%OS.get_process_id()
	check(DirAccess.copy_absolute(ProjectSettings.globalize_path(source),ProjectSettings.globalize_path(profile))==OK,"copy actual profile to isolated route test")
	var account=Economy.new(profile);check(account.load_state().get("ok",false),"load isolated route profile")
	if not account.state.active_run.is_empty():check(account.abandon_sortie().get("ok",false),"legally abandon only cloned old voyage")
	check(account.set_formation(["IBS-U-USN-FLETCHER"]).get("ok",false),"normal service selects owned tutorial flagship")
	app=load("res://scenes/main.tscn").instantiate();app.boot_to_title=false;app.economy=account;root.add_child(app);app.set_process(false)
	await frames();app.page_motion=false
	app.audio.settings_path=OUTPUT+"isolated-volume-%d.json"%OS.get_process_id();app.audio.configure(.25,.8,.3,true,true)
	app.show_page("title");await cue("title",false,"title")
	app.show_page("home");await cue("home",false,"home")
	app.show_page("home_recruit");await cue("home",false,"home_recruit")
	app.show_page("home_story");await cue("story_tension",true,"home_story/pre")
	# This real account is currently at a guide, which legitimately navigates to
	# formation. Use the existing read-only scene replay to enter actual dialogue.
	app.set_meta("chapter_replay_node","rescue");app.set_meta("chapter_replay_line",0)
	app.show_page("chapter");await cue("story",true,"chapter/rescue read-only dialogue")
	app.remove_meta("chapter_replay_node");app.remove_meta("chapter_replay_line")
	app.show_page("home")
	var prepared:Dictionary=app.home.prepare_littoral("tutorial",42,["MCP-034"],["IBS-U-USN-FLETCHER"],"balanced")
	if check(prepared.get("ok",false),"normal prepared sea-land tutorial"):
		app.launch_littoral(prepared.request)
		check(not app.running and app.audio._paused,"new littoral battle starts deliberately paused")
		app.toggle_pause()
		await cue("landing",false,"battle/littoral")
		check(app.issue({"op":"step","seconds":.1}).get("ok",false),"real littoral microstep via production issue")
		await cue("landing",false,"battle/littoral after update")
		app.abandon();await frames()
		check(app.economy.state.active_run.is_empty() and app.last_receipt.get("mode","")=="littoral","real tutorial abandon settles before next mode")
		await cue("defeat",false,"littoral failure result")
	app.show_page("tide_event");await cue("tide",false,"tide_event lobby")
	app.set_meta("next_tide_seed",42);app.launch_tide("IBS-U-USN-FLETCHER","normal",[])
	check(not app.running and app.audio._paused,"new tide battle starts deliberately paused")
	app.toggle_pause()
	if check(app.core.view.has("tide") and app.screen=="battle","production main launches actual tide v2"):
		await cue("tide",false,"battle/tide")
		check(app.issue({"op":"step","seconds":.1}).get("ok",false),"real tide microstep via production issue")
		await cue("tide",false,"battle/tide after update")
		app.abandon();await frames();check(app.economy.state.active_run.is_empty(),"real tide abandon settles only isolated account")
	check(FileAccess.get_sha256(primary)==primary_sha and FileAccess.get_sha256(primary+".bak")==backup_sha,"normal primary and backup unchanged")
	check(FileAccess.get_sha256(audio_settings)==settings_sha,"normal volume preferences unchanged")
	check(FileAccess.get_sha256(source)==source_sha,"read-only source clone unchanged")
	app.core.close();app.queue_free();await process_frame
	var manifest:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://bin/core-current.json"))
	var core_path:String=OS.get_environment("CAS_SIM_PATH")
	if core_path.is_empty():core_path=ProjectSettings.globalize_path("res://bin/"+str(manifest.executable))
	var receipt:Dictionary={"checks":checks,"failures":failures,"passed":failures.is_empty(),"routes":routes,"core_override":OS.get_environment("CAS_SIM_PATH"),"core_path":core_path,"core_sha256":FileAccess.get_sha256(core_path),"manifest_sha256":manifest.sha256,"profile":ProjectSettings.globalize_path(profile),"primary_sha256":primary_sha,"backup_sha256":backup_sha,"normal_settings_unchanged":FileAccess.get_sha256(audio_settings)==settings_sha}
	FileAccess.open(OUTPUT+"receipt.json",FileAccess.WRITE).store_string(JSON.stringify(receipt,"  "))
	print("SCENE_MUSIC_ROUTING ",JSON.stringify(receipt));quit(0 if failures.is_empty() else 1)
