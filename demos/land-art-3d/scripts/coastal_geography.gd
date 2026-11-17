extends RefCounted
## Shared metre-space data for the ART DEMO. Not production-core authority.
## Render detail, weather, tree density and camera scale cannot change this data.

const VERSION: String = "coastal-visual-demo-v2"
const AUTHORITY_SCOPE: String = "visual_demo"
const EXTENT_M: float = 360.0
var seed_value: int
var relief: FastNoiseLite = FastNoiseLite.new()
var detail: FastNoiseLite = FastNoiseLite.new()
var moisture: FastNoiseLite = FastNoiseLite.new()
var phase: float

func _init(map_seed: int = 714) -> void:
	seed_value = map_seed
	relief.seed = map_seed
	relief.frequency = .009
	relief.fractal_octaves = 4
	detail.seed = map_seed + 71
	detail.frequency = .035
	detail.fractal_octaves = 3
	moisture.seed = map_seed + 8197
	moisture.frequency = .024
	phase = float(posmod(map_seed, 31)) * .018

func coast_z(x: float) -> float:
	return -55.0 + 18.0 * sin(x*.016) + 9.0 * sin(x*.043+1.2) + relief.get_noise_2d(x, -170.0)*4.0

func land_distance(x: float, z: float) -> float:
	# Signed coastal proxy, in metres; not a claim of an exact Euclidean SDF.
	var rim: float = (1.0-Vector2((x+15.0)/275.0, (z-50.0)/245.0).length()) * 220.0
	rim += relief.get_noise_2d(x+1700.0,z)*3.0
	return minf(z-coast_z(x), rim)

func beach_access(x: float, z: float) -> float:
	if z > coast_z(x)+62.0: return 0.0
	var main: float = exp(-pow((x+15.0)/48.0, 4.0))
	var east_cove: float = exp(-pow((x-94.0)/15.0, 4.0))
	var west_cove: float = exp(-pow((x+214.0)/12.0, 4.0))
	return maxf(main, maxf(east_cove,west_cove))

func swamp_weight(x: float, z: float) -> float:
	var warp_x: float=detail.get_noise_2d(x+912.0,z)*11.0
	var warp_z: float=moisture.get_noise_2d(x,z-511.0)*15.0
	var west_pool: float=exp(-pow((x+170.0+warp_x)/34.0,2.0)-pow((z-138.0+warp_z)/39.0,2.0))
	var east_pool: float=exp(-pow((x+137.0-warp_z*.5)/28.0,2.0)-pow((z-115.0+warp_x)/44.0,2.0))
	return clampf(maxf(west_pool,east_pool)*1.18,0.0,1.0)

func river_x(z: float) -> float:
	return -134.0 + 12.0*sin(z*.027+phase) + 4.0*sin(z*.067)

func river_weight(x: float, z: float) -> float:
	return (1.0-smoothstep(4.0,14.0,absf(x-river_x(z)))) * smoothstep(-58.0,-35.0,z) * (1.0-smoothstep(135.0,162.0,z))

func river_level(z: float) -> float:
	return clampf((z+48.0)/180.0,0.0,1.0)*1.65 + .10

func water_level_at(x: float, z: float) -> float:
	if swamp_weight(x,z)>.25: return 1.82
	if river_weight(x,z)>.20: return river_level(z)+.12
	return -100.0

