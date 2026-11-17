@tool
extends CanvasLayer
## Full-screen anime cloud/iris/paper-sail cover and reveal, with three large hopping SD actors.
## Decorative legacy playback plus an explicit cover/prepare/reveal readiness barrier.
## UI time and a private RNG never enter the combat clock, commands, or authoritative state.
const Art=preload("res://scripts/character_art.gd")
const OverlayScene=preload("res://scenes/ui/page_transition_overlay.tscn")
const StrideShader=preload("res://shaders/transition_stride.gdshader")
signal covered
signal finished
signal loading_covered(generation:int)

@export_category("Full-screen transition")
@export var full_screen_wipe:bool=true:
	set(value):
		full_screen_wipe=value
		_refresh_editor_preview()
@export_enum("Random","Cloud wave","Circular iris","Paper sails") var style:int=0:
	set(value):
		style=value
		_refresh_editor_preview()
@export_range(.30,1.50,.01) var duration:float=1.18
@export var cloud_color:Color=Color("e4f3f1"):
	set(value):
		cloud_color=value
		_refresh_editor_preview()
@export var sea_color:Color=Color("3f829b"):
	set(value):
		sea_color=value
		_refresh_editor_preview()
@export var accent_color:Color=Color("f0cb85"):
	set(value):
		accent_color=value
		_refresh_editor_preview()
@export var show_character:bool=true:
	set(value):
		show_character=value
		_refresh_editor_preview()
@export var use_registered_cast:bool=true
@export var animate_stride:bool=true
@export var show_ground_shadow:bool=true:
	set(value):show_ground_shadow=value;_refresh_editor_preview()
@export_range(2,4,1) var hop_count:int=3:
	set(value):hop_count=value;_refresh_editor_preview()
@export_range(.06,.22,.01) var travel_distance_fraction:float=.14:
	set(value):travel_distance_fraction=value;_refresh_editor_preview()
@export_range(36.0,82.0,1.0) var hop_height:float=58.0:
	set(value):hop_height=value;_refresh_editor_preview()
@export_range(1,3,1) var max_transition_characters:int=3
@export_range(.18,.34,.01) var character_height_fraction:float=.26
@export_range(.05,.95,.005) var swap_fraction:float=.455
@export_category("Editor preview")
@export_range(0.0,1.0,.01) var editor_preview:float=.5:
	set(value):
		editor_preview=value
		_refresh_editor_preview()

var overlay:Control
var actor:TextureRect
var old_frame:TextureRect
var mask:ColorRect
var player:AnimationPlayer
var actor_pool:Array[TextureRect]=[]
var shadow_pool:Array[ColorRect]=[]
var actor_states:Array[Dictionary]=[]
var random:=RandomNumberGenerator.new()
var elapsed:=1.0
var serial:=0
var active_style:=0
var _snapshot:Texture2D
var _revealing:=false
var _busy:=false
var _page:WeakRef
var _loading_mode:bool=false
var _loading_phase:String=""
var _loading_phase_time:float=0
var _loading_motion_time:float=0
var _loading_ready:bool=false
var _loading_reduced:bool=false
var _covered_generation:int=-1
var loading_status:Control

func _ready() -> void:
	layer=30
	process_mode=Node.PROCESS_MODE_ALWAYS
	random.randomize()
	overlay=get_node_or_null("Overlay")
	if overlay==null:
		overlay=OverlayScene.instantiate()
		add_child(overlay)
	old_frame=overlay.get_node("OldFrame")
	mask=overlay.get_node("Mask")
	actor=overlay.get_node("Actor")
	_prepare_actor(actor)
	actor_pool=[actor]
	var shadow:ColorRect=overlay.get_node("ActorShadow")
	shadow_pool=[shadow]
	player=overlay.get_node("Timeline")
	loading_status=overlay.get_node("LoadingStatus")
	player.animation_finished.connect(_on_animation_finished)
	if not Engine.is_editor_hint():overlay.hide()
	_sync_material()
	_refresh_editor_preview()

func _refresh_editor_preview() -> void:
	if Engine.is_editor_hint() and is_instance_valid(player):
		preview_at(maxi(style-1,0),editor_preview)

