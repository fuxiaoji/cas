extends SceneTree
## Actual save transactions and a real Boot/ship-detail view, always isolated.
const Economy=preload("res://scripts/economy.gd")
const Appearance=preload("res://scripts/ship_appearance_service.gd")
const Art=preload("res://scripts/character_art.gd")
const ID:String="IBS-U-USN-ERMA-MISSOURI"
var checks:int=0
var failures:Array[String]=[]
var output:String
var app
var normal_hashes:Dictionary={}

func _initialize()->void:call_deferred("run")
func check(ok:bool,message:String)->void:
	checks+=1
	if not ok:failures.append(message);push_error(message)
func same(a:Variant,b:Variant)->bool:return JSON.stringify(a)==JSON.stringify(b)
func frames(count:int=4)->void:
	for _i in count:await process_frame
func button_named(node:Node,id:String)->Button:
	if node is Button and str(node.name)==id:return node
	for child in node.get_children():
		var found:Button=button_named(child,id)
		if found!=null:return found
	return null
func snapshot(account)->Dictionary:
	return {"wallet":account.state.wallet.duplicate(true),"owned":account.state.owned.duplicate(true),"inventory":account.state.inventory.duplicate(true),"progression":account.state.get("progression",{}).duplicate(true),"formation":account.formation.duplicate()}
func go(route:String)->void:
	app.show_page(route);check(await app.wait_for_page(route),"staged route completes "+route);await frames()
func capture(label:String)->void:
	if DisplayServer.get_name()=="headless":return
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(output+"/"+label+".png")==OK,"GPU image "+label)

func run()->void:
	output=ProjectSettings.globalize_path("res://../artifacts/story-canon-v2/appearance-%d"%OS.get_process_id())
	DirAccess.make_dir_recursive_absolute(output)
	for suffix in ["",".bak"]:normal_hashes[suffix]=FileAccess.get_sha256("user://cas_port_v1.json"+suffix)
	var path:String=output+"/account.json"
	var account=Economy.new(path)
	check(account.load_state().ok,"isolated ordinary account loads")
	var service=Appearance.new(account)
	check(not service.choose(ID,"military").ok,"unowned appearance cannot equip")
	account.state.owned[ID]=account._new_owned(ID)
	account.state.owned[ID].level=19
	check(account.save_state().ok,"save real level19 owner")
	var before:Dictionary=snapshot(account)
	check(service.options(ID).size()==2 and not service.options(ID)[1].unlocked,"second form is visibly locked at19")
	check(not service.choose(ID,"military").ok and same(before,snapshot(account)),"locked form rejects without economic changes")
	account.state.owned[ID].level=20
	before=snapshot(account)
	check(service.choose(ID,"military").ok,"real level20 unlocks military")
	check(service.selected(ID)=="military","military selected")
	check(same(before,snapshot(account)),"appearance cannot change any owned statistic wallet inventory progress or formation")
	var hash:String=FileAccess.get_sha256(path)
	check(service.choose(ID,"military").ok and FileAccess.get_sha256(path)==hash,"repeat selection is idempotent with no second disk transaction")
	check(not service.choose(ID,"unknown").ok and FileAccess.get_sha256(path)==hash,"unknown form cannot write")
	var restored=Economy.new(path)
	check(restored.load_state().ok and Appearance.new(restored).selected(ID)=="military","appearance persists through real reload")
	account.state.active_run={"id":"isolated-ongoing-run"}
	check(not service.choose(ID,"base").ok and service.selected(ID)=="military","ongoing voyage protects original appearance")
	account.state.active_run={}
	var blocker:=FileAccess.open(output+"/blocked",FileAccess.WRITE);blocker.store_string("test file prevents save directory creation");blocker.close()
	account.save_path=output+"/blocked/account.json"
	var previous:Dictionary=account.state.duplicate(true)
	check(not service.choose(ID,"base").ok and same(previous,account.state),"real write failure rolls back cosmetic selection")
	account.save_path=path
	account.state.owned[ID].level=19
	check(service.selected(ID)=="base","invalid saved selection cannot bypass level requirement")
	account.state.owned[ID].level=20
	var source:Dictionary=account._cards[ID].duplicate(true)
	var visual:Dictionary=service.visual(ID)
	for key in source:
		if key not in Appearance.VISUAL_FIELDS:check(same(source[key],visual[key]),"authoritative field preserved "+str(key))
	var registry:Dictionary={ID:visual}
	var display_card:Dictionary=Art.visual_card(source,registry)
	check(Art.projection(display_card).path==visual.chibi_generated,"explicit account registry resolves selected SD")
	check(Art.pose_texture(display_card,"walk",.1).resource_path.contains("uniform"),"explicit account registry resolves military walk")
	check(not Art.pose_texture(source,"walk",.1).resource_path.contains("uniform"),"an original or independent preview cannot read another account's appearance")
	var loaded:Array=[]
	var boot=load("res://scenes/boot.tscn").instantiate()
	boot.profile_override=path;boot.boot_completed.connect(func(value):loaded.append(value))
	root.content_scale_size=Vector2i(1600,900);root.size=Vector2i(1280,720);root.add_child(boot)
	var deadline:int=Time.get_ticks_msec()+60000
	while loaded.is_empty() and Time.get_ticks_msec()<deadline:await process_frame
	check(not loaded.is_empty() and loaded[0].get("ok",false),"real staged Boot succeeds")
	if not loaded.is_empty() and loaded[0].get("ok",false):
		app=boot.app;app.page_motion=false;app.set_process(false)
		app.set_meta("detail_ship_id",ID);app.set_meta("ship_detail_tab","appearance")
		await go("ship_detail")
		var military:Button=button_named(app.page,"Appearance_military")
		var base:Button=button_named(app.page,"Appearance_base")
		check(military!=null and military.disabled and base!=null and not base.disabled,"detail shows real selected state and available switch")
		await capture("military-1280x720")
		if base!=null:
			base.pressed.emit();check(await app.wait_for_page("ship_detail"),"base UI callback rerenders through transition")
			check(Appearance.new(app.economy).selected(ID)=="base","detail button commits base portrait and SD together")
			await frames();await capture("base-1280x720")
		app.economy.state.owned[ID].level=19
		await go("ship_detail")
		military=button_named(app.page,"Appearance_military")
		check(military!=null and military.disabled,"actual detail disables locked level19 form")
		await capture("locked-1280x720")
		app.economy.state.owned[ID].level=20
		root.size=Vector2i(1920,1080)
		await go("ship_detail");await frames();await capture("unlocked-1920x1080")
		military=button_named(app.page,"Appearance_military")
		if military!=null:military.pressed.emit();await app.wait_for_page("ship_detail")
		check(Appearance.new(app.economy).selected(ID)=="military","unlocked UI equips military")
		check(str(app.cards[ID].portrait).contains("uniform"),"page refresh selects same-person portrait in presentation registry")
	for suffix in normal_hashes:check(FileAccess.get_sha256("user://cas_port_v1.json"+str(suffix))==normal_hashes[suffix],"normal profile untouched "+str(suffix))
	var receipt:={"checks":checks,"passed":checks-failures.size(),"failures":failures,"profile":path,"ordinary_account_never_loaded":true,"normal_hashes":normal_hashes,"display":DisplayServer.get_name()}
	var file:=FileAccess.open(output+"/receipt.json",FileAccess.WRITE);file.store_string(JSON.stringify(receipt,"  "));file.close()
	print(JSON.stringify(receipt));boot.queue_free();await frames();quit(0 if failures.is_empty() else 1)
