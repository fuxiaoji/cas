extends SceneTree
const OUTPUT:String="res://../artifacts/island-war-v4/presentation/"
var failures:Array[String]=[]
var checks:int=0
func check(value:bool,message:String)->void:
	checks+=1
	if not value:failures.append(message);push_error(message)
func _initialize()->void:call_deferred("run")
func run()->void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	var formal:String=FileAccess.get_sha256("user://cas_port_v1.json");var backup:String=FileAccess.get_sha256("user://cas_port_v1.json.bak")
	for name in ["main","canon_story_data","canon_story_actions","canon_story_service","canon_tactical_v3","tactical_weapons_tutorial_v3","tactical_weapon_fx_v3","tactical_weapon_badge_v3","tactical_transport_art","littoral_battle","littoral_land","tactical_sprite","progression"]:
		var script:Script=load("res://scripts/%s.gd"%name)
		check(script!=null and script.reload()==OK and script.can_instantiate(),"load "+name)
	var Data=load("res://scripts/canon_story_data.gd");var Upgrade=load("res://scripts/canon_tactical_v3.gd")
	var chapter_one:Dictionary=Data.chapter("chapter-01").duplicate(true)
	for node in chapter_one.get("scenes",[]):
		if str(node.id)!="v2c1-combined-school":continue
		check(node.lines.any(func(line):return str(line.get("speaker",""))=="hologram" and "火力窗口" in str(line.get("text",""))),"weapon teaching preserves the mysterious battleship support dialogue")
		check(node.lines.any(func(line):return "短促的连射" in str(line.get("text",""))) and node.lines.any(func(line):return "打得快不代表换弹也快" in str(line.get("text",""))),"story teaches actual weapon cadence separately from magazine reload")
	var once:Dictionary=chapter_one.duplicate(true);Upgrade.enrich(chapter_one)
	check(chapter_one==once,"runtime story teaching enrichment is idempotent")
	for chapter in Data.IDS:
		for node in Data.chapter(chapter).get("scenes",[]):
			if Upgrade.LESSONS.has(str(node.id)):
				check(str(node.get("mechanics_version",""))==Upgrade.VERSION,"new mechanism profile "+str(node.id))
				var plan:Dictionary=Upgrade.request(str(node.tactical_lesson))
				check(plan.get("ok",false),"actual configured lesson "+str(node.id))
	var Tutorial=load("res://scripts/tactical_weapons_tutorial_v3.gd")
	var guide=Tutorial.new();root.add_child(guide);guide.start_tutorial({"step_id":"complete","proofs":{"fake":true}})
	guide.observe_state({"island_war":{"version":"cas-island-war-v3"},"littoral":{"training":{"lesson":"landing","complete":false,"checks":[{"id":"real_landing","done":false,"label":"等待真实登陆"}]},"groups":[]}})
	check(not guide._finished,"UI save cannot complete native lesson")
	guide.notify_event("deploy_queued",{"accepted":true});check(not guide._finished,"accepted drag cannot complete native lesson")
	var observed:Dictionary={"island_war":{"version":"cas-island-war-v3"},"littoral":{"training":{"complete":false,"checks":[]},"groups":[]}}
	guide.observe_state(observed);var unchanged:Dictionary=observed.duplicate(true);guide.start_tutorial({})
	check(observed==unchanged,"restarting help never clears the shared native observation")
	guide.queue_free()
	var cases:Array=[]
	for lesson in ["landing","combined_arms","airborne","artillery","roles"]:cases.append({"lesson":lesson,"version":"cas-island-war-v4"})
	cases.append({"lesson":"landing","version":"cas-island-war-v3"})
	for test_case in cases:
		var lesson:String=str(test_case.lesson);var version:String=str(test_case.version)
		var terminal_dir:String="res://../artifacts/island-war-v4/core/" if version==Upgrade.VERSION else "res://../artifacts/island-war-v3/core/"
		var fixture_path:String=terminal_dir+"training-%s-terminal.json"%lesson
		if not FileAccess.file_exists(fixture_path):
			check(false,"missing actual training terminal "+lesson);continue
		var fixture:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(fixture_path))
		var serialized:String=str(fixture.get("serialized",""))
		var account=load("res://scripts/economy.gd").new(OUTPUT+"story-isolated-%s-%d.json"%[lesson,OS.get_process_id()]);account.new_profile()
		var Home=load("res://scripts/home_service.gd").new(account)
		var service=load("res://scripts/canon_story_service.gd").new(account);service.ensure()
		var chapter:String="chapter-01" if lesson in ["landing","combined_arms"] else "chapter-02" if lesson=="airborne" else "chapter-03"
		var node_id:String={"landing":"v2c1-landing","combined_arms":"v2c1-combined","airborne":"v2c2-land-cooperate","artillery":"v2c3-shore-collaboration","roles":"v2c3-maintenance-beach"}[lesson]
		service.state().selected=chapter;service.chapter().node=node_id
		check(service.arm().get("ok",false),"arm true lesson "+lesson)
		if version=="cas-island-war-v3":service.state().pending.erase("mechanics_version")
		else:check(str(service.state().pending.get("mechanics_version",""))==version,"new story pending explicitly binds v4 "+lesson)
		var native:Dictionary=Home._native(serialized)
		check(native.get("ok",false),"reopen actual native terminal "+lesson)
		if not native.get("ok",false):continue
		var view:Dictionary=native.get("view",{})
		check(bool(view.get("littoral",{}).get("training",{}).get("complete",false)),"native checks completed "+lesson)
		var progression=load("res://scripts/progression.gd").new(account)
		var plan:Dictionary=Upgrade.request(lesson,version)
		var context:Dictionary={"mode":"exercise","id":node_id,"title":"武器训练","canon_version":service.VERSION,"tactical_lesson":lesson,"request":plan.get("request",{})}
		var before:Dictionary={"wallet":account.state.wallet.duplicate(true),"owned":account.state.owned.duplicate(true)}
		check(progression.begin_mode(context,serialized).get("ok",false),"begin borrowed exercise "+lesson)
		check(service.bind_run().get("ok",false),"bind same native lesson "+lesson)
		check(progression.finish_mode(view,serialized).get("ok",false),"real terminal settles borrowed exercise "+lesson)
		check(service.check_action(Home).get("ok",false),"real saved battle advances story "+lesson)
		check(str(service.chapter().node)!=node_id,"story advanced once "+lesson)
		check(account.state.wallet==before.wallet and account.state.owned==before.owned,"borrowed exercise preserves assets "+lesson)
	check(formal==FileAccess.get_sha256("user://cas_port_v1.json") and backup==FileAccess.get_sha256("user://cas_port_v1.json.bak"),"formal account unchanged")
	var report:Dictionary={"ok":failures.is_empty(),"checks":checks,"failures":failures,"scope":"Native course terminals independently loaded into isolated Progression and CanonService; synthetic UI noncompletion checks labelled separately; no player assets changed"}
	var file=FileAccess.open(OUTPUT+"story-receipt.json",FileAccess.WRITE);file.store_string(JSON.stringify(report,"\t"));file.close();print(JSON.stringify(report));quit(0 if failures.is_empty() else 1)
