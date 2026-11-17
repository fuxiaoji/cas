@tool
extends Control
## Editable route points, scaled with the actual Control instead of fixed map photos.
signal node_selected(id:String)
const Design=preload("res://scripts/ui_design.gd")
const Content=preload("res://scripts/chapter_story_data.gd")
@export var route_points:PackedVector2Array=PackedVector2Array([Vector2(.08,.61),Vector2(.18,.43),Vector2(.30,.57),Vector2(.39,.38),Vector2(.48,.18),Vector2(.59,.27),Vector2(.69,.10),Vector2(.83,.21),Vector2(.93,.39),Vector2(.80,.53),Vector2(.67,.47),Vector2(.54,.63),Vector2(.42,.79),Vector2(.63,.88),Vector2(.80,.78),Vector2(.94,.91)])
var nodes:Array=[]
var current:=""
var selected:=""
var available:Dictionary={}
var all_nodes:Array=[]
var route_state:Dictionary={}
var page_index:int=0
const PAGE_SIZE:int=16
func bind(rows:Array,saved:Dictionary,picked:String)->void:
	all_nodes=rows;route_state=saved;current=str(saved.node);selected=picked
	for i in range(all_nodes.size()):
		if str(all_nodes[i].id)==picked:page_index=i/PAGE_SIZE;break
	_build_page()

func _build_page()->void:
	var pages:int=maxi(1,ceili(float(all_nodes.size())/PAGE_SIZE))
	page_index=clampi(page_index,0,pages-1)
	nodes=all_nodes.slice(page_index*PAGE_SIZE,mini(all_nodes.size(),(page_index+1)*PAGE_SIZE))
	var saved:Dictionary=route_state
	var picked:String=selected
	for child in get_children():remove_child(child);child.queue_free()
	available.clear()
	for i in range(nodes.size()):
		var row:Dictionary=nodes[i];var id:=str(row.id)
		var known:bool=str(Content.scene(current).get("kind",""))=="complete" or saved.seen.has(id) or id==current or saved.cleared.has(str(row.get("stage","")))
		available[id]=known
		var button:=Button.new();button.name="Route_"+id;button.set_meta("chapter_route_node",id)
		button.disabled=not known;button.tooltip_text=str(row.title) if known else "先完成前面的故事与行动"
		if known:button.icon=Design.icon_texture("target" if str(row.kind)=="battle" else "story")
		else:button.text="·";button.add_theme_font_size_override("font_size",33)
		button.expand_icon=true;button.add_theme_constant_override("icon_max_width",26);button.modulate=Color.WHITE
		var color:=Color("eac57a") if id==current else Color("28434c") if known else Color(0,0,0,0)
		for state in ["normal","hover","pressed","disabled"]:
			var style:=Design.box(color.lightened(.08) if state=="hover" else color,32,Color("f1cf8f") if id==picked else Color(.64,.78,.81,.55))
			style.set_border_width_all(3 if id==picked else 1 if known else 0);button.add_theme_stylebox_override(state,style)
		button.add_theme_color_override("icon_normal_color",Design.INK if id==current else Color("d1e4e6"));button.add_theme_color_override("icon_disabled_color",Color(.48,.56,.59))
		button.add_theme_color_override("font_disabled_color",Color(.65,.75,.78,.50))
		button.pressed.connect(func():node_selected.emit(id))
		add_child(button)
		var label:=Label.new();label.name="Label_"+id;label.text=str(row.title).trim_prefix("01 · ").trim_prefix("02 · ").trim_prefix("03 · ") if known else ""
		label.add_theme_font_override("font",Design.font(500 if id==current else 400));label.add_theme_font_size_override("font_size",18)
		label.add_theme_color_override("font_color",Color("e4eeee") if known else Color("889da5"));label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
		label.mouse_filter=Control.MOUSE_FILTER_IGNORE;add_child(label)
	if pages>1:
		var previous:=Button.new();previous.name="RoutePreviousPage";previous.text="‹";previous.tooltip_text="上一段航线";previous.disabled=page_index==0
		previous.pressed.connect(func():page_index-=1;_build_page());add_child(previous)
		var next:=Button.new();next.name="RouteNextPage";next.text="›";next.tooltip_text="下一段航线";next.disabled=page_index>=pages-1
		next.pressed.connect(func():page_index+=1;_build_page());add_child(next)
		var caption:=Label.new();caption.name="RoutePageNumber";caption.text="航线 %d / %d"%[page_index+1,pages];caption.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
		caption.add_theme_font_override("font",Design.font());caption.add_theme_font_size_override("font_size",18);caption.add_theme_color_override("font_color",Color("e4eeee"));add_child(caption)
	_layout();queue_redraw()
func _notification(what:int)->void:
	if what==NOTIFICATION_RESIZED:_layout();queue_redraw()
func _layout()->void:
	if has_node("RoutePreviousPage"):
		$RoutePreviousPage.position=Vector2(size.x-215,0);$RoutePreviousPage.size=Vector2(40,32)
		$RouteNextPage.position=Vector2(size.x-42,0);$RouteNextPage.size=Vector2(40,32)
		$RoutePageNumber.position=Vector2(size.x-175,0);$RoutePageNumber.size=Vector2(133,32)
	for i in range(mini(nodes.size(),route_points.size())):
		var center:Vector2=route_points[i]*size
		var id:=str(nodes[i].id)
		var button:Control=get_node_or_null("Route_"+id)
		if button==null:continue
		button.position=center-Vector2(27,27);button.size=Vector2(54,54)
		var label:Label=get_node("Label_"+id);label.position=center+Vector2(-100,32);label.size=Vector2(200,31)
func _draw()->void:
	# Quiet lighthouse rays suggest a fractured nautical chart, without hiding the art.
	var light:=Vector2(.49,.48)*size
	for endpoint in [Vector2(0,.05),Vector2(.15,1),Vector2(.9,0),Vector2(1,.66)]:
		draw_line(light,endpoint*size,Color(.62,.77,.82,.08),1.2,true)
	for i in range(1,mini(nodes.size(),route_points.size())):
		var from:=route_points[i-1]*size;var to:=route_points[i]*size
		var known:bool=bool(available.get(str(nodes[i].id),false))
		draw_line(from,to,Color("c8d9d6") if known else Color(.65,.76,.81,.25),2.0 if known else 1.0,true)
