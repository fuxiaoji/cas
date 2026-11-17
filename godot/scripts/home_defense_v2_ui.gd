extends RefCounted
const Design=preload("res://scripts/ui_design.gd")
const Chart=preload("res://scripts/home_defense_map_v2.gd")
var app
var home
var war
var screen:Control
var chart:Control
var status:Label
var confirm:Button
var kind:String="land_mine"
var quote:Dictionary={}
var selected:String=""
var transaction:String=""
static func open(owner)->void:
	var ui=load("res://scripts/home_defense_v2_ui.gd").new();ui.app=owner;ui.home=owner.home;ui.war=ui.home.latest_island();ui._build()
func _cost(value:Dictionary)->String:
	var parts:Array[String]=[]
	for key in value:parts.append(str(home.RESOURCE_NAMES.get(key,key))+" "+str(value[key]))
	return " · ".join(parts)
func _build()->void:
	screen=app.open_modal("家园布防 · 拖动选址");screen.name="HomeDefenseV2";screen.set_meta("ui_owner",self)
	var keys:Array=["land_mine","beach_position","sea_mine",""]
	for index in range(keys.size()):
		var chosen:String=str(keys[index]);var title:String=str(war.DEPLOYABLES[chosen].name) if not chosen.is_empty() else "查看 / 撤除"
		var button:Button=app.button(screen,title,380+index*208,206,196,58,func():kind=chosen;quote={};selected="";transaction="";chart.draw_kind=kind;chart.marker_visible=false;chart.queue_redraw();_instruction(),chosen==kind);button.name="DefenseKind_"+(chosen if not chosen.is_empty() else "inspect");button.add_theme_font_size_override("font_size",20)
	chart=Chart.new();chart.name="HomeDefenseChart";chart.draw_kind=kind;app.place(chart,screen,380,275,820,346);chart.picked.connect(_pick);chart.deployment_selected.connect(_select)
	status=app.label(screen,"",380,629,820,45,18,Design.MUTED);status.name="HomeDefenseStatus"
	app.button(screen,"取消选址",380,684,200,60,func():quote={};selected="";transaction="";chart.marker_visible=false;chart.queue_redraw();_instruction()).name="CancelDefensePlacement"
	app.button(screen,"返回岛务",590,684,210,60,func():load("res://scripts/home_conflict_ui.gd").open(app,"islands")).name="BackFromDefense"
	confirm=app.button(screen,"确认布设",810,684,390,60,_commit,true);confirm.name="ConfirmDefensePlacement";confirm.disabled=true
	var preview:Dictionary=home.prepare_latest_exercise(home.state().tactical_garrison,home.state().garrison,"balanced")
	if not preview.get("ok",false):status.text=str(preview.get("message","先安排驻防，才能查看真实岛屿布防图"));return
	chart.observe(preview.preview,war.deployables());_instruction()
	if chart.placement.is_empty():status.text="布防坐标流尚未就绪 · 未发生资源扣除"
func _instruction()->void:
	if not is_instance_valid(confirm):return
	confirm.disabled=true;confirm.text="确认布设"
	status.text="点选已有部署可撤除，材料不返还。" if kind.is_empty() else str(war.DEPLOYABLES[kind].placement)+" · 拖动并松手检查 · "+_cost(war.DEPLOYABLES[kind].cost)
func _pick(point:Vector2)->void:
	quote={};selected="";transaction="defense-place-%d"%Time.get_ticks_usec()
	quote=war.placement_preview(kind,point.x,point.y);chart.marker_valid=bool(quote.get("ok",false));chart.queue_redraw()
	confirm.text="确认布设";confirm.disabled=not bool(quote.get("ok",false)) or not bool(quote.get("ready",false))
	status.text=("位置可用 · 确认费用："+_cost(quote.cost)) if quote.get("ok",false) else str(quote.get("message","位置不适合"))
	if quote.get("ok",false) and not quote.get("ready",false):status.text+=" · 资源不足或行动中"
func _select(id:String)->void:
	selected=id;quote={};transaction="defense-remove-%d"%Time.get_ticks_usec();confirm.text="确认撤除 · 不返材料";confirm.disabled=not home._idle();status.text="撤除这处部署不返还材料；不影响周边设施。"
func _commit()->void:
	var result:Dictionary
	if not selected.is_empty():result=war.remove(selected,transaction)
	elif quote.get("ok",false):result=war.place(str(quote.entry.kind),float(quote.entry.x),float(quote.entry.y),transaction,quote.cost)
	else:return
	app.notify(result)
	if result.get("ok",false):quote={};selected="";_build()
