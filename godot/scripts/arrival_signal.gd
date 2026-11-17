extends Control
## A short, quiet light crossing the sky. Cosmetic; the result already exists.
var elapsed := 0.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _process(delta: float) -> void:
	elapsed += delta
	queue_redraw()

func _draw() -> void:
	var progress := clampf(elapsed / 1.8, 0.0, 1.0)
	var origin := size * Vector2(0.85, 0.12)
	var destination := size * Vector2(0.43, 0.54)
	var head := origin.lerp(destination, ease(progress, 0.7))
	for index in range(24):
		var fraction := float(index) / 24.0
		var behind := clampf(progress-fraction*0.18, 0, 1)
		var point := origin.lerp(destination, ease(behind, 0.7))
		draw_circle(point, (1-fraction)*6+1, Color(1,0.93,0.64,(1-fraction)*0.55),true,-1,true)
	for ring in range(8):
		draw_circle(head, 11+ring*7, Color(1,0.96,0.76,0.04*(1-progress*0.5)),true,-1,true)
	draw_circle(head, 4, Color("fffbed"),true,-1,true)
	var spread := smoothstep(0.65,1.0,progress)
	for index in range(28):
		var angle := float(index)*TAU/28.0
		var offset := Vector2(cos(angle),sin(angle))*(35+spread*240)
		draw_circle(head+offset, 1.5+sin(float(index))*0.7, Color(1,0.95,0.74,spread*0.65),true,-1,true)
