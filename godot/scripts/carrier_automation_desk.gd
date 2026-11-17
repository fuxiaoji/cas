extends RefCounted
## The ordinary aviation surface: one choice and one support card per mother.
const VERSION:String="cas-carrier-ops-v3"
const LEVELS:Array[String]=["high","medium","low"]
const NAMES:Dictionary={"high":"高自动化","medium":"中自动化","low":"低自动化"}
const HELP:Dictionary={"high":"航母自动选择目标、安排防空与对陆支援。你只需继续战斗。","medium":"你指定目标，航母选机并安排起飞、打击和返航。拖下方航空支援卡到敌舰、陆上敌人或海面。","low":"你调度具体编队。拖中队卡排下一波，拖在空卡改令；拖回所属母舰召回。"}
static func active(hud)->bool:return str(hud.app.core.view.get("littoral",{}).get("carrier_ops",{}).get("version",""))==VERSION
static func state(hud)->Dictionary:return hud.app.core.view.get("littoral",{}).get("carrier_ops",{}).get("automation",{})
static func level(hud)->String:return str(state(hud).get("level","high"))
static func choose(hud,value:String)->void:
	hud.app.close_modal();hud.app.issue({"op":"carrier_automation","version":VERSION,"level":value});hud.roster_signature="";hud.update()
	hud._hint(str(HELP[value]))
static func open(hud)->void:
	var app=hud.app;var layer:Control=app.open_modal("航母 · 选择你想负责多少");layer.z_index=100
	var current:String=level(hud) if active(hud) else ""
	for i:int in range(3):
		var value:String=LEVELS[i];var y:float=235+i*112
		var b:Button=app.button(layer,("✓ " if current==value else "")+str(NAMES[value])+" · "+str({"high":"航母全权安排","medium":"我只指定目标","low":"我调度具体编队"}[value]),420,y,760,54,func():choose(hud,value));b.name="CarrierLevel_"+value;b.disabled=hud.replay_mode or app.core.view.get("result")!=null
		app.label(layer,str(HELP[value]),420,y+58,760,50,18)
	app.button(layer,"海陆航空支援 · 看一页就会",420,583,365,52,func():help(hud))
	app.button(layer,"原书资料 / 舰娘图鉴",815,583,365,52,func():load("res://scripts/carrier_command_desk.gd").catalogue(hud))
	app.button(layer,"返回战斗",420,665,760,52,app.close_modal)
static func help(hud)->void:
	var app=hud.app;app.close_modal();var layer:Control=app.open_modal("航母 · 海陆通用的一张支援卡");layer.z_index=100
	app.label(layer,"① 选高档：继续模拟，航母自动安排防空、海上打击和对陆支援。\n\n② 选中档：把‘企业/翔鹤 · 航空支援’拖到敌舰、岛上敌人或海面。陆图与海图完全同用；海面是盘旋防空。拖回本舰召回，召回后不自行重新起飞。\n\n③ 想指定机型和波次再选低档。所有档位都真实飞行、盘旋耗油、有限武器，着舰整备后才能再次出击。",420,225,760,310,22)
	app.label(layer,"看卡牌了解任务与等待原因。中档空白区域不会盲目投弹；友军过近会等待。切换档位不补充任何飞机、燃油或武器。",420,545,760,70,20)
	app.button(layer,"返回战斗",420,665,365,52,app.close_modal)
	app.button(layer,"切低档 · 调度具体编队",815,665,365,52,func():choose(hud,"low")).disabled=hud.replay_mode or not active(hud) or app.core.view.get("result")!=null
static func cards(hud,row:HBoxContainer)->void:
	var data:Dictionary=hud.app.core.view.littoral
	for deck:Dictionary in data.carrier_ops.get("decks",[]):
		var identity:String=""
		for s:Dictionary in data.aviation.squadrons:
			if int(s.carrier)==int(deck.carrier):identity=str(s.carrier_identity);break
		hud._add_card({"kind":"aviation_support","unit_id":"aviation-%s"%deck.carrier,"carrier":int(deck.carrier),"name":str(deck.name)+" · 航空支援","texture":hud._portrait(identity,hud.app.cards.get(identity,{}))},row)
	for c in row.get_children():
		if str(c.payload.kind)!="aviation_support":continue
		c.custom_minimum_size=Vector2(250,140);c.portrait.custom_minimum_size.y=46;c.title_label.add_theme_font_size_override("font_size",18);c.status.add_theme_font_size_override("font_size",16);c.status.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;c.status.max_lines_visible=2
static func status(hud,p:Dictionary)->Dictionary:
	var text:String="自动安排中" if level(hud)=="high" else "拖到目标 · 航母选机"
	for row:Dictionary in state(hud).get("carriers",[]):
		if int(row.carrier)==int(p.carrier):text=str(row.status);break
	for deck:Dictionary in hud.app.core.view.littoral.carrier_ops.get("decks",[]):
		if int(deck.carrier)==int(p.carrier):return {"text":text,"allowed":bool(deck.alive)}
	return {"text":"母舰已损失","allowed":false}
static func request(hud,p:Dictionary,location:Dictionary,preview:bool)->Dictionary:
	var point:Vector2=location.world;var hit:Dictionary=location.get("hit",{})
	var q:Dictionary={"op":"carrier_mission_preview" if preview else "carrier_mission","carrier":int(p.carrier),"action":"strike","target_kind":"land","x":point.x,"y":point.y}
	for ship:Dictionary in hud.app.core.view.get("ships",[]):
		if int(ship.id)==int(p.carrier) and point.distance_to(Vector2(float(ship.x),float(ship.y)))<=600:q.action="return";return q
	if str(hit.get("row",{}).get("side",""))=="allies":hit={}
	if str(hit.get("kind","")) in ["ship","aircraft"]:q.target_kind=str(hit.kind);q["target_id"]=int(hit.id) if str(hit.kind)=="aircraft" else str(hit.id)
	elif not hud._island_contains(point):q.action="patrol"
	return q
static func clicked(hud,p:Dictionary)->void:
	var app=hud.app;var layer:Control=app.open_modal(str(p.name));layer.z_index=100
	app.label(layer,str(NAMES[level(hud)])+"\n"+str(status(hud,p).text)+"\n\n拖此卡到目标：自动选择兼容飞机。\n在陆图拖到实际敌人：对陆航空支援。\n拖回所属母舰：全联队返航并停止新派遣。",420,235,760,280,23)
	app.button(layer,"召回本舰飞机并停止派遣",420,540,760,55,func():app.close_modal();app.issue({"op":"carrier_mission","carrier":int(p.carrier),"action":"return"})).disabled=hud.replay_mode or app.core.view.get("result")!=null
	app.button(layer,"返回战斗拖动",420,650,760,55,app.close_modal)
static func update(hud)->void:
	var b:Button=hud.ui.get_node_or_null("CarrierCommandDesk")
	if b==null:return
	if active(hud):
		b.text="航母 · "+str(NAMES[level(hud)]);b.tooltip_text=str(HELP[level(hud)])
		var swap:Button=hud.ui.get_node_or_null("CarrierMapSwitch")
		if swap==null:
			swap=Button.new();swap.name="CarrierMapSwitch";hud.ui.add_child(swap);swap.anchor_left=.755;swap.anchor_right=.975;swap.anchor_top=.115;swap.anchor_bottom=.16;swap.z_index=40;swap.add_theme_font_size_override("font_size",18)
			swap.pressed.connect(func():hud.set_primary_map("land" if hud.primary_map=="sea" else "sea"))
		swap.text="切到陆图 · 航空支援" if hud.primary_map=="sea" else "切到海图 · 航空支援"
