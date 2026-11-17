extends RefCounted
## The three drag verbs stay separate: next flight, airborne retask, whole-wing recall.
const VERSION:String="cas-carrier-ops-v2"
const Simple=preload("res://scripts/carrier_automation_desk.gd")
static func active(hud)->bool:return str(hud.app.core.view.get("littoral",{}).get("carrier_ops",{}).get("version","")) in [VERSION,Simple.VERSION]
static func signature(hud)->Array:
	var data:Dictionary=hud.app.core.view.get("littoral",{})
	return [data.get("carrier_ops",{}).get("version",""),Simple.level(hud),int(hud.get_meta("carrier_filter",0)),data.get("aviation",{}).get("squadrons",[]).map(func(s):return [s.id,int(s.get("airborne",0))>0])]
static func cards(hud,row:HBoxContainer)->void:
	if Simple.active(hud) and Simple.level(hud)!="low":Simple.cards(hud,row);return
	var data:Dictionary=hud.app.core.view.littoral;var selected:int=int(hud.get_meta("carrier_filter",0))
	for deck:Dictionary in data.carrier_ops.get("decks",[]):
		var identity:String=""
		for s:Dictionary in data.aviation.squadrons:
			if int(s.carrier)==int(deck.carrier):identity=str(s.carrier_identity);break
		var ship_card:Dictionary=hud.app.cards.get(identity,{})
		hud._add_card({"kind":"wing","unit_id":"wing-%s"%deck.carrier,"carrier":int(deck.carrier),"name":str(deck.name)+" · 航空联队","selected":selected==int(deck.carrier),"texture":hud._portrait(identity,ship_card)},row)
	for s:Dictionary in data.aviation.squadrons:
		if selected!=0 and int(s.carrier)!=selected:continue
		var identity:String=str(s.carrier_identity);var texture:Texture2D=hud._portrait(identity,hud.app.cards.get(identity,{}))
		var caption:String=hud._carrier_caption(s)+" · "+hud.AircraftArt.display_name(str(s.visual_type))
		hud._add_card({"kind":"squadron","unit_id":str(s.id),"squadron_id":str(s.id),"air_role":str(s.role),"name":caption,"texture":texture},row)
		if int(s.airborne)>0:hud._add_card({"kind":"flight","unit_id":"flight-"+str(s.id),"squadron_id":str(s.id),"carrier":int(s.carrier),"air_role":str(s.role),"name":"在空 · "+caption,"texture":texture},row)
	for card in row.get_children():
		if str(card.payload.get("kind","")) not in ["wing","flight","squadron"]:continue
		card.custom_minimum_size=Vector2(220,140);card.portrait.custom_minimum_size.y=46
		card.title_label.custom_minimum_size.x=200;card.title_label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;card.title_label.max_lines_visible=2;card.title_label.add_theme_font_size_override("font_size",17)
		card.status.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;card.status.max_lines_visible=2;card.status.add_theme_font_size_override("font_size",14)
