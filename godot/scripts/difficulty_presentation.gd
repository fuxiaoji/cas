extends RefCounted
const Scene=preload("res://scenes/ui/expedition_select.tscn")
static func render(app)->void:
	var screen:Control=Scene.instantiate()
	app.page.add_child(screen);screen.bind(app)
