extends SceneTree
const Economy=preload("res://scripts/economy.gd")
const OUTPUT:String="C:/Users/fwj/AppData/Local/Temp/CAS-home-mobile-review/"
var app
var home
var checks:int=0
var failures:Array[String]=[]
var screenshots:Array=[]
var input_count:int=0
var artwork_evidence:Array=[]
func _initialize()->void:call_deferred("run")
func check(ok:bool,message:String)->bool:
	checks+=1
	if not ok:failures.append(message);push_error(message)
	return ok
func frames()->void:
	for index in range(4):await process_frame
func screen_point(node:Control,local:Vector2)->Vector2:return node.get_viewport().get_screen_transform()*node.get_global_transform_with_canvas()*local
func mouse_at(point:Vector2,pressed:bool)->void:
	var event:=InputEventMouseButton.new();event.position=point;event.global_position=point;event.button_index=MOUSE_BUTTON_LEFT;event.button_mask=MOUSE_BUTTON_MASK_LEFT if pressed else 0;event.pressed=pressed;Input.parse_input_event(event);input_count+=1;await process_frame
func click(control:Control)->void:
	var point:Vector2=screen_point(control,control.size*.5)
	var motion:=InputEventMouseMotion.new();motion.position=point;Input.parse_input_event(motion);input_count+=1;await process_frame
	await mouse_at(point,true);await mouse_at(point,false);await frames()
func canvas_click(local:Vector2)->void:
	var point:Vector2=screen_point(home.canvas,local);await mouse_at(point,true);await mouse_at(point,false);await frames()
func drag_canvas(from:Vector2,to:Vector2,touch:bool=false)->void:
	var start:Vector2=screen_point(home.canvas,from);var finish:Vector2=screen_point(home.canvas,to)
	if touch:
		var down:=InputEventScreenTouch.new();down.index=0;down.position=start;down.pressed=true;Input.parse_input_event(down);input_count+=1;await process_frame
		for index in range(1,6):
			var event:=InputEventScreenDrag.new();event.index=0;event.position=start.lerp(finish,index/5.0);event.relative=(finish-start)/5;Input.parse_input_event(event);input_count+=1;await process_frame
		var up:=InputEventScreenTouch.new();up.index=0;up.position=finish;up.pressed=false;Input.parse_input_event(up);input_count+=1
	else:
		await mouse_at(start,true)
		for index in range(1,6):
			var event:=InputEventMouseMotion.new();event.position=start.lerp(finish,index/5.0);event.relative=(finish-start)/5;event.button_mask=MOUSE_BUTTON_MASK_LEFT;Input.parse_input_event(event);input_count+=1;await process_frame
		await mouse_at(finish,false)
	await frames()
func escape()->void:
	for pressed in [true,false]:
		var event:=InputEventKey.new();event.keycode=KEY_ESCAPE;event.pressed=pressed;Input.parse_input_event(event);input_count+=1;await process_frame
	await frames()
func wheel(local:Vector2,up:bool)->void:
	for pressed in [true,false]:
		var event:=InputEventMouseButton.new();event.position=screen_point(home.canvas,local);event.button_index=MOUSE_BUTTON_WHEEL_UP if up else MOUSE_BUTTON_WHEEL_DOWN;event.pressed=pressed;Input.parse_input_event(event);input_count+=1;await process_frame
	await frames()
func pinch()->void:
	var center:Vector2=screen_point(home.canvas,home.canvas.size*Vector2(.45,.55))
	for index in range(2):
		var event:=InputEventScreenTouch.new();event.index=index;event.position=center+Vector2((index*2-1)*50,0);event.pressed=true;Input.parse_input_event(event);input_count+=1;await process_frame
	for index in range(2):
		var event:=InputEventScreenDrag.new();event.index=index;event.position=center+Vector2((index*2-1)*130,0);event.relative=Vector2((index*2-1)*80,0);Input.parse_input_event(event);input_count+=1;await process_frame
	for index in range(2):
		var event:=InputEventScreenTouch.new();event.index=index;event.position=center+Vector2((index*2-1)*130,0);event.pressed=false;Input.parse_input_event(event);input_count+=1;await process_frame
	await frames()
