extends SceneTree
const Main=preload("res://scenes/main.tscn")
const Economy=preload("res://scripts/economy.gd")
const Details=preload("res://scripts/ship_detail_presentation.gd")
var app
var checks:=0
var failures:Array[String]=[]
var screenshots:Array[String]=[]
var directory:="res://../artifacts/godot/meta-ui/"

func _initialize() -> void:call_deferred("run")
func check(value:bool,title:String) -> void:
	checks+=1
	if not value:failures.append(title);push_error(title)
func button(text:String) -> Button:
	for node in app.find_children("*","Button",true,false):
		if node.text==text and node.is_visible_in_tree():return node
	return null
func tagged(key:String,value:String) -> Button:
	for node in app.find_children("*","Button",true,false):
		if str(node.get_meta(key,""))==value and node.is_visible_in_tree():return node
	return null
func shot(name:String) -> void:
	await process_frame
	if DisplayServer.get_name()=="headless":return
	await RenderingServer.frame_post_draw
	var path:=ProjectSettings.globalize_path(directory+name+".png")
	check(root.get_texture().get_image().save_png(path)==OK,"screenshot "+name)
	screenshots.append(path)

func run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	var path:="user://tests/meta-ui-%d.json"%OS.get_process_id()
	app=Main.instantiate();app.boot_to_title=false;app.economy=Economy.new(path);root.add_child(app)
	await process_frame
	for category in ["supply","ships","bundles","exchange","tactics"]:
		app.set_meta("supply_category",category);app.show_page("shop")
		await process_frame
		check(button("舰娘")!=null and button("兑换")!=null,"store categories visible: "+category)
		await shot("shop-"+category)
	app.set_meta("supply_category","exchange");app.show_page("shop")
	await process_frame
	var wallet:Dictionary=app.economy.wallet()
	var exchange:=tagged("product_id","origins-ticket")
	check(exchange!=null and not exchange.disabled,"real premium exchange reachable")
	if exchange:exchange.pressed.emit()
	await process_frame
	check(int(app.economy.wallet().tickets)==int(wallet.tickets)+1 and int(app.economy.wallet().origins)==int(wallet.origins)-160,"exchange commits exact wallet delta")
	app.set_meta("supply_category","ships");app.show_page("shop")
	await process_frame
	var purchase:=tagged("product_id","ship:IBS-U-USN-DRAYTON")
	check(purchase!=null and not purchase.disabled,"direct ship purchase reachable")
	if purchase:purchase.pressed.emit()
	await process_frame
	check(app.economy.state.owned.has("IBS-U-USN-DRAYTON"),"direct purchase grants actual ship")
	var already:=tagged("product_id","ship:IBS-U-USN-DRAYTON")
	check(already!=null and already.disabled,"owned ship cannot be purchased again")
	app.set_meta("supply_category","supply");app.show_page("shop");await process_frame
	var material_pack:=tagged("product_id","silver-training")
	check(material_pack!=null and not material_pack.disabled,"training material purchase reachable")
	if material_pack:material_pack.pressed.emit()
	await process_frame
	app.show_page("mail");await process_frame
	var before:=int(app.economy.wallet().tickets)
	check(button("领取附件")!=null,"separate mail page attachment")
	button("领取附件").pressed.emit();await process_frame
	check(int(app.economy.wallet().tickets)==before+20 and button("已领取").disabled,"mail claim commits once and disables")
	await shot("mail")
	app.set_meta("activity_tab","supply");app.show_page("activity");await process_frame
	check(button("领取今日签到")!=null and app.screen=="activity","daily supplies live in activity's own supply tab")
	await shot("activity")
	app.show_page("mail");await process_frame
	check(button("已领取")!=null and app.screen=="mail","mail retains its independent claimed-attachment page")
	for route in ["resources","ladder"]:
		app.show_page(route);await process_frame
		check(button("出击")!=null and not app.economy.mission_catalog(route).is_empty(),"real mission catalogue "+route)
		await shot(route)
	var identity:="IBS-U-USN-FLETCHER"
	var reference:=Details.sheet_reference(identity)
	check(float(reference.base.dp)==144 and float(reference.base.max_knots)==37,"CAS original ship statistics copied faithfully")
	var source_before:=JSON.stringify(reference)
	app.set_meta("detail_ship_id",identity)
	for tab in ["reference","growth","equipment","crews"]:
		app.set_meta("ship_detail_tab",tab);app.show_page("ship_detail");await process_frame
		check(button("舰表")!=null and button("水手")!=null,"detail tabs "+tab)
		await shot("ship-"+tab)
	app.set_meta("ship_detail_tab","growth");app.show_page("ship_detail");await process_frame
	var train:=button("+40 EXP")
	var growth_before:Dictionary=app.economy.growth_profile(identity)
	var silver_before:=int(app.economy.wallet().credits)
	var materials_before:=int(app.economy.wallet().materials)
	check(train!=null and not train.disabled,"paid training follows current material affordability")
	if train:train.pressed.emit()
	await process_frame
	var growth_after:Dictionary=app.economy.growth_profile(identity)
	check(int(growth_after.level)>int(growth_before.level) or int(growth_after.xp)>int(growth_before.xp),"training advances actual ship progress")
	check(int(app.economy.wallet().credits)==silver_before-50 and int(app.economy.wallet().materials)==materials_before-1,"training spends displayed one-record and 50-silver costs")
	check(int(growth_after.mastery)==int(growth_before.mastery),"training cannot buy combat mastery")
	await shot("ship-trained")
	# Explicit test-only loot fixtures. Actual assignment still uses the UI and account transaction.
	var gear_id:String=app.economy._create_item("equipment")
	app.economy.state.inventory.equipment=int(app.economy.state.inventory.equipment)+1
	Details._picker(app,identity,"equipment");await process_frame
	var gear_button:=tagged("gear_instance_id",gear_id)
	check(gear_button!=null,"specific inventory instance is selectable")
	if gear_button:gear_button.pressed.emit()
	await process_frame
	check(str(app.economy.growth_profile(identity).equipment.id)==gear_id,"UI equipment assignment commits instance")
	app.set_meta("ship_detail_tab","equipment");app.show_page("ship_detail");await process_frame
	await shot("ship-equipped")
	check(button("卸下")!=null,"equipped item has removal action")
	button("卸下").pressed.emit();await process_frame
	check(app.economy.growth_profile(identity).equipment.is_empty(),"UI removal returns item to warehouse")
	var crews:Dictionary={}
	for i in range(80):
		var item_id:String=app.economy._create_item("command")
		app.economy.state.inventory.command=int(app.economy.state.inventory.command)+1
		var item:Dictionary=app.economy.state.item_instances[item_id]
		crews[str(item.slot)]=item_id
		if crews.size()==4:break
	check(crews.size()==4,"deterministic crew fixtures cover four real slots")
	app.set_meta("ship_detail_tab","crews")
	for slot in ["helmsman","gunnery","damage_control","command"]:
		Details._picker(app,identity,slot);await process_frame
		var crew_button:=tagged("gear_instance_id",str(crews.get(slot,"")))
		check(crew_button!=null,"crew inventory selector "+slot)
		if crew_button:crew_button.pressed.emit()
		await process_frame
		check(str(app.economy.growth_profile(identity).crews[slot].get("id",""))==str(crews.get(slot,"")),"crew slot transaction "+slot)
	await shot("ship-crews-equipped")
	for slot in ["helmsman","gunnery","damage_control","command"]:
		Details._assign(app,identity,slot,"");await process_frame
		check(app.economy.growth_profile(identity).crews[slot].is_empty(),"crew return to warehouse "+slot)
	check(JSON.stringify(Details.sheet_reference(identity))==source_before,"growth and equipment do not mutate original CAS card")
	app.audio.shutdown();app.core.close();app.queue_free();await process_frame
	for suffix in ["",".bak",".tmp"]:
		if FileAccess.file_exists(path+suffix):DirAccess.remove_absolute(ProjectSettings.globalize_path(path+suffix))
	var report:={"checks":checks,"passed":checks-failures.size(),"failures":failures,"screenshots":screenshots,"scope":"real store/mail/equipment callbacks on isolated profile; test-only item fixture; mission launch covered by root integration"}
	var file:=FileAccess.open(directory+"receipt.json",FileAccess.WRITE)
	if file:file.store_string(JSON.stringify(report,"\t"));file.close()
	print(JSON.stringify(report));quit(0 if failures.is_empty() else 1)
