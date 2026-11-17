extends RefCounted
## Shared visual vocabulary. Icons are original vector artwork, portraits use non-destructive crops.
const INK := Color("182f46")
const MUTED := Color("5e7182")
const PAPER := Color("f5f8fa")
const GOLD := Color("f2cf84")
const ACCENT := Color("23869a")
static var textures: Dictionary = {}
static var faces: Dictionary = {}

static func font(weight: int = 400) -> Font:
	if faces.has(weight): return faces[weight]
	var face := FontVariation.new()
	face.base_font = load("res://assets/fonts/NotoSansSC.ttf")
	face.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): float(weight)}
	faces[weight] = face
	return face

static func apply_overlay_button(button:Button) -> void:
	apply_button(button,false,true)
	for state in ["normal","hover","pressed","focus"]:
		var style:=box(Color(0.035,0.09,0.14,0.12 if state=="normal" else 0.68),3)
		if state=="focus":style.border_color=GOLD;style.set_border_width_all(1)
		style.content_margin_left=18;style.content_margin_right=18
		button.add_theme_stylebox_override(state,style)
	for color_key in ["font_color","font_hover_color","font_pressed_color","font_focus_color"]:button.add_theme_color_override(color_key,Color("eef0e9"))

static func panel_style() -> StyleBoxFlat:
	return box(Color(1.0,1.0,1.0,.94), 3)

static func apply_button(button: Button, primary := false, quiet := false) -> void:
	button.add_theme_font_override("font", font(600 if primary else 500))
	button.add_theme_font_size_override("font_size", 22)
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		var fill := GOLD if primary else Color(1.0,1.0,1.0,.92)
		if quiet and not primary: fill = Color(1.0,1.0,1.0,0.0)
		if state == "hover": fill = Color("f8dc9f") if primary else Color("dceef2")
		if state == "pressed": fill = Color("ddba6d") if primary else Color("c4dfe6")
		if state == "disabled": fill = Color("e1e7ec")
		var style := box(fill, 3)
		style.content_margin_left = 18
		style.content_margin_right = 18
		if state == "focus":
			style.border_color = ACCENT
			style.set_border_width_all(2)
		button.add_theme_stylebox_override(state, style)
	for key in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		button.add_theme_color_override(key, INK)
	button.add_theme_color_override("font_disabled_color", Color("7b8996"))
const PATHS := {
	"mail": '<path d="M5 10h38v28H5Z M5 11l19 15 19-15 M5 38l13-13 M43 38 30 25"/>',
	"sortie": '<path d="M24 5 39 39 24 31 9 39Z"/><path d="M24 5v26"/>',
	"fleet": '<path d="M7 30h34l-7 10H15Z M14 30V17h20v13 M21 17V8h6v9 M5 44h38"/>',
	"crew": '<circle cx="24" cy="15" r="8"/><path d="M9 41v-5c0-9 30-9 30 0v5 M8 14a7 7 0 0 0 0 14 M40 14a7 7 0 0 1 0 14"/>',
	"cargo": '<path d="m7 15 17-8 17 8v24l-17 6-17-6Z M7 15l17 8 17-8 M24 23v22 M15 11l18 8v10"/>',
	"supply": '<path d="M8 18h32v25H8Z M5 11h38v7H5Z M24 11v32 M24 11C10 12 10 1 18 5Z M24 11C38 12 38 1 30 5Z"/>',
	"recruit": '<path d="m24 4 5 14 15 6-15 5-5 15-5-15-15-5 15-6Z M38 4v9 M34 8h9"/>',
	"story": '<path d="M24 13C16 6 7 8 5 10v30c6-4 14-3 19 1 5-4 13-5 19-1V10c-5-3-13-2-19 3Z M24 13v28 M10 17h8 M30 17h8 M10 24h8 M30 24h8"/>',
	"training": '<path d="m4 17 20-9 20 9-20 9Z M12 22v12c6 7 18 7 24 0V22 M43 18v18"/>',
	"trophy": '<path d="M15 6h18v16c0 12-18 12-18 0Z M15 10H7v8c0 5 4 8 9 8 M33 10h8v8c0 5-4 8-9 8 M24 31v10 M15 43h18"/>',
	"archive": '<path d="M11 5h19l8 8v30H11Z M30 5v9h8 M18 22h13 M18 29h13 M18 36h8"/>',
	"gear": '<path d="m19 5-1 6-5 3-6-2-4 8 5 4v6l-4 4 5 8 6-2 5 3 1 4h9l1-6 5-3 6 2 4-8-5-4v-6l4-4-5-8-6 2-5-3-1-6Z"/><circle cx="25" cy="25" r="7"/>',
	"coin": '<circle cx="24" cy="24" r="18"/><path d="m24 12 9 12-9 12-9-12Z"/>',
	"ticket": '<path d="M7 12h34v8c-7 0-7 8 0 8v8H7v-8c7 0 7-8 0-8Z M28 13v5 M28 22v5 M28 31v4"/>',
	"ammo": '<path d="M10 41V18l6-10 6 10v23Z M28 41V18l6-10 6 10v23Z M10 32h12 M28 32h12"/>',
	"search": '<circle cx="20" cy="20" r="13"/><path d="m30 30 12 12"/>',
	"back": '<path d="m29 8-16 16 16 16"/>',
	"close": '<path d="m12 12 24 24 M12 36l24-24"/>',
	"check": '<path d="m8 25 10 10 23-23"/>',
	"sun": '<circle cx="24" cy="24" r="10"/><path d="M24 3v5 M24 40v5 M3 24h5 M40 24h5 M9 9l4 4 M35 35l4 4 M9 39l4-4 M35 13l4-4"/>',
	"compass": '<circle cx="24" cy="24" r="18"/><path d="m30 14-3 13-13 7 7-13Z M24 2v6 M24 40v6 M2 24h6 M40 24h6"/>',
	"repair": '<path d="m28 8 1 9 9 1 4-7c6 14-5 23-15 18L12 44 5 37l15-15C15 12 23 3 33 4Z"/>',
	"heart": '<path d="M24 40S4 28 4 16C4 3 20 3 24 13 28 3 44 3 44 16 44 28 24 40 24 40Z"/>',
	"shield": '<path d="m24 5 16 6v15c0 9-16 18-16 18S8 35 8 26V11Z M16 24l6 6 11-13"/>'
}