static func status(hud,p:Dictionary)->Dictionary:
	if str(p.kind)=="aviation_support":return Simple.status(hud,p)
	var data:Dictionary=hud.app.core.view.littoral
	if p.kind=="wing":
		for deck:Dictionary in data.carrier_ops.get("decks",[]):
			if int(deck.carrier)!=int(p.carrier):continue
			var text:String="点卡筛选 · 拖回母舰全召回"
			if int(deck.recovering)>0:text="回收优先 %d架 · 在空%d"%[int(deck.recovering),int(deck.airborne)]
			elif float(deck.busy_in)>0:text="甲板 %.1f秒 · 在空%d"%[float(deck.busy_in),int(deck.airborne)]
			return {"text":text,"allowed":bool(deck.alive)}
	if p.kind=="flight":
		var planes:Array=data.aviation.aircraft.filter(func(a):return str(a.squadron_id)==str(p.squadron_id) and str(a.side)=="allies")
		var names:Dictionary={"launching":"起飞中","outbound":"飞向目标","patrolling":"警戒中","returning":"返航中"};var phases:Array=[];var fuel:float=INF
		for a:Dictionary in planes:
			var phase:String=str(names.get(str(a.phase),str(a.phase)))
			if phase not in phases:phases.append(phase)
			fuel=minf(fuel,float(a.fuel_remaining))
		return {"text":"%s · 余航%.1f公里"%["/".join(phases),fuel/1000.] if not planes.is_empty() else "已回收","allowed":not planes.is_empty()}
	for q:Dictionary in data.carrier_ops.get("queue",[]):
		if str(q.squadron_id)==str(p.get("squadron_id","")):return {"text":str(q.wait_reason)+" · 下一波待命","allowed":true}
	var notices:Array=data.carrier_ops.get("rejected",[]).duplicate();notices.reverse()
	for notice:Dictionary in notices:
		if str(notice.squadron_id)==str(p.get("squadron_id","")):return {"text":"待命取消："+str(notice.reason),"allowed":true}
	if p.kind=="squadron":
		for s:Dictionary in data.aviation.squadrons:
			if str(s.id)!=str(p.squadron_id):continue
			if int(s.lost)==int(s.total):return {"text":"全队飞机已损失","allowed":false}
			if int(s.available)==0 and int(s.airborne)>0:return {"text":"在空%d · 拖此卡排下一波"%int(s.airborne),"allowed":true}
			if float(s.ready_in)>0:return {"text":"整备 %.1f秒 · 可排队"%float(s.ready_in),"allowed":true}
			return {"text":"可用%d · 武器%d · 拖动出击"%[int(s.available),int(s.ammunition)],"allowed":int(s.ammunition)>0 or int(s.airborne)>0}
	return {}
static func request(hud,p:Dictionary,location:Dictionary,preview:bool)->Dictionary:
	if str(p.kind)=="aviation_support":return Simple.request(hud,p,location,preview)
	var point:Vector2=location.world;var hit:Dictionary=location.get("hit",{})
	if str(hit.get("kind",""))=="aircraft" and str(hit.get("row",{}).get("side",""))=="allies":hit={}
	var q:Dictionary={"op":"carrier_preview" if preview else "carrier_air_order","scope":"wing" if p.kind=="wing" else "flight","squadron_id":str(p.get("squadron_id","")),"carrier":int(p.get("carrier",0)),"action":"strike","x":point.x,"y":point.y,"target_kind":"land"}
	if hit.is_empty() and not hud._island_contains(point):q.action="patrol"
	for ship:Dictionary in hud.app.core.view.get("ships",[]):
		if int(ship.id)==int(p.get("carrier",-1)) and point.distance_to(Vector2(float(ship.x),float(ship.y)))<=600:q.action="return";break
	if str(hit.get("kind","")) in ["ship","aircraft"]:q.target_kind=str(hit.kind);q["target_id"]=int(hit.id) if str(hit.kind)=="aircraft" else str(hit.id)
	return q
static func clicked(hud,p:Dictionary)->bool:
	if not active(hud):return false
	if str(p.kind)=="aviation_support":Simple.clicked(hud,p);return true
	if p.kind=="wing":
		var same:bool=int(hud.get_meta("carrier_filter",0))==int(p.carrier);hud.set_meta("carrier_filter",0 if same else int(p.carrier));hud.roster_signature="";hud.update()
		hud._hint("已显示所有母舰" if same else "只显示这艘母舰的中队 · 再点联队卡恢复全部；拖回母舰可全联队召回");return true
	if p.kind=="flight":
		var layer:Control=hud.app.open_modal("在空编队 · 拖动即时改令");layer.z_index=100
		hud.app.label(layer,"拖到海面：战斗机改警戒点\n拖到敌机/敌舰：兼容机型改目标\n拖回所属母舰：真实返航\n\n不增加飞机/武器，不重置燃油；返航中不能重新出击。\n地面中队卡安排下一波；在空卡只改变这一波。",420,235,760,330,23)
		hud.app.button(layer,"回到海图拖动",420,625,760,60,hud.app.close_modal);return true
	return false
