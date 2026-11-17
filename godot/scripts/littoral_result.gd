@tool
extends Control
const Design=preload("res://scripts/ui_design.gd")
const Service=preload("res://scripts/home_service.gd")
@export var use_default_styles:bool=true
var app
var receipt:Dictionary={}
var return_action:Callable
func _ready()->void:
	if use_default_styles:theme=Design.theme()
	if use_default_styles:Design.apply_button($Layout/Return,true)
func bind(owner,value:Dictionary,back:Callable=Callable())->void:
	app=owner;receipt=value;return_action=back
	var success:bool=bool(receipt.get("success",false))
	$Layout/Title.text=str(receipt.get("title","海陆行动结束"))
	$Layout/Subtitle.text="任务已完成 · 返航与损耗记录已保存" if success else "行动结束 · 保存真实损耗，核心仍在"
	var v4:bool=str(receipt.get("request",{}).get("version","")) in ["cas-island-war-v4","cas-island-war-coastal-v1"]
	var v3:bool=str(receipt.get("request",{}).get("version","")) in ["cas-island-war-v3","cas-island-war-v4","cas-island-war-coastal-v1"]
	var vehicles:Array=receipt.get("vehicles",[]) if v3 else []
	var missing_vehicles:int=vehicles.filter(func(row):return bool(row.get("lost",false)) or not bool(row.get("recovered",false))).size()
	if missing_vehicles>0:$Layout/Subtitle.text+=" · %d辆/架作战载具未回收"%missing_vehicles
	$Layout/Ammo.text="弹药装载 %d  ·  返库 %d  ·  消耗或损失 %d"%[int(receipt.get("ammo_loaded",0)),int(receipt.get("ammo_returned",0)),maxi(0,int(receipt.get("ammo_loaded",0))-int(receipt.get("ammo_returned",0)))]
	var rewards:Array[String]=[]
	for key in receipt.get("rewards",{}):
		if int(receipt.rewards[key])>0:rewards.append("%s +%d"%[str(Service.RESOURCE_NAMES.get(key,key)),int(receipt.rewards[key])])
	for key in receipt.get("home_losses",{}):
		if int(receipt.home_losses[key])>0:rewards.append("%s −%d"%[str(Service.RESOURCE_NAMES.get(key,key)),int(receipt.home_losses[key])])
	$Layout/Resources.text="   ·   ".join(rewards) if not rewards.is_empty() else "本次没有新增岛屿资源"
	var list:VBoxContainer=$Layout/Scroll/Rows
	for child in list.get_children():list.remove_child(child);child.queue_free()
	for row in receipt.get("ships",[]):
		var identity:String=str(row.get("id",""));var card:Dictionary=app.cards.get(identity,{})
		_entry(list,str(card.get("name",identity)),"舰体 %.1f%% · %s"%[float(row.get("hp_percent",0)),"已回收" if bool(row.get("recovered",false)) else "沉没" if bool(row.get("sunk",false)) else "未返航"],str(card.get("portrait","")),float(row.get("hp_percent",0)))
	for row in receipt.get("units",[]):
		var id:String=str(row.get("id",""));var card:Dictionary=app.home.unit(id) if app.get("home")!=null else {}
		var v2:bool=str(receipt.get("request",{}).get("version","")) in ["cas-island-war-v2","cas-island-war-v3","cas-island-war-v4","cas-island-war-coastal-v1"]
		if v4 and app.home.has_method("v4_unit"):card=app.home.v4_unit(id)
		elif v3 and app.home.has_method("v3_unit"):card=app.home.v3_unit(id)
		elif v2 and app.home.has_method("v2_unit"):card=app.home.v2_unit(id)
		var status:String="核心保存 · 缓慢重建" if bool(row.get("incapacitated",false)) or bool(row.get("missing",false)) else "编制回收"
		var recovered_health:float=float(row.get("recovered_hp_percent",row.get("hp_percent",0))) if v2 else float(row.get("hp_percent",0))
		if v2 and bool(row.get("partial_missing",false)):status="部分连队未返舰 · 损失已计入整备"
		var detail:String="身体整备 %.1f%% · %s"%[recovered_health,status] if v3 else "整备 %.1f%% · %s"%[recovered_health,status]
		var own_vehicles:Array=vehicles.filter(func(vehicle):return str(vehicle.get("unit_id",""))==id)
		if not own_vehicles.is_empty():
			var recovered_count:int=own_vehicles.filter(func(vehicle):return bool(vehicle.get("recovered",false)) and not bool(vehicle.get("lost",false))).size()
			detail+="\n作战载具 %d/%d归队 · 车损请到本人档案维修"%[recovered_count,own_vehicles.size()]
		_entry(list,str(card.get("name",id)),detail,str(card.get("portrait","")),recovered_health)
		if not success and (bool(row.get("missing",false)) or bool(row.get("incapacitated",false)) or recovered_health<35) and ResourceLoader.exists("res://assets/tactical/defeat-cg-v1/"+id+".png"):
			var image_button:=Button.new();image_button.name="DefeatCG_"+id;image_button.text="查看 "+str(card.get("name",id))+" 的抢滩失利 CG";image_button.custom_minimum_size.y=52;Design.apply_button(image_button);image_button.pressed.connect(func():load("res://scripts/home_cg_gallery.gd").open(app,id));list.add_child(image_button)
	var tutorial:bool=success and str(receipt.get("request",{}).get("mode",""))=="tutorial"
	var canon_pending:Dictionary=app.economy.state.get("progression",{}).get("story_canon_v2",{}).get("pending",{})
	var canon_return:bool=not canon_pending.is_empty() and str(canon_pending.get("run_id",""))==str(receipt.get("run_id",""))
	$Layout/Return.text="继续 · 第五小队航海日志" if canon_return else "继续 · 岛屿的第一盏灯" if tutorial else "返回返航灯岛"
	$Layout/Return.pressed.connect(func():
		if canon_return:app.show_page("canon_story")
		elif tutorial:app.show_page("home_story")
		elif return_action.is_valid():return_action.call()
		else:app.show_page("home"))
func _entry(parent:Node,title:String,detail:String,portrait:String,health:float)->void:
	var row:=HBoxContainer.new();row.add_theme_constant_override("separation",18);row.custom_minimum_size.y=110;parent.add_child(row)
	var art:=TextureRect.new();art.custom_minimum_size=Vector2(90,110);art.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;art.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED;art.texture=load(portrait) if ResourceLoader.exists(portrait) else null;row.add_child(art)
	var text:=VBoxContainer.new();text.size_flags_horizontal=Control.SIZE_EXPAND_FILL;row.add_child(text)
	var heading:=Label.new();heading.text=title;heading.add_theme_font_size_override("font_size",25);text.add_child(heading)
	var line:=Label.new();line.text=detail;line.add_theme_font_size_override("font_size",19);line.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;text.add_child(line)
	var bar:=ProgressBar.new();bar.custom_minimum_size.y=7;bar.show_percentage=false;bar.value=health;text.add_child(bar)
