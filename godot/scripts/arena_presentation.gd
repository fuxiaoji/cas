@tool
extends Control
const Design=preload("res://scripts/ui_design.gd")
const Art=preload("res://scripts/character_art.gd")
const Badge=preload("res://scripts/arena_badge.gd")
var app
var mode:String="ranked"
var current_preview:Dictionary={}

static func render(owner)->void:
	var scene=load("res://scenes/ui/arena_hub.tscn").instantiate()
	owner.page.add_child(scene);scene.bind(owner)

func _ready()->void:
	if theme==null:theme=Design.theme()
	for child in find_children("*","Button",true,false):Design.apply_button(child,child.name=="Launch")
	for child in find_children("*","Label",true,false):child.add_theme_font_override("font",Design.font(500))
	$RankName.add_theme_font_override("font",Design.font(700))
	$Rating.add_theme_font_override("font",Design.font(700))

func bind(owner)->void:
	app=owner;mode="team3" if str(app.get_meta("arena_mode","ranked"))=="team3" else "ranked"
	$Ranked.pressed.connect(func():_switch("ranked"))
	$Team3.pressed.connect(func():_switch("team3"))
	$EditFleet.pressed.connect(func():app.show_page("formation"))
	$TierRewards.pressed.connect(_rewards)
	$History.pressed.connect(_history)
	$Launch.pressed.connect(func():app.launch_arena(mode))
	_refresh()

func _switch(next:String)->void:
	if next==mode:return
	app.set_meta("arena_mode",next);app.show_page("arena")

func _color(value:Variant)->Color:
	return value if value is Color else Color(str(value))

func _refresh()->void:
	if app==null:return
	var profile:Dictionary=app.arena.profile(mode)
	var tiers:Array=app.arena.tiers()
	var rating:int=int(profile.get("rating",0))
	var tier:Dictionary=tiers[0] if not tiers.is_empty() else {"name":"见习","minimum":0,"color":"bc9564"}
	var next_tier:Dictionary={};var tier_index:int=0
	for i in range(tiers.size()):
		if rating>=int(tiers[i].get("minimum",0)):tier=tiers[i];tier_index=i
		elif next_tier.is_empty():next_tier=tiers[i]
	$RankName.text=str(tier.get("name","见习"))
	$RankBadge.rank_color=_color(tier.get("color","bc9564"));$RankBadge.rank_index=tier_index
	$Rating.text=str(rating)
	$ModeLabel.text="三人协同" if mode=="team3" else "舰队排位"
	$RankHint.text="最高 %d"%int(profile.get("peak",rating))
	$Progress.max_value=maxi(1,int(next_tier.get("minimum",rating+1))-int(tier.get("minimum",0)))
	$Progress.value=rating-int(tier.get("minimum",0))
	$NextRank.text="%s · %d"%[str(next_tier.get("name","")),int(next_tier.get("minimum",0))] if not next_tier.is_empty() else "已抵达最高段位"
	$ModeHint.text="你与两支友方AI协同，对阵三支AI舰队" if mode=="team3" else "自由编成舰队，争夺海域制海权"
	$RuleHint.text="本席3400分 · 两名队友各3300分" if mode=="team3" else "10000分预算 · 最多四个编队"
	$Launch.text="开始3v3" if mode=="team3" else "开始排位"
	Design.apply_button($Ranked,mode=="ranked");Design.apply_button($Team3,mode=="team3")
	current_preview=app.arena.preview(mode)
	var selected:Array=app.arena.selected(mode)
	var points:int=int(current_preview.get("points",0))
	var budget:int=int(current_preview.get("budget",3400 if mode=="team3" else 10000))
	$Budget.max_value=budget;$Budget.value=points
	$Budget.add_theme_stylebox_override("background",Design.box(Color("dce6e9"),3))
	$Budget.add_theme_stylebox_override("fill",Design.box(Color("d77162") if points>budget else Design.ACCENT,3))
	$BudgetValue.text="%d / %d"%[points,budget]
	$Selection.text="出击编队  %d / 4"%selected.size()
	var active:bool=not app.economy.state.get("active_run",{}).is_empty()
	$Launch.disabled=not bool(current_preview.get("ok",false)) or active
	$Feedback.text="先继续当前航次" if active else "准备就绪" if current_preview.get("ok",false) else str(current_preview.get("message","请选择出击编队"))
	$Feedback.add_theme_color_override("font_color",Design.ACCENT if current_preview.get("ok",false) and not active else Color("a05e45"))
	for child in $FleetScroll/Fleets.get_children():child.queue_free();$FleetScroll/Fleets.remove_child(child)
	var rows:Array=app.fleets.rows()
	if rows.is_empty():
		var empty:=Label.new();empty.text="先组建一支舰队";$FleetScroll/Fleets.add_child(empty)
	for row in rows:_group(row,selected.has(str(row.id)))

