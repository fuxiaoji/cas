@tool
extends Control
const Design=preload("res://scripts/ui_design.gd")
const Pilot=preload("res://scripts/extraction_pilot_service.gd")
const POLICIES=["cautious","balanced","bold"]
const POLICY_NAMES=["谨慎 · 优先保全","均衡 · 连续搜索","大胆 · 深入探索"]
const STATUS_NAMES={"offered":"可选","accepted":"已接取","working":"交互中","complete":"已完成","abandoned":"已放弃"}
const SCENES={"sunken_metropolis":"溺城街区","cult_relay":"拜教中继","storm_wrecks":"风暴船冢","thermal_vent":"热泉裂谷","refugee_causeway":"流民堤道"}
var app
var board:Control
var task_rows:Dictionary={}
var selected_policy:String="balanced"
static func attach(owner)->void:
	if owner.core.view.get("salvage",{}).get("expedition",{}).is_empty():return
	var view:Control=load("res://scenes/ui/expedition_operations.tscn").instantiate();view.app=owner;owner.page.add_child(view)
	if not owner.core.view.get("salvage",{}).get("amphibious",{}).is_empty():
		var army:Control=load("res://scenes/ui/amphibious_expedition.tscn").instantiate();army.app=owner;owner.page.add_child(army)
func _ready()->void:
	for button in [$Tasks,$Auto]:Design.apply_button(button);button.add_theme_font_size_override("font_size",19)
	$Fuel.add_theme_stylebox_override("background",Design.box(Color(.04,.15,.22,.72),4))
	$Fuel.add_theme_stylebox_override("fill",Design.box(Color("79c6b4"),4))
	for label in [$Status,$FuelLabel]:
		label.add_theme_color_override("font_color",Color("f2f6ef"));label.add_theme_color_override("font_shadow_color",Color(.02,.10,.17,.9));label.add_theme_constant_override("shadow_offset_x",1);label.add_theme_constant_override("shadow_offset_y",1)
	if Engine.is_editor_hint():return
	$Tasks.pressed.connect(open_board);$Auto.pressed.connect(open_board);refresh()
func state()->Dictionary:
	return app.core.view.get("salvage",{}).get("expedition",{}) if is_instance_valid(app) else {}
func refresh()->void:
	if not is_instance_valid(app):return
	var data:Dictionary=state();var ai:Dictionary=data.get("autopilot",{})
	var fuel:Dictionary=app.core.view.get("fuel",{})
	$Fuel.visible=not fuel.is_empty();$FuelLabel.visible=not fuel.is_empty()
	if not fuel.is_empty():
		$Fuel.value=float(fuel.get("fraction",1))*100
		$Fuel.tooltip_text="剩余%.1f / %d · 当前每分钟%.1f · 20节返航需%.1f"%[float(fuel.get("remaining",0)),int(fuel.get("loaded",0)),float(fuel.get("rate_per_minute",0)),float(fuel.get("return_required",0))]
		$FuelLabel.text="油料耗尽 · 拖救倒计时%d秒"%int(fuel.get("rescue_in",0)) if str(fuel.get("state",""))=="empty" else "低油量 · 建议返航" if float(fuel.get("fraction",1))<=.2 else "油料充足"
	$Auto.text="接管 · 自动中" if ai.get("enabled",false) else "自动打捞"
	$Auto.tooltip_text="打开自动指挥，查看评估、切换策略或接管"
	var boss:String=str(data.get("boss",{}).get("status","dormant"))
	$Status.visible=bool(ai.get("enabled",false)) or boss in ["announced","active"]
	$Status.text="自动 · "+str(ai.get("reason","正在评估")) if ai.get("enabled",false) else "渊喉将至 · 可提前撤离" if boss=="announced" else "渊喉在场 · 留意攻击预警"
	$Status.max_lines_visible=1;$Status.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS;$Status.tooltip_text=$Status.text
	var assignments:Array=ai.get("fleet_targets",[])
	if str(ai.get("phase","")) in ["extract","extract_wait","blocked","complete"]:assignments=[]
	for assignment in assignments:
		var fleet_name:String="编队"
		for fleet in app.core.view.get("fleets",[]):
			if int(fleet.get("id",-1))==int(assignment.get("fleet",-2)):fleet_name=str(fleet.get("name",fleet_name));break
		var action:String=str({"approach":"前往搜索点","wait_search":"等待搜索","search":"搜索中","wait_group":"已搜索，等待其他编队","escort":"伴随支援其他编队","return":"返航集结","hold":"已进入接驳区"}.get(str(assignment.get("phase","")),"行动中"))
		$Status.tooltip_text+="\n"+fleet_name+" · "+action
	if is_instance_valid(board):_refresh_board()
