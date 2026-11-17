extends SceneTree
## Twenty real identities, readable details, and native recruitment/formation input.
const OUTPUT:String="res://../artifacts/drag-littoral-v2/roster/"
const Economy=preload("res://scripts/economy.gd")
var app
var checks:int=0
var failures:Array[String]=[]
var screenshots:Array[String]=[]
var inputs:int=0
func _initialize()->void:call_deferred("run")
func check(ok:bool,label:String)->bool:
	checks+=1
	if not ok:failures.append(label);push_error(label)
	return ok
func frames()->void:
	for index in range(4):await process_frame
func screen_point(control:Control,point:Vector2)->Vector2:return control.get_viewport().get_screen_transform()*control.get_global_transform_with_canvas()*point
func click(control:Control)->void:
	var point:Vector2=screen_point(control,control.size*.5)
	var motion:=InputEventMouseMotion.new();motion.position=point;Input.parse_input_event(motion);inputs+=1;await process_frame
	for pressed in [true,false]:
		var event:=InputEventMouseButton.new();event.position=point;event.global_position=point;event.button_index=MOUSE_BUTTON_LEFT;event.pressed=pressed;event.button_mask=MOUSE_BUTTON_MASK_LEFT if pressed else 0;Input.parse_input_event(event);inputs+=1;await process_frame
	await frames()
func button(parent:Node,text:String)->Button:
	for child in parent.find_children("*","Button",true,false):
		if child.text==text:return child
	return null
func shot(name:String)->void:
	if DisplayServer.get_name()=="headless":return
	await frames();await RenderingServer.frame_post_draw
	var path:String=ProjectSettings.globalize_path(OUTPUT+name+".png")
	check(root.get_texture().get_image().save_png(path)==OK,"actual GPU "+name);screenshots.append(path)
func inside(control:Control,size:Vector2i)->bool:
	var start:Vector2=screen_point(control,Vector2.ZERO);var finish:Vector2=screen_point(control,control.size)
	return start.x>=-1 and start.y>=-1 and finish.x<=size.x+1 and finish.y<=size.y+1
