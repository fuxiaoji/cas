extends SceneTree
## Isolated full-collection UI workload; no formal save and no simulated 6000-body claim.
const OUTPUT:String="res://../artifacts/island-war-v2/home/"
const Art=preload("res://scripts/character_art.gd")
var failures:Array[String]=[]
var app
var account
var report:Dictionary={}
func _initialize()->void:call_deferred("run")
func frames(count:int)->void:
	for index in range(count):await process_frame
func check(value:bool,message:String)->void:
	if not value:failures.append(message);push_error(message)
func counters()->Dictionary:
	return {"tracked_static_bytes":int(Performance.get_monitor(Performance.MEMORY_STATIC)),"texture_bytes":int(Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED)),"node_count":int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),"resource_count":int(Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT)),"draw_calls":int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),"portrait_cache_count":Art.textures.size()}
func p95(values:Array)->float:
	var ordered:Array=values.duplicate();ordered.sort();return float(ordered[mini(ordered.size()-1,int(ceil(ordered.size()*.95))-1)]) if not ordered.is_empty() else 0.0
func timings(count:int)->Dictionary:
	var durations:Array=[];var previous:int=Time.get_ticks_usec()
	for index in range(count):
		await process_frame;var current:int=Time.get_ticks_usec();durations.append(float(current-previous)/1000.0);previous=current
	return {"frames":count,"p95_frame_ms":p95(durations),"mean_frame_ms":durations.reduce(func(a,b):return a+b,0.0)/maxi(1,count),"maximum_frame_ms":durations.max()}
func loaded(entries:Array)->int:
	var count:int=0
	for item in entries:
		if is_instance_valid(item.node) and item.node.texture!=null:count+=1
	return count
func pointer(node:Control,ratio:float)->void:
	var point:Vector2=node.get_viewport().get_screen_transform()*(node.get_global_transform_with_canvas()*Vector2(node.size.x*ratio,node.size.y*.5))
	for pressed in [true,false]:
		var event:=InputEventMouseButton.new();event.position=point;event.button_index=MOUSE_BUTTON_LEFT;event.pressed=pressed;Input.parse_input_event(event);await process_frame
func run()->void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	var formal:String=FileAccess.get_sha256("user://cas_port_v1.json");var backup:String=FileAccess.get_sha256("user://cas_port_v1.json.bak")
	account=load("res://scripts/economy.gd").new(OUTPUT+"performance-isolated-%d.json"%OS.get_process_id());check(account.new_profile().ok,"isolated profile created")
	var home=load("res://scripts/home_service.gd").new(account)
	account.state.commander.level=30;account.state.progression.first_voyage_canon.active=false;home.state().unlocked=true;home.state().tutorial_complete=true;home.state().drag_tutorial_completed=true
	for card in account.catalog:
		if bool(card.get("playable",false)):account.state.owned[str(card.id)]=account._new_owned(str(card.id))
	for card in home.v2_units():home._own_unit(str(card.id));home.state().units[str(card.id)].condition=100;home.state().units[str(card.id)].at=home._now()
	home.state().garrison=["IBS-U-USN-ERMA-IOWA","CAS-H-USN-ENTERPRISE-1942"];home.state().tactical_garrison=["MCP-088","MCP-006","MCP-034"]
	account.save_state();report["owned_ships"]=account.state.owned.size();report["tactical_identities"]=home.v2_cards.size();check(account.state.owned.size()>=200,"full collection fixture covers200plus ownedships")
	app=load("res://scenes/main.tscn").instantiate();app.boot_to_title=false;app.deferred_startup=false;app.staged_navigation=false;app.immersive_fullscreen=false;app.economy=account;app.fullscreen_battle=false;root.content_scale_size=Vector2i(1600,900);root.size=Vector2i(1280,720);root.add_child(app);await frames(8);app.page_motion=false;app.page_transition.cancel();AudioServer.set_bus_mute(0,true);app.show_page("home");await frames(20)
	report["home_baseline"]=counters();report["home_baseline"].merge(await timings(90));var account_before:Dictionary=account.state.duplicate(true);var disk_before:String=FileAccess.get_file_as_string(account.save_path)
	var started:int=Time.get_ticks_usec();load("res://scripts/home_sortie_v2.gd").open(app,"exercise");await frames(8);report["first_open_ready_ms"]=float(Time.get_ticks_usec()-started)/1000.0
	var ui=app.modal.get_meta("ui_owner");check(ui.ship_thumbnails.size()>=200,"full collection has real ship controls");report["initial_loaded_ship_portraits"]=loaded(ui.ship_thumbnails);report["initial_loaded_tactical_portraits"]=loaded(ui.unit_thumbnails);check(loaded(ui.ship_thumbnails)>0 and loaded(ui.ship_thumbnails)<=16,"only visible plus prefetched ship portraits have texture references");check(loaded(ui.unit_thumbnails)>0 and loaded(ui.unit_thumbnails)<=10,"tactical strip also loads only its visible and prefetched portraits")
	report["deployment"]=counters();report["deployment"].merge(await timings(150));var bar:HScrollBar=ui.ship_window.get_h_scroll_bar();var scroll_durations:Array=[];var loaded_max:int=loaded(ui.ship_thumbnails)
	for index in range(24):
		started=Time.get_ticks_usec();await pointer(bar,float(index%12)/11.0);await frames(3);scroll_durations.append(float(Time.get_ticks_usec()-started)/1000.0);loaded_max=maxi(loaded_max,loaded(ui.ship_thumbnails))
	var unit_max:int=loaded(ui.unit_thumbnails)
	for index in range(12):await pointer(ui.unit_window.get_h_scroll_bar(),float(index)/11.0);await frames(3);unit_max=maxi(unit_max,loaded(ui.unit_thumbnails))
	report["scroll"]=counters();report["scroll"].merge({"steps":24,"five_frame_pointer_step_p95_ms":p95(scroll_durations),"maximum_loaded_ship_portraits":loaded_max,"maximum_loaded_tactical_portraits":unit_max});check(loaded_max<=16 and unit_max<=10,"scrolling full collection releases offscreen thumbnail references");check(Art.textures.size()<=Art.TEXTURE_CACHE_LIMIT,"image cache remains bounded after collection scroll")
	app.close_modal();await frames(12);report["closed_once"]=counters()
	for index in range(4):load("res://scripts/home_sortie_v2.gd").open(app,"exercise");await frames(5);app.close_modal();await frames(8)
	report["closed_after_five"]=counters();report["closed_after_five"].merge(await timings(90));check(home._same(account_before,account.state) and FileAccess.get_file_as_string(account.save_path)==disk_before,"viewing and scrolling collection never changes account")
	check(FileAccess.get_sha256("user://cas_port_v1.json")==formal and FileAccess.get_sha256("user://cas_port_v1.json.bak")==backup,"formal account andbackup are untouched")
	report["failures"]=failures;report["device"]=RenderingServer.get_video_adapter_name();report["scope"]="RTX desktop 1280x720 full collection: viewport lazy ship portraits, boundedcache, actual pointer scrollbar, repeated modal closure; tracked heap and renderer texture counters, nottotal processRSS/mobile/6000 bodies"
	FileAccess.open(OUTPUT+"receipt-performance-ui.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "));print("HOME_V2_PERFORMANCE ",JSON.stringify(report));app.core.close();quit(0 if failures.is_empty() else 1)
