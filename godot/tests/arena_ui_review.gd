extends SceneTree
const Main=preload("res://scenes/main.tscn")
const Economy=preload("res://scripts/economy.gd")
var app
var checks:int=0
var failures:Array[String]=[]
var images:Array[String]=[]
var output:String="res://../artifacts/godot/arena-ui/"
var save_path:String
func _initialize()->void:call_deferred("run")
func check(ok:bool,title:String)->void:
	checks+=1
	if not ok:failures.append(title);push_error(title)
func frame()->void:
	await process_frame;await process_frame
	if DisplayServer.get_name()!="headless":await RenderingServer.frame_post_draw
func shot(name:String)->void:
	await frame()
	var path:String=ProjectSettings.globalize_path(output+name+".png")
	check(root.get_texture().get_image().save_png(path)==OK,"actual GPU image "+name);images.append(path)
func click(control:Control)->void:
	var position:Vector2=control.get_viewport().get_screen_transform()*(control.get_global_rect().get_center())
	for pressed in [true,false]:
		var event:=InputEventMouseButton.new();event.button_index=MOUSE_BUTTON_LEFT;event.pressed=pressed;event.position=position;Input.parse_input_event(event);await process_frame
	await frame()
func hub()->Control:return app.page.get_node("ArenaHub")
func setup()->void:
	app=Main.instantiate();app.boot_to_title=false
	app.economy=Economy.new(save_path)
	root.add_child(app);app.set_process(false);await frame();app.page_motion=false;app.set_meta("reduced_motion",true)
func refresh()->void:
	app.show_page("arena");await frame()
func full_match(mode:String)->void:
	app.set_meta("arena_mode",mode);app.set_meta("next_arena_seed",8116 if mode=="ranked" else 8117);await refresh()
	var before:Dictionary=app.arena.profile(mode)
	check(not hub().get_node("Launch").disabled,"valid "+mode+" formation enables the real start button")
	await click(hub().get_node("Launch"))
	check(app.screen=="battle" and str(app.core.view.get("arena",{}).get("mode",""))==mode,"real UI launches native "+mode+" battle")
	if app.screen!="battle":return
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED);app.fullscreen_battle=false;root.size=Vector2i(1280,720);await frame()
	var teams:Array=app.core.view.arena.groups
	check(teams.any(func(row):return row.get("bot",false) and str(row.side)=="axis"),mode+" native roster contains actual named bot opponents")
	if mode=="team3":
		check(teams.filter(func(row):return str(row.side)=="allies" and bool(row.get("bot",false))).size()==2 and teams.filter(func(row):return str(row.side)=="axis").size()==3,"3v3 has two real AI allies and three enemy AI teams")
		var bot_group:Dictionary=teams.filter(func(row):return str(row.side)=="allies" and bool(row.get("bot",false)))[0]
		var bot_ship:Dictionary=app.core.view.ships.filter(func(row):return int(row.fleet)==int(bot_group.fleet))[0]
		app.battle_controller.select("ship",bot_ship)
		check(app.sea.readonly and app.battle_controller._closed(),"inspecting an AI ally immediately makes tactical map and controls read-only")
		var denied:Dictionary=app.core.request({"op":"speed","fleet":int(bot_group.fleet),"speed":10})
		check(not denied.get("ok",false),"authoritative core also rejects commands to independent AI allies")
		var own_ship:Dictionary=app.core.view.ships.filter(func(row):return app.core.view.arena.player_fleets.any(func(value):return int(value)==int(row.fleet)))[0]
		app.battle_controller.select("ship",own_ship)
		check(not app.sea.readonly and not app.battle_controller._closed(),"returning to the player ship restores tactical control immediately")
	for fleet in app.core.view.get("fleets",[]):
		app.core.request({"op":"ai","fleet":int(fleet.id),"mode":"auto","profile":"coord","move":true,"gun":true,"torpedo":true})
	for step in range(50):
		app.core.request({"op":"step","seconds":30})
		if app.core.view.get("result")!=null:break
	check(app.core.view.get("result") is Dictionary,mode+" native match reaches a true result")
	app.update_battle();await shot(mode+"-actual-battle")
	app.finish_battle();await frame()
	check(app.screen=="result" and str(app.last_receipt.get("mode",""))=="arena",mode+" result uses actual arena settlement")
	check(int(app.arena.profile(mode).played)==int(before.played)+1 and app.economy.state.active_run.is_empty(),mode+" clears active voyage and records one real result")
	await shot(mode+"-result")
	app.set_meta("arena_mode",mode);await refresh()
	check(not app.arena.history(mode).is_empty(),mode+" history contains the real outcome")