static func icon_texture(key: String) -> Texture2D:
	if textures.has(key): return textures[key]
	var svg := '<svg xmlns="http://www.w3.org/2000/svg" width="192" height="192" viewBox="0 0 48 48"><g fill="none" stroke="#ffffff" stroke-width="2.7" stroke-linecap="round" stroke-linejoin="round">%s</g></svg>' % str(PATHS.get(key, PATHS.compass))
	var bitmap := Image.new()
	if bitmap.load_svg_from_string(svg) != OK: return null
	textures[key] = ImageTexture.create_from_image(bitmap)
	return textures[key]

static func box(color: Color, radius := 3, border := Color(0, 0, 0, 0)) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(radius)
	style.border_color = border
	style.set_border_width_all(1 if border.a > 0 else 0)
	style.content_margin_left = 16
	style.content_margin_right = 16
	return style

static func theme() -> Theme:
	var result := Theme.new()
	result.default_font = font(400)
	result.default_font_size = 22
	result.set_font("font", "Button", font(500))
	result.set_font("font", "OptionButton", font(500))
	for type in ["Label", "Button", "OptionButton", "CheckButton", "CheckBox", "LineEdit", "TextEdit"]:
		result.set_color("font_color", type, INK)
		result.set_color("font_hover_color", type, INK)
		result.set_color("font_focus_color", type, INK)
		result.set_color("font_pressed_color", type, INK)
	for type in ["Button", "OptionButton", "LineEdit", "TextEdit"]:
		result.set_stylebox("normal", type, box(Color("ffffff"), 3))
		result.set_stylebox("hover", type, box(Color("dceef2"), 3))
		result.set_stylebox("pressed", type, box(Color("c4dfe6"), 3))
		result.set_stylebox("focus", type, box(Color(0,0,0,0), 3, ACCENT))
	result.set_stylebox("panel", "PopupMenu", box(PAPER, 3))
	result.set_color("font_color", "PopupMenu", INK)
	result.set_color("font_placeholder_color", "LineEdit", MUTED)
	result.set_color("caret_color", "LineEdit", INK)
	result.set_color("font_selected_color", "LineEdit", INK)
	result.set_color("selection_color", "LineEdit", Color("a9d6d4"))
	result.set_stylebox("hover", "PopupMenu", box(Color("d8eeeb"), 4))
	return result

static func crop(texture: Texture2D, portion := 0.56) -> AtlasTexture:
	var key := "%s:%s" % [texture.resource_path, portion]
	if textures.has(key): return textures[key]
	var atlas := AtlasTexture.new()
	atlas.atlas = texture
	var bounds := Rect2i(0, 0, texture.get_width(), texture.get_height())
	var bitmap := texture.get_image()
	if bitmap != null: bounds = bitmap.get_used_rect()
	atlas.region = Rect2(bounds.position, Vector2(bounds.size.x, bounds.size.y * portion))
	textures[key] = atlas
	return atlas
