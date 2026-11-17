extends "res://tests/littoral_v4_world_review.gd"
var training
func aviation_card(kind:String,id:String="",carrier:int=0)->Control:
	for c in controller().ui.get_node("Tray/Scroll/Cards").get_children():
		if str(c.payload.kind)==kind and ((kind=="wing" and int(c.payload.carrier)==carrier) or (kind!="wing" and str(c.payload.get("squadron_id",""))==id)):return c
	return null
func gesture(kind:String,id:String,point:Vector2,carrier:int=0,touch:bool=false)->void:
	var c:Control=aviation_card(kind,id,carrier)
	if not check(c!=null,"actual %s card exists"%kind):return
	controller().ui.get_node("Tray/Scroll").ensure_control_visible(c);await frames(4)
	await drag(c,world(point),touch);await frames(2)
func cue_drag()->void:
	var q:Dictionary=training.cue();await gesture(str(q.kind),str(q.squadron_id),q.target,int(q.carrier))
func wait_step(wanted:int,limit:int=800)->void:
	for _i in range(limit):
		if training.step>=wanted:break
		await advance(.1)
	check(training.step>=wanted,"observed authority advances tutorial to %d (now %d)"%[wanted,training.step])
func run()->void:
	output_dir="res://../artifacts/carrier-v2/ui/";DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_dir))
	main_hash=FileAccess.get_sha256("user://cas_port_v1.json");backup_hash=FileAccess.get_sha256("user://cas_port_v1.json.bak")
	profile=output_dir+"isolated-%d.json"%OS.get_process_id();var account=load("res://scripts/economy.gd").new(profile);account.load_state()
	app=load("res://scenes/main.tscn").instantiate();app.economy=account;app.boot_to_title=false;app.fullscreen_battle=true
	root.content_scale_size=Vector2i(1600,900);root.size=Vector2i(1280,720);root.add_child(app);await frames();app.set_process(false);app.page_motion=false
	var config:Dictionary={"op":"new_littoral","version":"cas-littoral-v4","mode":"tutorial","lesson":"landing","seed":42,"ships":[{"id":"CAS-H-USN-ENTERPRISE-1942","hp":100,"ammo":100},{"id":"CAS-H-IJN-SHOKAKU-1942","hp":100,"ammo":100}],"roster":["MCP-034","MCP-001"],"unit_condition":[],"transport_preset":"combat","defense":[]}
	if not check(app.core.request(config).get("ok",false),"isolated actual two-carrier practice starts"):return finish()
	app.core.request({"op":"carrier_ops","version":"cas-carrier-ops-v2","ally_ai":false});app.show_page("battle");await frames(6)
	controller().tutorial_dismissed=true;controller().tutorial.active=false;controller().tutorial.hide();app.sea.focus_fleet();await frames()
	controller().interaction_event.connect(func(kind,data):events.append({"kind":kind,"data":data.duplicate(true),"tick":app.core.view.tick}))
	load("res://scripts/carrier_training.gd").start(controller());training=controller().get_meta("carrier_training");await frames()
	check(training.step==0,"reading starts no fake progress")
	await shot("01-drag-teaching-start")
	await cue_drag();await wait_step(1)
	var samples:Array=[];var moving_id:int=int(app.core.view.littoral.aviation.aircraft[0].id)
	for _i in range(30):
		var before:Dictionary=app.core.view.littoral.aviation.aircraft.filter(func(a):return int(a.id)==moving_id)[0];await advance(.1)
		var after:Dictionary=app.core.view.littoral.aviation.aircraft.filter(func(a):return int(a.id)==moving_id)[0]
		samples.append({"tick":app.core.view.tick,"x":after.x,"y":after.y,"phase":after.phase,"fuel":after.fuel_remaining,"travel":Vector2(float(after.x)-float(before.x),float(after.y)-float(before.y)).length()})
	check(samples.all(func(s):return float(s.travel)>14 and float(s.travel)<15),"actual patrol keeps flying at airspeed every tenth second")
	FileAccess.open(output_dir+"orbit-motion.json",FileAccess.WRITE).store_string(JSON.stringify(samples,"  "))
	await cue_drag();await wait_step(2)
	await shot("02-two-carrier-actual-patrol")
	await cue_drag();check(training.step==3,"pointer queues next flight behind actual airborne squadron")
	var old:Dictionary=app.core.view.littoral.carrier_ops.queue[0].duplicate(true)
	await cue_drag();check(training.step==4,"pointer replaces queued target")
	check(app.core.view.littoral.carrier_ops.queue.size()==1 and old.x!=app.core.view.littoral.carrier_ops.queue[0].x,"latest queued drag replaces rather than duplicates")
	var before:Array=app.core.view.littoral.aviation.aircraft.filter(func(a):return str(a.squadron_id)==training.first).map(func(a):return [a.id,a.fuel_remaining,a.weapon_remaining])
	await cue_drag();check(training.step==5,"actual airborne card retasks existing planes")
	var after:Array=app.core.view.littoral.aviation.aircraft.filter(func(a):return str(a.squadron_id)==training.first).map(func(a):return [a.id,a.fuel_remaining,a.weapon_remaining])
	check(before==after,"pointer retask creates no plane, fuel or weapon")
	await shot("03-airborne-retask-and-queue")
	var saved:String=app.core.request({"op":"save","serialized":true}).serialized
	await gesture("flight",training.first,Vector2(100000,100000));check(str(app.core.request({"op":"save","serialized":true}).serialized)==saved,"invalid pointer target preserves authority")
	await cue_drag();await wait_step(6);check(app.core.view.littoral.carrier_ops.queue.is_empty(),"wing recall cancels that mother's queued flight")
	await cue_drag();await wait_step(7);await shot("04-real-second-wave")
	await click(controller().ui.get_node("CarrierCommandDesk"));await frames()
	var ai:Button=_button_text("开启多航母航空托管");if check(ai!=null,"actual AI menu action exists"):await click(ai)
	load("res://scripts/carrier_air_desk.gd").dashboard(controller());await frames()
	for mother in [1,2]:
		var choices:Array=app.find_children("*","Button",true,false).filter(func(b):return b.text=="均衡" and b.is_visible_in_tree())
		if check(choices.size()==2,"two real carrier posture actions exist"):await click(choices[mother-1]);await frames()
	app.close_modal();await frames()
	await wait_step(8);check(training.finished,"all eight lessons require actual input and aircraft state")
	FileAccess.open(output_dir+"final-observation.json",FileAccess.WRITE).store_string(JSON.stringify(app.core.view,"  "))
	check(app.core.view.littoral.aviation.squadrons.all(func(s):return int(s.available)+int(s.airborne)+int(s.lost)==int(s.total)),"physical squadron conservation")
	await shot("05-multi-carrier-ai-and-completed-practice")
	load("res://scripts/carrier_air_desk.gd").dashboard(controller());await frames();await shot("06-decks-and-postures")
	app.close_modal();var wing:Control=aviation_card("wing","",1);controller().ui.get_node("Tray/Scroll").ensure_control_visible(wing);await frames();await click(wing)
	check(int(controller().get_meta("carrier_filter",0))==1,"actual mother card click filters its aircraft")
	check(controller().ui.get_node("Tray/Scroll/Cards").get_children().all(func(c):return c.payload.kind not in ["flight","squadron"] or str(c.payload.get("squadron_id","")).begins_with("air-1-")),"mother filter never mixes other carrier squadrons")
	await shot("07-mother-filter")
	controller().replay_mode=true;load("res://scripts/carrier_command_desk.gd").open(controller());await frames()
	check(_button_text("关闭航空托管").disabled and _button_text("跟随实际操作的航母教学").disabled,"replay keeps aviation control and training read-only")
	app.close_modal();controller().replay_mode=false
	finish()