func height_at(x: float, z: float) -> float:
	var d: float = land_distance(x,z)
	if d<0.0:
		var bed: float = maxf(-27.0,d*.20+relief.get_noise_2d(x,z)*.5*clampf(-d/10.0,0.0,1.0))
		var shoal: float = exp(-pow((x+98.0)/25.0,2.0)-pow((z+115.0)/18.0,2.0))
		return lerpf(bed,-.80+detail.get_noise_2d(x,z)*.22,shoal*.96)
	var access: float = beach_access(x,z)
	var beach: float = minf(d,23.0)*.105
	var cliff: float = smoothstep(.3,7.0,d)*(11.0+7.0*(relief.get_noise_2d(x,z)*.5+.5))
	var base: float = lerpf(cliff,beach,access)
	var inland: float = maxf(d-22.0,0.0)*.028
	var east_massif: float = exp(-pow((x-201.0)/58.0,2.0)-pow((z-139.0)/83.0,2.0))*70.0
	var west_ridge: float = exp(-pow((x+197.0)/49.0,2.0)-pow((z-34.0)/64.0,2.0))*43.0
	var rear_ridge: float = exp(-pow((x+13.0)/110.0,2.0)-pow((z-242.0)/34.0,2.0))*36.0
	var ridge_detail: float = 1.0-absf(relief.get_noise_2d(x+912.0,z-613.0))
	var hills: float = (east_massif+west_ridge+rear_ridge)*(.72+ridge_detail*.28)
	var soften: float = smoothstep(8.0,32.0,d)
	var h: float = base+inland+(hills+relief.get_noise_2d(x,z)*3.1+detail.get_noise_2d(x,z)*.55)*soften
	# Broad low floodplain joins the river; small pools sit inside it rather
	# than excavating a circular, steep-sided crater into the existing hill.
	var floodplain: float=exp(-pow((x+158.0)/77.0,2.0)-pow((z-125.0)/79.0,2.0))
	h=lerpf(h,3.7+detail.get_noise_2d(x,z)*1.1,smoothstep(.10,.52,floodplain))
	# Small existing settlement pads; mountains and wetlands remain outside.
	var town: float = (1.0-smoothstep(56.0,92.0,absf(x)))*(1.0-smoothstep(86.0,112.0,z))
	h = lerpf(h,beach+inland,town*.96)
	var district: float = (1.0-smoothstep(78.0,103.0,absf(x+3.0)))*smoothstep(81.0,96.0,z)*(1.0-smoothstep(196.0,218.0,z))
	h = lerpf(h,6.2+(z-100.0)*.025,district)
	var fortification: float=(1.0-smoothstep(86.0,117.0,absf(x)))*smoothstep(184.0,200.0,z)*(1.0-smoothstep(236.0,273.0,z))
	h=lerpf(h,8.7+(z-200.0)*.018,fortification)
	var industrial: float = (1.0-smoothstep(52.0,82.0,absf(x-128.0)))*(1.0-smoothstep(47.0,74.0,absf(z-58.0)))*smoothstep(24.0,40.0,d)
	# Preserve the occupied home plots west of the connecting street. The
	# industrial earthworks must not raise one half of their existing slabs.
	industrial*=1.0-smoothstep(81.0,94.0,z)*(1.0-smoothstep(72.0,90.0,x))
	h = lerpf(h,8.0+(z-30.0)*.018,industrial)
	# River and bog are real low relief, not a coloured patch on a hill.
	var swamp: float = swamp_weight(x,z)
	var wet_floor: float = 1.62+detail.get_noise_2d(x,z)*1.9+moisture.get_noise_2d(x,z)*.65
	h = lerpf(h,wet_floor,smoothstep(.20,.62,swamp))
	h = lerpf(h,river_level(z)-.5,river_weight(x,z)*.97)
	return h

func slope_at(x: float, z: float) -> float:
	return Vector2((height_at(x+1.5,z)-height_at(x-1.5,z))/3.0,(height_at(x,z+1.5)-height_at(x,z-1.5))/3.0).length()

func biome_at(x: float, z: float) -> String:
	var d: float = land_distance(x,z)
	if d<0.0: return "sea"
	if swamp_weight(x,z)>.36: return "swamp"
	if river_weight(x,z)>.28: return "river"
	if d<17.0: return "sand" if beach_access(x,z)>.65 else "sea_cliff"
	if height_at(x,z)>29.0 or slope_at(x,z)>.70: return "mountain"
	if moisture.get_noise_2d(x,z)>.08: return "forest"
	return "grassland"

func landing_at(x: float, z: float, craft: String = "ordinary_boat") -> Dictionary:
	var d: float = land_distance(x,z)
	var access: float = beach_access(x,z)
	var slope: float = slope_at(x,z)
	var allowed: bool = d>=.5 and d<=15.0 and access>.70 and slope<.38
	if craft=="heavy_boat": allowed = allowed and access>.94
	if craft=="amphibious": allowed = d>=.5 and d<=18.0 and access>.56 and slope<.62
	return {"allowed":allowed,"shore_kind":"beach" if access>.65 else "cliff_or_rock",
		"slope":slope,"scope":AUTHORITY_SCOPE,"reason":"valid_demo_beach" if allowed else "no_safe_unload_surface"}

func snapshot_header() -> Dictionary:
	return {"version":VERSION,"authority_scope":AUTHORITY_SCOPE,"seed":seed_value,"units":"metres",
		"axes":"Godot X east / Z north; production adapter must map core XY explicitly",
		"bounds_m":[-EXTENT_M,-EXTENT_M,EXTENT_M,EXTENT_M],
		"note":"visual sample only; production landing/path/collision/AI not installed"}
