@tool
extends Node
## Harbor/title only. Wall time never reaches the simulation or account state.
signal period_changed(period: String)
const LightShader=preload("res://shaders/local_time_backdrop.gdshader")
@export_enum("Harbor","Title") var composition:int=0
@export_range(-1,23,1) var preview_hour:int=-1
@export_range(1,60,1) var refresh_seconds:float=10.0
var clock:Callable
var target:TextureRect
var material:ShaderMaterial
var period:String=""
var hour_value:float=12.0
var elapsed:float=0.0
var seconds:float=0.0
var animated:bool=true

static func period_for(hour:float)->String:
	if hour>=5.0 and hour<8.0:return "dawn"
	if hour>=8.0 and hour<16.5:return "day"
	if hour>=16.5 and hour<19.0:return "dusk"
	return "night"

func bind(backdrop:TextureRect,kind:int=0)->void:
	target=backdrop;composition=kind
	material=ShaderMaterial.new();material.shader=LightShader
	target.material=material
	refresh()

func local_hour()->float:
	if preview_hour>=0:return float(preview_hour)
	var current:Dictionary=clock.call() if clock.is_valid() else Time.get_datetime_dict_from_system(false)
	return float(current.get("hour",12))+float(current.get("minute",0))/60.0+float(current.get("second",0))/3600.0

func refresh()->void:
	if material==null:return
	hour_value=local_hour()
	var next:=period_for(hour_value)
	var changed:=period!=next
	period=next
	material.set_shader_parameter("local_hour",hour_value)
	material.set_shader_parameter("title_composition",composition==1)
	if changed:period_changed.emit(period)

func _process(delta:float)->void:
	if material==null:return
	if animated:seconds+=delta
	elapsed+=delta
	material.set_shader_parameter("motion_time",seconds)
	if elapsed>=refresh_seconds:
		elapsed=0.0;refresh()
