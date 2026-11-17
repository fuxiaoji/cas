extends SceneTree
const Weather = preload("res://scripts/weather_visual.gd")
var checks := 0
var failures: Array[String] = []
func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
		push_error(description)
func _initialize() -> void:
	var model = Weather.new()
	var view := {"tick":220,"environment":{"light":"day","sea_state":2,"visibility":100,"precipitation":false},"weather":{"kind":"clear","next":"cloudy","transition_progress":.5,"cloud_cover":.35,"rain_intensity":.07,"fog_density":.04,"visual_wind_speed":13,"visual_wind_heading_deg":90}}
	var before := JSON.stringify(view)
	model.update(view,.1)
	check(is_equal_approx(model.current.cloud,.35),"native cloud interpolation used exactly")
	check(is_equal_approx(model.current.rain,.07),"native rain interpolation used exactly")
	check(is_equal_approx(model.current.fog,.04),"native fog interpolation used exactly")
	check(is_equal_approx(model.current.overcast,.12),"overcast follows native phase progress")
	check(is_equal_approx(model.current.wind,13),"visual wind magnitude uses native field")
	check(model.wind_vector().distance_to(Vector2.RIGHT)<.001,"native north-based wind heading")
	var altered: Dictionary = view.duplicate(true)
	altered.weather.cloud_cover=.9
	model.update(altered,.1)
	check(model.current.cloud>.35 and model.current.cloud<.9,"weather has smooth frame response")
	var paused_state := JSON.stringify(model.current)
	model.update(altered,120.0,true)
	check(JSON.stringify(model.current)==paused_state,"pause freezes weather easing")
	model.update(altered,120.0,false)
	check(is_equal_approx(model.current.cloud,.9),"resume converges to authority")
	check(JSON.stringify(view)==before,"presentation never mutates observation")
	var historical := {"environment":{"light":"night","sea_state":4,"visibility":10,"precipitation":false}}
	var historical_before := JSON.stringify(historical)
	var fixed = Weather.new()
	fixed.update(historical,.1)
	var original: Dictionary = fixed.current.duplicate(true)
	fixed.update(historical,999999.0)
	check(fixed.current==original,"historical weather never cycles by wall time")
	check(fixed.current.night==1.0,"historical night remains night")
	check(fixed.current.fog==0.0,"night visibility is not invented fog")
	check(JSON.stringify(historical)==historical_before,"historical environment unchanged")
	for kind in Weather.LOOKS:
		var sample := view.duplicate(true)
		sample.weather={"kind":kind,"next":kind}
		check(model.read(sample).kind==kind,"supports "+str(kind))
	var path := ProjectSettings.globalize_path("res://../artifacts/godot/weather-motion")
	DirAccess.make_dir_recursive_absolute(path)
	var receipt := {"checks":checks,"failures":failures,"scope":"presentation-only easing; native transition and rules verified separately"}
	var file := FileAccess.open(path.path_join("presentation-test.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(receipt,"\t"))
	print(JSON.stringify(receipt))
	quit(0 if failures.is_empty() else 1)

