extends SceneTree
## Standalone GPU checks with a presentation-only fixture, never a player save.
const Scene=preload("res://scenes/ui/page_transition.tscn")
class FixtureRoster extends RefCounted:
	func roster() -> Array:return []
class FixtureApp extends Control:
	var screen:="outgoing"
	var page:Control
	var page_motion:=true
	var economy:=FixtureRoster.new()

var checks:=0
var failures:Array[String]=[]
var pictures:Array[String]=[]
var output:="res://../artifacts/godot/fullscreen-transition/"

func _initialize() -> void:call_deferred("run")
func check(ok:bool,message:String) -> void:
	checks+=1
	if not ok:failures.append(message);push_error(message)
func frame() -> void:
	await process_frame
	if DisplayServer.get_name()!="headless":await RenderingServer.frame_post_draw
func shot(name:String) -> Image:
	await frame()
	var image:Image=root.get_texture().get_image()
	var path:String=ProjectSettings.globalize_path(output+name+".png")
	check(image.save_png(path)==OK,"wrote "+name)
	pictures.append(path)
	return image
func same_pixel(first:Color,second:Color) -> bool:
	return absf(first.r-second.r)+absf(first.g-second.g)+absf(first.b-second.b)<.03

func run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	var app:=FixtureApp.new()
	app.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(app)
	var backdrop:=ColorRect.new()
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.color=Color("6b2344")
	app.add_child(backdrop);app.page=backdrop
	var transition=Scene.instantiate()
	app.add_child(transition)
	transition.full_screen_wipe=true
	transition.show_character=false
	await frame()
	check(transition.overlay!=null and transition.player.has_animation("cover_reveal"),"real scene has named editable overlay and animation")
	if DisplayServer.get_name()=="headless":
		transition.capture_previous(app,"incoming");app.screen="incoming"
		transition.play(app,app.page,"outgoing","incoming")
		check(not transition.is_busy() and not transition.overlay.visible,"headless route is immediate")
	else:
		for dimensions in [Vector2i(960,540),Vector2i(1280,720),Vector2i(1600,900),Vector2i(1440,720)]:
			root.size=dimensions
			await frame()
			for kind in 3:
				transition.preview_at(kind,.5)
				var covered_image:Image=await shot("%dx%d-style%d-covered"%[dimensions.x,dimensions.y,kind])
				var fully_covered:=true
				for point in [Vector2(.01,.01),Vector2(.5,.01),Vector2(.99,.01),Vector2(.01,.5),Vector2(.99,.5),Vector2(.01,.99),Vector2(.5,.99),Vector2(.99,.99),Vector2(.5,.5)]:
					var px:=Vector2i(Vector2(covered_image.get_size())*point)
					fully_covered=fully_covered and not same_pixel(covered_image.get_pixelv(px),backdrop.color)
				check(fully_covered,"all nine samples covered at %s style%d"%[dimensions,kind])
				transition.preview_at(kind,1.0)
				await frame()
				var revealed:Image=root.get_texture().get_image()
				check(same_pixel(revealed.get_pixelv(revealed.get_size()/2),backdrop.color),"endpoint entirely reveals new page")
		root.size=Vector2i(1280,720)
		await frame()
		for kind in 3:
			transition.preview_at(kind,.24)
			await shot("1280x720-style%d-covering"%kind)
			transition.preview_at(kind,.75)
			await shot("1280x720-style%d-revealing"%kind)
		transition.cancel()
		await frame()
		transition.capture_previous(app,"incoming")
		check(transition._snapshot!=null,"outgoing pixels captured without a world query")
		app.screen="incoming";backdrop.color=Color("d7a95d")
		transition.play(app,app.page,"outgoing","incoming")
		check(transition.is_busy() and transition.overlay.mouse_filter==Control.MOUSE_FILTER_STOP,"transient mask intercepts clicks while active")
		await create_timer(transition.duration*.56).timeout
		check(not transition.old_frame.visible and transition.old_frame.texture==null and transition._snapshot==null,"midpoint releases outgoing frame")
		await create_timer(transition.duration*.44+.16).timeout
		check(not transition.is_busy() and not transition.overlay.visible and transition.overlay.mouse_filter==Control.MOUSE_FILTER_IGNORE,"animation settles and releases input")
		transition.capture_previous(app,"second")
		app.page_motion=false
		transition.play(app,app.page,"incoming","second")
		check(not transition.is_busy() and transition._snapshot==null,"motion-off releases snapshot and cuts immediately")
		app.page_motion=true;app.set_meta("reduced_motion",true)
		transition.capture_previous(app,"second")
		transition.play(app,app.page,"incoming","second")
		check(not transition.overlay.visible,"reduced-motion preference cuts immediately")
		app.set_meta("reduced_motion",false)
		transition.capture_previous(app,app.screen)
		transition.play(app,app.page,app.screen,app.screen)
		check(not transition.is_busy(),"same-page refresh is immediate")
	var report:={"checks":checks,"failures":failures,"display":DisplayServer.get_name(),"pictures":pictures}
	var receipt_name:="receipt-headless.json" if DisplayServer.get_name()=="headless" else "receipt.json"
	var file:=FileAccess.open(output+receipt_name,FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"  "));file.close()
	print(JSON.stringify(report))
	app.queue_free();await process_frame
	quit(0 if failures.is_empty() else 1)
