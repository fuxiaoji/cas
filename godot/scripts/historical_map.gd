extends RefCounted
## Original Web satellite chart, registered in world metres. No engine writes or authority access.
static var data: Dictionary = load_data()
static var texture: Texture2D

static func load_data() -> Dictionary:
	var source: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/historical-basemaps.json"))
	return source if source is Dictionary else {}

static func is_historical(view: Dictionary) -> bool:
	# campaign_mode also includes story/resource/event runs. Use the original
	# historical variant registry and explicit procedural-mode exclusions instead.
	return not view.has("chapter") and not view.has("salvage") and not view.has("tide") and data.get("historical_variants",[]).has(str(view.get("variant","")))

static func registration(view: Dictionary) -> Dictionary:
	return data.get("fields",{}).get(str(view.get("variant","")),{}) if is_historical(view) else {}

static func geo_to_world(view: Dictionary, lon: float, lat: float) -> Vector2:
	var field: Dictionary = registration(view)
	if field.is_empty(): return Vector2.INF
	var m_per_lon: float = 111320.0 * cos(deg_to_rad(float(field.lat_origin)))
	return Vector2((lon-float(field.lon_w))*m_per_lon,(lat-float(field.lat_origin))*110574.0)

static func world_bounds(view: Dictionary) -> Rect2:
	if registration(view).is_empty(): return Rect2()
	var bounds: Dictionary = data.bounds
	var north_west := geo_to_world(view,float(bounds.lon_w),float(bounds.lat_n))
	var south_east := geo_to_world(view,float(bounds.lon_e),float(bounds.lat_s))
	return Rect2(north_west,south_east-north_west)

static func screen_bounds(map: Control) -> Rect2:
	var bounds := world_bounds(map.view)
	if bounds.size == Vector2.ZERO: return Rect2()
	return Rect2(map.project(bounds.position),map.project(bounds.end)-map.project(bounds.position))

static func paint(map: Control) -> bool:
	if registration(map.view).is_empty(): return false
	if texture == null: texture = load(str(data.texture)) as Texture2D
	if texture == null: return false
	var dest := screen_bounds(map)
	var field := Rect2(map.project(Vector2(0,float(map.view.height))),map.project(Vector2(float(map.view.width),0))-map.project(Vector2(0,float(map.view.height))))
	var visible: Rect2 = dest.intersection(field).intersection(Rect2(Vector2.ZERO,map.size))
	if not visible.has_area(): return true
	# Exactly the same affine registration as BattleMap.tsx. Crop only the
	# visible portion; zoom, pan and recoil share the unit/world projection.
	var image_size := texture.get_size()
	var source := Rect2((visible.position-dest.position)/dest.size*image_size,visible.size/dest.size*image_size)
	map.draw_texture_rect_region(texture,visible,source,Color(1.3,1.3,1.3,1),false,true)
	map.draw_rect(visible,Color(8.0/255,37.0/255,51.0/255,.12))
	return true
