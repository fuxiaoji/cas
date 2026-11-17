extends SceneTree
const Art=preload("res://scripts/character_art.gd")
class FixtureRoster extends RefCounted:
	var rows:Array=[]
	func roster()->Array:return rows
class FixtureApp extends Control:
	var page_motion:=true
	var economy:=FixtureRoster.new()
	var screen:="outgoing"
	var page:Control
var checks:=0
var failures:Array=[]
func check(value:bool,title:String)->void:
	checks+=1
	if not value:failures.append(title);push_error(title)
func _initialize()->void:call_deferred("run")
func run()->void:
	var output:="res://../artifacts/godot/restored-transition/"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	root.size=Vector2i(1600,900)
	var app:=FixtureApp.new();root.add_child(app)
	app.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var background:=ColorRect.new();background.color=Color("214f67");app.add_child(background);background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);app.page=background
	var catalog:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/ships.json"))
	for card in catalog.ships:
		if Art.projection(card).kind in ["generated_chibi","reference_sd"]:app.economy.rows.append(card)
	var transition=load("res://scenes/ui/page_transition.tscn").instantiate();app.add_child(transition);await process_frame
	# Retained optional lightweight mode; production now defaults to the anime fullscreen wipe.
	transition.full_screen_wipe=false;transition.duration=.42;transition.use_registered_cast=false
	transition.random.seed=20261112
	check(not transition.full_screen_wipe and is_equal_approx(transition.duration,.42),"explicit lightweight option retains short page fade")
	var counts:Dictionary={};var identities:Dictionary={}
	for sample in range(80):
		transition._pick_characters(app)
		var count:int=transition.actor_states.size();counts[count]=int(counts.get(count,0))+1
		check(count==3,"exactly three available SD characters are selected")
		var selected:Dictionary={}
		for state in transition.actor_states:selected[state.identity]=true;identities[state.identity]=true
		check(selected.size()==3,"three selected identities never repeat within one transition")
	check(identities.size()>70,"private cosmetic RNG preserves varied identities across transitions")
	check(transition.actor_pool.size()==3,"pool allocates only three actors")
	var poses:Array=[]
	for dimensions in [Vector2i(960,540),Vector2i(1280,720),Vector2i(1600,900),Vector2i(1600,720)]:
		root.size=dimensions;await process_frame
		transition._pick_characters(app);transition.preview_at(0,.42);await process_frame;await RenderingServer.frame_post_draw
		var phases:Dictionary={};var heights:Dictionary={};var delays:Dictionary={};var positions:Array=[]
		for state in transition.actor_states:
			phases[state.phase]=true;heights[state.amplitude_factor]=true;delays[state.delay]=true
			var rect:Rect2=state.sprite.get_global_rect();positions.append({"identity":state.identity,"height":rect.size.y,"rect":str(rect)})
			check(rect.position.x>=0 and rect.end.x<=root.get_visible_rect().size.x,"large actors stay inside the screen")
			check(rect.size.y>root.get_visible_rect().size.y*.22 and rect.size.y<root.get_visible_rect().size.y*.30,"actor height is visibly larger at every window size")
		check(phases.size()==3 and heights.size()==3 and delays.size()==3,"three actors retain different hops, amplitudes and delays")
		check(not transition.mask.visible and not transition.old_frame.visible,"restored preview never covers the page with clouds or an old screenshot")
		var image:Image=root.get_texture().get_image()
		check(image.save_png(ProjectSettings.globalize_path(output+"%dx%d-three-large-chibis.png"%[dimensions.x,dimensions.y]))==OK,"saved restored default three-character preview")
		check(image.get_pixel(15,15).is_equal_approx(background.color),"unobstructed page remains visible behind the three actors")
		poses.append({"window":[dimensions.x,dimensions.y],"actors":positions})
	transition.max_transition_characters=999
	for i in range(20):transition._pick_characters(app);check(transition.actor_states.size()==3,"old serialized twenty-person maximum is now capped at three")
	transition.max_transition_characters=3
	transition.cancel();transition.capture_previous(app,"incoming")
	check(transition._snapshot==null,"lightweight default retains no old screenshot")
	transition.play(app,app.page,"outgoing","incoming")
	check(transition.is_busy() and transition.overlay.mouse_filter==Control.MOUSE_FILTER_STOP and not transition.mask.visible,"short input barrier protects an already-built visible page")
	await create_timer(.2).timeout
	check(app.page.modulate.a>.55 and app.page.modulate.a<1.0,"new page actually eases in rather than using a full-screen cover")
	transition.capture_previous(app,"another");transition.play(app,app.page,"incoming","another")
	await create_timer(.5).timeout
	check(not transition.is_busy() and not transition.overlay.visible and is_equal_approx(app.page.modulate.a,1.0),"rapid navigation finishes cleanly with a fully visible page")
	transition.play(app,app.page,"incoming","another");transition.cancel()
	check(is_equal_approx(app.page.modulate.a,1.0) and transition.overlay.mouse_filter==Control.MOUSE_FILTER_IGNORE,"cancel restores page opacity and releases input")
	app.page_motion=false;transition.play(app,app.page,"incoming","another")
	check(not transition.is_busy() and not transition.overlay.visible,"motion off cuts immediately")
	app.page_motion=true;app.set_meta("reduced_motion",true);transition.play(app,app.page,"incoming","another")
	check(not transition.is_busy(),"reduced motion cuts immediately")
	app.set_meta("reduced_motion",false);transition.play(app,app.page,"incoming","incoming")
	check(not transition.is_busy(),"same route refresh does not replay decoration")
	app.economy.rows=app.economy.rows.slice(0,1);transition._pick_characters(app)
	check(transition.actor_states.size()==1,"small rosters use available authentic SD without inventing duplicates")
	app.economy.rows=[];transition._pick_characters(app)
	check(transition.actor_states.is_empty() and transition.actor_pool.all(func(sprite):return not sprite.visible),"empty roster has no invented character")
	transition.show_character=false;transition.preview_at(0,.5)
	check(transition.actor_pool.all(func(sprite):return not sprite.visible),"character-off hides every actor")
	transition.cancel();check(not transition.overlay.visible and not transition.is_busy(),"cancel releases overlay")
	var editable=load("res://scenes/ui/page_transition.tscn").instantiate()
	editable.duration=.37;editable.max_transition_characters=2;editable.character_height_fraction=.30;editable.full_screen_wipe=false
	var packed:=PackedScene.new()
	check(packed.pack(editable)==OK,"production transition remains a packable native scene")
	var copy_path:="user://tests/restored-transition-editable-%d.tscn"%OS.get_process_id()
	check(ResourceSaver.save(packed,copy_path)==OK,"inspector tuning saves to a scene copy")
	var reloaded=ResourceLoader.load(copy_path,"PackedScene",ResourceLoader.CACHE_MODE_IGNORE).instantiate()
	check(is_equal_approx(reloaded.duration,.37) and reloaded.max_transition_characters==2 and is_equal_approx(reloaded.character_height_fraction,.30) and not reloaded.full_screen_wipe,"duration, actor count, size and lightweight mode survive reload")
	check(reloaded.has_node("Overlay/Actor") and reloaded.has_node("Overlay/Timeline"),"native actor and animation timeline remain directly editable")
	editable.free();reloaded.free()
	var report:Dictionary={"checks":checks,"failures":failures,"passed":failures.is_empty(),"count_distribution":counts,"pool":transition.actor_pool.size(),"unique_selected_identities":identities.size(),"poses":poses}
	FileAccess.open(output+"receipt.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "));print("CHIBI_CROWD ",JSON.stringify(report))
	app.queue_free();await process_frame;quit(0 if failures.is_empty() else 1)