func _group(row:Dictionary,on:bool)->void:
	var id:String=str(row.id)
	var panel:=PanelContainer.new();panel.name="Fleet_"+id;panel.custom_minimum_size=Vector2(0,172)
	panel.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	var box:=Design.box(Color(.91,.97,.97,.98) if on else Color(1,1,1,.94),4,Design.ACCENT if on else Color(.66,.75,.78,.35));box.content_margin_top=10;box.content_margin_bottom=10
	panel.add_theme_stylebox_override("panel",box);$FleetScroll/Fleets.add_child(panel)
	var body:=VBoxContainer.new();body.add_theme_constant_override("separation",6);panel.add_child(body)
	var heading:=HBoxContainer.new();body.add_child(heading)
	var title:=Label.new();title.text=str(row.get("name","舰队"));title.size_flags_horizontal=Control.SIZE_EXPAND_FILL;title.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS;title.add_theme_font_size_override("font_size",23);heading.add_child(title)
	var check:=CheckButton.new();check.name="SelectGroup";check.button_pressed=on;check.tooltip_text="选择出击编队";check.focus_mode=Control.FOCUS_ALL;heading.add_child(check)
	check.toggled.connect(func(enabled:bool):
		var result:Dictionary=app.arena.toggle_group(mode,id,enabled)
		app.notify(result);_refresh())
	var portraits:=HBoxContainer.new();portraits.add_theme_constant_override("separation",9);body.add_child(portraits)
	var score:int=0;var names:Array=[]
	var ships:Array=row.get("ships",[])
	for index in range(ships.size()):
		var identity:String=str(ships[index]);var card:Dictionary=app.cards.get(identity,{})
		score+=int(card.get("points",0));names.append(str(card.get("name",identity)))
		if index>=4:continue
		var portrait:=TextureRect.new();portrait.custom_minimum_size=Vector2(70,77)
		portrait.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;portrait.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_COVERED
		portrait.tooltip_text=str(card.get("name",identity));portrait.mouse_filter=Control.MOUSE_FILTER_STOP
		var texture:Texture2D=Art.texture(str(card.get("portrait","")))
		if texture!=null:portrait.texture=Design.crop(texture,.30)
		portraits.add_child(portrait)
	if ships.is_empty():
		var hint:=Label.new();hint.text="空编队 · 去编队页添加舰娘";hint.add_theme_color_override("font_color",Design.MUTED);hint.custom_minimum_size.y=77;portraits.add_child(hint)
	var detail:=Label.new();detail.text="%d 艘%s  ·  %d 分"%[ships.size(),"  +%d"%(ships.size()-4) if ships.size()>4 else "",score]
	detail.add_theme_font_size_override("font_size",17);detail.add_theme_color_override("font_color",Design.MUTED);body.add_child(detail)
	panel.tooltip_text="、".join(names)
	check.disabled=ships.is_empty() or not app.economy.state.get("active_run",{}).is_empty()

