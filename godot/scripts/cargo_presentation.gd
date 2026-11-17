extends Control
const Service=preload("res://scripts/cargo_service.gd")
const Design=preload("res://scripts/ui_design.gd")
const Grid=preload("res://scripts/cargo_grid.gd")
const Token=preload("res://scripts/cargo_token.gd")
var app
var stash_mode:=false
var warehouse_scope:String="base"
var selected:String=""
var turn:=0
var data:Dictionary={}
var grid:Control
var list:VBoxContainer
var detail:Label
var status:Label
var action:Button
var return_running:=false
var pending:Dictionary={}
var dragging:=false
var suppress_click:=false
var ghost:Control
var drag_hint:Label
var pointer_position:=Vector2.ZERO
static func open(owner)->void:
	_show(owner,false)
static func open_stash(owner,scope:String="base")->void:
	_show(owner,true,scope)
static func _show(owner,port:bool,scope:String="base")->void:
	var prior:bool=owner.running
	if not port:owner.running=false
	var layer:Control=owner.open_modal("仓库与编队货舱" if port else "航次货舱")
	var view=load("res://scenes/ui/cargo_hold.tscn").instantiate()
	view.app=owner;view.stash_mode=port;view.warehouse_scope=scope;view.return_running=prior;layer.add_child(view)
	view.position=Vector2(370,222);view.size=Vector2(860,502);view.build()
	if not port:
		layer.tree_exited.connect(func():
			if is_instance_valid(owner) and owner.screen=="battle" and owner.core.view.get("result")==null:owner.running=prior)
func build()->void:
	grid=$GridScroll/CargoGrid;list=$ItemsScroll/Items;status=$Status;detail=$Detail;action=$Action
	grid.picked.connect(_pick);grid.grabbed.connect(_begin_grab);grid.placed.connect(_place)
	for node in [$Rotate,$Clear,$Action,$Sort,$Quick]:Design.apply_button(node);node.add_theme_font_size_override("font_size",18)
	$Rotate.pressed.connect(_rotate);$Clear.pressed.connect(func():_cancel_drag();selected="";refresh());action.pressed.connect(_consume_or_drop)
	$Quick.pressed.connect(_quick_place)
	$Sort.pressed.connect(func():
		if stash_mode:app.notify(load("res://scripts/fleet_warehouse.gd").new(app.economy).clean(warehouse_scope))
		else:app.issue({"op":"cargo_sort"})
		refresh())
	if stash_mode:
		$Sort.text="一键整理";$Footnote.hide();$Status.position.x=440;$Status.size.x=410
		for i in range(2):
			var scope:String="fleet" if i==0 else "base"
			var tab:=Button.new();tab.name="Warehouse_"+scope;tab.text="当前编队" if i==0 else "基地仓库";tab.position=Vector2(i*215,0);tab.size=Vector2(205,36);Design.apply_button(tab,warehouse_scope==scope);add_child(tab)
			tab.pressed.connect(func():open_stash(app,scope))
		var transfer:=Button.new();transfer.name="Transfer";transfer.position=Vector2(0,468);transfer.size=Vector2(415,42);Design.apply_button(transfer);add_child(transfer)
		transfer.text="选中物资卸至基地" if warehouse_scope=="fleet" else "选中物资装入编队"
		transfer.pressed.connect(func():app.notify(load("res://scripts/fleet_warehouse.gd").new(app.economy).transfer(selected,warehouse_scope));selected="";refresh())
		var sell:=Button.new();sell.name="SellAll";sell.text="一键卖出 · 保留拆包物资";sell.position=Vector2(440,468);sell.size=Vector2(410,42);Design.apply_button(sell);add_child(sell)
		sell.pressed.connect(func():app.notify(load("res://scripts/fleet_warehouse.gd").new(app.economy).clean(warehouse_scope,true));selected="";refresh())
	$Footnote.text="拖动物资入格  ·  R 旋转  ·  双击快速装入  ·  右键取消"
	ghost=Token.new();ghost.name="CarriedCargo";ghost.z_index=100;ghost.visible=false;add_child(ghost)
	drag_hint=Label.new();drag_hint.name="DropHint";drag_hint.mouse_filter=Control.MOUSE_FILTER_IGNORE;drag_hint.add_theme_font_override("font",Design.font(600));drag_hint.add_theme_font_size_override("font_size",18);ghost.add_child(drag_hint)
	refresh()