func run()->void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	var source:String="user://cas_port_v1.json";var main_sha:String=FileAccess.get_sha256(source);var backup_sha:String=FileAccess.get_sha256(source+".bak")
	var baseline:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://../artifacts/home-review/receipt.json"))
	var profile:String=OUTPUT+"isolated-roster-%d.json"%OS.get_process_id()
	if not check(DirAccess.copy_absolute(str(baseline.profile),ProjectSettings.globalize_path(profile))==OK,"clone previously completed real island profile"):quit(1);return
	var account=Economy.new(profile);check(account.load_state().get("ok",false),"load completed island clone")
	check(account.state.active_run.is_empty(),"completed fixture has no voyage to discard")
	app=load("res://scenes/main.tscn").instantiate();app.economy=account;app.boot_to_title=false;app.page_motion=false;app.fullscreen_battle=false
	root.content_scale_size=Vector2i(1600,900);root.size=Vector2i(1280,720);root.add_child(app);await frames();app.set_process(false);app.page_motion=false
	account.state.erase("test_account");var unchanged:Dictionary=account.state.duplicate(true)
	check(not app.home.unlock_test_units().get("ok",false) and app.home._same(unchanged,account.state),"normal clone cannot unlock test resources")
	account.state.test_account="cas-local-qa-2026-11-12"
	check(app.home.unlock_test_units().get("ok",false),"explicit isolated QA grant unlocks twenty for catalogue verification")
	account.state.erase("test_account");var before:Dictionary=account.state.duplicate(true);check(account._commit(before,"Remove isolated QA marker").get("ok",false),"persist ordinary test clone")
	check(app.home.state().units.size()==20 and app.home.released().size()==20,"all twenty owned released identities")
	var identities:Array=[];var source_stats:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/tactical-profiles-v2.json"))
	for row in app.home.released():
		var id:String=str(row.id);identities.append(id);var stats:Dictionary=app.home.profile(id)
		check(not stats.is_empty() and not stats.get("bodies",[]).is_empty() and str(stats.get("role_label",""))!="","real core profile for "+id)
		check(ResourceLoader.exists(str(row.portrait)) and str(row.portrait).contains(id),"own portrait identity for "+id)
	check(source_stats.get("cards",[]).size()==20,"single source holds twenty numerical profiles")
	var state_before:Dictionary=account.state.duplicate(true);var disk_before:String=FileAccess.get_sha256(profile)
	for dimensions in [Vector2i(960,540),Vector2i(1280,720),Vector2i(1920,1080)]:
		root.size=dimensions;await frames();app.show_page("home_recruit");await frames()
		var pool=app.page.get_node("TacticalRecruit");var row:HBoxContainer=pool.get_node("Layout/FeaturedScroll/Featured");var scroll:ScrollContainer=pool.get_node("Layout/FeaturedScroll")
		check(row.get_child_count()==20,"twenty scrollable recruits at "+str(dimensions))
		for name in ["Layout/Actions/DrawOne","Layout/Actions/DrawTen","Layout/Actions/Archive","Layout/Probability"]:
			var control:Control=pool.get_node(name);var pixels:Vector2=screen_point(control,control.size)-screen_point(control,Vector2.ZERO)
			check(inside(control,dimensions) and pixels.y>=44,"visible finger target "+name+" at "+str(dimensions))
		scroll.scroll_horizontal=100000;await frames();await click(row.get_node("Recruit_MCP-240"))
		check(pool.focus_id=="MCP-240" and pool.get_node("Portrait").texture.resource_path==str(app.home.unit("MCP-240").portrait),"actual last recruit click binds own portrait at "+str(dimensions))
		await shot("recruit-"+str(dimensions.x));app.show_page("home");await frames()
		var home=app.page.get_node("HomeIsland");await click(home.get_node("Layout/Bottom/Sortie"))
		if not check(is_instance_valid(app.modal),"actual sortie click at "+str(dimensions)):continue
		var deploy:HBoxContainer=app.modal.find_child("DeploymentUnits",true,false);var carrier:ScrollContainer=app.modal.find_child("DeploymentUnitScroll",true,false)
		check(deploy.get_child_count()==20,"all twenty selectable in real formation at "+str(dimensions))
		carrier.scroll_horizontal=100000;await frames();await click(deploy.get_node("Deploy_MCP-240"))
		check(home.unit_selection.has("MCP-240"),"last tactical card selectable after scroll at "+str(dimensions))
		await shot("formation-"+str(dimensions.x));app.close_modal();await frames()
	app.show_page("home");await frames();var home=app.page.get_node("HomeIsland")
	home._unit_detail("MCP-240");await frames();await shot("unit-detail-rescue")
	var labels:String=""
	for label in app.modal.find_children("*","Label",true,false):labels+=label.text+"\n"
	check(labels.contains(app.home.profile_summary("MCP-240")) and not labels.contains("尚未加载"),"details contain actual rescue profile and ability")
	app.close_modal()
	check(app.home._same(state_before,account.state) and FileAccess.get_sha256(profile)==disk_before,"catalogue navigation cannot spend or grant resources")
	app.core.close();app.queue_free();await frames()
	check(FileAccess.get_sha256(source)==main_sha and FileAccess.get_sha256(source+".bak")==backup_sha,"user account and backup exact bytes preserved")
	var report:Dictionary={"checks":checks,"failures":failures,"passed":failures.is_empty(),"screenshots":screenshots,"input_events":inputs,"profile":ProjectSettings.globalize_path(profile),"isolated_qa_grant":true,"main_sha256":main_sha,"backup_sha256":backup_sha,"identities":identities,"actual_gpu":DisplayServer.get_name()!="headless"}
	FileAccess.open(OUTPUT+"report.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "));print("DRAG_ROSTER "+JSON.stringify(report));quit(0 if failures.is_empty() else 1)
