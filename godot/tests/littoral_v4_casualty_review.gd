extends "res://tests/littoral_v4_world_review.gd"
## Only native combat deaths drive the persistent casualty review.
func run()->void:
	output_dir="res://../artifacts/littoral-v4-ui/casualties/";DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_dir))
	main_hash=FileAccess.get_sha256("user://cas_port_v1.json");backup_hash=FileAccess.get_sha256("user://cas_port_v1.json.bak")
	profile=output_dir+"isolated-%d.json"%OS.get_process_id()
	var account=load("res://scripts/economy.gd").new(profile);check(account.load_state().get("ok",false),"isolated casualty review profile")
	app=load("res://scenes/main.tscn").instantiate();app.economy=account;app.boot_to_title=false;app.fullscreen_battle=true
	root.content_scale_size=Vector2i(1600,900);root.size=Vector2i(1280,720);root.add_child(app);await frames();app.set_process(false);app.page_motion=false
	var fixture:String="res://../artifacts/littoral-v4/v4-salvage-landing-44-MCP-034-commands.json"
	var commands:Array=JSON.parse_string(FileAccess.get_file_as_string(fixture))
	if not check(app.core.request(commands[0]).get("ok",false),"actual registered casualty scenario starts"):return finish()
	app.show_page("battle");await frames();controller().tutorial_dismissed=true;controller().tutorial.active=false;controller().tutorial.hide()
	var rejected:Array=[];var executed:int=1
	for command in commands.slice(1):
		if str(command.op) in ["save","load","replay"]:continue
		var response:Dictionary=app.core.request(command);executed+=1
		if not response.get("ok",false):rejected.append({"command":command,"error":response.get("error","")})
		if str(command.op)=="step":
			app.update_battle()
			if int(round(float(app.core.view.tick)*10))%20==0:await process_frame
			if float(app.core.view.tick)>=60:break
	var casualties:Array=app.core.view.littoral.get("corpses",[])
	var own:Array=casualties.filter(func(row):return str(row.side)=="allies")
	check(own.size()>=8,"actual combat killed multiple real friendly bodies")
	check(own.all(func(row):return str(row.unit_id) in ["MCP-034","MCP-009"]),"native casualty identities match the deployed original women")
	await click(controller().ui.get_node("MiniMap"));await frames()
	var land=controller().ui.get_node("LandWindow/Map")
	check(casualties.all(func(row):return land.actors.has(int(row.id))),"every public actual casualty has a persistent visual")
	check(own.all(func(row):return land.actors[int(row.id)].persistent_defeat and not land.actors[int(row.id)].expired()),"real casualties stay after the previous four-second cutoff")
	var pose_states:Dictionary={}
	for row in own:
		var visual:Dictionary=load("res://scripts/tactical_casualty_art.gd").lookup(row)
		pose_states[str(row.id)]={"unit":row.unit_id,"index":visual.get("index",-1),"death_tick":row.death_tick,"world":{"x":row.x,"y":row.y}}
	check(pose_states.values().map(func(row):return row.index).has(0) and pose_states.values().map(func(row):return row.index).has(1) and pose_states.values().map(func(row):return row.index).has(2),"actual saved pose seeds display all three own-identity lying poses")
	await shot("actual-persistent-casualties")
	var saved:String=app.core.request({"op":"save","serialized":true}).serialized
	var tick:float=float(app.core.view.tick)
	var ui:Dictionary=controller().serialize_ui_state()
	app.core.close();check(app.core.request({"op":"load","serialized":saved}).get("ok",false),"actual casualties restore after fully closing the native process")
	controller().restore_ui_state(ui);app.update_battle();await frames()
	check(str(app.core.request({"op":"save","serialized":true}).serialized)==saved,"full native casualty save remains byte-identical after restore")
	check(own.all(func(row):return land.actors.has(int(row.id)) and land.actors[int(row.id)].fire_until<=land.actors[int(row.id)].clock and land.actors[int(row.id)].hurt_until<=land.actors[int(row.id)].clock),"restoring real dead bodies activates neither gunfire nor fresh hurt")
	check(app.core.request({"op":"replay","serialized":saved,"tick":0}).get("ok",false),"real replay returns to the beginning")
	app.update_battle();await frames()
	check(app.core.view.littoral.corpses.is_empty() and not own.any(func(row):return land.actors.has(int(row.id))),"rewind removes future real casualties from the display")
	check(app.core.request({"op":"replay","serialized":saved,"tick":tick}).get("ok",false),"real replay reaches the actual casualty time")
	app.update_battle();await frames()
	check(JSON.stringify(app.core.view.littoral.corpses)==JSON.stringify(casualties),"deterministic replay recreates the same actual death records")
	check(own.all(func(row):return load("res://scripts/tactical_casualty_art.gd").lookup(row).index==pose_states[str(row.id)].index),"saved and replayed deaths retain their own stable pose")
	await shot("actual-casualties-restored")
	FileAccess.open(output_dir+"runtime.json",FileAccess.WRITE).store_string(JSON.stringify(runtime_info(),"  "))
	FileAccess.open(output_dir+"proof.json",FileAccess.WRITE).store_string(JSON.stringify({"fixture":fixture,"fixture_sha256":FileAccess.get_sha256(fixture),"commands_executed":executed,"legal_rejections":rejected,"tick":tick,"casualties":casualties,"poses":pose_states},"  "))
	finish()
