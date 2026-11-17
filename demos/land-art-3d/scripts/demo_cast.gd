extends Node3D
## Approved original SD frames in an isolated environment demo. No account or combat.
## Ground convention: X/Z plane, Y is height_at.call(x, z).

const MANIFEST: String = "res://assets/cast/cast-manifest.json"
const FOOT: Vector2 = Vector2(256.0, 368.0)
@export var display_height: float = 5.2
@export var walking_speed: float = 1.05
@export var wandering_distance: float = 3.2
var _height_at: Callable
var _cast: Array[Dictionary] = []
var _textures: Dictionary = {}
var _layout: Array[Vector3] = [Vector3(-4.2, 0.0, 18.0), Vector3(3.0, 0.0, 27.0), Vector3(-8.5, 0.0, 35.0)]
var _elapsed: float = 0.0

func set_layout(points: Array[Vector3]) -> void:
	if not points.is_empty(): _layout = points.duplicate()

func build(height_at: Callable) -> void:
	_height_at = height_at
	for row: Dictionary in _cast:
		(row["node"] as Node3D).queue_free()
	_cast.clear()
	if not FileAccess.file_exists(MANIFEST):
		push_warning("Demo cast manifest is missing")
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
	if not parsed is Dictionary: return
	var characters: Array = parsed.get("characters", [])
	for index: int in range(characters.size()):
		var entry: Dictionary = characters[index]
		if not bool(entry.get("approved", false)): continue
		var anchor: Node3D = Node3D.new()
		anchor.name = str(entry.get("id", "cast")) + "_" + str(entry.get("name", ""))
		add_child(anchor)
		var sprite: Sprite3D = Sprite3D.new()
		sprite.name = "ApprovedSD"
		sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		sprite.centered = false
		sprite.offset = Vector2(-FOOT.x,FOOT.y-384.0)
		sprite.pixel_size = display_height / maxf(1.0, float(entry.get("reference_height", 335.0)))
		sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		sprite.no_depth_test = false
		sprite.shaded = false
		sprite.double_sided = true
		sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
		sprite.alpha_scissor_threshold = 0.20
		sprite.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		anchor.add_child(sprite)
		var home: Vector3 = _layout[index % _layout.size()]
		home.y = _ground(home.x, home.z)
		anchor.position = home
		var row: Dictionary = {"node": anchor, "sprite": sprite, "entry": entry, "home": home, "index": index, "frame": -1, "time": 0.0, "pause": 1.2 + index * 1.1, "direction": 1.0, "target": home}
		_cast.append(row)
		_apply_frame(row, 0)
	set_process(true)

func _ground(x: float, z: float) -> float:
	return float(_height_at.call(x, z)) + 0.12 if _height_at.is_valid() else 0.12

func _apply_frame(row: Dictionary, index: int) -> void:
	var frames: Array = (row["entry"] as Dictionary).get("frames", [])
	if index < 0 or index >= frames.size(): return
	var frame: Dictionary = frames[index]
	var pivot: Array = frame.get("local_pivot", [256.0, 368.0])
	var sprite: Sprite3D = row["sprite"] as Sprite3D
	# Sprite3D uses upward Y: bottom is image_height - source_pivot_y.
	sprite.offset = Vector2(float(pivot[0]) - 512.0 if sprite.flip_h else -float(pivot[0]), float(pivot[1])-384.0)
	if int(row["frame"]) == index: return
	var path: String = str(frame.get("path", ""))
	if not _textures.has(path): _textures[path] = load(path) as Texture2D
	(row["sprite"] as Sprite3D).texture = _textures[path] as Texture2D
	row["frame"] = index

func _process(delta: float) -> void:
	_elapsed += delta
	for row: Dictionary in _cast:
		var actor: Node3D = row["node"] as Node3D
		var sprite: Sprite3D = row["sprite"] as Sprite3D
		row["time"] = float(row["time"]) + delta
		if float(row["pause"]) > 0.0:
			row["pause"] = float(row["pause"]) - delta
			var blinking: bool = fposmod(_elapsed + int(row["index"]) * 1.31, 4.4) > 4.23
			_apply_frame(row, 1 if blinking else 0)
			if float(row["pause"]) <= 0.0:
				var home: Vector3 = row["home"]
				row["target"] = home + Vector3(0.55, 0.0, 1.0).normalized() * wandering_distance * float(row["direction"])
				row["time"] = 0.0
			continue
		var goal: Vector3 = row["target"]
		var here: Vector2 = Vector2(actor.position.x, actor.position.z)
		var there: Vector2 = Vector2(goal.x, goal.z)
		var next: Vector2 = here.move_toward(there, walking_speed * delta)
		actor.position = Vector3(next.x, _ground(next.x, next.y), next.y)
		# Horizontal mirror keeps the packaged, centered foot pivot unchanged.
		sprite.flip_h = float(row["direction"]) < 0.0
		_apply_frame(row, 2 + posmod(int(float(row["time"]) * 7.0), 4))
		if next.distance_to(there) < 0.03:
			row["pause"] = 2.5 + int(row["index"]) * 0.7
			row["direction"] = -float(row["direction"])
			row["time"] = 0.0