func capture_previous(app,next:String) -> void:
	if Engine.is_editor_hint():return
	if not _enabled(app) or str(app.screen)==next or not is_instance_valid(app.page):
		cancel();return
	# The restored fade does not need an outgoing screenshot or a full-screen mask.
	if not full_screen_wipe:
		cancel();return
	# Snapshot contains only pixels already rendered for this player. No world-state query.
	if DisplayServer.get_name()=="headless":return
	if _busy:
		# A rapid replacement must not bake the previous trio into the next card.
		cancel();RenderingServer.force_draw()
	var rendered:Image=get_viewport().get_texture().get_image()
	if rendered!=null and not rendered.is_empty():_snapshot=ImageTexture.create_from_image(rendered)

func play(app,page:Control,previous:String,next:String) -> void:
	serial+=1
	var previous_snapshot:Texture2D=_snapshot
	cancel()
	if previous==next or not _enabled(app):
		return
	_snapshot=previous_snapshot if full_screen_wipe else null
	if full_screen_wipe and _snapshot==null:
		# No outgoing frame on initial launch, headless tests, or a detached preview.
		cancel();return
	old_frame.texture=_snapshot if full_screen_wipe else null
	old_frame.visible=full_screen_wipe
	mask.visible=full_screen_wipe
	_page=weakref(page)
	if not full_screen_wipe:page.modulate.a=.55
	active_style=random.randi_range(0,2) if style==0 else clampi(style-1,0,2)
	var requested:int=int(app.get_meta("transition_style",-1))
	if requested>=0:active_style=clampi(requested,0,2)
	_sync_material()
	(mask.material as ShaderMaterial).set_shader_parameter("reveal",false)
	_pick_characters(app)
	elapsed=0
	_revealing=false
	_busy=true
	overlay.mouse_filter=Control.MOUSE_FILTER_STOP
	overlay.show()
	player.play("cover_reveal",-1,_clip_length()/maxf(duration,.01))
	player.seek(0,true)

## Returns a generation token. Readiness belongs to this route, not elapsed time.
func begin_cover(app,previous:String,next:String)->int:
	var previous_snapshot:Texture2D=_snapshot
	cancel()
	_loading_mode=true;_loading_phase="cover";_loading_phase_time=0;_loading_motion_time=0;_loading_ready=false
	_loading_reduced=not bool(app.page_motion) or bool(app.get_meta("reduced_motion",false))
	_snapshot=previous_snapshot;old_frame.texture=_snapshot;old_frame.visible=_snapshot!=null
	active_style=random.randi_range(0,2) if style==0 else clampi(style-1,0,2)
	var requested:int=int(app.get_meta("transition_style",-1))
	if requested>=0:active_style=clampi(requested,0,2)
	_sync_material();mask.visible=true;mask.modulate=Color.WHITE
	(mask.material as ShaderMaterial).set_shader_parameter("reveal",false)
	(mask.material as ShaderMaterial).set_shader_parameter("coverage",1.0 if _loading_reduced else 0.0)
	_pick_characters(app)
	if _loading_reduced:
		for sprite in actor_pool:sprite.hide()
		for shadow in shadow_pool:shadow.hide()
	elapsed=0;_revealing=false;_busy=true
	overlay.modulate=Color.WHITE;overlay.mouse_filter=Control.MOUSE_FILTER_STOP;overlay.show()
	loading_status.visible=true;loading_status.set_reduced_motion(_loading_reduced)
	loading_status.set_status(0,"正在准备页面",false)
	return serial

func update_loading(progress:float,label:String,determinate:bool=true,generation:int=-1)->void:
	if not _loading_mode or not _busy or (generation>=0 and generation!=serial):return
	loading_status.set_status(clampf(progress,0,1),label,determinate)

## Safe before covered: records readiness, then reveals immediately after full cover.
func finish_loading(page:Control,generation:int=-1)->bool:
	if not _loading_mode or not _busy or (generation>=0 and generation!=serial):return false
	if not is_instance_valid(page):return false
	_page=weakref(page);page.modulate.a=1.0;_loading_ready=true
	if _loading_phase=="hold" and is_covered():_start_loading_reveal()
	return true

func is_covered()->bool:return _loading_mode and _covered_generation==serial
func is_loading_covered(generation:int=-1)->bool:return is_covered() and (generation<0 or generation==serial)
func is_current_generation(generation:int)->bool:return _loading_mode and _busy and serial==generation

