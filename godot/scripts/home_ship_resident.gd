@tool
extends Button
## Own-identity daily actor. Cosmetic time never mutates account or battle state.
const Daily=preload("res://scripts/home_daily_art.gd")
var card:Dictionary={}
var clock:float=0
var phase:float=0
var facing_left:bool=false
var greeting_until:float=-1
var neighbor_until:float=-1
var animation_state:String="idle"
var animation_time:float=0
var _previous_state:String=""
var _state_started:float=0
var moving:bool=true
var last_progress:float=0
var body_height:float=81
func _ready()->void:
	flat=true;mouse_filter=Control.MOUSE_FILTER_STOP;mouse_default_cursor_shape=Control.CURSOR_POINTING_HAND
	texture_filter=CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	for state in ["normal","hover","pressed","focus"]:add_theme_stylebox_override(state,StyleBoxEmpty.new())
	pressed.connect(greet)
func greet()->void:
	greeting_until=clock+2.8;queue_redraw()
func _gui_input(event:InputEvent)->void:
	if event is InputEventScreenTouch and not event.pressed:
		greet();accept_event()
func routine(time:float)->Dictionary:
	var local:float=fposmod(time+phase*9.71,54)
	var progress:float=0;var requested:String="idle";var walking:bool=false
	if local<15:progress=local/15;requested="walk";walking=true
	elif local<19:progress=1;requested="blink" if local>18.65 else "idle"
	elif local<22:progress=1;requested="wave"
	elif local<37:progress=1-(local-22)/15;requested="walk";walking=true
	elif local<41:requested="stretch"
	elif local<50:requested="sit"
	else:requested="blink" if local>53.65 else "idle"
	if time<maxf(greeting_until,neighbor_until):requested="wave";walking=false;progress=last_progress
	return {"progress":progress,"walking":walking,"facing_left":local>=22 and local<37,"state":requested}
func update_motion(time:float,left:bool,is_moving:bool=true)->void:
	clock=time;facing_left=left;moving=is_moving
	var scheduled:Dictionary=routine(clock);last_progress=float(scheduled.progress)
	var requested:String=str(scheduled.state)
	if not moving and requested=="walk":requested="idle"
	animation_state=Daily.state(card,requested)
	if animation_state!=_previous_state:_previous_state=animation_state;_state_started=clock
	animation_time=clock-_state_started;queue_redraw()
func _draw()->void:
	if card.is_empty():return
	var at:Vector2=Vector2(size.x*.5,size.y-6)
	draw_ellipse_shadow(at)
	var friendly:bool=clock<maxf(greeting_until,neighbor_until)
	# Each authored pose keeps its ground pivot; no portrait-shrinking fallback.
	if not Daily.paint(self,card,animation_state,animation_time,int(phase*100),body_height,at,facing_left):return
	if friendly:
		var center:Vector2=Vector2(size.x*.65,11)
		var tone:Color=Color("f8d777") if clock<greeting_until else Color("a9e1ed")
		draw_circle(center,8,tone)
		draw_line(center+Vector2(-3,0),center+Vector2(3,0),Color("34525f"),1.8)
		draw_line(center+Vector2(0,-3),center+Vector2(0,3),Color("34525f"),1.8)
	if has_focus():draw_arc(at-Vector2(0,3),22,0,TAU,24,Color("f8d777"),2)
func draw_ellipse_shadow(at:Vector2)->void:
	draw_set_transform(at,0,Vector2(1,.3));draw_circle(Vector2.ZERO,18,Color(0,.12,.16,.22));draw_set_transform(Vector2.ZERO)
