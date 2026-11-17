@tool
extends Control
## F6 editable seed preview. This does not generate or modify battle physics.
const Terrain=preload("res://scripts/procedural_amphibious_terrain.gd")
@export var terrain_seed:int=4567:
	set(value):terrain_seed=value;queue_redraw()
@export_range(0,2,1) var detail:int=2:
	set(value):detail=value;queue_redraw()
var clock:float=0
var polygon:PackedVector2Array=[]
func _ready()->void:
	resized.connect(queue_redraw)
	_generate()
func _generate()->void:
	var random:=RandomNumberGenerator.new();random.seed=terrain_seed
	polygon.clear()
	for index in range(28):
		var angle:float=TAU*index/28;var radius:float=1+.10*sin(angle*3+terrain_seed)+random.randf_range(-.06,.06)
		polygon.append(Vector2(cos(angle)*430*radius,sin(angle)*270*radius))
func project(point:Vector2)->Vector2:return point*minf(size.x/1050,size.y/700)+size*.5
func _process(delta:float)->void:
	clock+=delta;queue_redraw()
func _draw()->void:
	_generate()
	draw_rect(Rect2(Vector2.ZERO,size),Color("287f8c"))
	Terrain.paint(self,polygon,project,terrain_seed,clock,detail)
