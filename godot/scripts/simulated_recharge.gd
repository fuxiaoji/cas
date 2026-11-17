@tool
extends Control
const Design=preload("res://scripts/ui_design.gd")
const Store=preload("res://scripts/simulated_store.gd")
var app
var service
func _ready() -> void:
	theme=Design.theme()
	Design.apply_button($Orders,false,true)
func bind(owner) -> void:
	app=owner;service=Store.new(app.economy)
	for card in $Packs.get_children():
		var id:String=card.pack_id
		var buy:Button=card.get_node("Body/Buy")
		buy.disabled=not app.economy.state.get("active_run",{}).is_empty()
		buy.tooltip_text="返港后可模拟补给" if buy.disabled else "创建本地订单，不发生真实付款"
		buy.pressed.connect(func():
			var response:Dictionary=service.create_order(id)
			if response.get("ok",false):_checkout(response.order)
			else:app.notify(response))
	$Orders.pressed.connect(_orders)
func _checkout(order:Dictionary) -> void:
	var layer:Control=app.open_modal("模拟补给确认")
	app.label(layer,"本地模拟 · 不扣真钱",390,226,800,50,24,Design.ACCENT)
	app.label(layer,str(order.name),390,300,800,70,34)
	app.label(layer,"%d 元词    %s"%[int(order.origins),str(order.price_label)],390,384,800,65,27)
	app.label(layer,"确认后直接发放试玩资源，可在订单记录中查看。",390,472,800,68,22,Design.MUTED)
	var id:String=str(order.id)
	app.button(layer,"取消订单",390,594,340,64,func():
		var response:Dictionary=service.cancel_order(id)
		app.close_modal();app.show_page("shop");app.notify(response))
	var fulfill:Button=app.button(layer,"模拟到账",790,594,400,64,func():
		var response:Dictionary=service.complete_order(id)
		app.close_modal();app.show_page("shop");app.notify(response),true)
	fulfill.name="SimulateFulfill"
func _orders() -> void:
	var layer:Control=app.open_modal("模拟订单记录")
	app.label(layer,"本地模拟记录 · 所有订单均未付款",390,219,800,45,22,Design.ACCENT)
	var scroll:=ScrollContainer.new();app.place(scroll,layer,390,285,830,352)
	var column:=VBoxContainer.new();column.size_flags_horizontal=Control.SIZE_EXPAND_FILL;column.add_theme_constant_override("separation",18);scroll.add_child(column)
	var history:Array=service.orders();history.reverse()
	if history.is_empty():
		var empty:=Label.new();empty.text="还没有模拟补给记录";column.add_child(empty)
	for row in history:
		var entry:Dictionary=row
		var panel:=VBoxContainer.new();panel.add_theme_constant_override("separation",8);column.add_child(panel)
		var title:=Label.new();title.text="%s · %d 元词"%[str(entry.name),int(entry.origins)];title.add_theme_font_size_override("font_size",24);panel.add_child(title)
		var status:=Label.new();status.text={"pending":"待模拟到账","fulfilled":"已模拟到账 · 未付款","cancelled":"已取消"}.get(str(entry.status),"未知状态");status.add_theme_color_override("font_color",Design.MUTED);panel.add_child(status)
		if str(entry.status)=="pending":
			var resume:=Button.new();resume.text="继续模拟补给";Design.apply_button(resume);panel.add_child(resume)
			resume.disabled=not app.economy.state.get("active_run",{}).is_empty()
			resume.pressed.connect(func():app.close_modal();_checkout(entry))