func _rewards()->void:
	var layer:Control=app.open_modal("航海段位")
	var scroll:=ScrollContainer.new();scroll.name="ArenaTierScroll";scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;app.place(scroll,layer,370,228,860,476)
	var list:=VBoxContainer.new();list.size_flags_horizontal=Control.SIZE_EXPAND_FILL;list.add_theme_constant_override("separation",12);scroll.add_child(list)
	var profile:Dictionary=app.arena.profile(mode)
	var peak:int=int(profile.get("peak",profile.get("rating",0)))
	var eligible:bool=int(profile.get("completed",0))>0 and app.economy.state.get("active_run",{}).is_empty()
	var claims:Variant=profile.get("claims",[])
	var tiers:Array=app.arena.tiers()
	for i in range(tiers.size()):
		var tier:Dictionary=tiers[i];var id:String=str(tier.id)
		var row:=HBoxContainer.new();row.custom_minimum_size.y=98;row.add_theme_constant_override("separation",22);list.add_child(row)
		var badge:=Badge.new();badge.custom_minimum_size=Vector2(80,90);badge.rank_color=_color(tier.get("color","bc9564"));badge.rank_index=i;row.add_child(badge)
		var text:=VBoxContainer.new();text.size_flags_horizontal=Control.SIZE_EXPAND_FILL;row.add_child(text)
		var name:=Label.new();name.text="%s  ·  %d"%[str(tier.name),int(tier.minimum)];name.add_theme_font_size_override("font_size",24);text.add_child(name)
		var rewards:Dictionary=tier.get("rewards",{});var reward_label:=Label.new();reward_label.text="元词 %d   银币 %d"%[int(rewards.get("origins",0)),int(rewards.get("credits",0))];reward_label.add_theme_font_size_override("font_size",19);reward_label.add_theme_color_override("font_color",Design.MUTED);text.add_child(reward_label)
		var claimed:bool=claims.has(id)
		var claim:=Button.new();claim.name="Claim_"+id;claim.text="已领取" if claimed else "先完成一局" if not eligible else "领取" if peak>=int(tier.minimum) else "尚未到达";claim.custom_minimum_size=Vector2(150,62);Design.apply_button(claim,eligible and peak>=int(tier.minimum) and not claimed);claim.disabled=claimed or not eligible or peak<int(tier.minimum);row.add_child(claim)
		claim.pressed.connect(func():app.notify(app.arena.claim_tier(mode,id));app.close_modal();_refresh();_rewards())

func _history()->void:
	var layer:Control=app.open_modal("最近对局")
	var scroll:=ScrollContainer.new();scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;app.place(scroll,layer,370,232,860,465)
	var list:=VBoxContainer.new();list.size_flags_horizontal=Control.SIZE_EXPAND_FILL;list.add_theme_constant_override("separation",14);scroll.add_child(list)
	var history:Array=app.arena.history(mode)
	if history.is_empty():
		var empty:=Label.new();empty.text="尚未出战，一起写下第一份战报。";list.add_child(empty)
	for result in history:
		var row:=HBoxContainer.new();row.custom_minimum_size.y=60;list.add_child(row)
		var outcome:=Label.new();var key:String=str(result.get("result","win" if result.get("won",false) else ""));outcome.text={"win":"胜利","loss":"失利","draw":"平局","forfeit":"认输"}.get(key,"结束");outcome.custom_minimum_size.x=128;row.add_child(outcome)
		var title:=Label.new();title.text=str(result.get("title","三人协同" if mode=="team3" else "舰队排位"));title.size_flags_horizontal=Control.SIZE_EXPAND_FILL;title.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS;row.add_child(title)
		var delta:=Label.new();delta.text="%+d"%int(result.get("delta",0));delta.add_theme_color_override("font_color",Design.ACCENT if int(result.get("delta",0))>=0 else Color("ae6c60"));row.add_child(delta)
