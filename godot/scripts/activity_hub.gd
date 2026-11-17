@tool
extends Control
const Design=preload("res://scripts/ui_design.gd")
const Supply=preload("res://scripts/supply_presentation.gd")
@export_enum("本期活动","更新公告","战役进度","本期UP","回港补给") var preview_tab:int=0:
	set(value):
		preview_tab=value
		if is_node_ready() and Engine.is_editor_hint():_preview()
@export_file("*.json") var content_path:String="res://data/liveops.json"
@export var content:Resource=preload("res://data/liveops.tres")
var app
var data:Dictionary={}
const KEYS=["overview","updates","campaigns","featured","supply"]
func _ready() -> void:
	theme=Design.theme()
	data=content.to_dictionary() if content!=null else JSON.parse_string(FileAccess.get_file_as_string(content_path))
	var path:String=str(data.get("hero",""))
	if not ResourceLoader.exists(path):path="res://assets/story/chapter1/gate.png"
	$Hero.texture=load(path)
	$HeroTitle.text=str(data.get("title","潮线档案"))
	$HeroSubtitle.text=str(data.get("subtitle",""))
	call_deferred("_preview")
func _clear_content() -> void:
	$Editorial.hide()
	for parent in [$Side,$Wide]:
		for child in parent.get_children():parent.remove_child(child);child.queue_free()
func _preview() -> void:
	if app!=null:return
	_clear_content()
	if content!=null:data=content.to_dictionary()
	var hero_path:String=str(data.get("hero",""))
	if ResourceLoader.exists(hero_path):$Hero.texture=load(hero_path)
	$HeroTitle.text=str(data.get("title","潮线档案"))
	$HeroSubtitle.text=str(data.get("subtitle",""))
	var wide:bool=preview_tab in [2,4]
	for key in ["Hero","HeroShade","HeroTitle","HeroSubtitle","Side"]:get_node(key).visible=not wide
	$Wide.visible=wide
	$ReadingPaper.visible=preview_tab!=0
	for i in range(KEYS.size()):Supply.style_tab($Tabs.get_child(i),preview_tab==i)
	if preview_tab==1:_updates()
	elif preview_tab==3:
		var art:String="res://assets/story/canon-v2/missouri-limited-banner.png"
		if not ResourceLoader.exists(art):art=str(data.get("featured_art",""))
		if ResourceLoader.exists(art):$Hero.texture=load(art)
		$HeroTitle.text="本期UP · 密苏里"
		_text($Side,"特别邀请",31);_text($Side,"运行游戏后，可直接前往当前UP征募。",23)
	elif preview_tab==2:_text($Side,"战役进度",31);_text($Side,"游戏运行时读取实际战役目录与核验状态。",23)
	elif preview_tab==4:_text($Side,"回港补给",31);_text($Side,"运行游戏后显示个人签到与每周实战进度。",23)
	else:
		for path in ["Hero","HeroShade","HeroTitle","HeroSubtitle","Side","Wide"]:get_node(path).hide()
		$Editorial.show()
		$Editorial/Title.text=str(data.get("title","潮线档案"))
func bind(owner) -> void:
	app=owner
	load("res://scripts/banner_design.gd").chrome(app,self,"活动")
	_clear_content()
	var selected:String=str(app.get_meta("activity_tab","overview"))
	for i in range(KEYS.size()):
		var b:Button=$Tabs.get_child(i);Supply.style_tab(b,KEYS[i]==selected)
		_tab_art(b,i,KEYS[i]==selected)
		b.pressed.connect(func():app.set_meta("activity_tab",KEYS[i]);app.show_page("activity"))
	var wide:bool=selected in ["campaigns","supply"]
	for key in ["Hero","HeroShade","HeroTitle","HeroSubtitle","Side"]:get_node(key).visible=not wide
	$Wide.visible=wide
	$ReadingPaper.visible=selected!="overview"
	match selected:
		"updates":_updates()
		"campaigns":_campaigns()
		"featured":_featured()
		"supply":_supply()
		_:_overview()
func _tab_art(button:Button,index:int,selected:bool)->void:
	var title:String=button.text;button.text="";button.tooltip_text=title;button.clip_contents=true
	var paths:Array=[str(data.get("hero","")),"res://assets/story/canon-v2/c3-white-tower.png","res://assets/story/canon-v2/c2-waterline.png",load("res://scripts/recruit_presentation.gd").featured_art(app),"res://assets/backgrounds/harbor-day-v2.png"]
	if ResourceLoader.exists(str(paths[index])):
		var art:=TextureRect.new();art.texture=load(str(paths[index]));art.mouse_filter=Control.MOUSE_FILTER_IGNORE;art.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;art.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_COVERED;button.add_child(art);art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);art.modulate=Color(1,1,1,.7 if selected else .35)
	var shade:=ColorRect.new();shade.color=Color(.02,.04,.065,.42);shade.mouse_filter=Control.MOUSE_FILTER_IGNORE;button.add_child(shade);shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var caption:=Label.new();caption.text=title;caption.vertical_alignment=VERTICAL_ALIGNMENT_CENTER;caption.mouse_filter=Control.MOUSE_FILTER_IGNORE;caption.add_theme_font_override("font",Design.font(600));caption.add_theme_font_size_override("font_size",24);caption.add_theme_color_override("font_color",Color("f1f2ed"));button.add_child(caption);caption.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);caption.offset_left=20
	for state in ["normal","hover","pressed","focus"]:
		var style=Design.box(Color("1b2b3a"),2,Color("e6d4aa") if selected or state=="focus" else Color(.5,.6,.7,.4));style.set_border_width_all(2 if selected else 1);button.add_theme_stylebox_override(state,style)
