extends SceneTree
const TransitionSettle=preload("res://tests/transition_settle.gd")
var app
var checks:=0
var events:=0
var failures:Array[String]=[]
var pictures:Array[String]=[]
var account_path:="user://tests/fleet-navigation-%d.json"%OS.get_process_id()
var output:="res://../artifacts/godot/fleet-navigation/"
func _initialize() -> void: call_deferred("run")
func check(ok:bool,message:String) -> void:
	checks+=1
	if not ok: failures.append(message);push_error(message)
func button(text:String) -> Control:
	for child in app.find_children("*","BaseButton",true,false):
		if child.is_visible_in_tree() and child.text==text: return child
	return null
func click_control(control:Control) -> void:
	await TransitionSettle.wait_for_route(self,app)
	check(control!=null,"visible control available")
	if control==null:return
	var point:=control.get_viewport().get_screen_transform()*control.get_global_transform_with_canvas()*(control.size*.5)
	var motion:=InputEventMouseMotion.new();motion.position=point;Input.parse_input_event(motion)
	var down:=InputEventMouseButton.new();down.button_index=MOUSE_BUTTON_LEFT;down.pressed=true;down.position=point;Input.parse_input_event(down)
	await process_frame
	var up:=InputEventMouseButton.new();up.button_index=MOUSE_BUTTON_LEFT;up.position=point;Input.parse_input_event(up)
	events+=3
	await process_frame;await process_frame
	await TransitionSettle.wait_for_route(self,app)
func click(text:String) -> void: await click_control(button(text))
func shot(name:String) -> void:
	if DisplayServer.get_name()=="headless":return
	await RenderingServer.frame_post_draw
	var path:=ProjectSettings.globalize_path(output+name+".png")
	check(root.get_texture().get_image().save_png(path)==OK,"rendered "+name);pictures.append(path)
func new_app() -> void:
	app=load("res://scenes/main.tscn").instantiate();app.boot_to_title=false;app.economy=load("res://scripts/economy.gd").new(account_path);root.add_child(app)
	await process_frame;await process_frame