static func dashboard(hud)->void:
	var app=hud.app;app.close_modal();var layer:Control=app.open_modal("多航母航空调度");layer.z_index=100
	var scroll:=ScrollContainer.new();scroll.position=Vector2(420,220);scroll.size=Vector2(760,400);layer.add_child(scroll)
	var list:=VBoxContainer.new();list.custom_minimum_size.x=730;list.add_theme_constant_override("separation",12);scroll.add_child(list)
	for deck:Dictionary in app.core.view.littoral.carrier_ops.get("decks",[]):
		var label:=Label.new();label.text="%s · 在空%d · 甲板%.1f秒 · 近舰返航%d"%[deck.name,int(deck.airborne),float(deck.busy_in),int(deck.recovering)];label.add_theme_font_size_override("font_size",21);list.add_child(label)
		var line:=HBoxContainer.new();list.add_child(line)
		for policy:String in ["balanced","defend","strike","hold"]:
			var b:=Button.new();b.text=str({"balanced":"均衡","defend":"防空","strike":"打击","hold":"停止派遣"}[policy]);b.custom_minimum_size=Vector2(140,48);line.add_child(b);b.toggle_mode=true;b.button_pressed=str(deck.policy)==policy
			b.pressed.connect(func():app.issue({"op":"carrier_policy","carrier":int(deck.carrier),"policy":policy,"release_manual":true});dashboard(hud))
			b.disabled=hud.replay_mode or app.core.view.get("result")!=null
	var label:=Label.new();label.text="姿态按钮把该舰手动中队交回托管；已在空任务继续。";label.add_theme_font_size_override("font_size",18);list.add_child(label)
	app.button(layer,"回海图 · 拖动联队卡/中队卡/在空卡",420,650,760,60,app.close_modal)
static func squadron_menu(hud,id:String)->void:
	var app=hud.app;var data:Dictionary=app.core.view.littoral;var s:Dictionary={}
	for row:Dictionary in data.aviation.squadrons:
		if str(row.id)==id:s=row;break
	if s.is_empty():return
	var queued:bool=data.carrier_ops.get("queue",[]).any(func(q):return str(q.squadron_id)==id)
	var layer:Control=app.open_modal(hud._carrier_caption(s)+" · "+hud.AircraftArt.display_name(str(s.visual_type)));layer.z_index=100
	app.label(layer,"可用 %d · 在空 %d · 损失 %d / 原始%d\n航空武器 %d · 整备剩余 %.1f秒"%[int(s.available),int(s.airborne),int(s.lost),int(s.total),int(s.ammunition),float(s.ready_in)],420,235,760,95,24)
	var hand_back:String="想交回自动安排，点击右侧航母选择高档或中档。" if Simple.active(hud) else "手动接管后，在各舰姿态面板交回托管。"
	app.label(layer,"拖中队卡安排下一波；拖‘在空’卡改当前航线。\n警戒与等待着舰都持续盘旋并消耗燃油。\n"+hand_back,420,340,760,125,22)
	app.button(layer,"取消下一波待命 · 在空任务继续",420,490,760,55,func():app.close_modal();app.issue({"op":"carrier_air_order","scope":"cancel","squadron_id":id})).disabled=not queued or hud.replay_mode
	app.button(layer,"召回本队并取消待命",420,560,760,55,func():app.close_modal();app.issue({"op":"littoral_air_order","squadron_id":id,"action":"return","queue":true})).disabled=(int(s.airborne)==0 and not queued) or hud.replay_mode
	app.button(layer,"返回海图拖动",420,640,760,55,app.close_modal)
