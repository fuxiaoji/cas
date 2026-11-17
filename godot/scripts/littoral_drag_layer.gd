extends Control
signal started(payload:Dictionary,point:Vector2)
signal moved(payload:Dictionary,point:Vector2)
signal dropped(payload:Dictionary,point:Vector2)
signal clicked(payload:Dictionary)
signal cancelled
signal map_pinch_requested(first_pointer:int,first_point:Vector2,second_pointer:int,second_point:Vector2)
var payload:Dictionary={}
var origin:Vector2
var point:Vector2
var pointer:int=-1
var dragging:bool=false
var ghost:PanelContainer
var scroll_container:ScrollContainer
var scrolling:bool=false
var scroll_origin:int=0
func _ready()->void:mouse_filter=Control.MOUSE_FILTER_IGNORE;set_process_input(true)
func _notification(what:int)->void:
	if what==NOTIFICATION_APPLICATION_FOCUS_OUT and not payload.is_empty():cancel()
func arm(value:Dictionary,at:Vector2,touch:int=-1)->void:
	if not payload.is_empty():return
	payload=value.duplicate();origin=at;point=at;pointer=touch;dragging=false;scrolling=false
	if is_instance_valid(scroll_container):scroll_origin=scroll_container.scroll_horizontal
func cancel()->void:
	if ghost!=null:ghost.queue_free();ghost=null
	payload.clear();dragging=false;scrolling=false;pointer=-1;cancelled.emit()
func _input(event:InputEvent)->void:
	if payload.is_empty():return
	# Global drag input owns the first touch. Hand both live positions back to
	# the map before clearing it, even if the drag ghost covers the second touch.
	if bool(payload.get("map_origin",false)) and pointer>=0 and event is InputEventScreenTouch and event.pressed and event.index!=pointer:
		map_pinch_requested.emit(pointer,point,event.index,event.position)
		cancel();get_viewport().set_input_as_handled();return
	if event is InputEventKey and event.pressed and event.keycode==KEY_ESCAPE:cancel();get_viewport().set_input_as_handled();return
	var moving:bool=false;var released:bool=false
	if pointer<0:
		if event is InputEventMouseMotion:point=event.position;moving=true
		elif event is InputEventMouseButton and not event.pressed and event.button_index==MOUSE_BUTTON_LEFT:point=event.position;released=true
	else:
		if event is InputEventScreenDrag and event.index==pointer:point=event.position;moving=true
		elif event is InputEventScreenTouch and event.index==pointer and not event.pressed:point=event.position;released=true
	if moving:
		if not dragging and origin.distance_to(point)>10:
			var delta:Vector2=point-origin
			if not scrolling and is_instance_valid(scroll_container) and scroll_container.get_global_rect().has_point(origin) and scroll_container.get_global_rect().has_point(point) and absf(delta.y)<=12 and absf(delta.x)>absf(delta.y)*1.35:scrolling=true
			if not scrolling:dragging=true;_ghost();started.emit(payload,point)
		if scrolling:
			scroll_container.scroll_horizontal=scroll_origin-int(point.x-origin.x);get_viewport().set_input_as_handled();return
		if dragging:
			ghost.position=point+Vector2(20,-96);moved.emit(payload,point);get_viewport().set_input_as_handled()
	if released:
		# A successful extraction can replace the battle scene in dropped.emit().
		# Consume this release while the layer still belongs to its viewport.
		get_viewport().set_input_as_handled()
		var value:Dictionary=payload.duplicate()
		if scrolling:pass
		elif dragging:dropped.emit(value,point)
		else:clicked.emit(value)
		cancel()
func _ghost()->void:
	ghost=PanelContainer.new();ghost.custom_minimum_size=Vector2(96,110);ghost.mouse_filter=Control.MOUSE_FILTER_IGNORE;add_child(ghost)
	var box:=VBoxContainer.new();ghost.add_child(box)
	var image:=TextureRect.new();image.custom_minimum_size=Vector2(90,78);image.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;image.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED;image.mouse_filter=Control.MOUSE_FILTER_IGNORE
	if payload.get("texture") is Texture2D:image.texture=payload.texture
	box.add_child(image)
	var label:=Label.new();label.text=str(payload.get("name","指令"));label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;label.add_theme_font_size_override("font_size",18);box.add_child(label)