func _text(parent:Node,value:String,size:int=23,color:Color=Design.INK) -> Label:
	var node:=Label.new();node.text=value;node.add_theme_font_override("font",Design.font(600 if size>=27 else 400));node.add_theme_font_size_override("font_size",size);node.add_theme_color_override("font_color",color);node.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;node.mouse_filter=Control.MOUSE_FILTER_IGNORE;parent.add_child(node);return node
func _action(parent:Node,title:String,callback:Callable,primary:bool=false) -> Button:
	var b:=Button.new();b.text=title;b.custom_minimum_size.y=58;b.disabled=app==null;Design.apply_button(b,primary);b.pressed.connect(func():
		if app.audio!=null:app.audio.ui("tap")
		callback.call())
	parent.add_child(b)
	return b
func _space(parent:Node) -> void:
	var spacer:=Control.new();spacer.size_flags_vertical=Control.SIZE_EXPAND_FILL;parent.add_child(spacer)
func _scroll(parent:Node) -> VBoxContainer:
	var scroll:=ScrollContainer.new();scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL;parent.add_child(scroll)
	var column:=VBoxContainer.new();column.size_flags_horizontal=Control.SIZE_EXPAND_FILL;column.add_theme_constant_override("separation",20);scroll.add_child(column);return column
func _overview() -> void:
	if app!=null:
		for path in ["Hero","HeroShade","HeroTitle","HeroSubtitle","Side","Wide"]:get_node(path).hide()
		$Editorial.show();$Editorial/Title.text=str(data.get("title","潮线档案"))
		$Editorial/Editorial_tide_event.bind(app,str(data.get("hero","")),"潮汐回响","舰队肉鸽 · 呼叫援军","tide_event")
		$Editorial/Editorial_recruit.bind(app,load("res://scripts/recruit_presentation.gd").featured_art(app),"特别邀请","密苏里 · 本期UP","recruit")
		$Editorial/Editorial_canon_catalog.bind(app,"res://assets/story/canon-v2/c1-rescue.png","第五小队航海日志","翻开新的篇章","canon_catalog")
		return

	_text($Side,"潮汐回响",34)
	_text($Side,"沉城观测环重新苏醒。用短暂放大的舰装，为流民船队守住归航信标。",23,Design.MUTED)
	_text($Side,"舰队割草 · 连续敌潮 · 呼叫援军",20,Design.ACCENT)
	_space($Side)
	_action($Side,"进入版本活动",func():app.show_page("tide_event"),true)
	_action($Side,"进入航海日志",func():app.show_page("canon_catalog"),true)
	_action($Side,"前往资源海域",func():app.show_page("resources"))
	_action($Side,"查看本期UP",func():app.set_meta("activity_tab","featured");app.show_page("activity"))
func _updates() -> void:
	$HeroTitle.text="试玩更新 · 潮线档案";$HeroSubtitle.text="当前本地版本的内容说明"
	var column:=_scroll($Side)
	for row in data.get("announcements",[]):
		_text(column,str(row.title),26)
		_text(column,str(row.body),21,Design.MUTED)
func _featured() -> void:
	var gacha:Dictionary=app.economy.config.get("gacha",{})
	var card:Dictionary=app.cards.get(str(gacha.get("featured_id","")),{})
	var art:String=load("res://scripts/recruit_presentation.gd").featured_art(app)
	if ResourceLoader.exists(art):$Hero.texture=load(art)
	$HeroTitle.text="当前UP · "+str(card.get("name","密苏里"));$HeroSubtitle.text="同伴的名字，写进新的航海日志。"
	_text($Side,"特别邀请",21,Design.ACCENT)
	_text($Side,str(card.get("name","密苏里")),38)
	_text($Side,str(card.get("class","战列舰")),23,Design.MUTED)
	_text($Side,"舰炮与海风之中，她仍会为你留一盏返航灯。",23,Design.MUTED)
	_space($Side)
	_action($Side,"前往UP征募",func():app.set_meta("recruit_pool","up");app.show_page("recruit"),true)
	_action($Side,"查看征募规则",func():
		var total:=0.0
		for weight in gacha.get("weights",{}).values():total+=float(weight)
		var chance:=float(gacha.get("weights",{}).get("ur",0))/maxf(total,1.0)
		var layer:Control=app.open_modal("本期征募规则")
		app.label(layer,"UR概率 %.1f%%；获得UR时，本期UP占 %.0f%%。"%[chance*100,float(gacha.get("featured_ur_share",0)) *100],390,255,800,100,25)
		app.label(layer,"连续%d次普通后，下一次至少稀有。UP不保证每轮获得；重复角色按现有规则兑换。"%int(gacha.get("rare_or_better_after_common",9)),390,385,800,150,22,Design.MUTED))
