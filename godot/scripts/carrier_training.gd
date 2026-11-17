extends Control
## Optional practice: accepted player gestures plus observed authority, never a Next button.
var hud
var step:int=0
var accepted_command:Dictionary={}
var first:String=""
var second:String=""
var first_carrier:int=0
var second_carrier:int=0
var previous_goal:Vector2
var initial_max_id:int=0
var launch_floor:int=0
var finished:bool=false
var panel:PanelContainer
var text:Label
const TITLES:Array[String]=["第一波警戒","另一艘母舰并行","安排下一波","替换待命目标","在空编队改令","整联队真实召回","整备后的第二波","观察多航母托管"]
const HELP:Array[String]=["底栏可横拖找卡。拖第一艘战斗机中队卡离开底栏、移到光圈，等实际盘旋。","拖另一艘的战斗机卡到海面，观察两艘甲板与真实在空飞机。","再次拖第一艘战斗机的中队卡：这次安排下一波，当前飞机继续盘旋。","把同一中队卡拖到新的光圈；待命只保留一个，且落点必须改变。","拖带‘在空’的战斗机卡到新光圈，改变当前这一波的盘旋空域。","把第一艘的航空联队卡拖回所属母舰，等飞机盘旋进场并逐架回收。","重新拖第一艘战斗机中队卡，等待整备、再次起飞并盘旋。","在菜单开启航空托管，再进各舰航空姿态，分别选‘均衡’把手动中队交回AI。"]
static func start(controller)->void:
	if controller.replay_mode or controller.app.core.view.get("result")!=null:controller._hint("回放或已结束的战斗只读；请用新航母练习进行实操");return
	if controller.has_meta("carrier_training"):controller.get_meta("carrier_training").queue_free()
	var node=load("res://scripts/carrier_training.gd").new();node.hud=controller;controller.ui.add_child(node);controller.set_meta("carrier_training",node)
	controller.interaction_event.connect(node._event);controller.app.close_modal();controller.app.running=false;node.observe(controller.app.core.view)
func _ready()->void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);mouse_filter=Control.MOUSE_FILTER_IGNORE;z_index=70
	panel=PanelContainer.new();panel.position=Vector2(38,120);panel.size=Vector2(600,150);panel.mouse_filter=Control.MOUSE_FILTER_IGNORE;add_child(panel)
	var style:=StyleBoxFlat.new();style.bg_color=Color(.04,.13,.18,.95);style.border_color=Color("efd48c");style.set_border_width_all(2);style.set_corner_radius_all(10);style.content_margin_left=16;style.content_margin_right=16;style.content_margin_top=10;style.content_margin_bottom=10;panel.add_theme_stylebox_override("panel",style)
	var box:=VBoxContainer.new();panel.add_child(box);text=Label.new();text.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;text.custom_minimum_size.x=560;text.add_theme_font_size_override("font_size",20);text.add_theme_color_override("font_color",Color("fff4d2"));box.add_child(text)
	var close:=Button.new();close.text="收起教学，继续自由操作";close.custom_minimum_size.y=38;box.add_child(close);close.pressed.connect(func():hud.remove_meta("carrier_training");queue_free())
func _event(_kind:String,_data:Dictionary)->void:queue_redraw()
func accepted(q:Dictionary)->void:
	if finished:return
	var id:String=str(q.get("squadron_id",""));var regular:bool=str(q.get("op",""))=="littoral_air_order" and str(q.get("action",""))=="patrol"
	if step in [0,2,3,6] and regular and id==first:
		if step==3 and Vector2(float(q.x),float(q.y)).distance_to(previous_goal)<250:return
		accepted_command=q.duplicate(true)
	elif step==1 and regular and id==second:accepted_command=q.duplicate(true)
	elif step==4 and str(q.get("op",""))=="carrier_air_order" and str(q.get("scope",""))=="flight" and str(q.get("action",""))=="patrol" and id==first:accepted_command=q.duplicate(true)
	elif step==5 and str(q.get("scope",""))=="wing" and str(q.get("action",""))=="return" and int(q.get("carrier",0))==first_carrier:accepted_command=q.duplicate(true)
	if step in [0,1,6] and not accepted_command.is_empty():
		launch_floor=0
		for a:Dictionary in hud.app.core.view.littoral.aviation.aircraft:launch_floor=maxi(launch_floor,int(a.id))
	observe(hud.app.core.view)
