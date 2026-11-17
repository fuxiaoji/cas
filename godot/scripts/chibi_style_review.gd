extends Control
## Developer-only GPU review: compares registered sprites at a fixed 80px height.

const GENERATED_DIR := "res://assets/characters/chibis-generated-2026-11-12-v3"
const FLETCHER_STYLE := "res://assets/characters/chibis-generated/ibs-u-usn-fletcher.png"
const KAGERO_STYLE := "res://assets/characters/chibis/ibs-u-ijn-kagero.png"
const CELL_WIDTH := 232
const COLUMNS := 5
var icon_height := 80
var grid: GridContainer

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_review_grid()

func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	if event.keycode == KEY_1:
		icon_height = 80
		_build_review_grid()
	elif event.keycode == KEY_2:
		icon_height = 160
		_build_review_grid()

func _build_review_grid() -> void:
	for child in get_children():
		child.queue_free()
	var background := ColorRect.new()
	background.color = Color("172633")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_bottom", 8)
	add_child(margin)
	var columns := VBoxContainer.new()
	columns.add_theme_constant_override("separation", 4)
	margin.add_child(columns)
	var title := Label.new()
	title.text = "SD Sprite Review · 1 = 80 px · 2 = 160 px · CAS portrait vs generated SD"
	title.add_theme_font_size_override("font_size", 16)
	columns.add_child(title)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_child(scroll)
	grid = GridContainer.new()
	grid.columns = COLUMNS
	grid.add_theme_constant_override("h_separation", 2)
	grid.add_theme_constant_override("v_separation", 2)
	scroll.add_child(grid)
	_add_reference(grid, FLETCHER_STYLE, "OLD FLETCHER v2")
	_add_reference(grid, KAGERO_STYLE, "OLD KAGERO SD")
	var directory := DirAccess.open(GENERATED_DIR)
	if directory == null:
		push_warning("Generated SD review directory is missing: " + GENERATED_DIR)
		return
	var paths: Array[String] = []
	directory.list_dir_begin()
	var file_name := directory.get_next()
	while not file_name.is_empty():
		if not directory.current_is_dir() and file_name.to_lower().ends_with(".png"):
			paths.append(GENERATED_DIR.path_join(file_name))
		file_name = directory.get_next()
	directory.list_dir_end()
	paths.sort()
	for path in paths:
		var portrait_path := "res://assets/characters/portraits/" + path.get_file().get_basename() + ".webp"
		_add_character(grid, path, portrait_path, path.get_file().get_basename().to_upper())

func _add_reference(target_grid: GridContainer, path: String, caption: String) -> void:
	var texture := load(path) as Texture2D
	if texture == null:
		push_warning("Unable to load review sprite: " + path)
		return
	var tile := _make_tile(caption)
	var pair := HBoxContainer.new()
	pair.alignment = BoxContainer.ALIGNMENT_CENTER
	tile.add_child(pair)
	_add_picture(pair, texture, "STYLE")
	target_grid.add_child(tile)

func _add_character(target_grid: GridContainer, sd_path: String, portrait_path: String, caption: String) -> void:
	var sd_texture := load(sd_path) as Texture2D
	var portrait_texture := load(portrait_path) as Texture2D
	if sd_texture == null or portrait_texture == null:
		push_warning("Missing portrait or SD sprite for " + caption)
		return
	var tile := _make_tile(caption)
	var pair := HBoxContainer.new()
	pair.alignment = BoxContainer.ALIGNMENT_CENTER
	tile.add_child(pair)
	_add_picture(pair, portrait_texture, "PORTRAIT")
	_add_picture(pair, sd_texture, "SD")
	target_grid.add_child(tile)

func _make_tile(caption: String) -> VBoxContainer:
	var tile := VBoxContainer.new()
	tile.custom_minimum_size = Vector2(CELL_WIDTH, icon_height + 36)
	tile.add_theme_constant_override("separation", 1)
	var label := Label.new()
	label.text = caption
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 9)
	label.clip_text = true
	tile.add_child(label)
	return tile

func _add_picture(parent: HBoxContainer, texture: Texture2D, caption: String) -> void:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 0)
	var picture := TextureRect.new()
	picture.custom_minimum_size = Vector2(96, icon_height)
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	picture.texture = texture
	column.add_child(picture)
	var label := Label.new()
	label.text = caption
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 8)
	column.add_child(label)
	parent.add_child(column)
