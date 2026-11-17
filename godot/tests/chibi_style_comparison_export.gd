extends SceneTree
## Render existing, unmodified textures in a compact review panel.
func _initialize()->void:call_deferred("run")
func run()->void:
	root.content_scale_size=Vector2i(1200,430)
	root.content_scale_aspect=Window.CONTENT_SCALE_ASPECT_IGNORE
	root.min_size=Vector2i(1200,430)
	root.size=Vector2i(1200,430)
	var panel:=Control.new();root.add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var font:=load("res://assets/fonts/NotoSansSC.ttf") as Font
	var background:=ColorRect.new();background.color=Color("e9f2ef");panel.add_child(background)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var title:=Label.new();title.text="沿用上次的小人画法";title.position=Vector2(30,18)
	title.add_theme_font_override("font",font);title.add_theme_font_size_override("font_size",27)
	title.add_theme_color_override("font_color",Color("203e49"));panel.add_child(title)
	var rows:Array=[
		["旧版参照 · 弗莱彻","res://assets/characters/chibis-generated/ibs-u-usn-fletcher.png"],
		["旧版参照 · 阳炎","res://assets/characters/chibis/ibs-u-ijn-kagero.png"],
		["修正补图 · 中途岛","res://assets/characters/chibis-generated-2026-11-12-v3/ibs-u-usn-midway.png"],
		["修正补图 · 蒙森","res://assets/characters/chibis-generated-2026-11-12-v3/ibs-u-usn-monssen.png"]]
	for index in range(rows.size()):
		var picture:=TextureRect.new();picture.position=Vector2(30+index*292,76);picture.size=Vector2(264,254)
		picture.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;picture.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		picture.texture=load(rows[index][1]);panel.add_child(picture)
		var label:=Label.new();label.text=rows[index][0];label.position=Vector2(30+index*292,336);label.size=Vector2(264,34)
		label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;label.add_theme_font_override("font",font)
		label.add_theme_font_size_override("font_size",21);label.add_theme_color_override("font_color",Color("203e49"));panel.add_child(label)
	var note:=Label.new();note.text="本人立绘定身份，旧小人定比例与画法。";note.position=Vector2(30,388)
	note.add_theme_font_override("font",font);note.add_theme_font_size_override("font_size",17)
	note.add_theme_color_override("font_color",Color("4b6d74"));panel.add_child(note)
	await process_frame;await process_frame;await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../artifacts/godot/chibi-style-root/style-comparison.png"))
	panel.queue_free();await process_frame;quit()