func _campaigns() -> void:
	var response:Dictionary=app.core.request({"op":"campaign"})
	if not bool(response.get("ok",false)):
		_text($Wide,"战役目录暂时不可用，请使用启动器重新打开游戏。",25);return
	var rows:Array=response.get("data",{}).get("scenarios",[])
	var playable:=0;var verified:=0
	for row in rows:
		if bool(row.get("playable",false)):playable+=1
		if bool(row.get("runtime",{}).get("historicalReady",false)):verified+=1
	_text($Wide,"可试玩 %d 份  /  历史核验完成 %d 份"%[playable,verified],27)
	var column:=_scroll($Wide)
	for row in rows:
		var entry:Dictionary=row
		var line:=HBoxContainer.new();line.add_theme_constant_override("separation",22);column.add_child(line)
		var title:Label=_text(line,str(entry.get("ibs_title","战役")),24);title.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		var ready:bool=bool(entry.get("runtime",{}).get("historicalReady",false))
		_text(line,"核验完成" if ready else "可试玩 · 核验中" if bool(entry.get("playable",false)) else "开发中",20,Design.ACCENT if ready else Design.MUTED)
		_action(line,"查看",func():
			var layer:Control=app.open_modal(str(entry.get("ibs_title","战役进度")))
			app.label(layer,str(entry.get("note","数据接线与原页逐项核对中。")),390,245,800,245,23)
			app.label(layer,"可试玩与历史核验是不同阶段；完整核验前保留对应限制。",390,520,800,90,20,Design.MUTED))
	_action($Wide,"打开战役航图",func():app.show_page("campaign"))
func _supply() -> void:
	_text($Wide,"每天靠港，都有一份新的补给。",27)
	var days:Array=app.progression.rewards.get("check_in",[])
	var claimed:int=app.progression.data().attendance.size()
	var history:Array=app.progression.data().attendance
	var today_claimed:bool=not history.is_empty() and app.progression.day_key()<=int(history.back())
	var cards:=HBoxContainer.new();cards.add_theme_constant_override("separation",12);$Wide.add_child(cards)
	for i in range(days.size()):
		var card:=VBoxContainer.new();card.custom_minimum_size=Vector2(138,245);card.size_flags_horizontal=Control.SIZE_EXPAND_FILL;card.add_theme_constant_override("separation",12);cards.add_child(card)
		_text(card,"第 %d 天"%(i+1),22,Design.ACCENT)
		var icon:=TextureRect.new();icon.texture=Design.icon_texture("recruit" if days[i].has("ship_ids") else "ticket" if days[i].has("standard_tickets") or days[i].has("up_tickets") else "coin");icon.custom_minimum_size.y=76;icon.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;icon.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED;card.add_child(icon)
		var reward:String=Supply.rewards_text(days[i])
		if days[i].has("ship_ids"):
			var names:PackedStringArray=[]
			for id in days[i].ship_ids:names.append(str(app.cards.get(str(id),{}).get("name",id)))
			reward+=("\n" if not reward.is_empty() else "")+"、".join(names)
		_text(card,reward,20)
		_text(card,"已领取" if i<claimed else ("明日可领" if today_claimed else "今日可领") if i==claimed else "待开启",18,Design.MUTED)
	var claim:Button=_action($Wide,"领取今日签到",func():var result:Dictionary=app.progression.claim_attendance();app.show_page("activity");app.notify(result),true)
	claim.disabled=today_claimed or claimed>=days.size() or not app.economy.state.get("active_run",{}).is_empty()
	var week:Dictionary=app.progression.weekly_status()
	_text($Wide,"本周挑战通关 %d / 3 场 · 每日北京时间刷新，漏签顺延"%int(week.clears),22,Design.MUTED)
	var row:=HBoxContainer.new();row.add_theme_constant_override("separation",18);$Wide.add_child(row)
	_action(row,"采购周配给券 · 500银币",func():var result:Dictionary=app.progression.buy_weekly_ticket();app.show_page("activity");app.notify(result))
	_action(row,"领取3场实战周补给",func():var result:Dictionary=app.progression.claim_weekly_supply();app.show_page("activity");app.notify(result))