func refresh()->void:
	data=(load("res://scripts/fleet_warehouse.gd").new(app.economy).hold() if warehouse_scope=="fleet" else Service.new(app.economy).stash()) if stash_mode else app.core.view.get("salvage",{}).get("cargo_grid",{})
	grid.refresh(data,selected,turn)
	var count:int=data.get("items",[]).filter(func(item):return item.get("placement")!=null).size()
	status.text=("%d件 · %d/%d kg"%[data.items.size(),int(load("res://scripts/fleet_warehouse.gd").weight(data.items)),int(data.max_kg)] if warehouse_scope=="fleet" else "%d 件 · 指挥官等级扩容"%data.items.size()) if stash_mode else "%d 件已入舱 · %d / %d kg"%[count,int(data.get("kg",0)),int(data.get("max_kg",0))]
	if stash_mode:$Transfer.disabled=selected.is_empty() or not app.economy.state.get("active_run",{}).is_empty();$SellAll.disabled=not app.economy.state.get("active_run",{}).is_empty()
	for node in list.get_children():list.remove_child(node);node.queue_free()
	var selected_item:Dictionary={}
	for item in data.get("items",[]):
		var row:=HBoxContainer.new();row.custom_minimum_size=Vector2(0,70);row.add_theme_constant_override("separation",5);list.add_child(row)
		row.gui_input.connect(_list_input.bind(str(item.id)))
		var icon:=TextureRect.new();icon.texture=load(Service.art_path(item));icon.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;icon.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED;icon.custom_minimum_size=Vector2(54,64);icon.mouse_filter=Control.MOUSE_FILTER_IGNORE;row.add_child(icon)
		var button:=Button.new();button.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		button.text=str(item.name)+"\n"+("待整理" if stash_mode and item.get("placement")==null else "待装" if item.get("placement")==null else "✓ 已入库" if stash_mode else "✓ 已装载")
		button.name="Item_"+str(item.id).validate_node_name();button.set_meta("cargo_id",str(item.id));button.alignment=HORIZONTAL_ALIGNMENT_LEFT
		Design.apply_button(button,str(item.id)==selected);button.add_theme_font_size_override("font_size",17);row.add_child(button)
		var identity:String=str(item.id);button.pressed.connect(func():
			if not suppress_click:_pick(identity))
		button.gui_input.connect(_list_input.bind(identity))
		button.tooltip_text="拖到货舱 · R旋转 · 双击快速装入"
		var shape:Control=Token.new();shape.custom_minimum_size=Vector2(47,48);shape.configure(item,int(item.placement[2]) if item.get("placement")!=null else 0);row.add_child(shape)
		if identity==selected:selected_item=item
	if selected_item.is_empty():detail.text="把物资拖进货舱，放得下再松手。\n只有入舱的物资才能随撤离带回。" if not stash_mode else "拖动物资整理位置。\n选择物资可拆包或兑换。";action.disabled=true;action.text="选择物资";$Quick.disabled=true;$Rotate.disabled=true
	else:
		var use:String="返港拆包获得舰装/水手" if Service.can_unpack(selected_item) else "返港兑换 %d 银币"%int(selected_item.value)
		detail.text="%s  ·  %d 格  ·  %d kg\n%s"%[str(selected_item.name),selected_item.shape.size(),int(selected_item.kg),use]
		$Quick.disabled=selected_item.get("placement")!=null;$Rotate.disabled=false
		action.disabled=false;action.text=("拆包入库" if Service.can_unpack(selected_item) else "兑换 %d 银币"%int(selected_item.value)) if stash_mode else "弃置物资"
func _pick(id:String)->void:
	selected=id;turn=0
	for item in data.get("items",[]):
		if str(item.id)==id and item.get("placement")!=null:turn=int(item.placement[2])
	refresh()