func touch_click(control:Control)->void:
	var point:Vector2=screen_point(control,control.size*.5)
	for pressed in [true,false]:
		var event:=InputEventScreenTouch.new();event.index=0;event.position=point;event.pressed=pressed;Input.parse_input_event(event);input_count+=1;await process_frame
	await frames()
func button_text(parent:Node,text:String)->Button:
	for child in parent.find_children("*","Button",true,false):
		if child.text==text:return child
	return null
func target_size(control:Control)->Vector2:return screen_point(control,control.size)-screen_point(control,Vector2.ZERO)
func shot(name:String)->void:
	if DisplayServer.get_name()=="headless":return
	await frames();await RenderingServer.frame_post_draw
	var path:String=ProjectSettings.globalize_path(OUTPUT+name+".png");check(root.get_texture().get_image().save_png(path)==OK,"actual GPU "+name);screenshots.append(path)
func run()->void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	var source:String="user://cas_port_v1.json";var source_sha:String=FileAccess.get_sha256(source);var backup_sha:String=FileAccess.get_sha256(source+".bak")
	var previous:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://../artifacts/home-review/receipt.json"));var profile:String=OUTPUT+"isolated-mobile-%d.json"%OS.get_process_id()
	check(DirAccess.copy_absolute(str(previous.profile),ProjectSettings.globalize_path(profile))==OK,"isolate a real completed tutorial profile")
	var economy=Economy.new(profile);check(economy.load_state().get("ok",false),"load actual island and resources")
	app=load("res://scenes/main.tscn").instantiate();app.boot_to_title=false;app.economy=economy;root.content_scale_size=Vector2i(1600,900);root.size=Vector2i(1280,720);root.add_child(app);await frames();app.set_process(false);app.page_motion=false
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED);app.show_page("home");await frames();home=app.page.find_child("HomeIsland",true,false)
	if not check(home!=null,"production native home binds new island interface"):quit(1);return
	check(home.get_node_or_null("Layout/Main/Details")==null,"no permanent right-hand console")
	check(home.get_node("Layout/Bottom").get_child_count()==5,"five short main actions")
	check(home.canvas.texture_filter==CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS,"detailed island artwork uses actual linear mipmapped filtering")
	for group in [{"folder":"buildings","names":["hq","recycler","forge","solar","medical","turret","aa","depot","dock"]},{"folder":"environment","names":["tree_cluster","rock_cluster","grass_patch","coastal_cliff","ruin_cluster","ground_patch","beach_patch"]}]:
		for name in group.names:
			var path:String="res://assets/home/"+str(group.folder)+"/"+str(name)+".png";var texture:Texture2D=load(path);var image:Image=texture.get_image() if texture!=null else null
			check(image!=null and image.has_mipmaps(),"actual imported mip levels exist: "+str(name))
			artwork_evidence.append({"path":path,"sha256":FileAccess.get_sha256(path),"mipmaps":image.get_mipmap_count() if image!=null else -1})
	await shot("home-main-initial-1280")
	var before:Dictionary=app.economy.state.duplicate(true);var before_sha:String=FileAccess.get_sha256(profile)
	await drag_canvas(home.canvas.size*Vector2(.15,.65),home.canvas.size*Vector2(.15,.65)+Vector2(100,35))
	check(home.canvas.pan.length()>40 and not home.get_node("Layout/Context").visible,"actual mouse drag pans island without selecting a facility")
	await wheel(home.canvas.size*.5,true);check(home.canvas.zoom>1,"actual wheel zooms around pointer")
	await pinch();check(home.canvas.zoom<=home.canvas.maximum_zoom and home.canvas.zoom>1.5,"actual two-finger pinch zooms within safe bounds")
	await click(home.get_node("Layout/Top/ResetView"));check(is_equal_approx(home.canvas.zoom,1) and home.canvas.pan==Vector2.ZERO,"actual reset recovers complete island")
	check(app.economy.state==before and FileAccess.get_sha256(profile)==before_sha,"camera gestures never change any account bytes")
	await canvas_click(home.canvas.point(Vector2(6,4))-Vector2(0,home.canvas.rect().size.x/12*.9))
	check(home.get_node("Layout/Context").visible and home.selected_cell==Vector2i(6,4),"visible HQ upper structure is clickable beyond its footprint center")
	await escape()
	await click(home.get_node("Layout/Bottom/Build"));check(home.get_node("Layout/Tray").visible,"actual mouse opens construction tray")
	await shot("home-construction-tray")
	var select:Button=home.find_child("Build_solar",true,false)
	if not check(select!=null,"native construction card offers solar placement"):quit(1);return
	await click(select);check(home.get_node("Layout/Placement").visible and not home.building_kind.is_empty(),"actual mouse selects a ghost instead of building")
	check(app.economy.state==before and FileAccess.get_sha256(profile)==before_sha,"choosing and previewing never charges or saves")
	await shot("home-placement-valid")
	await drag_canvas(home.canvas.point(Vector2(7,4)),home.canvas.point(Vector2(6,4)))
	check(not home.canvas.placement_valid and home.get_node("Layout/Placement/Body/Confirm").disabled,"occupied cell produces blocked ghost and disabled confirmation")
	await shot("home-placement-blocked")
	await drag_canvas(home.canvas.point(Vector2(6,4)),home.canvas.point(Vector2(7,4)),true)
	check(home.canvas.placement_valid,"moving ghost to genuinely empty cell makes placement valid")
	check(app.economy.state==before and FileAccess.get_sha256(profile)==before_sha,"changing target never builds implicitly")
	await escape();check(app.screen=="home" and home.building_kind.is_empty() and not home.get_node("Layout/Placement").visible,"Escape closes pending placement before leaving home")
	check(app.economy.state==before and FileAccess.get_sha256(profile)==before_sha,"cancelling preview preserves exact account and disk bytes")
	await click(home.get_node("Layout/Bottom/Build"));await click(home.find_child("Build_solar",true,false));await canvas_click(home.canvas.point(Vector2(7,4)))
	await click(home.get_node("Layout/Placement/Body/Confirm"))
	check(home.building_kind.is_empty() and not home.get_node("Layout/Placement").visible,"actual confirm closes successful placement")
	check(app.home.building_at(Vector2i(7,4)).get("kind","")=="solar","true account contains confirmed facility at chosen cell")
	check(int(app.home.state().resources.scrap)==int(before.home_v1.resources.scrap)-50 and int(app.home.state().resources.alloy)==int(before.home_v1.resources.alloy)-25,"actual construction charges exact unchanged service costs once")
	await canvas_click(home.canvas.point(Vector2(7,4)));check(home.get_node("Layout/Context").visible,"clicking actual facility opens anchored action card")
	await shot("home-building-card")
	await escape();check(app.screen=="home" and not home.get_node("Layout/Context").visible,"Escape closes building card before leaving home")
	for dimensions in [Vector2i(960,540),Vector2i(1280,720),Vector2i(1920,1080)]:
		root.size=dimensions;await frames();home.canvas.reset_camera()
		for name in ["Build","Recruit","Units","Garrison","Sortie"]:
			var control:Control=home.get_node("Layout/Bottom/"+name);var actual:Vector2=target_size(control)
			check(actual.x>=44 and actual.y>=44,"finger target "+name+" at "+str(dimensions))
			var origin:Vector2=screen_point(control,Vector2.ZERO);var end:Vector2=screen_point(control,control.size)
			check(origin.x>=0 and origin.y>=0 and end.x<=dimensions.x+1 and end.y<=dimensions.y+1,"main action not clipped "+name+" at "+str(dimensions))
		await click(home.get_node("Layout/Bottom/Build"));check(home.get_node("Layout/Tray").visible,"real construction click at "+str(dimensions))
		check(target_size(home.find_child("CloseConstruction",true,false)).y>=44,"construction close touch target at "+str(dimensions))
		var card:Control=home.find_child("Build_solar",true,false);var end:Vector2=screen_point(card,card.size)
		check(end.y<=screen_point(home.get_node("Layout/Bottom"),Vector2.ZERO).y,"construction confirmation is above persistent navigation at "+str(dimensions))
		await shot("home-tray-"+str(dimensions.x));await escape();await shot("home-main-"+str(dimensions.x))
		await click(home.get_node("Layout/Bottom/Sortie"));check(is_instance_valid(app.modal),"actual sortie opens native formation at "+str(dimensions))
		var mode:OptionButton=app.modal.find_child("LittoralMode",true,false);var npc:OptionButton=app.modal.find_child("NPCIsland",true,false)
		check(mode!=null and mode.item_count==3 and npc!=null and npc.item_count==3,"three real operation modes and named NPCs remain available")
		check(app.modal.find_child("DeploymentUnits",true,false).get_child_count()==5,"all five owned released tactical units remain selectable")
		for control in [mode,npc,app.modal.find_child("TransportPreset",true,false),button_text(app.modal,"出发"),button_text(app.modal,"关闭")]:check(target_size(control).y>=44,"sortie finger targets at "+str(dimensions))
		await shot("home-sortie-"+str(dimensions.x));await click(button_text(app.modal,"关闭"));check(not is_instance_valid(app.modal),"real modal close at "+str(dimensions))
	root.size=Vector2i(960,540);await frames()
	await touch_click(home.get_node("Layout/Bottom/Build"));check(home.get_node("Layout/Tray").visible,"actual screen touch opens construction")
	await touch_click(home.find_child("CloseConstruction",true,false));check(not home.get_node("Layout/Tray").visible,"actual screen touch closes construction")
	await click(home.get_node("Layout/Bottom/Build"));await click(home.find_child("Build_forge",true,false))
	var paid:Dictionary=app.economy.state.duplicate(true);var paid_sha:String=FileAccess.get_sha256(profile)
	await click(home.get_node("Layout/Placement/Body/Cancel"));check(home.building_kind.is_empty() and app.economy.state==paid and FileAccess.get_sha256(profile)==paid_sha,"explicit Cancel discards ghost without charging")
	await click(home.get_node("Layout/Bottom/Build"));await click(home.find_child("Build_forge",true,false))
	var previous_home=home;await click(button_text(app.page,"母港"));check(app.screen=="harbor" and app.economy.state==paid and FileAccess.get_sha256(profile)==paid_sha,"direct mother-port leaves unconfirmed facility uncharged")
	app.show_page("home");await frames();home=app.page.find_child("HomeIsland",true,false);check(home!=previous_home and home.building_kind.is_empty(),"returning to island does not restore a discarded ghost")
	var persisted=Economy.new(profile);check(persisted.load_state().get("ok",false) and persisted.state.home_v1.buildings.size()==app.home.state().buildings.size(),"confirmed placement survives complete disk reload")
	# A controlled clock fixture exercises the real hourly production transaction; no wallet or inventory is filled by the test.
	var clock_before:Dictionary=app.economy.state.duplicate(true);app.home.state().last_collect=int(Time.get_unix_time_from_system())-7200
	check(app.economy._commit(clock_before,"isolated UI clock fixture").get("ok",false),"save isolated two-hour production clock fixture")
	home.refresh();await frames();var stock_before:int=int(app.home.state().resources.energy);var pending:int=int(app.home.overview().pending.energy)
	check(pending==60 and not home.get_node("Layout/Top/Collect").disabled,"actual production exposes two real solar facilities and collect action")
	await shot("home-production-bubbles-960")
	var at:Vector2=home.canvas.point(Vector2(7,4));var bubble:Vector2=at+Vector2(0,-home.canvas.rect().size.x/12*home.canvas.facility_scale*.60-sin(home.canvas.clock*2)*3)
	await canvas_click(bubble)
	check(int(app.home.state().resources.energy)==stock_before+pending and int(app.home.overview().pending.energy)==0,"actual facility bubble collects all genuine elapsed production once")
	var collected:Dictionary=app.economy.state.duplicate(true);await click(home.get_node("Layout/Top/Collect"));check(app.economy.state==collected,"disabled empty collection cannot duplicate resources")
	var prepared:Dictionary=app.home.prepare_littoral("raid",18031,["MCP-034"],["IBS-U-USN-FLETCHER"],"transport")
	check(prepared.get("ok",false),"prepare a genuine owned-force voyage for active-state gate")
	if prepared.get("ok",false):
		app.launch_littoral(prepared.request);app.running=false;app.show_page("home");await frames();home=app.page.find_child("HomeIsland",true,false)
		var active_state:Dictionary=app.economy.state.duplicate(true);var active_disk:String=FileAccess.get_sha256(profile)
		await click(home.get_node("Layout/Bottom/Build"));check(home.get_node("Layout/Notice").visible and not home.get_node("Layout/Tray").visible,"real active voyage explains why construction is unavailable")
		check(app.economy.state==active_state and FileAccess.get_sha256(profile)==active_disk,"blocked construction leaves active voyage and all supplies byte-identical")
		await shot("home-active-voyage-960");await escape();await click(home.get_node("Layout/Bottom/Sortie"));check(home.get_node("Layout/Notice").visible,"active sortie offers continuation instead of a second voyage")
		await click(button_text(home.get_node("Layout/Notice"),"继续行动"));check(app.screen=="battle" and not app.economy.state.active_run.is_empty(),"actual continue resumes the same authoritative voyage")
	var runtime:Dictionary=load("res://tests/home_runtime_evidence.gd").capture(app.core)
	app.core.close();app.queue_free();await process_frame
	var locked_profile:String=OUTPUT+"isolated-locked-%d.json"%OS.get_process_id();var locked=Economy.new(locked_profile)
	check(locked.load_state().get("ok",false),"create an ordinary fresh profile through the normal account factory")
	app=load("res://scenes/main.tscn").instantiate();app.boot_to_title=false;app.economy=locked;root.size=Vector2i(960,540);root.add_child(app);await frames();app.set_process(false);app.page_motion=false;app.show_page("home");await frames();home=app.page.find_child("HomeIsland",true,false)
	check(not bool(app.home.state().unlocked) and home.get_node("Layout/Notice").visible,"ordinary new island shows a single actionable unlock guide")
	await shot("home-locked-guide-960")
	await click(button_text(home.get_node("Layout/Notice"),"开始登陆"));check(app.screen=="home_story" and not bool(app.home.state().unlocked),"actual unlock guide opens narrative teaching without granting island resources")
	app.core.close();app.queue_free();await process_frame
	check(FileAccess.get_sha256(source)==source_sha,"main profile exact bytes untouched");check(FileAccess.get_sha256(source+".bak")==backup_sha,"main backup exact bytes untouched")
	FileAccess.open(OUTPUT+"receipt.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"passed":failures.is_empty(),"screenshots":screenshots,"input_events":input_count,"runtime":runtime,"artwork":artwork_evidence,"canvas_texture_filter":CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS,"profile":ProjectSettings.globalize_path(profile),"locked_profile":locked_profile,"production_clock_fixture":"only isolated last_collect set to now-7200; actual 2 solar hourly rates and real collect transaction; no resources directly assigned","source_sha256":source_sha,"backup_sha256":backup_sha},"  "))
	print("HOME_MOBILE "+JSON.stringify({"checks":checks,"failures":failures,"input_events":input_count}));quit(0 if failures.is_empty() else 1)