func _start_loading_reveal()->void:
	if _loading_phase=="reveal":return
	_loading_phase="reveal";_loading_phase_time=0;_revealing=true
	(mask.material as ShaderMaterial).set_shader_parameter("reveal",true)
	loading_status.hide()

func _input(_event:InputEvent)->void:
	if _loading_mode and _busy:get_viewport().set_input_as_handled()

func _enabled(app) -> bool:
	return bool(app.page_motion) and not bool(app.get_meta("reduced_motion",false)) and DisplayServer.get_name()!="headless"

func _pick_characters(app) -> void:
	var previous:Array[String]=[]
	for state in actor_states:previous.append(str(state.get("identity","")))
	actor_states.clear()
	for sprite in actor_pool:sprite.hide()
	for shadow in shadow_pool:shadow.hide()
	if not show_character:return
	var candidates:Array[Dictionary]=[]
	var seen:Dictionary={}
	var cast:Array=app.economy.roster().duplicate()
	if use_registered_cast:
		var catalog:Variant=JSON.parse_string(FileAccess.get_file_as_string("res://data/ships.json"))
		if catalog is Dictionary:cast.append_array(catalog.get("ships",[]))
	var registry_value:Variant=app.get("cards")
	var registry:Dictionary=registry_value if registry_value is Dictionary else {}
	for raw:Dictionary in cast:
		var card:Dictionary=Art.visual_card(raw,registry)
		var info:Dictionary=Art.projection(card)
		var path:=str(info.get("path",""))
		var identity:=str(card.get("characterId",card.get("id",path)))
		if info.kind in ["generated_chibi","reference_sd"] and not path.is_empty() and not seen.has(identity):
			seen[identity]=true
			candidates.append({"path":path,"identity":identity})
	if candidates.is_empty():return
	# Use different faces on consecutive page changes when the roster permits it.
	# This private presentation choice never consumes the simulation random stream.
	var count:=mini(clampi(max_transition_characters,1,3),candidates.size())
	var fresh:Array[Dictionary]=[]
	for candidate in candidates:
		if str(candidate.identity) not in previous:fresh.append(candidate)
	if fresh.size()>=count:candidates=fresh
	for i in range(candidates.size()-1,0,-1):
		var j:=random.randi_range(0,i)
		var swap:Dictionary=candidates[i]
		candidates[i]=candidates[j]
		candidates[j]=swap
	for i in count:
		var sprite:=_actor_at(i)
		var shadow:ColorRect=_shadow_at(i)
		var selection:Dictionary=candidates[i]
		sprite.texture=Art.texture(str(selection.path))
		sprite.show()
		actor_states.append({
			"identity":str(selection.identity),
			"path":str(selection.path),
			"sprite":sprite,
			"shadow":shadow,
			"slot":i,
			"count":count,
			"phase":random.randf_range(0.0,TAU),
			"speed":random.randf_range(.72,1.58),
			"delay":.035+float(i)*.035+random.randf_range(-.006,.006),
			"height_factor":random.randf_range(.94,1.03),
			"amplitude_factor":random.randf_range(.92,1.12),
			"x_jitter":random.randf_range(-.08,.08),
			"y_offset":random.randf_range(-.015,.015),
			"rotation":random.randf_range(-.04,.04),
			"motion_end":.90+float(i)*.025+random.randf_range(-.004,.004)
		})

## Retained as a compatibility entry point for the original single-actor review fixture.
func _pick_character(app) -> void:
	_pick_characters(app)

func _actor_at(index:int) -> TextureRect:
	while actor_pool.size()<=index:
		var sprite:=TextureRect.new()
		sprite.name="Actor%02d"%actor_pool.size()
		sprite.mouse_filter=Control.MOUSE_FILTER_IGNORE
		sprite.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
		sprite.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		_prepare_actor(sprite)
		overlay.add_child(sprite)
		overlay.move_child(sprite,overlay.get_node("Timeline").get_index())
		actor_pool.append(sprite)
	return actor_pool[index]

func _prepare_actor(sprite:TextureRect)->void:
	if sprite.material==null:
		var material:=ShaderMaterial.new();material.shader=StrideShader;sprite.material=material

func _shadow_at(index:int)->ColorRect:
	while shadow_pool.size()<=index:
		var shadow:ColorRect=shadow_pool[0].duplicate()
		shadow.name="ActorShadow%02d"%shadow_pool.size();overlay.add_child(shadow)
		overlay.move_child(shadow,overlay.get_node("Actor").get_index())
		shadow_pool.append(shadow)
	return shadow_pool[index]

