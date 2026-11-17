extends SceneTree
## Standalone component composition; not an image of a live battle.
const Token = preload("res://scripts/tactical_type_token.gd")
const Tutorial = preload("res://scenes/ui/littoral_drag_tutorial.tscn")
const OUTPUT: String = "C:/Users/fwj/AppData/Local/Temp/CAS-littoral-tutorial-components"

func _initialize() -> void:
	call_deferred("run")

func label(text: String, font_size: int = 18) -> Label:
	var node := Label.new()
	node.text = text
	node.add_theme_font_size_override("font_size", font_size)
	node.add_theme_color_override("font_color", Color("f8efd7"))
	return node

func shot(name: String) -> void:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUTPUT.path_join(name+".png"))

func run() -> void:
	if DisplayServer.get_name() == "headless":
		quit(0)
		return
	root.size = Vector2i(1280,720)
	root.content_scale_size = Vector2i(1280,720)
	root.title = "CAS · Tutorial Component Review"
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	var surface := Control.new()
	surface.theme = preload("res://scripts/ui_design.gd").theme()
	root.add_child(surface)
	surface.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color("32626a")
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	surface.add_child(bg)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var title: Label = label("战术类型兵牌 · 独立组件审美校验",28)
	title.position = Vector2(50,30)
	surface.add_child(title)
	var grid := GridContainer.new()
	grid.columns = 7
	grid.position = Vector2(50,100)
	grid.add_theme_constant_override("h_separation",32)
	grid.add_theme_constant_override("v_separation",30)
	surface.add_child(grid)
	for role: String in Token.ROLES:
		var column := VBoxContainer.new()
		column.custom_minimum_size = Vector2(130,100)
		grid.add_child(column)
		var token = Token.new()
		token.custom_minimum_size = Vector2(76,54)
		token.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		token.role = role
		column.add_child(token)
		var name: Label = label(Token.role_name(role),18)
		name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		column.add_child(name)
		var key: Label = label(role,12)
		key.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		key.modulate.a = .68
		column.add_child(key)
	var caption: Label = label("原创游戏化符号；借鉴军用兵牌的外框 / 功能语法，非 APP-6 合规实现",16)
	caption.position = Vector2(50,590)
	surface.add_child(caption)
	await shot("tactical-types-1280")
	var tutorial: Control = Tutorial.instantiate()
	surface.add_child(tutorial)
	tutorial.start_tutorial()
	tutorial.observe_state({"tick":0,"littoral":{"groups":[{"id":"mcp01","stage":"embarked","order":"hold","position":{"x":0,"y":0}}]}})
	tutorial.set_targets({"deploy_card":Rect2(80,510,125,65),"landing_zone":Rect2(770,340,155,90)})
	await create_timer(1.3).timeout
	await shot("tutorial-gesture-1280")
	root.size = Vector2i(960,540)
	root.content_scale_size = Vector2i(960,540)
	tutorial.set_targets({"deploy_card":Rect2(40,430,115,60),"landing_zone":Rect2(640,290,130,75)})
	await create_timer(.4).timeout
	await shot("tutorial-gesture-960")
	print("Component screenshots: "+OUTPUT)
	quit(0)
