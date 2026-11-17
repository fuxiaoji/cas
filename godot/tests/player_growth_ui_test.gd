extends SceneTree
const Main=preload("res://scenes/main.tscn")
const Economy=preload("res://scripts/economy.gd")
const Details=preload("res://scripts/ship_detail_presentation.gd")
const TransitionSettle=preload("res://tests/transition_settle.gd")
var app
var checks:=0
var failures:Array[String]=[]
var screenshots:Array[String]=[]
var directory:="res://../artifacts/godot/player-growth/"
func _initialize()->void:call_deferred("run")
func check(value:bool,title:String)->void:
	checks+=1
	if not value:failures.append(title);push_error(title)
func button(text:String) -> Button:
	for node in app.find_children("*","Button",true,false):
		if node.text==text and node.is_visible_in_tree():return node
	return null
func shot(name:String)->void:
	await process_frame
	if DisplayServer.get_name()=="headless":return
	await TransitionSettle.wait_for_route(self,app)
	await RenderingServer.frame_post_draw
	var path:=ProjectSettings.globalize_path(directory+name+".png")
	check(root.get_texture().get_image().save_png(path)==OK,"screenshot "+name);screenshots.append(path)
func run()->void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	app=Main.instantiate();app.boot_to_title=false;app.economy=Economy.new("user://tests/player-ui-%d.json"%OS.get_process_id());root.add_child(app)
	await process_frame
	var identity:=str(app.economy.formation[0]);app.set_meta("detail_ship_id",identity)
	app.show_page("player");await process_frame
	check(button("前往资源海域")!=null and button("3 → 1 合成")!=null,"commander page has actionable material bins")
	await shot("commander-materials")
	button("前往资源海域").pressed.emit();await process_frame
	check(button("深层海域 · Lv.6")!=null,"tier navigation reachable")
	button("深层海域 · Lv.6").pressed.emit();await process_frame
	check(button("指挥官 Lv.6 解锁")!=null and button("指挥官 Lv.6 解锁").disabled,"deep tier visible and correctly locked")
	app.economy.grant_player_xp("test-ui-unlock",2000)
	app.show_page("resources");await process_frame
	check(button("出击")!=null and not button("出击").disabled,"genuine commander progress opens deep missions")
	await shot("resources-deep")
	var info_wallet:Dictionary=app.economy.wallet();button("查看掉落").pressed.emit();await process_frame
	check(is_instance_valid(app.modal) and button("查看材料仓 / 养成解锁")!=null,"full resource drops available in details")
	check(app.economy.wallet()==info_wallet,"inspecting mission rewards never charges resources")
	await shot("resource-drops-detail");app.close_modal()
	app.economy.state.wallet.credits=10000;app.economy.state.wallet.training_t2=2;app.economy.state.wallet.core_t1=30
	app.set_meta("ship_detail_tab","growth");app.show_page("ship_detail");await process_frame
	var before:Dictionary=app.economy.growth_profile(identity)
	var train:=button("+160 EXP")
	check(train!=null and not train.disabled,"tiered training available from ship page")
	train.pressed.emit();await process_frame
	check(int(app.economy.wallet().training_t2)==1 and int(app.economy.growth_profile(identity).mastery)==int(before.mastery),"training callback debits chosen material without buying mastery")
	app.economy.state.owned[identity].level=10;app.show_page("ship_detail");await process_frame
	var ascend:=button("等级突破");check(ascend!=null and not ascend.disabled,"breakthrough button ready at real cap")
	ascend.pressed.emit();await process_frame
	check(app.economy.growth_profile(identity).level_cap==20,"breakthrough callback updates actual progression")
	await shot("ship-ascended")
	var instance_id:String=app.economy._create_item("equipment");app.economy.state.inventory.equipment=int(app.economy.state.inventory.equipment)+1
	app.economy.assign_item(identity,"equipment",instance_id)
	app.set_meta("ship_detail_tab","equipment");app.show_page("ship_detail");await process_frame
	for type in ["fire_control","propulsion","bulkhead","balanced","ballistics"]:
		Details._refit_picker(app,instance_id);await process_frame
		var chosen:Button=null
		for node in app.find_children("*","Button",true,false):
			if node.is_visible_in_tree() and node.text.begins_with({"fire_control":"火控测距仪","propulsion":"轮机增压器","bulkhead":"复合隔舱","balanced":"平衡改装套件","ballistics":"弹道计算仪"}[type]):chosen=node;break
		check(chosen!=null,"selectable refit "+type)
		if chosen:chosen.pressed.emit()
		await process_frame
		check(str(app.economy.growth_profile(identity).equipment.gear_type)==type,"actual equipped profile "+type)
		var expected:="res://assets/gear/icons/%s.tres"%type
		var found:=false
		for node in app.find_children("*","TextureRect",true,false):
			if node.is_visible_in_tree() and node.texture!=null and str(node.texture.resource_path)==expected:found=true
		check(found,"equipped icon uses correct native atlas "+type)
		await shot("equipment-"+type)
	app.audio.shutdown();app.core.close();app.queue_free();await process_frame
	var report:Dictionary={"checks":checks,"passed":checks-failures.size(),"failures":failures,"screenshots":screenshots}
	var f=FileAccess.open(directory+"receipt.json",FileAccess.WRITE);f.store_string(JSON.stringify(report,"  "));f.close()
	print(JSON.stringify(report));quit(0 if failures.is_empty() else 1)