func _sync_material() -> void:
	if not is_instance_valid(mask) or not mask.material is ShaderMaterial:return
	var material:ShaderMaterial=mask.material
	material.set_shader_parameter("style",active_style)
	material.set_shader_parameter("cloud_color",cloud_color)
	material.set_shader_parameter("sea_color",sea_color)
	material.set_shader_parameter("accent_color",accent_color)

func _process(_delta:float) -> void:
	if Engine.is_editor_hint() or not _busy:return
	if _loading_mode:
		_process_loading(_delta);return
	var phase:=player.current_animation_position/_clip_length()
	elapsed=phase*duration
	if not full_screen_wipe and _page!=null:
		var page:Control=_page.get_ref()
		if is_instance_valid(page):page.modulate.a=lerpf(.55,1.0,1.0-pow(1.0-clampf(phase,0,1),3))
	if not _revealing and phase>=swap_fraction:
		_revealing=true
		old_frame.hide()
		old_frame.texture=null
		_snapshot=null
		(mask.material as ShaderMaterial).set_shader_parameter("reveal",true)
		covered.emit()
	_update_actor(phase)

func _process_loading(delta:float)->void:
	var generation:int=serial
	_loading_phase_time+=delta;_loading_motion_time+=delta;elapsed+=delta
	var material:ShaderMaterial=mask.material
	if _loading_phase=="cover":
		var progress:float=clampf(_loading_phase_time/(.10 if _loading_reduced else maxf(.05,duration*swap_fraction)),0,1)
		material.set_shader_parameter("coverage",1.0 if _loading_reduced else progress)
		mask.modulate.a=progress if _loading_reduced else 1.0
		if progress>=1:
			_loading_phase="hold";_loading_phase_time=0
			old_frame.hide();old_frame.texture=null;_snapshot=null
			_announce_loading_cover(generation)
	elif _loading_phase=="hold":
		material.set_shader_parameter("coverage",1.0);mask.modulate.a=1.0
	elif _loading_phase=="reveal":
		var progress:float=clampf(_loading_phase_time/(.10 if _loading_reduced else maxf(.05,duration*(1.0-swap_fraction))),0,1)
		material.set_shader_parameter("coverage",1.0 if _loading_reduced else 1.0-progress)
		mask.modulate.a=1.0-progress if _loading_reduced else 1.0
		if progress>=1:
			cancel();finished.emit();return
	if not _loading_reduced:_update_loading_actors()

func _announce_loading_cover(generation:int)->void:
	# The opaque cover must have reached the GPU before a caller can do heavy
	# synchronous page construction; setting a uniform alone is not a drawn frame.
	if DisplayServer.get_name()=="headless":await get_tree().process_frame
	else:await RenderingServer.frame_post_draw
	if generation!=serial or not _loading_mode or not _busy:return
	_covered_generation=generation;covered.emit()
	if generation!=serial or not _loading_mode:return
	loading_covered.emit(generation)
	if generation!=serial or not _loading_mode:return
	if _loading_ready and _loading_phase=="hold":_start_loading_reveal()