func _place(x:int,y:int,r:int)->void:
	if selected.is_empty():return
	var item:Dictionary=grid.current_item()
	if not item.is_empty() and not grid.valid_at(item,[x,y,r]):
		detail.text="这里放不下，试试旋转或换个空位。";return
	if stash_mode:app.notify(Service.new(app.economy).place_stash(selected,[x,y,r],warehouse_scope))
	else:app.issue({"op":"cargo_place","item":selected,"x":x,"y":y,"rotation":r})
	refresh()
func _rotate()->void:
	if selected.is_empty():return
	if dragging:
		var h:=1
		for p in Service.item_cells(grid.current_item(),[0,0,turn]):h=maxi(h,int(p[1])+1)
		grid.grab_offset=Vector2i(h-1-grid.grab_offset.y,grid.grab_offset.x)
		pending.fraction=Vector2(1.0-pending.fraction.y,pending.fraction.x)
	turn=(turn+1)%4;grid.refresh(data,selected,turn)
	if dragging:_update_drag()
func _unhandled_key_input(event:InputEvent)->void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode==KEY_R and not selected.is_empty():_rotate();get_viewport().set_input_as_handled()
func _list_input(event:InputEvent,id:String)->void:
	if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT and event.pressed:
		if event.double_click:
			_pick(id);_quick_place();pending={};suppress_click=true;call_deferred("_allow_click")
		else:_begin_grab(id,Vector2i.ZERO,Vector2(.5,.5))
func _begin_grab(id:String,offset:Vector2i,fraction:Vector2)->void:
	pending={"id":id,"start":pointer_position,"offset":offset,"fraction":fraction}
func _input(event:InputEvent)->void:
	if not is_visible_in_tree() or not is_instance_valid(app) or not is_instance_valid(app.modal):return
	if event is InputEventMouse: pointer_position=get_canvas_transform().affine_inverse()*event.position
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode==KEY_ESCAPE and (dragging or not pending.is_empty()):
			_cancel_drag();get_viewport().set_input_as_handled();return
		if event.keycode==KEY_R and dragging:
			_rotate();get_viewport().set_input_as_handled();return
	if event is InputEventMouseButton and event.pressed and event.button_index==MOUSE_BUTTON_RIGHT and (dragging or not pending.is_empty()):
		_cancel_drag();get_viewport().set_input_as_handled();return
	if event is InputEventMouseMotion and not pending.is_empty():
		if not dragging and pointer_position.distance_to(pending.start)>8.0:
			selected=str(pending.id);turn=0
			for item in data.get("items",[]):
				if str(item.id)==selected and item.get("placement")!=null:turn=int(item.placement[2])
			dragging=true;grid.dragging=true;grid.grab_offset=pending.offset;grid.refresh(data,selected,turn);ghost.visible=true
		if dragging:_update_drag();get_viewport().set_input_as_handled()
	if event is InputEventMouseButton and not event.pressed and event.button_index==MOUSE_BUTTON_LEFT and not pending.is_empty():
		if dragging:
			_update_drag();var p:Array=grid.target();var inside:bool=_inside_grid()
			var valid:bool=grid.preview_valid and inside
			_cancel_drag()
			if valid:_place(int(p[0]),int(p[1]),int(p[2]))
			else:detail.text="已取消，物资留在原处。"
			get_viewport().set_input_as_handled()
		else:pending={}
func _inside_grid()->bool:
	var scroll:Control=$GridScroll
	return scroll.get_global_rect().has_point(pointer_position) and Rect2(Vector2.ZERO,grid.size).has_point(grid.get_global_transform().affine_inverse()*pointer_position)
func _update_drag()->void:
	grid.update_pointer(grid.get_global_transform().affine_inverse()*pointer_position)
	ghost.configure(grid.current_item(),turn,grid.cell,true)
	ghost.accepted=grid.preview_valid and _inside_grid();ghost.queue_redraw()
	ghost.global_position=pointer_position-(Vector2(grid.grab_offset)+Vector2(pending.get("fraction",Vector2(.5,.5))))*grid.cell
	var bounds:=Vector2.ZERO
	for p in Service.item_cells(grid.current_item(),[0,0,turn]):bounds=bounds.max((Vector2(float(p[0]),float(p[1]))+Vector2.ONE)*grid.cell)
	drag_hint.position=Vector2(0,bounds.y+7)
	drag_hint.text=("✓ "+grid.preview_reason) if ghost.accepted else "× "+grid.preview_reason if _inside_grid() else "松开取消"
	drag_hint.add_theme_color_override("font_color",Color("187b69") if ghost.accepted else Color("a33f3d"))
