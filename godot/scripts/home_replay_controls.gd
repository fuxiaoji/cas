extends PanelContainer
## Editable replay controls; a slider drag submits one seek, not hundreds.
var app
var controller
var dragging:bool=false
var refresh_elapsed:float=0
@onready var play:Button=$Margin/Column/Row/Play
@onready var seek:HSlider=$Margin/Column/Seek
@onready var time:Label=$Margin/Column/Row/Time
func setup(owner_app,battle)->void:
	app=owner_app;controller=battle
	$Margin/Column/Row/Title.text=str(app.home_replay_session.record.get("title","岛屿攻防录像"))+" · 本地演练"
	seek.max_value=maxf(.1,controller.replay_duration)
	play.pressed.connect(func():app.running=not app.running;controller.update();_refresh())
	seek.drag_started.connect(func():dragging=true)
	seek.drag_ended.connect(func(_changed):dragging=false;controller.seek_littoral(seek.value);_refresh())
	seek.gui_input.connect(func(event):
		if event is InputEventKey and event.pressed and event.keycode in [KEY_LEFT,KEY_RIGHT,KEY_HOME,KEY_END]:_keyboard_seek.call_deferred())
	for rate in [1,2,4,8]:
		var b:=Button.new();b.text=str(rate)+"×";b.custom_minimum_size=Vector2(48,42);b.pressed.connect(func():app.speed=rate;controller.update();_refresh());$Margin/Column/Row.add_child(b)
	var leave:=Button.new();leave.text="退出回看";leave.custom_minimum_size=Vector2(112,42);leave.pressed.connect(app.close_home_replay);$Margin/Column/Row.add_child(leave)
	_refresh()
func _keyboard_seek()->void:controller.seek_littoral(seek.value);_refresh()
func _process(delta:float)->void:
	refresh_elapsed+=delta
	if refresh_elapsed>=.1:refresh_elapsed=0;_refresh()
func _refresh()->void:
	if controller==null:return
	play.text="暂停" if app.running else "播放"
	time.text="%02d:%02d / %02d:%02d"%[int(controller.replay_seconds)/60,int(controller.replay_seconds)%60,int(controller.replay_duration)/60,int(controller.replay_duration)%60]
	if not dragging:seek.set_value_no_signal(controller.replay_seconds)
