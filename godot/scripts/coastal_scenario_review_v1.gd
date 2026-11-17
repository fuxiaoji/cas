extends SceneTree
## P1-3 playable entry acceptance: real clicks through the training modal into
## the standard assault sample battle. No forged state; genuine battle screen.
const OUT:String="res://../artifacts/coastal-combat-v2-20261116/scenario-entry/"
var app:Control
var checks:int=0
var failures:Array[String]=[]
func _initialize()->void:call_deferred("run")
func check(value:bool,label:String)->void:
	checks+=1
	if not value:failures.append(label);push_error(label)
func frames(count:int=3)->void:
	for i in range(count):await process_frame
	if DisplayServer.get_name()!="headless":await RenderingServer.frame_post_draw
func capture(name:String)->void:
	if DisplayServer.get_name()=="headless":return
	await frames(3)
	var path:String=OUT+name+".png"
	root.get_texture().get_image().save_png(path)
func click(control:Control)->void:
	var point:Vector2=control.get_global_rect().get_center()
	var motion:InputEventMouseMotion=InputEventMouseMotion.new();motion.position=point;motion.global_position=point;root.push_input(motion,true);await frames(1)
	for pressed:bool in [true,false]:
		var button:InputEventMouseButton=InputEventMouseButton.new();button.button_index=MOUSE_BUTTON_LEFT;button.pressed=pressed;button.position=point;button.global_position=point;root.push_input(button,true);await frames(1)
	await frames(2)
func run()->void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var normal:Dictionary={}
	for name in ["cas_port_v1.json","cas_port_v1.json.bak"]:normal[name]=FileAccess.get_sha256("user://"+name)
	var profile:String=ProjectSettings.globalize_path(OUT+"review-player-%d.json"%OS.get_process_id())
	DirAccess.copy_absolute(ProjectSettings.globalize_path("res://../artifacts/coastal-rebuild-20261116/player.json"),profile)
	app=load("res://scenes/main.tscn").instantiate()
	app.economy=load("res://scripts/economy.gd").new(profile)
	app.immersive_fullscreen=false;app.boot_to_title=false;app.page_motion=false
	root.size=Vector2i(1600,900);root.add_child(app);app.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var ready:bool=await app.startup_ready
	check(ready,"real Main starts with coastal trial account")
	app.page_motion=false;app.set_meta("reduced_motion",true)
	app.show_page("home");await frames(6)
	var home=app.page.get_node_or_null("HomeIsland")
	check(home!=null,"home opens")
	if home==null:return finish()
	await click(home.get_node("Layout/Top/Training"));await frames(3)
	print("ENTRY_DIAG modal=",app.modal!=null," children=",app.modal.get_child_count() if app.modal!=null else -1)
	if app.modal!=null:
		var names:Array=[]
		for child in app.modal.get_children():names.append(str(child.name))
		print("ENTRY_DIAG modal children=",names)
	var lessons:Control=app.modal.find_child("TrainingLessonScroll",true,false)
	check(lessons!=null,"training modal opens")
	if lessons==null:return finish()
	var scroll:Control=app.modal.find_child("TrainingLessonScroll",true,false)
	if scroll!=null:scroll.scroll_vertical=10000
	await frames(2)
	var beach:Control=app.modal.find_child("Lesson-scenario-beach_fire",true,false)
	check(beach!=null,"standard assault beach_fire entry present")
	if beach!=null:print("ENTRY_DIAG beach_rect=",beach.get_global_rect()," visible=",beach.is_visible_in_tree())
	var depth:Control=app.modal.find_child("Lesson-scenario-industrial_depth",true,false)
	var mobile:Control=app.modal.find_child("Lesson-scenario-mobile_garrison",true,false)
	check(depth!=null and mobile!=null,"all three standard assault entries present")
	await capture("training-modal-with-scenarios")
	if beach==null:return finish()
	await click(beach);await frames(5)
	for i:int in range(80):
		if app.battle_controller!=null:break
		await create_timer(.025).timeout
	var battle=app.battle_controller
	check(battle!=null,"sample battle screen opens")
	if battle==null:return finish()
	battle.set_primary_map("land")
	if battle.tutorial!=null and battle.tutorial.active:await click(battle.tutorial._close)
	await frames(3)
	var view:Dictionary=app.core.view
	var allied_units:Array=[]
	for g:Dictionary in view.get("littoral",{}).get("groups",[]):
		if str(g.get("side"))!="axis" and not allied_units.has(str(g.get("unit_id"))):allied_units.append(str(g.get("unit_id")))
	print("ENTRY_DIAG battle units=",allied_units," npc=",view.get("island_war",{}).get("npc_id")," exercise=",view.get("island_war",{}).get("exercise"))
	var garrison:Array=view.get("island_war",{}).get("garrison",[])
	check(garrison.size()>=1 and str(garrison[0].get("side"))!="0","defender garrison ship anchored: "+JSON.stringify(garrison))
	var axis:int=0
	for e:Dictionary in view.get("littoral",{}).get("land",{}).get("entities",[]):
		if str(e.get("side"))!="allies":axis+=1
	check(axis>=80,"defender garrison and forts deploy for assault: %d"%axis)
	var units:Dictionary={}
	for g:Dictionary in view.get("littoral",{}).get("groups",[]):
		if str(g.get("side"))!="axis":units[str(g.get("unit_id"))]=true
	check(units.has("MCP-034") and units.has("MCP-063"),"sample assault companies present")
	check(units.has("MCP-145") or units.has("MCP-001") or units.has("MCP-022"),"support company present")
	await capture("scenario-battle-opened")
	# Let the built-in autonomy run the naval and landing phases briefly.
	app.core.request({"op":"island_autonomy","version":"cas-island-war-coastal-v1","enabled":true})
	app.speed=4;app.running=true;battle.update()
	await frames(2)
	var started:int=Time.get_ticks_msec()
	while Time.get_ticks_msec()-started<45000:
		await process_frame
	app.running=false
	view=app.core.view
	var stages:Dictionary={}
	for g:Dictionary in view.get("littoral",{}).get("groups",[]):
		stages[str(g.get("stage"))]=true
	check(stages.has("transit") or stages.has("ground"),"sample battle advances under autonomy: "+JSON.stringify(stages))
	await capture("scenario-battle-advancing")
	finish()
func finish()->void:
	var report:Dictionary={"passed":failures.is_empty(),"checks":checks,"failures":failures,"mode":"real clicks through training modal into standard assault samples"}
	var file=FileAccess.open(OUT+("entry-headless.json" if DisplayServer.get_name()=="headless" else "entry-gpu.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"  "));file.close()
	print("COASTAL_SCENARIO_ENTRY ",JSON.stringify(report))
	if is_instance_valid(app):
		app.running=false
		if app.core!=null:app.core.close()
		app.queue_free()
	await frames(2);quit(0 if failures.is_empty() else 1)