func _process(delta:float)->void:
	if not dragging:return
	var scroll:ScrollContainer=$GridScroll;var p:Vector2=scroll.get_global_transform().affine_inverse()*pointer_position
	if p.x>=0 and p.x<=scroll.size.x:
		var direction:=1 if p.y>scroll.size.y-28 else -1 if p.y<28 else 0
		if direction!=0:scroll.scroll_vertical+=int(float(direction)*delta*420.0);_update_drag()
func _cancel_drag()->void:
	pending={};dragging=false;grid.dragging=false;grid.grab_offset=Vector2i.ZERO
	grid.hovered=Vector2i(-1,-1);grid.queue_redraw();ghost.visible=false
	suppress_click=true;call_deferred("_allow_click")
	refresh()
func _allow_click()->void:suppress_click=false
func _quick_place()->void:
	var item:Dictionary=grid.current_item()
	if item.is_empty() or item.get("placement")!=null:return
	for y in range(int(data.get("rows",0))):
		for x in range(int(data.get("cols",0))):
			for r in range(4):
				if grid.valid_at(item,[x,y,r]):turn=r;_place(x,y,r);return
	detail.text="没有合适的空位，先调整舱内物资。"
func _consume_or_drop()->void:
	if selected.is_empty():return
	if stash_mode:app.notify(Service.new(app.economy).consume(selected,warehouse_scope));selected="";refresh()
	else:
		var id:=selected
		var owner=app;var resume:bool=return_running
		app.confirm_action("弃置后本航次无法找回。确定放弃这件物资？",func():owner.issue({"op":"cargo_drop","item":id});open(owner))
		app.running=false
		app.modal.tree_exited.connect(func():
			if is_instance_valid(owner) and owner.screen=="battle" and owner.core.view.get("result")==null:owner.running=resume)
static func open_loadout(owner)->void:
	var layer:Control=owner.open_modal("航前装载")
	layer.tree_exited.connect(func():
		if not is_instance_valid(owner) or owner.screen!="formation":return
		var summary:Label=owner.page.find_child("SortieCargoSummary",true,false)
		if summary!=null:
			var cargo:Dictionary=owner.economy.cargo_budget();var fleet:Dictionary=owner.economy.formation_preview()
			summary.text="货舱  %d 格 · %.1f 吨\n搜索  %d 秒\n弹药  %d 份"%[int(cargo.cells),float(cargo.max_kg)/1000.0,int(cargo.search_seconds),int(fleet.ammo_required)])
	var service:=Service.new(owner.economy);var budget:Dictionary=owner.economy.cargo_budget()
	var view:Control=load("res://scenes/ui/cargo_loadout.tscn").instantiate();layer.add_child(view)
	var rows:VBoxContainer=view.get_node("Scroll/Ships")
	for ship in budget.ships:
		var line:=HBoxContainer.new();line.custom_minimum_size=Vector2(820,136);line.add_theme_constant_override("separation",18);rows.add_child(line)
		var portrait:=TextureRect.new();portrait.texture=load(str(owner.cards.get(str(ship.id),{}).get("portrait","")));portrait.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;portrait.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_COVERED;portrait.custom_minimum_size=Vector2(85,130);line.add_child(portrait)
		var row:=VBoxContainer.new();row.size_flags_horizontal=Control.SIZE_EXPAND_FILL;row.add_theme_constant_override("separation",12);line.add_child(row)
		var title:=Label.new();title.text="%s  ·  %s"%[str(ship.name),"运输支援 +12格" if ship.transport else "轻装可腾出载货空间"];title.add_theme_font_override("font",Design.font(600));title.add_theme_font_size_override("font_size",22);title.add_theme_color_override("font_color",Design.INK);row.add_child(title)
		var bar:=HBoxContainer.new();row.add_child(bar)
		var amount:=Label.new();amount.text="炮弹 %d%%"%int(ship.ammo);amount.custom_minimum_size.x=116;amount.add_theme_color_override("font_color",Design.INK);bar.add_child(amount)
		var slider:=HSlider.new();slider.name="Ammo_"+str(ship.id).validate_node_name();slider.min_value=20;slider.max_value=100;slider.step=1;slider.value=int(ship.ammo);slider.custom_minimum_size=Vector2(245,48);bar.add_child(slider)
		slider.value_changed.connect(func(value:float):amount.text="炮弹 %d%%"%int(value))
		var identity:String=str(ship.id);var torps:bool=bool(ship.torpedoes)
		slider.drag_ended.connect(func(changed:bool):
			if changed:owner.notify(service.set_loadout(identity,int(slider.value),torps)))
		slider.focus_exited.connect(func():
			if int(owner.economy.state.owned[identity].ammo)!=int(slider.value):owner.notify(service.set_loadout(identity,int(slider.value),torps)))
		if bool(ship.has_torpedoes):
			var b:=Button.new();b.custom_minimum_size=Vector2(154,48);b.text="鱼雷：携带" if ship.torpedoes else "鱼雷：卸下 +4格";Design.apply_button(b);b.add_theme_font_size_override("font_size",17);bar.add_child(b)
			var carry:bool=not bool(ship.torpedoes)
			b.pressed.connect(func():owner.notify(service.set_loadout(identity,int(slider.value),carry));open_loadout(owner))
	_fuel_row(owner,rows,budget)
	view.get_node("Capacity").text="载货预算 %d 格  /  %d kg"%[int(budget.cells),int(budget.max_kg)]
	var done:Button=view.get_node("Complete");Design.apply_button(done,true);done.pressed.connect(owner.close_modal)