func open_board()->void:
	if not is_instance_valid(app):return
	var previous:bool=app.running;app.running=false
	var layer:Control=app.open_modal("海域行动")
	board=load("res://scenes/ui/expedition_board.tscn").instantiate();layer.add_child(board);board.position=Vector2(370,222)
	layer.tree_exited.connect(func():
		if is_instance_valid(app) and app.screen=="battle" and app.core.view.get("result")==null:app.running=previous)
	task_rows={}
	for task in state().get("tasks",[]):
		var row:Control=load("res://scenes/ui/expedition_task_card.tscn").instantiate();board.get_node("Scroll/Tasks").add_child(row)
		row.add_theme_stylebox_override("panel",Design.box(Color("e8f1f2"),3))
		task_rows[str(task.id)]=row
		var body:Control=row.get_node("Margin/Body")
		body.get_node("Icon").texture=Design.icon_texture({"relay":"radar","survey":"search","rescue":"crew","beacon":"sortie","cache":"cargo"}.get(str(task.kind),"compass"))
		body.get_node("Icon").modulate=Design.ACCENT
		var id:String=str(task.id)
		body.get_node("Actions/Locate").pressed.connect(func():_locate(id))
		body.get_node("Actions/Act").pressed.connect(func():_act(id))
		body.get_node("Actions/Abandon").pressed.connect(func():app.issue({"op":"expedition_task","task":id,"action":"abandon"}))
		for button in body.get_node("Actions").get_children():Design.apply_button(button);button.add_theme_font_size_override("font_size",17);button.size_flags_vertical=Control.SIZE_SHRINK_CENTER
		body.get_node("Actions/Act").tooltip_text="靠近650米，降至8节以下；受伤会中断交互"
	var policy:OptionButton=board.get_node("Policy")
	for title in POLICY_NAMES:policy.add_item(title)
	selected_policy=str(state().get("autopilot",{}).get("policy","balanced"));policy.select(maxi(0,POLICIES.find(selected_policy)))
	policy.tooltip_text="均衡策略会在舰况、弹药、油料和空位允许时继续搜索，必要时集结撤离。"
	policy.item_selected.connect(func(i:int):
		selected_policy=POLICIES[i]
		if state().get("autopilot",{}).get("enabled",false):app.issue(Pilot.command(true,selected_policy)))
	Design.apply_button(policy);policy.add_theme_font_size_override("font_size",17)
	var toggle:Button=board.get_node("Toggle");Design.apply_button(toggle,true)
	toggle.pressed.connect(func():
		var enabled:bool=not bool(state().get("autopilot",{}).get("enabled",false))
		var response:Dictionary=app.issue(Pilot.command(enabled,selected_policy))
		if response.get("ok",false) and enabled:app.close_modal();app.running=true)
	_refresh_board();toggle.grab_focus()
func _refresh_board()->void:
	var data:Dictionary=state();var ai:Dictionary=data.get("autopilot",{})
	var boss:String=str(data.get("boss",{}).get("status","dormant"))
	board.get_node("Situation").text="%s  ·  警戒 %d/100  ·  %s"%[str(SCENES.get(str(data.get("scene","")),"远征海域")),int(data.get("pressure",0)),{"dormant":"可选任务不影响撤离","announced":"渊喉即将出现","active":"渊喉已入场，可战可退","defeated":"渊喉已击败，核心可打捞"}.get(boss,boss)]
	for task in data.get("tasks",[]):
		if not task_rows.has(str(task.id)):continue
		var body:Control=task_rows[str(task.id)].get_node("Margin/Body");var phase:String=str(task.status)
		body.get_node("Info/Title").text=str(task.title)+" · "+str(STATUS_NAMES.get(phase,phase))
		body.get_node("Info/Effect").text=str(task.effect)
		var bar:ProgressBar=body.get_node("Info/Progress");bar.max_value=maxi(1,int(task.duration));bar.value=int(task.progress);bar.visible=phase=="working"
		var action:Button=body.get_node("Actions/Act");action.text="接取" if phase=="offered" else "交互中" if phase=="working" else "开始交互"
		action.disabled=phase not in ["offered","accepted"]
		body.get_node("Actions/Abandon").visible=phase in ["accepted","working"]
	board.get_node("Toggle").text="接管，关闭自动" if ai.get("enabled",false) else "启动自动打捞"
	board.get_node("Reason").text=str(ai.get("reason","等待启动"))+"\n"+str(ai.get("boss_assessment",""))
func _task(id:String)->Dictionary:
	for task in state().get("tasks",[]):
		if str(task.id)==id:return task
	return {}
func _locate(id:String)->void:
	var task:Dictionary=_task(id)
	if task.is_empty():return
	app.close_modal();var point:=Vector2(float(task.x),float(task.y));app.sea.pan+=app.sea.size*.5-app.sea.project(point)+app.sea.combat_offset;app.sea.queue_redraw()
func _act(id:String)->void:
	var task:Dictionary=_task(id)
	if task.is_empty():return
	var command:Dictionary={"op":"expedition_task","task":id,"action":"accept"} if str(task.status)=="offered" else {"op":"expedition_interact","task":id}
	var response:Dictionary=app.issue(command)
	if response.get("ok",false) and command.op=="expedition_interact":app.close_modal();app.running=true