func run()->void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output));save_path="user://tests/arena-ui-%d.json"%OS.get_process_id()
	root.content_scale_size=Vector2i(1600,900);root.size=Vector2i(1280,720)
	await setup()
	var old:Dictionary=app.economy.state.duplicate(true)
	var ids:Array=[]
	for card in app.economy.catalog:
		if bool(card.get("playable",false)) and str(card.get("type",""))=="DD" and int(card.get("points",0))<=600 and ids.size()<6:
			var id:String=str(card.id);ids.append(id);app.economy.state.owned[id]=app.economy._new_owned(id)
	check(ids.size()==6,"isolated test roster has six distinct low-point destroyers")
	app.economy.state.fleet_book=[]
	for i in range(6):app.economy.state.fleet_book.append({"id":"arena-ui-f%d"%i,"name":["晨雾先锋","蓝湾护卫","星灯巡航","海风游击","备用舰队","远洋支援"][i],"ships":[ids[i]]})
	app.economy.state.arena_league.selection={"ranked":["arena-ui-f0"],"team3":["arena-ui-f0"]}
	check(app.economy._commit(old,"isolated arena test fixture").get("ok",false),"test fleet book saves independently from normal account")
	await refresh()
	check(app.screen=="arena" and hub()!=null,"actual arena route builds the native editable hub")
	check(hub().get_node("FleetScroll/Fleets").get_child_count()==6,"all saved fleets appear in the scrollable portrait grid")
	for dimension in [Vector2i(960,540),Vector2i(1280,720),Vector2i(1600,900),Vector2i(1600,720)]:
		root.size=dimension;await shot("ranked-hub-%dx%d"%[dimension.x,dimension.y])
		check(hub().get_node("Launch").get_global_rect().end.x<=root.get_visible_rect().size.x+.1,"start button remains inside scaled safe layout "+str(dimension))
	root.size=Vector2i(1280,720)
	await click(hub().get_node("TierRewards"))
	check(app.modal!=null and app.modal.find_child("Claim_cadet",true,false).disabled,"new account cannot claim tier rewards before a real match")
	await shot("tier-rewards-before-match");app.close_modal()
	for i in range(1,4):
		var row=hub().get_node("FleetScroll/Fleets").get_node("Fleet_arena-ui-f%d"%i)
		var selector:CheckButton=row.find_child("SelectGroup",true,false);selector.button_pressed=true;await frame()
	check(app.arena.selected("ranked").size()==4,"portrait card selectors persist four chosen formations")
	var blocked:Dictionary=app.arena.toggle_group("ranked","arena-ui-f4",true)
	check(not blocked.ok and app.arena.selected("ranked").size()==4,"a fifth group is rejected by the real account service")
	await refresh();await shot("ranked-four-groups")
	var previous:Dictionary=app.economy.state.duplicate(true)
	app.economy.state.fleet_book[1].ships=[ids[0]];app.economy._commit(previous,"isolated duplicate-group fixture")
	await refresh();check(hub().get_node("Launch").disabled and hub().get_node("Feedback").text.contains("同一"),"duplicate ship across groups disables start with a clear message")
	previous=app.economy.state.duplicate(true);app.economy.state.fleet_book[1].ships=[ids[1]];app.economy._commit(previous,"restore isolated unique groups");await refresh()
	await click(hub().get_node("Team3"))
	check(str(app.get_meta("arena_mode",""))=="team3" and hub().get_node("BudgetValue").text.ends_with("3400"),"actual tab selects the independently budgeted 3v3 mode")
	check(app.arena.selected("team3").size()==1 and app.arena.selected("ranked").size()==4,"ranked and team lineups remain independent")
	await shot("team3-hub")
	await full_match("ranked")
	await click(hub().get_node("TierRewards"))
	var claim=app.modal.find_child("Claim_cadet",true,false)
	check(not claim.disabled,"actual completed match enables an earned tier reward")
	var credits:int=int(app.economy.state.wallet.credits);await click(claim)
	check(app.arena.profile("ranked").claims.has("cadet") and int(app.economy.state.wallet.credits)>credits,"tier reward button grants and saves real resources")
	check(app.modal.find_child("Claim_cadet",true,false).disabled,"already claimed reward is disabled")
	await shot("tier-rewards-after-claim");app.close_modal()
	await full_match("team3")
	await click(hub().get_node("History"));await shot("team3-history");check(app.modal!=null,"history opens after an actual team battle");app.close_modal()
	var saved_rank:Dictionary=app.arena.profile("ranked");var saved_team:Dictionary=app.arena.profile("team3")
	app.core.close();app.queue_free();await frame();await setup()
	var restart_evidence:Dictionary={"before_rank":saved_rank,"after_rank":app.arena.profile("ranked"),"before_team":saved_team,"after_team":app.arena.profile("team3")}
	check(app.arena.profile("ranked")==saved_rank and app.arena.profile("team3")==saved_team,"both ratings and claimed rewards survive a full app reload")
	app.set_meta("arena_mode","ranked");await refresh();await shot("ranked-after-restart")
	app.core.close();app.queue_free();await process_frame
	var report:Dictionary={"checks":checks,"failures":failures,"passed":failures.is_empty(),"restart":restart_evidence,"screenshots":images,"renderer":RenderingServer.get_video_adapter_name(),"profile":"PID-isolated fixture; six owned DD supplied only to this test account; both modes played through real native results"}
	FileAccess.open(output+"receipt.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "));print("ARENA_UI ",JSON.stringify({"checks":checks,"failures":failures,"passed":failures.is_empty()}));quit(0 if failures.is_empty() else 1)