func _update_loading_actors()->void:
	var viewport_size:Vector2=get_viewport().get_visible_rect().size
	var unit:float=clampf(viewport_size.y/900.0,.6,2.5)
	for state in actor_states:
		var sprite:TextureRect=state.sprite
		if sprite.texture==null:continue
		var local_time:float=maxf(0,_loading_motion_time-float(state.delay))
		var trip_duration:float=maxf(.95,duration)*float(state.get("speed",1.0))*.85
		var trip:int=int(floor(local_time/trip_duration));var local_t:float=fposmod(local_time,trip_duration)/trip_duration
		var hops:int=clampi(hop_count,2,4);var cycle:float=local_t*hops;var step:int=mini(int(floor(cycle)),hops-1);var beat:float=cycle-step
		var air:float=clampf((beat-.16)/.64,0,1);var hop:float=4*air*(1-air);var advance:float=air*air*(3-2*air)
		var travel:float=(step+advance)/float(hops)
		if trip%2==1:travel=1-travel
		var count:int=maxi(int(state.count),1);var cell_width:float=minf(viewport_size.x*.17,viewport_size.y*.31)
		var height:float=minf(viewport_size.y*character_height_fraction*float(state.height_factor),cell_width*.95)
		sprite.size=sprite.texture.get_size()*(height/maxf(sprite.texture.get_height(),1))
		var center:=Vector2(viewport_size.x*(.5-float(count-1)*.125-travel_distance_fraction*.5+int(state.slot)*.25+travel_distance_fraction*travel),viewport_size.y*(.81+float(state.y_offset)))
		sprite.pivot_offset=Vector2(sprite.size.x*.5,sprite.size.y*.94);sprite.position=center-sprite.pivot_offset-Vector2(0,hop*hop_height*unit*float(state.amplitude_factor))
		var compression:float=sin(PI*clampf(beat/.16,0,1))*.55 if beat<=.16 else sin(PI*clampf((beat-.80)/.20,0,1)) if beat>=.80 else 0.0
		sprite.rotation=sin(air*TAU)*.055 if beat>.16 and beat<.8 else 0
		sprite.scale=Vector2(1+compression*.10-hop*.035,1-compression*.12+hop*.055)
		var alpha:float=clampf(_loading_motion_time/.08,0,1)
		if _loading_phase=="reveal":alpha*=clampf(1-_loading_phase_time/maxf(.05,duration*(1-swap_fraction)),0,1)
		sprite.modulate.a=alpha
		if sprite.material is ShaderMaterial:
			sprite.material.set_shader_parameter("stride_phase",air*TAU+float(state.phase)*.08 if animate_stride else 0)
			sprite.material.set_shader_parameter("airborne",hop if animate_stride else 1)
			sprite.material.set_shader_parameter("stride_strength",1.0 if animate_stride else 0.0)
		var shadow:ColorRect=state.shadow;shadow.visible=show_ground_shadow;shadow.size=Vector2(sprite.size.x*.42*(1-hop*.22),11*unit);shadow.position=center+Vector2(0,4*unit)-shadow.size*.5;shadow.modulate.a=alpha*(1-hop*.48)
		state["grounded"]=not (beat>.16 and beat<.8);state["foot_position"]=center-Vector2(0,hop*hop_height*unit);state["hop_height_pixels"]=hop*hop_height*unit;state["travel_progress"]=travel

func _clip_length() -> float:
	return maxf(player.get_animation("cover_reveal").length,.01)