static func attach_search(owner)->void:
	var overlay=load("res://scenes/ui/cargo_search.tscn").instantiate();overlay.app=owner;owner.page.add_child(overlay)

static func _fuel_row(owner,rows:VBoxContainer,budget:Dictionary)->void:
	var fuel=load("res://scripts/fuel_service.gd").new(owner.economy)
	var fleet:Array=owner.economy.roster().filter(func(row):return owner.economy.formation.has(str(row.id)))
	var estimate:Dictionary=fuel.preview(fleet)
	var column:=VBoxContainer.new();column.name="FuelPreparation";column.add_theme_constant_override("separation",12);rows.add_child(column)
	var title:=Label.new();title.text="舰队油料 · %d吨位对应 %d单位/分钟"%[budget.ships.reduce(func(sum,row):return sum+int(row.tons),0),int(estimate.per_minute)];title.add_theme_color_override("font_color",Design.INK);title.add_theme_font_size_override("font_size",23);column.add_child(title)
	var amount:=Label.new();amount.add_theme_color_override("font_color",Design.MUTED);column.add_child(amount)
	var slider:=HSlider.new();slider.name="FuelLoadSlider";slider.min_value=1;slider.max_value=100;slider.step=1;slider.value=int(estimate.percent);slider.custom_minimum_size.y=46;column.add_child(slider)
	var update:=func(value:float):amount.text="装油 %d%% · %d单位 · 20节预计%.1f分钟 · 库存%d"%[int(value),maxi(1,int(ceil(int(estimate.capacity)*value/100.0))),12.0*value/100.0,int(owner.economy.state.wallet.fuel)]
	update.call(slider.value);slider.value_changed.connect(update)
	var save:=func():
		if int(owner.economy.state.get("fuel_load_percent",100))!=int(slider.value):owner.notify(fuel.configure(int(slider.value)))
	slider.drag_ended.connect(func(_changed:bool):save.call());slider.focus_exited.connect(save)
	var buy:=Button.new();buy.text="采购100单位油料 · 300银币";Design.apply_button(buy);buy.custom_minimum_size.y=48;column.add_child(buy)
	buy.pressed.connect(func():owner.notify(fuel.purchase(100));update.call(slider.value))
	var hint:=Label.new();hint.text="高速更耗油；停船保持低耗。新搜打撤油量耗尽后将失去推进力。";hint.add_theme_color_override("font_color",Design.MUTED);hint.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;column.add_child(hint)

