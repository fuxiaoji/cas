extends RefCounted
## Naval-only contextual desk; no account mutation, no land tutorial changes.
const VERSION:String="cas-carrier-ops-v2"
const GUIDE:Array[String]=[
"1 · 先认母舰\n每张中队卡显示所属母舰和机型。不同母舰各有甲板，同一母舰的战斗/轰炸/鱼雷中队共用串行甲板。可出击数、在空数、武器库存与损失分别计算。",
"2 · 拖动就是下令\n把战斗机卡拖到海面安排警戒，拖到敌机安排拦截；轰炸机卡拖到已发现敌舰或岛上落点打击；鱼雷机卡只拖到敌舰。松手前先看有效性提示，超程和非法目标不会扣飞机或弹药。",
"3 · 下一波与当前波次分开拖\n中队卡安排下一波，每队最多一个待命，新落点替换旧任务；甲板忙、飞机在空或未整备时等待。‘在空’卡改变当前任务，不能增加飞机/燃油/武器；起飞未完、正在返航、武器耗尽或返程燃油不足时拒绝改令。",
"4 · 两艘航母怎么分工\n先让一艘战斗机警戒，再拖另一艘轰炸机打击。两条甲板可并行，同舰逐架起飞。不要所有飞机同时出击；留战斗机、返航空间和第二波武器。托管轮换中队，每方航空托管最多12架，双方活动总数最多24。",
"5 · 看真实飞行\n起飞 → 出航 → 打击或盘旋警戒 → 返航 → 依次着舰 → 整备。新版飞机离开甲板后持续飞行，不能停在航点。警戒绕指定点盘旋，忙甲板前在母舰附近盘旋等待；这些运动实际耗油。警戒3000米内寻找敌机；召回不瞬移或补血。",
"6 · 拖回母舰召回\n中队卡拖回所属母舰取消本队待命并召回；航空联队卡拖回母舰则召回这艘母舰的全部中队。点联队卡可筛选该舰，再点恢复全部。返航追随真实母舰，甲板忙时持续盘旋；撤离前必须等在空数归零。",
"7 · 托管与接管\n开启航空托管后手动拖过的中队仍由玩家负责；在‘各舰航空姿态’选择均衡/防空/打击/停止派遣，会把该舰中队交回AI。关闭托管停止新安排，已有在空飞机继续任务。邻近航母共享警戒，各舰有出击份额，返航回收优先。",
"8 · 实操检验\n完成一次警戒、两舰并行出击、忙甲板排队、重新拖卡更换落点、主动召回、着舰整备后第二波。观察可出击+在空+损失=该中队原始总数；武器不能凭等待恢复。阅读本页不算通过实战训练。",
"9 · 原书与当前玩法\n当前是独立近场航空：3架小中队、2秒起飞、3秒着舰、20秒整备。原规则直甲板起飞3架/分钟、着舰1架/45秒，并有风、高度、挂载和事故要求。新录舰机图鉴保留原数值，source_only条目尚未开放战斗，不能冒称完整CAS航空。"
]

static func install(hud)->void:
	var button:=Button.new();button.name="CarrierCommandDesk";button.text="航母指挥 / 教学"
	hud.ui.add_child(button);button.anchor_left=.755;button.anchor_right=.975;button.anchor_top=.32;button.anchor_bottom=.32;button.offset_bottom=48;button.z_index=24
	button.pressed.connect(func():open(hud));button.add_theme_font_size_override("font_size",18)

static func open(hud)->void:
	if str(hud.app.core.view.get("littoral",{}).get("carrier_ops",{}).get("version",""))==VERSION:legacy_open(hud);return
	load("res://scripts/carrier_automation_desk.gd").open(hud)