func observe(view:Dictionary)->void:
	if not is_instance_valid(text):return
	var data:Dictionary=view.get("littoral",{});var ops:Dictionary=data.get("carrier_ops",{});var squads:Array=data.get("aviation",{}).get("squadrons",[])
	if first.is_empty():
		for s:Dictionary in squads:
			if str(s.role)!="fighter":continue
			if first.is_empty():first=str(s.id);first_carrier=int(s.carrier)
			elif int(s.carrier)!=first_carrier:second=str(s.id);second_carrier=int(s.carrier);break
	if first.is_empty() or second.is_empty():text.text="实操教学需要两艘实际配有战斗机的航母；可用独立航母练习入口。";return
	if finished:text.text="实操完成：双甲板、待命替换、在空改令、实际回收、第二波与交回AI。\n空中拦截、实战打击及原版CAS完整航空不在本次安全练习认证内。";queue_redraw();return
	var aircraft:Array=data.aviation.aircraft;var ready:bool=false
	if not accepted_command.is_empty():
		if step in [0,1,6]:
			var id:String=second if step==1 else first
			ready=aircraft.any(func(a):return str(a.squadron_id)==id and str(a.phase)=="patrolling" and int(a.id)>launch_floor)
		elif step in [2,3]:
			ready=ops.get("queue",[]).any(func(q):return str(q.squadron_id)==first and Vector2(float(q.x),float(q.y)).distance_to(Vector2(float(accepted_command.x),float(accepted_command.y)))<1)
		elif step==4:
			ready=ops.get("flights",[]).any(func(a):return str(a.squadron_id)==first and Vector2(float(a.target.x),float(a.target.y)).distance_to(Vector2(float(accepted_command.x),float(accepted_command.y)))<1)
		elif step==5:
			ready=not aircraft.any(func(a):return int(a.carrier)==first_carrier and str(a.side)=="allies") and squads.any(func(s):return str(s.id)==first and int(s.available)>0)
	if step==7:
		var manual:Array=ops.get("manual_squadrons",[])
		ready=bool(ops.get("ally_ai",false)) and [first_carrier,second_carrier].all(func(c):return squads.filter(func(s):return int(s.carrier)==c).all(func(s):return str(s.id) not in manual) and aircraft.any(func(a):return int(a.carrier)==c and str(a.side)=="allies"))
	if ready:
		if step in [2,3]:previous_goal=Vector2(float(accepted_command.x),float(accepted_command.y))
		if step==5:
			for a:Dictionary in aircraft:initial_max_id=maxi(initial_max_id,int(a.id))
		step+=1;accepted_command.clear();finished=step>=TITLES.size()
		if finished:observe(view);return
	text.text="航母实操 %d/%d · %s\n%s"%[step+1,TITLES.size(),TITLES[step],HELP[step]]
	if not accepted_command.is_empty():text.text+="\n已接令，等待真实飞行状态；可用右上加速。"
	queue_redraw()
func cue()->Dictionary:
	if finished or first.is_empty():return {}
	var carrier:int=second_carrier if step==1 else first_carrier;var p:Vector2=Vector2.ZERO
	for c:Dictionary in hud.app.core.view.get("ships",[]):
		if int(c.id)==carrier:p=Vector2(float(c.x),float(c.y));break
	var kind:String="wing" if step==5 else "flight" if step==4 else "squadron";var sid:String=second if step==1 else first
	var destination:Vector2=p if step==5 else p+Vector2(-1800-350*(step%3),-1200)
	return {"kind":kind,"squadron_id":sid,"carrier":carrier,"target":destination}
func _draw()->void:
	if hud==null or not is_instance_valid(hud.ui):return
	var info:Dictionary=cue()
	if info.is_empty() or step==7:return
	var target:Vector2=get_global_transform().affine_inverse()*(hud.app.sea.get_global_transform()*hud.app.sea.project(info.target))
	var source:Vector2=Vector2.ZERO;var card_found:bool=false
	for card in hud.ui.get_node("Tray/Scroll/Cards").get_children():
		var p:Dictionary=card.payload
		if str(p.kind)!=str(info.kind):continue
		if (p.kind=="wing" and int(p.carrier)==int(info.carrier)) or (p.kind!="wing" and str(p.get("squadron_id",""))==str(info.squadron_id)):
			var rect:Rect2=card.get_global_rect();var tray:Rect2=hud.ui.get_node("Tray").get_global_rect()
			if tray.encloses(rect):source=get_global_transform().affine_inverse()*rect.get_center();card_found=true;draw_rect(Rect2(get_global_transform().affine_inverse()*rect.position,rect.size),Color("f5dc99"),false,3);break
	draw_circle(target,27,Color("f5dc99"),false,3);draw_circle(target,7,Color("f5dc99"))
	if card_found:draw_dashed_line(source,target,Color(.97,.86,.60,.7),3,12)