func _update_actor(t:float) -> void:
	var viewport_size:Vector2=get_viewport().get_visible_rect().size
	if actor_states.is_empty():
		if not actor.visible:return
		actor_states=[{"sprite":actor,"slot":0,"count":1,"phase":0.0,"speed":1.0,"delay":0.0,"height_factor":1.0,"amplitude_factor":1.0,"x_jitter":0.0,"y_offset":0.0,"rotation":0.0}]
	for state in actor_states:
		var sprite:TextureRect=state.sprite
		if t<0.0 or t>1.0 or sprite.texture==null:
			sprite.modulate.a=0.0
			continue
		var local_t:float=clampf((t-float(state.delay))/maxf(float(state.get("motion_end",.94))-float(state.delay),.01),0.0,1.0)
		var count:int=maxi(int(state.count),1)
		var cell_width:=minf(viewport_size.x*.17,viewport_size.y*.31)
		var target_height:=viewport_size.y*clampf(character_height_fraction,.18,.34)*float(state.height_factor)
		target_height=minf(target_height,cell_width*.95)
		var texture_size:=sprite.texture.get_size()
		sprite.size=texture_size*(target_height/maxf(texture_size.y,1.0))
		# Feet stay planted through anticipation and landing. Horizontal travel is
		# accumulated only during each short airborne arc, never a screen-wide slide.
		var hops:int=clampi(hop_count,2,4)
		var cycle:float=local_t*float(hops)
		var step_index:int=mini(int(floor(cycle)),hops-1)
		var beat:float=cycle-float(step_index)
		var air:float=clampf((beat-.16)/.64,0.0,1.0)
		var airborne:bool=beat>.16 and beat<.80
		var hop:float=4.0*air*(1.0-air)
		var advance:float=air*air*(3.0-2.0*air)
		var travel:float=(float(step_index)+advance)/float(hops)
		var spacing:float=.25 if count==3 else .34
		var start:float=.5-float(count-1)*spacing*.5-travel_distance_fraction*.5+float(state.slot)*spacing
		var center_x:float=viewport_size.x*(start+travel_distance_fraction*travel)+cell_width*float(state.x_jitter)*.15
		var center_y:float=viewport_size.y*(.81+float(state.y_offset))
		var unit:=clampf(viewport_size.y/900.0,.6,2.5)
		var amplitude:float=hop_height*unit*float(state.amplitude_factor)
		sprite.pivot_offset=Vector2(sprite.size.x*.5,sprite.size.y*.94)
		sprite.position=Vector2(center_x,center_y)-sprite.pivot_offset+Vector2(0,-hop*amplitude)
		var compression:float=sin(PI*clampf(beat/.16,0.0,1.0))*.55 if beat<=.16 else sin(PI*clampf((beat-.80)/.20,0.0,1.0)) if beat>=.80 else 0.0
		sprite.rotation=float(state.rotation)*.35+sin(air*TAU)*.055 if airborne else float(state.rotation)*.35
		sprite.scale=Vector2(1.0+compression*.10-hop*.035,1.0-compression*.12+hop*.055)
		if sprite.material is ShaderMaterial and sprite.material.shader==StrideShader:
			sprite.material.set_shader_parameter("stride_phase",air*TAU+float(state.phase)*.08 if animate_stride else 0.0)
			sprite.material.set_shader_parameter("airborne",hop if animate_stride else 1.0)
			sprite.material.set_shader_parameter("stride_strength",1.0 if animate_stride else 0.0)
		sprite.modulate.a=clampf(minf(t/.08,(1.0-t)/.08),0.0,1.0)
		var shadow:ColorRect=state.get("shadow",shadow_pool[0])
		shadow.visible=show_ground_shadow and show_character
		shadow.size=Vector2(sprite.size.x*.42*(1.0-hop*.22),11.0*unit*(1.0-hop*.10))
		shadow.position=Vector2(center_x,center_y+4.0*unit)-shadow.size*.5
		shadow.modulate.a=sprite.modulate.a*(1.0-hop*.48)
		state["grounded"]=not airborne
		state["hop_height_pixels"]=hop*amplitude
		state["step_index"]=step_index
		state["travel_progress"]=travel
		state["foot_position"]=Vector2(center_x,center_y-hop*amplitude)

func _on_animation_finished(animation:StringName) -> void:
	if animation==&"cover_reveal" and not _loading_mode and _busy:
		cancel()
		finished.emit()

func cancel() -> void:
	serial+=1
	_busy=false
	_loading_mode=false;_loading_phase="";_loading_ready=false;_covered_generation=-1
	if _page!=null:
		var page:Control=_page.get_ref()
		if is_instance_valid(page):page.modulate.a=1.0
	_page=null
	_snapshot=null
	if is_instance_valid(player):player.stop()
	if is_instance_valid(old_frame):old_frame.texture=null
	if is_instance_valid(loading_status):loading_status.hide()
	if is_instance_valid(mask):mask.modulate=Color.WHITE
	if is_instance_valid(overlay):
		overlay.hide()
		overlay.mouse_filter=Control.MOUSE_FILTER_IGNORE

func is_busy() -> bool:return _busy

## The F6 demo and visual QA can preview a frame without starting a route or changing account data.
func preview_at(style_index:int,time_fraction:float,previous_texture:Texture2D=null) -> void:
	_loading_mode=false
	if is_instance_valid(loading_status):loading_status.hide()
	active_style=clampi(style_index,0,2)
	_sync_material()
	_busy=false
	overlay.show()
	mask.visible=full_screen_wipe
	overlay.mouse_filter=Control.MOUSE_FILTER_IGNORE
	old_frame.texture=previous_texture
	old_frame.visible=previous_texture!=null and time_fraction<swap_fraction
	(mask.material as ShaderMaterial).set_shader_parameter("reveal",time_fraction>=swap_fraction)
	player.play("cover_reveal")
	player.pause()
	player.seek(clampf(time_fraction,0,1)*_clip_length(),true)
	for sprite in actor_pool:sprite.visible=show_character and (sprite==actor or actor_states.any(func(state):return state.sprite==sprite))
	for shadow in shadow_pool:shadow.visible=show_character and show_ground_shadow
	if not show_character:actor_states.clear()
	_update_actor(time_fraction)
