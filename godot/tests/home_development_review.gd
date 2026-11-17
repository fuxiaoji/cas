extends SceneTree
var checks:int=0
var failures:Array[String]=[]
var output:String="res://../artifacts/island-war-v1/home-development/"
var app
var account
var home
var formal_hash:String
var backup_hash:String
func _initialize()->void:call_deferred("run")
func check(value:bool,message:String)->void:
	checks+=1
	if not value:failures.append(message);push_error(message)
func frames(count:int=4)->void:
	for index in range(count):await process_frame
func click(node:Control)->void:
	check(node!=null,"requested UI control exists")
	if node==null:return
	var point:Vector2=node.get_viewport().get_screen_transform()*(node.get_global_transform_with_canvas()*(node.size*.5))
	for pressed in [true,false]:
		var event:=InputEventMouseButton.new();event.position=point;event.button_index=MOUSE_BUTTON_LEFT;event.pressed=pressed;Input.parse_input_event(event);await process_frame
	await frames()
func shot(name:String)->void:
	if DisplayServer.get_name()=="headless":return
	await frames();await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(ProjectSettings.globalize_path(output+name+".png"))==OK,"GPU screenshot "+name)
func run()->void:
	if OS.has_environment("CAS_HOME_REVIEW_OUTPUT"):output=OS.get_environment("CAS_HOME_REVIEW_OUTPUT").trim_suffix("/")+"/"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output));formal_hash=FileAccess.get_sha256("user://cas_port_v1.json");backup_hash=FileAccess.get_sha256("user://cas_port_v1.json.bak")
	account=load("res://scripts/economy.gd").new(output+"isolated-%d.json"%OS.get_process_id());check(account.new_profile().ok,"isolated ordinary account created")
	account.state.progression.first_voyage_canon.active=false;account.state.commander.level=20
	home=load("res://scripts/home_service.gd").new(account);home.state().unlocked=true;home.state().tutorial_complete=true;home.state().drag_tutorial_completed=true
	for key in home.RESOURCE_NAMES:home.state().resources[key]=10000
	for id in home.RELEASED:home._own_unit(id)
	var develop=home.development();check(home.state().units.size()==20,"all twenty real tactical identities supported")
	for id in home.RELEASED:
		var profile:Dictionary=develop.unit_profile(id)
		check(profile.owned and int(profile.level)==1 and int(profile.deployed_bodies)>=12 and int(profile.deployed_bodies)<=50,"finite independent progression profile "+id)
	check(int(develop.unit_profile("MCP-034").deployed_bodies)==45,"MCP034 is five nine-person companies, not protocol body cap")
	var now:int=int(Time.get_unix_time_from_system());home.state().units["MCP-034"].condition=40;home.state().units["MCP-034"].at=now
	check(is_equal_approx(home.condition("MCP-034",now+1800),41.0),"natural recovery is one percent per thirty minutes")
	var before:Dictionary=home.state().resources.duplicate(true);var quote:Dictionary=develop.replenishment_preview("MCP-034",70)
	check(home.state().resources==before and home.condition("MCP-034")<41,"replenishment preview has no charges or free healing")
	var paid:Dictionary=develop.replenish("MCP-034",70,"qa-replenish",quote.cost);check(paid.ok,"confirmed replenishment succeeds")
	for key in quote.cost:check(int(home.state().resources[key])==int(before[key])-int(quote.cost[key]),"exact replenishment ledger "+key)
	var after:Dictionary=home.state().resources.duplicate(true);check(develop.replenish("MCP-034",70,"qa-replenish",quote.cost).get("duplicate",false) and home.state().resources==after,"repeated transaction is idempotent")
	check(not develop.replenish("MCP-034",101,"qa-invalid").ok and home.state().resources==after,"invalid target has no partial charge")
	account.state.active_run={"mode":"qa"};check(not develop.replenish("MCP-034",100,"qa-active").ok,"active battle cannot replace missing bodies");account.state.active_run={}
	var health:float=home.condition("MCP-034");check(develop.train("MCP-034",10,"qa-training").ok and home.condition("MCP-034")<health+.01,"training cannot heal battle losses")
	var saved_training:Dictionary=home.state().resources.duplicate(true);check(develop.train("MCP-034",10,"qa-training").get("duplicate",false) and home.state().resources==saved_training,"training transaction is idempotent")
	home.state().units["MCP-034"].level=10;check(develop.ascend("MCP-034","qa-ascension").ok and int(develop.unit_profile("MCP-034").level_cap)==20,"first breakthrough raises own cap to twenty")
	check(not develop.specialize("MCP-034","assault","qa-locked-specialization").ok,"specialization is locked before level fifteen")
	home.state().units["MCP-034"].level=15;check(develop.specialize("MCP-034","assault","qa-specialization").ok,"native-compatible specialization can be selected")
	var area:int=int(home.island_profile().buildable_cells);check(home.upgrade("home-hq").ok and int(home.island_profile().buildable_cells)>area,"HQ upgrade unlocks actual additional building cells")
	var stock:Dictionary=home.storage_profile();home.state().buildings.append({"id":"qa-depot","kind":"depot","level":2,"cell":{"x":5,"y":4},"hp":100})
	var safer:Dictionary=home.storage_profile();check(int(safer.protection_capacity.scrap)>int(stock.protection_capacity.scrap) and int(safer.exposed.scrap)<=int(stock.exposed.scrap),"warehouse raises protected stock and never raises risk")
	check(int(safer.exposed.energy)==0,"energy is excluded from local plunder")
	var saved_credits:int=int(home.state().resources.credits);home.state().resources.credits=50000;home._give({"credits":3});check(int(home.state().resources.credits)==50000,"receiving resources never truncates an already above-cap test or legacy balance");home.state().resources.credits=saved_credits
	check(not home.replay_record("old-fake").ok,"missing old logs are never fabricated as replays")
	check(account.save_state().ok,"extended island state saves")
	var loaded=load("res://scripts/economy.gd").new(account.save_path);check(loaded.load_state().ok,"extended island state reloads")
	var restored=load("res://scripts/home_service.gd").new(loaded);check(int(restored.tactical_profile("MCP-034").ascension)==1 and str(restored.tactical_profile("MCP-034").specialization)=="assault","identity progression survives save/load")
	# A minimal legacy extension is migrated without moving facilities or healing losses.
	var original:Dictionary=home.state().units["MCP-001"].duplicate(true);home.state().units["MCP-001"]={"condition":23,"at":now,"losses":4};var migrated:Dictionary=home.tactical_profile("MCP-001")
	check(int(migrated.level)==1 and float(migrated.condition)<24 and int(migrated.losses)==4,"legacy identity defaults preserve actual damage and losses");home.state().units["MCP-001"]=original
	app=load("res://scenes/main.tscn").instantiate();app.boot_to_title=false;app.deferred_startup=false;app.staged_navigation=false;app.economy=account;app.fullscreen_battle=false;root.content_scale_size=Vector2i(1600,900);root.size=Vector2i(1280,720);root.add_child(app);await frames(8);app.page_motion=false;app.page_transition.cancel();AudioServer.set_bus_mute(0,true);app.show_page("home");await frames(7)
	var island:Node=app.page.find_child("HomeIsland",true,false);check(island!=null,"production editable island scene is active");await shot("expanded-island")
	await click(island.get_node("Layout/Top/IslandAffairs"));check(app.modal.name=="HomeConflictPanel","actual island-affairs button opens management")
	check(app.modal.find_child("InspectIsland_shoal_watch",true,false)!=null,"real six-island catalogue is consumed by UI");await shot("npc-islands")
	await click(app.modal.find_child("HomeTab_storage",true,false));await shot("warehouse-protection")
	await click(app.modal.find_child("CloseHomeConflict",true,false));island._unit_detail("MCP-034");await frames();await click(app.modal.find_child("TacticalReplenishment",true,false));await shot("replenishment-preview")
	var slider:Node=app.modal.find_child("ReplenishmentTarget",true,false);check(slider is HSlider,"replenishment uses a slider instead of numeric input")
	var funds:Dictionary=home.state().resources.duplicate(true);await click(app.modal.find_child("CancelTacticalReplenishment",true,false));check(home.state().resources==funds,"cancel from real preview does not charge")
	app.close_modal();await frames()
	for dimensions in [Vector2i(960,540),Vector2i(1920,1080)]:root.size=dimensions;await frames();island.open_conflicts("storage");await frames();await shot("storage-%dx%d"%[dimensions.x,dimensions.y]);app.close_modal()
	if is_instance_valid(app):app.core.close()
	check(FileAccess.get_sha256("user://cas_port_v1.json")==formal_hash and FileAccess.get_sha256("user://cas_port_v1.json.bak")==backup_hash,"formal account and backup remain unchanged")
	var receipt:Dictionary={"checks":checks,"failures":failures,"scope":"isolated real account transactions, current island UI, finite identity bodies, save/load"};FileAccess.open(output+"receipt.json",FileAccess.WRITE).store_string(JSON.stringify(receipt,"  "));print("HOME_DEVELOPMENT ",JSON.stringify(receipt));quit(0 if failures.is_empty() else 1)
