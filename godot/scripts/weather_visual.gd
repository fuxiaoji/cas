extends RefCounted
## Presentation-only easing. All targets come from the authorized seat observation.
const LOOKS := {
	"clear": {"cloud":.18,"rain":0.0,"fog":0.0,"overcast":0.0,"wind":8.0},
	"cloudy": {"cloud":.52,"rain":0.0,"fog":.035,"overcast":.24,"wind":12.0},
	"overcast": {"cloud":.88,"rain":0.0,"fog":.08,"overcast":.76,"wind":17.0},
	"rain": {"cloud":.96,"rain":.78,"fog":.13,"overcast":.86,"wind":24.0},
	"fog": {"cloud":.34,"rain":0.0,"fog":.68,"overcast":.43,"wind":5.0}}
var current: Dictionary = {}
var target: Dictionary = {}
var kind := "clear"
var elapsed := 0.0

func read(view: Dictionary) -> Dictionary:
	var environment: Dictionary = view.get("environment", {})
	var weather: Dictionary = view.get("weather", environment.get("weather", {}))
	var light: String = str(environment.get("light", "day"))
	var fallback := "rain" if bool(environment.get("precipitation", false)) else ("fog" if light == "day" and int(environment.get("visibility",100)) <= 10 else "clear")
	var next_kind := str(weather.get("kind", fallback))
	if not LOOKS.has(next_kind):
		next_kind = fallback
	var result: Dictionary = LOOKS[next_kind].duplicate()
	result["kind"] = next_kind
	result["night"] = 1.0 if light == "night" else (.4 if light == "twilight" else 0.0)
	result["roughness"] = clampf(float(environment.get("sea_state",2))/6.0,.12,1.0)
	# Native weather owns its transition clock and interpolated cloud/rain/fog fields.
	# No random weather or independent phase timer is allowed in this renderer.
	var next: String = str(weather.get("next", next_kind))
	var progress := clampf(float(weather.get("transition_progress",0.0)),0,1)
	if LOOKS.has(next):
		result["overcast"] = lerpf(float(result.overcast),float(LOOKS[next].overcast),progress)
	result["cloud"] = clampf(float(weather.get("cloud_cover",result.cloud)),0,1)
	result["rain"] = clampf(float(weather.get("rain_intensity",result.rain)),0,1)
	result["fog"] = clampf(float(weather.get("fog_density",result.fog)),0,1)
	result["wind"] = float(weather.get("visual_wind_speed",result.wind))
	result["heading"] = deg_to_rad(float(weather.get("visual_wind_heading_deg",65.0)))
	return result

func update(view: Dictionary, delta: float, paused: bool = false) -> void:
	target = read(view)
	kind = str(target.kind)
	if current.is_empty():
		current = target.duplicate()
		return
	if paused:
		return
	var blend := 1.0-exp(-delta*4.0)
	for key in ["cloud","rain","fog","overcast","wind","roughness","night"]:
		current[key] = lerpf(float(current[key]),float(target[key]),blend)
	current.heading = lerp_angle(float(current.heading),float(target.heading),blend)
	current.kind = kind
	elapsed += delta

func wind_vector() -> Vector2:
	return Vector2(sin(float(current.get("heading",0.0))),cos(float(current.get("heading",0.0))))