static func legacy_open(hud)->void:
	var app=hud.app;var layer:Control=app.open_modal("航母指挥 · 拖动编排波次")
	layer.z_index=100
	var current:Dictionary=app.core.view.get("littoral",{}).get("carrier_ops",{})
	app.label(layer,"各舰独立甲板 · 同舰串行起降 · 返航优先",420,230,760,45,23)
	app.button(layer,"开启新版手动指挥 / 待命队列",420,300,760,56,func():app.close_modal();app.issue({"op":"carrier_ops","version":VERSION,"ally_ai":false}))
	app.button(layer,"关闭航空托管" if bool(current.get("ally_ai",false)) else "开启多航母航空托管",420,370,760,56,func():app.close_modal();app.issue({"op":"carrier_ops","version":VERSION,"ally_ai":not bool(current.get("ally_ai",false))}))
	app.button(layer,"详细教学 · 九个操作环节",420,440,760,56,func():lesson(hud,0))
	app.button(layer,"太平洋新增舰机 · 原书资料图鉴",420,510,760,56,func():catalogue(hud))
	if str(current.get("version",""))==VERSION:
		app.button(layer,"跟随实际操作的航母教学",420,578,365,56,func():load("res://scripts/carrier_training.gd").start(hud))
		app.button(layer,"各舰航空姿态 / 调度",815,578,365,56,func():load("res://scripts/carrier_air_desk.gd").dashboard(hud))
	else:app.label(layer,"新版需独立航母核心；旧核心拒绝启用时不改变原航次。",420,585,760,55,18)
	app.button(layer,"返回海图",420,665,760,56,app.close_modal)
	if hud.replay_mode or app.core.view.get("result")!=null:
		for b in layer.find_children("*","Button",true,false):
			if b.text in ["开启新版手动指挥 / 待命队列","开启多航母航空托管","关闭航空托管","跟随实际操作的航母教学","各舰航空姿态 / 调度"]:b.disabled=true

static func lesson(hud,index:int)->void:
	var app=hud.app;app.close_modal();var layer:Control=app.open_modal("航母使用教学 · %d / %d"%[index+1,GUIDE.size()]);layer.z_index=100
	app.label(layer,GUIDE[index],420,250,760,320,24)
	if index>0:app.button(layer,"上一环节",420,610,230,58,func():lesson(hud,index-1))
	if index+1<GUIDE.size():app.button(layer,"下一环节",685,610,230,58,func():lesson(hud,index+1))
	app.button(layer,"回海图实操",950,610,230,58,app.close_modal)

static func catalogue(hud)->void:
	var app=hud.app;app.close_modal();var layer:Control=app.open_modal("太平洋舰机资料 · 原页核对录入");layer.z_index=100
	var path:String="res://data/carrier-pacific-source-v1.json"
	if not FileAccess.file_exists(path):return
	var data:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(path));var rows:Array=data.get("ships",[])+data.get("aircraft",[])
	var scroll:=ScrollContainer.new();scroll.position=Vector2(420,235);scroll.size=Vector2(760,405);layer.add_child(scroll)
	var list:=VBoxContainer.new();list.custom_minimum_size.x=730;scroll.add_child(list)
	for row:Dictionary in rows:
		var label:=Button.new();label.alignment=HORIZONTAL_ALIGNMENT_LEFT;label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;label.custom_minimum_size=Vector2(720,75);label.add_theme_font_size_override("font_size",18)
		var source:Dictionary=row.get("source",{});var values:String=("DP %s · %s节"%[row.get("dp",0),row.get("max_knots",0)]) if row.has("dp") else ("DV %s · 巡航总航程%s海里"%[row.get("damage_value",0),row.get("cruise_range_nm",0)])
		label.text="%s · %s\n%s PDF%s / %s · 资料录入，未开放出战"%[row.name,values,source.get("book",""),source.get("pdf_page",0),source.get("printed_page","")];list.add_child(label)
		label.pressed.connect(func():character(hud,str(row.id)))
	app.button(layer,"返回海图",420,670,760,56,app.close_modal)

static func character(hud,id:String)->void:
	var app=hud.app;var path:String="res://data/carrier-art-v1.json"
	if not FileAccess.file_exists(path):return
	var manifest:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(path));var found:Dictionary={}
	for row:Dictionary in manifest.get("characters",[]):
		if str(row.id)==id:found=row;break
	if found.is_empty():return
	app.close_modal();var layer:Control=app.open_modal(str(found.name)+" · 本人立绘与两头身小人");layer.z_index=100
	var portrait:=TextureRect.new();portrait.position=Vector2(400,210);portrait.size=Vector2(430,460);portrait.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;portrait.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED;portrait.texture=load(str(found.portrait));layer.add_child(portrait)
	if found.has("chibi"):
		var chibi:=TextureRect.new();chibi.position=Vector2(890,250);chibi.size=Vector2(220,250);chibi.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;chibi.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED;chibi.texture=load(str(found.chibi));layer.add_child(chibi)
	app.label(layer,"资料收录 · 未开放出战\n"+str(found.get("costume","原创舰娘")),850,510,320,90,20)
	app.button(layer,"返回图鉴",850,635,320,55,func():catalogue(hud))
