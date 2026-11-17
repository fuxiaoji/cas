extends SceneTree
# Film director: uses production UI and legal native commands on an isolated save.
const Main=preload("res://scenes/main.tscn")
const Economy=preload("res://scripts/economy.gd")
const OUT="res://../artifacts/promo-20261113/"
const SOURCE="res://../artifacts/extraction-stall-20261113/actual-account-refilled.json"
var app
var film_frame:int=0
var mode:String=""
var next_choice:int=0
var last_route:float=-1
var facts:Array=[]
var source_sha:String
func _initialize()->void:call_deferred("run")
func windowed()->void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	root.size=Vector2i(1280,720)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
func event(label:String)->void:
	var row:Dictionary={"frame":film_frame,"seconds":film_frame/30.0,"label":label,"screen":app.screen,"tick":app.core.view.get("tick",0)}
	if app.core.view.has("tide"):row["team"]=app.core.view.ships.size();row["tide"]=app.core.view.tide.duplicate(true)
	if not app.last_receipt.is_empty():row["receipt"]=app.last_receipt.duplicate(true)
	facts.append(row);print("FILM ",label," ",film_frame)
	FileAccess.open(OUT+"combat-events.json",FileAccess.WRITE).store_string(JSON.stringify(facts,"  "))
func choose()->void:
	var tide:Dictionary=app.core.view.get("tide",{})
	var choices:Array=tide.get("choices",[]).duplicate()
	if choices.is_empty():next_choice=0;return
	if next_choice==0:next_choice=film_frame+45;return
	if film_frame<next_choice:return
	var reinforcement:bool=str(tide.get("offer_kind",""))=="reinforcement"
	var priorities:Array=["chain","orbit","multishot","haste","magnet","blast","damage","shield","repair","torpedo","maneuver"]
	if reinforcement:
		choices=choices.filter(func(c):return str(c.get("kind",""))=="reinforcement")
		var desired:String=["heavy","barrage","torpedo","barrage","torpedo"][mini(4,app.core.view.ships.size()-1)]
		var roles:Array=[desired]+["heavy","barrage","torpedo"]
		choices.sort_custom(func(a,b):return roles.find(str(a.get("role","barrage")))<roles.find(str(b.get("role","barrage"))))
	else:choices.sort_custom(func(a,b):return priorities.find(str(a.id))<priorities.find(str(b.id)))
	var container:Node=app.page.get_node("TideBattleHud/Upgrades/ReserveScroll/CrewGrid" if reinforcement else "TideBattleHud/Upgrades/Choices")
	for button in container.get_children():
		if str(button.get_meta("tide_choice_id",""))==str(choices[0].id):
			button.pressed.emit();event("reinforcement" if reinforcement else "upgrade");break
	next_choice=0
func drive()->void:
	if app.screen!="battle":return
	if mode=="tide":
		choose()
		var tick:float=float(app.core.view.get("tick",0))
		if tick-last_route>=1:
			app.battle_controller.move(Vector2(12000,7000)+Vector2.from_angle(tick*.13)*1500);last_route=tick
		app._process(1.0/30*1.5)
	elif mode=="expedition":app._process(1.0/30)
	elif mode=="historical" or mode=="arena":app._process(1.0/30)
func until(seconds:int)->void:
	while film_frame<seconds*30:
		drive()
		await process_frame
		film_frame+=1
		if film_frame%900==0:
			event("progress")
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_jpg(ProjectSettings.globalize_path(OUT+"combat-%03d.jpg"%(film_frame/30)),.85)
func page(route:String)->void:
	mode="";app.running=false;app.show_page(route);windowed();event(route)
func clear_run()->void:
	mode="";app.running=false
	if not app.run.is_empty():app.save_leave()
	app.economy.abandon_sortie();app.run={};app.campaign_mode=false
func tide()->void:
	clear_run();app.set_meta("next_tide_seed",42);app.launch_tide("IBS-U-USN-FLETCHER");windowed();mode="tide";app.running=true;app.speed=1;last_route=-1;next_choice=0;event("tide-launch")
func auto_fleets()->void:
	for fleet in app.core.view.get("fleets",[]):
		app.core.request({"op":"ai","fleet":int(fleet.id),"mode":"auto","profile":"coord","move":true,"gun":true,"torpedo":true})
	app.update_battle()
func run()->void:
	root.content_scale_size=Vector2i(1600,900);windowed()
	var path:String="user://tests/promo-combat-20261113.json"
	DirAccess.copy_absolute(ProjectSettings.globalize_path(SOURCE),ProjectSettings.globalize_path(path))
	app=Main.instantiate();app.boot_to_title=false;app.economy=Economy.new(path);root.add_child(app);app.set_process(false)
	await process_frame;app.page_motion=false;AudioServer.set_bus_mute(0,true)
	app.economy.abandon_sortie()
	app.start_campaign();windowed();auto_fleets();mode="historical";app.running=true;app.speed=8;event("historical-auto");await until(55)
	if not app.run.is_empty():app.abandon()
	app.run={};app.running=false;mode=""
	app.fleets.set_members(["IBS-U-USN-FLETCHER","IBS-U-USN-STERETT","IBS-U-USN-UNNAMED-T01-R24"])
	app.economy.service_all(app.economy.formation)
	for id in app.arena.selected("ranked").duplicate():app.arena.toggle_group("ranked",str(id),false)
	app.arena.toggle_group("ranked",str(app.fleets.active().id),true)
	app.set_meta("next_arena_seed",8116);app.launch_arena("ranked");windowed();auto_fleets();mode="arena";app.running=true;app.speed=16;event("arena-auto");await until(100)
	event("combat-final");app.audio.shutdown();app.core.close();quit()