func run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	await new_app()
	await click("活动");check(app.screen=="activity","activity moved to top bar")
	await click("‹  返回")
	var mail:Control
	for child in app.find_children("*","Button",true,false):
		if child.tooltip_text=="邮件":mail=child
	await click_control(mail);check(app.screen=="mail","independent upper-right mail")
	await click("‹  返回");await click("仓库");await click("舰装与水手")
	check(str(app.get_meta("warehouse_tab",""))=="gear","warehouse separates physical cargo from instance loadouts")
	await shot("01-warehouse")
	await click("‹  返回");await click("舰娘")
	var service_ids:Array=app.economy.state.owned.keys()
	var first:String=str(service_ids[0]);var second:String=str(service_ids[1])
	app.economy.state.owned[first].hp=60;app.economy.state.owned[second].hp=70
	app.economy.state.owned[first].ammo=12;app.economy.state.owned[second].ammo=15
	app.economy.state.wallet.credits=5000;app.economy.state.wallet.ammo_stock=0
	var credits_before:int=app.economy.state.wallet.credits
	await click("一键维修");await click("确认整备")
	check(int(app.economy.state.owned[first].hp)==100 and int(app.economy.state.owned[second].hp)==100,"one-click repair heals all damaged owned ships")
	check(int(app.economy.state.owned[first].ammo)==12 and int(app.economy.state.wallet.ammo_stock)==0,"repair does not purchase or change ammunition")
	check(int(app.economy.state.wallet.credits)==credits_before-140,"repair invoice debits exact aggregate price once")
	app.economy.state.owned[first].hp=90
	await click("一键补给");await shot("01b-service-invoice");await click("确认整备")
	check(int(app.economy.state.owned[first].hp)==90 and int(app.economy.state.owned[first].ammo)==100,"ammo-only service updates plan without healing")
	check(int(app.economy.state.wallet.ammo_stock)>=service_ids.size()*100,"ammo-only purchases stock sufficient for all selected plans")
	var stocked:int=app.economy.state.wallet.ammo_stock
	await click("一键整备");await click("确认整备")
	check(int(app.economy.state.owned[first].hp)==100 and int(app.economy.state.wallet.ammo_stock)==stocked,"combined service reuses stock and repairs remaining damage")
	await click("‹  返回");await click("更换 / 调整")
	check(is_instance_valid(app.modal),"secretary controls accessible")
	var slider:HSlider=app.modal.find_children("*","HSlider",true,false)[0]
	slider.value=1.25
	var horizontal:HSlider=app.modal.find_child("SecretaryHorizontal",true,false)
	var vertical:HSlider=app.modal.find_child("SecretaryVertical",true,false)
	check(horizontal.min_value<=-1200 and horizontal.max_value>=1200,"secretary can move across expanded horizontal range")
	check(vertical.min_value<=-900 and vertical.max_value>=700,"secretary can move across expanded vertical range")
	horizontal.value=900
	vertical.value=300
	await click("保存展示")
	check(is_equal_approx(float(app.economy.state.harbor.scale),1.25),"secretary scale persists through public UI save")
	check(int(app.economy.state.harbor.x)==900 and int(app.economy.state.harbor.y)==300,"secretary position beyond old limits persists through public UI save")
	await click("更换 / 调整")
	await click_control(app.modal.find_child("Secretary_IBS-U-USN-MAURY",true,false))
	check(str(app.economy.state.harbor.secretary)=="IBS-U-USN-MAURY","owned secretary replaced")
	await shot("02-secretary")
	await click("编队");await click("＋ 管理成员")
	await click_control(app.modal.find_child("FleetMember_IBS-U-USN-MAURY",true,false))
	await click("完成编队")
	check(app.economy.formation.size()==2,"remove hull from first composition via roster")
	await click("＋ 新建")
	var field:LineEdit=app.modal.find_children("*","LineEdit",true,false)[0]
	field.text="护航编队"
	await click("保存")
	await click("＋ 管理成员")
	await click_control(app.modal.find_child("FleetMember_IBS-U-USN-MAURY",true,false))
	await click("完成编队")
	await click("随队出航 · 1 艘")
	check(app.fleets.groups().size()==2 and app.economy.formation.size()==3,"two independent nonduplicated groups selected via UI")
	check(app.economy.preview_sortie(6109).groups.size()==2,"sortie preview freezes the actual two group selection")
	await shot("03-multiple-fleets")
	app.queue_free();await process_frame;await process_frame
	await new_app()
	check(app.fleets.groups().size()==2 and app.economy.formation.size()==3,"restart retains multiple fleet deployment")
	check(str(app.economy.state.harbor.secretary)=="IBS-U-USN-MAURY" and is_equal_approx(float(app.economy.state.harbor.scale),1.25),"restart retains secretary and scale")
	check(int(app.economy.state.harbor.x)==900 and int(app.economy.state.harbor.y)==300,"restart retains expanded secretary position after identity replacement")
	app.page_motion=true;app.set_meta("reduced_motion",false);app.show_page("modes")
	await process_frame
	if DisplayServer.get_name()=="headless":
		check(not app.page_transition.overlay.visible,"headless route cuts immediately")
	else:
		check(app.page_transition.overlay.visible and app.page_transition.overlay.mouse_filter==Control.MOUSE_FILTER_STOP,"full-screen transition temporarily intercepts input")
	await shot("04-fullscreen-transition")
	await TransitionSettle.wait_for_route(self,app)
	check(not app.page_transition.overlay.visible and is_equal_approx(app.page.modulate.a,1.0),"transition finishes automatically without a loading hold")
	app.page_motion=false;app.show_page("harbor")
	check(not app.page_transition.overlay.visible and is_equal_approx(app.page.modulate.a,1.0),"disabled motion switches directly to a fully visible page")
	app.queue_free();await process_frame
	var receipt_name:="receipt-headless.json" if DisplayServer.get_name()=="headless" else "receipt.json"
	var file:=FileAccess.open(ProjectSettings.globalize_path(output+receipt_name),FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"failures":failures,"input_events":events,"screenshots":pictures,"input_method":"Godot internal pointer events, slider/text use native UI properties; isolated profile"},"  "));file.close()
	print("FLEET_NAVIGATION: %d/%d"%[checks-failures.size(),checks]);quit(0 if failures.is_empty() else 1)
