@tool
extends Node2D
## Presentation only. The caller supplies public body observations and simulation time.
@export_file("*.png") var sheet_path:String="res://assets/tactical/sprites/MCP-034-sheet.png":
	set(value):sheet_path=value;_load_sheet();queue_redraw()
@export_range(24,90,1) var display_height:float=48:
	set(value):
		if is_equal_approx(display_height,value):return
		display_height=value;queue_redraw()
@export_range(0,11,1) var preview_frame:int=0:
	set(value):preview_frame=value;queue_redraw()
@export var preview_mode:bool=false:
	set(value):preview_mode=value;queue_redraw()
@export var preview_equipment:String="":
	set(value):preview_equipment=value;queue_redraw()
@export var defeat_hold_seconds:float=4.0
@export var persistent_defeat:bool=false
var texture:Texture2D
var equipment_texture:Texture2D
var identity:String=""
var entity_id:int=0
var friendly:bool=true
var kind:String="rifle"
var selected:bool=false
var hp_ratio:float=1
var clock:float=0
var phase:float=0
var moving:bool=false
var searching:bool=false
var facing_left:bool=false
var fire_until:float=-1
var fire_started:float=-1
var fire_duration:float=.34
var hurt_until:float=-1
var heal_until:float=-1
var defeated_at:float=-1
var frame_index:int=0
var state_name:String="idle"
var source_position:Vector2=Vector2.ZERO
var target_position:Vector2=Vector2.ZERO
var interpolation:float=1
var interpolation_seconds:float=.1
var primed:bool=false
var last_world_position:Vector2=Vector2.ZERO
var fallback_portrait:Texture2D
var role:String="infantry"
var token_script
var observation_tick:float=-1
var playback_rate:float=1
var animation_time:float=0
var anchor_data:Dictionary={}
static var texture_cache:Dictionary={}
static var anchor_catalogue:Dictionary={}
const TransportArt=preload("res://scripts/tactical_transport_art.gd")
const CasualtyArt=preload("res://scripts/tactical_casualty_art.gd")
const ArtV2=preload("res://scripts/tactical_art_v2.gd")
const AircraftArt=preload("res://scripts/littoral_aircraft_art.gd")
const WeaponBadge=preload("res://scripts/tactical_weapon_badge_v3.gd")
@export var art_v2:bool=false:
	set(value):art_v2=value;queue_redraw()
@export var preview_identity:String="MCP-088":
	set(value):preview_identity=value;queue_redraw()
@export_enum("idle","walk","fire","hurt","search","parachuting","defeated") var preview_action:String="idle":
	set(value):preview_action=value;queue_redraw()
var public_row:Dictionary={}
var compact_draw_key:Array=[]
var travel_heading:float=0
var target_heading:float=0
var motion_projector:Callable
var compact_mode:bool=false

func _ready()->void:
	texture_filter=CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_load_sheet()
	var path:String="res://assets/tactical/sprites/vehicle-equipment.png"
	if ResourceLoader.exists(path):equipment_texture=load(path)
	queue_redraw()

func _load_sheet()->void:
	if sheet_path.is_empty() or not ResourceLoader.exists(sheet_path):texture=null;return
	if not texture_cache.has(sheet_path):texture_cache[sheet_path]=load(sheet_path)
	texture=texture_cache[sheet_path]
	if anchor_catalogue.is_empty() and FileAccess.file_exists("res://data/tactical-sprite-anchors-v1.json"):
		var data:Variant=JSON.parse_string(FileAccess.get_file_as_string("res://data/tactical-sprite-anchors-v1.json"))
		if data is Dictionary:anchor_catalogue=data.get("atlases",{})
	anchor_data=anchor_catalogue.get(sheet_path,{})

func configure(row:Dictionary,path:String,height:float,portrait:Texture2D=null,unit_role:String="infantry")->void:
	identity=str(row.get("unit_id",""));entity_id=int(row.get("id",0));friendly=str(row.get("side","axis"))=="allies"
	kind=str(row.get("kind","rifle"));sheet_path=path;display_height=height;phase=fposmod(entity_id*.731,TAU);fallback_portrait=portrait;role=unit_role
	# A newly registered identity may be absent from an older voyage's catalogue.
	# During a missing SD import show her own face rather than an unidentified box.
	if path.is_empty() and fallback_portrait==null and not ArtV2.available(identity):
		var own:Dictionary=ArtV2.entry(identity)
		if not str(own.get("portrait","")).is_empty():fallback_portrait=ArtV2.texture(str(own.portrait))
	if ResourceLoader.exists("res://scripts/tactical_type_token.gd"):token_script=load("res://scripts/tactical_type_token.gd")

func observe(row:Dictionary,point:Vector2,tick:float,elapsed:float,is_searching:bool)->void:
	var previous_hp:float=float(public_row.get("hp",row.get("hp",0)))
	public_row=row
	var world:Vector2=Vector2(float(row.get("x",0)),float(row.get("y",0)))
	var displacement:Vector2=world-last_world_position
	var was_primed:bool=primed
	var new_time:bool=not primed or tick>observation_tick+.00001
	if not primed:
		position=point;source_position=point;target_position=point;primed=true
		animation_time=tick
	elif new_time and (point-target_position).length_squared()>.0001:
		source_position=position;target_position=point;interpolation=0
		if absf(displacement.x)>.05:facing_left=displacement.x<0
	if new_time:
		if identity=="MCP-306" and was_primed and elapsed>0 and elapsed<=.5 and float(row.get("hp",0))>previous_hp+1:
			heal_until=tick+.8
		moving=was_primed and displacement.length()>.01 and elapsed>0
		if str(row.get("equipment_version","")) in ["tactical-vehicles-v3","tactical-vehicles-v4"] and row.has("heading") and (not was_primed or displacement.length()<=.01):
			var bearing:float=deg_to_rad(float(row.heading))
			var direction:=Vector2(sin(bearing),cos(bearing))*100.0
			var projected:Vector2=motion_projector.call(world+direction)-motion_projector.call(world) if motion_projector.is_valid() else direction*Vector2(1,-1)
			if projected.length_squared()>.00001:target_heading=atan2(projected.x,-projected.y);travel_heading=target_heading
		if displacement.length()>.01 and was_primed:
			# An isometric camera rotates world north. Use the projected world
			# motion, without the crowd-separation offset, as the equipment bow.
			var delta_screen:Vector2=motion_projector.call(world)-motion_projector.call(last_world_position) if motion_projector.is_valid() else displacement*Vector2(1,-1)
			if delta_screen.length_squared()>.00001:target_heading=atan2(delta_screen.x,-delta_screen.y)
			if absf(delta_screen.x)>.05:facing_left=delta_screen.x<0
			if not moving:travel_heading=target_heading
		last_world_position=world;observation_tick=tick
	searching=is_searching
	hp_ratio=clampf(float(row.get("hp",0))/maxf(.001,float(row.get("max_hp",1))),0,1)
	interpolation_seconds=clampf(elapsed/maxf(.1,playback_rate),.012,.25);clock=maxf(clock,tick)
	_refresh()
func reproject(point:Vector2)->void:
	# A camera/map layout change is not a new world observation or an animation.
	position=point;source_position=point;target_position=point;interpolation=1

func fire(tick:float,target:Vector2,shot:Dictionary={})->void:
	if defeated_at>=0:return
	var precise:bool=str(public_row.get("equipment_version","")) in ["tactical-vehicles-v3","tactical-vehicles-v4"] and not shot.is_empty()
	var emitted:float=float(shot.get("tick",tick)) if precise else tick
	if emitted<fire_started:return
	fire_started=emitted;fire_duration=.34
	if precise:
		var family:String=str(shot.get("weapon_family_id",shot.get("weapon_id","")))
		fire_duration=.14 if family in ["smg","lmg","helicopter_cannon","autocannon"] else .24 if family in ["dmr","rifle","carbine","pistol"] else .34
	fire_until=emitted+fire_duration
	if absf(target.x-target_position.x)>.1:facing_left=target.x<target_position.x
	_refresh()

func hurt(tick:float)->void:
	if defeated_at<0:hurt_until=tick+.27;_refresh()

func defeat(tick:float)->void:
	if defeated_at>=0:
		# Loading a persistent casualty can observe its entity before its corpse
		# record. Keep the authoritative death time, never restart the fall.
		if tick<defeated_at:defeated_at=tick;_refresh()
		return
	defeated_at=tick;moving=false;searching=false;hp_ratio=0;clock=maxf(clock,tick);_refresh()

func advance(delta:float,simulation_clock:float,playing:bool)->void:
	if not playing:return
	clock=simulation_clock
	animation_time+=delta*minf(playback_rate,2.0)
	travel_heading=lerp_angle(travel_heading,target_heading,1-exp(-delta*14*minf(playback_rate,2)))
	interpolation=minf(1,interpolation+delta/interpolation_seconds)
	position=source_position.lerp(target_position,interpolation)
	_refresh()

func expired()->bool:return not persistent_defeat and defeated_at>=0 and clock-defeated_at>=defeat_hold_seconds

func _refresh()->void:
	if defeated_at>=0:
		var age:float=maxf(0,clock-defeated_at)
		state_name="defeated";frame_index=8 if age<.12 else 10 if age<.46 else 11
	elif clock<hurt_until:state_name="hurt";frame_index=8
	elif clock<fire_until:state_name="fire";frame_index=6 if fire_until-clock>fire_duration*(.23/.34) else 7
	elif identity=="MCP-306" and clock<heal_until:state_name="heal";frame_index=14
	elif identity=="MCP-306" and fire_started>=0 and clock<fire_started+.8:state_name="bolt";frame_index=12
	elif moving:state_name="walk";frame_index=2+int(floor((animation_time+phase)*9))%4
	elif searching:state_name="search";frame_index=9
	else:state_name="idle";frame_index=1 if fposmod(animation_time+phase,3.7)>3.52 else 0
	if art_v2 and defeated_at<0 and str(public_row.get("phase",""))=="parachuting":state_name="parachuting"
	if compact_mode and not Engine.is_editor_hint() and not preview_mode and defeated_at<0:
		var next:Array=[display_height,role,friendly,clock<hurt_until]
		if next!=compact_draw_key:compact_draw_key=next;queue_redraw()
	else:compact_draw_key.clear();queue_redraw()

func _draw()->void:
	var preview:bool=Engine.is_editor_hint() or preview_mode
	var index:int=preview_frame if preview else frame_index
	var item:String=preview_equipment if preview else kind
	var age:float=maxf(0,clock-defeated_at) if defeated_at>=0 else 0
	var alpha:float=1.0-clampf((age-(defeat_hold_seconds-.5))/.5,0,1) if defeated_at>=0 and not persistent_defeat else 1
	if art_v2 and preview and ArtV2.paint(self,preview_identity,preview_action,preview_frame*.17,preview_frame,display_height,Vector2.ZERO,false):return
	if art_v2 and not preview and _draw_v2(alpha,age):return
	if art_v2 and not preview and not friendly:
		var lift:float=visual_lift()
		draw_set_transform(Vector2.ZERO,0,Vector2(1,.32));draw_circle(Vector2.ZERO,display_height*.3,Color(.08,.14,.17,.3));draw_set_transform(Vector2(0,-lift))
		var column:int=3 if defeated_at>=0 else 2 if clock<fire_until else 1 if moving else 0
		var painted:bool=CasualtyArt.paint_land_enemy(self,public_row,column,display_height,facing_left)
		if defeated_at<0:
			var width:float=clampf(display_height*.65,8,24);draw_line(Vector2(-width*.5,4),Vector2(-width*.5+width*hp_ratio,4),Color("efa295"),2,true)
		draw_set_transform(Vector2.ZERO)
		if painted:return
	if not friendly and not preview:
		var enemy_column:int=3 if defeated_at>=0 else 2 if clock<fire_until else 1 if moving else 0
		if CasualtyArt.paint_land_enemy(self,public_row,enemy_column,display_height,facing_left):
			if defeated_at<0:
				var bar:float=clampf(display_height*.65,8,24);var foot:float=3 if display_height<30 else 5
				draw_line(Vector2(-bar*.5,foot),Vector2(-bar*.5+bar*hp_ratio,foot),Color("e9a28c"),1.5 if display_height<30 else 3)
			return
	if persistent_defeat and defeated_at>=0 and not preview and age>=.46:
		if CasualtyArt.paint(self,public_row,display_height,facing_left):return
	if compact_mode and not preview and defeated_at<0:
		# Far/unselected company members remain individual, hittable own-identity
		# markers; selection restores their original full SD instead of another face.
		var token_size:Vector2=Vector2(clampf(display_height*.9,8,22),clampf(display_height*.65,6,16))
		if token_script!=null:token_script.paint(self,Rect2(Vector2(-token_size.x*.5,-token_size.y) if display_height<30 else Vector2(-11,-13),token_size),role,"friendly" if friendly else "hostile",false)
		else:draw_circle(Vector2(0,-5),8,Color("b8d8c7") if friendly else Color("d99078"))
		if clock<hurt_until:draw_arc(Vector2(0,-5),13,0,TAU,16,Color("ffdcab"),1.5,true)
		return
	var vehicle:bool=item in ["ifv","armor","tank","gunship","helicopter","transport_helicopter","landing_craft","amphibious_vehicle"]
	var extent:float=display_height*(1.35 if vehicle else .76)
	draw_set_transform(Vector2.ZERO,0,Vector2(1,.32));draw_circle(Vector2.ZERO,extent*.42,Color(.08,.15,.16,.25*alpha));draw_set_transform(Vector2.ZERO)
	if selected and defeated_at<0:draw_arc(Vector2.ZERO,display_height*.44,0,TAU,28,Color("f5dda0"),1.8,true)
	var precise_vehicle:bool=false
	if vehicle and friendly and defeated_at<0:precise_vehicle=TransportArt.paint(self,public_row,Vector2.ZERO,display_height*1.5,travel_heading,animation_time,moving,selected,role,clock<fire_until)
	if precise_vehicle:pass
	elif item=="landing_craft" and defeated_at<0:
		draw_colored_polygon(PackedVector2Array([Vector2(-27,-8),Vector2(24,-8),Vector2(34,1),Vector2(21,10),Vector2(-27,10)]),Color("728b89"));draw_rect(Rect2(Vector2(-21,-5),Vector2(39,12)),Color("a6b6a5"));draw_line(Vector2(-21,9),Vector2(25,9),Color("3d575c"),3)
	elif vehicle and equipment_texture!=null and defeated_at<0:
		var equipment_index:int={"ifv":0,"armor":1,"tank":1,"gunship":2,"helicopter":2,"transport_helicopter":3}.get(item,0)
		var cell:Vector2=equipment_texture.get_size()/2
		var source:Rect2=Rect2(Vector2(equipment_index%2,equipment_index/2)*cell,cell)
		var width:float=display_height*1.65
		var dest:Rect2=Rect2(Vector2(-width*.5,-width*.7),Vector2(width,width))
		if facing_left:dest.size.x=-dest.size.x
		draw_texture_rect_region(equipment_texture,dest,source,Color(1,1,1,alpha))
	var height:float=display_height*(.52 if vehicle and defeated_at<0 else 1)
	var offset:Vector2=Vector2(display_height*.26,-display_height*.28) if vehicle and defeated_at<0 else Vector2.ZERO
	var rise:float=sin((animation_time+phase)*TAU*4.5)*1.2 if state_name=="walk" else 0
	var settle:float=sin(clampf((age-.46)/.18,0,1)*PI)*1.2 if defeated_at>=0 else 0
	if texture!=null:
		var cell:Vector2=texture.get_size()/Vector2(4,3)
		var source:Rect2=Rect2(Vector2(index%4,index/4)*cell,cell)
		var dest:Rect2=Rect2(offset+Vector2(-height*.5,-height+rise+settle),Vector2(height,height))
		if not anchor_data.is_empty() and index<anchor_data.get("frames",[]).size():
			var frame:Dictionary=anchor_data.frames[index];var bounds:Array=frame.bounds;var pivot:Array=frame.pivot
			var factor:float=height/maxf(1,float(anchor_data.reference_height))
			source=Rect2(Vector2(index%4,index/4)*cell+Vector2(float(bounds[0]),float(bounds[1])),Vector2(float(bounds[2]),float(bounds[3])))
			dest=Rect2(offset+(Vector2(float(bounds[0]),float(bounds[1]))-Vector2(float(pivot[0]),float(pivot[1])))*factor+Vector2(0,rise+settle),source.size*factor)
		if facing_left:dest.position.x=2.0*offset.x-dest.end.x;dest.size.x=-dest.size.x
		draw_texture_rect_region(texture,dest,source,Color(1,1,1,alpha))
	elif fallback_portrait!=null:
		# Planned SD identities use their actual face plus an explicit type token, never another woman's SD.
		var dest:Rect2=Rect2(offset+Vector2(-height*.42,-height*.9),Vector2(height*.84,height*.84))
		draw_circle(dest.get_center(),height*.43,Color("163b46"));draw_texture_rect(fallback_portrait,dest,false,Color(1,1,1,alpha))
		if token_script!=null:token_script.paint(self,Rect2(Vector2(-height*.27,-height*.22),Vector2(height*.54,height*.28)),role,"friendly" if friendly else "hostile",selected)
	else:
		# Unknown allied identities are explicitly unidentified; never borrow another MCP.
		draw_rect(Rect2(Vector2(-10,-27),Vector2(20,24)),Color("34474b"));draw_string(ThemeDB.fallback_font,Vector2(-4,-9),"?",HORIZONTAL_ALIGNMENT_LEFT,-1,18,Color("e9dfb9"))
	if not Engine.is_editor_hint() and defeated_at<0:
		var color:Color=Color("beddae") if friendly else Color("e9a28c")
		var bar:float=clampf(display_height*.65,8,24);var foot:float=3 if display_height<30 else 5;var thickness:float=1.5 if display_height<30 else 3
		draw_line(Vector2(-bar*.5,foot),Vector2(bar*.5,foot),Color(.08,.15,.16,.6),thickness)
		draw_line(Vector2(-bar*.5,foot),Vector2(-bar*.5+bar*hp_ratio,foot),color,thickness)

func _draw_v2(alpha:float,age:float)->bool:
	if not ArtV2.available(identity):return false
	var transport:bool=bool(public_row.get("_transport_visual",false))
	var body_state:String="defeated" if defeated_at>=0 and age>=.2 else "fall" if defeated_at>=0 else state_name
	var physical:String=str(public_row.get("physical_class","infantry"))
	var vehicle:bool=not str(public_row.get("vehicle_id","")).is_empty() and physical in ["armor","amphibious","air"]
	var lift:float=visual_lift()
	draw_set_transform(Vector2.ZERO,0,Vector2(1,.32));draw_circle(Vector2.ZERO,display_height*.33,Color(.06,.15,.17,.28*alpha));draw_set_transform(Vector2.ZERO)
	if selected and defeated_at<0:draw_arc(Vector2.ZERO,display_height*.48,0,TAU,28,Color("ffe7a5"),1.8,true)
	var independent_vehicle:bool=str(public_row.get("equipment_version","")) in ["tactical-vehicles-v3","tactical-vehicles-v4"] and not str(public_row.get("vehicle_kind","")).is_empty()
	if independent_vehicle:
		var row:Dictionary=public_row.duplicate();row["kind"]=str(row.vehicle_kind);row["art_version"]="tactical-art-v2"
		TransportArt.paint(self,row,Vector2(0,-lift),display_height*2.1,travel_heading,animation_time,moving and defeated_at<0,selected,role,clock<fire_until)
	elif transport:
		var row:Dictionary=public_row.duplicate();row["art_version"]="tactical-art-v2"
		if str(row.get("kind","")) in ["plane","transport_aircraft","aircraft","parachute_aircraft"]:
			var painted:bool=false
			if str(row.get("equipment_version","")) in ["tactical-vehicles-v3","tactical-vehicles-v4"]:painted=TransportArt.paint(self,row,Vector2(0,-lift),display_height*2.2,travel_heading,animation_time,moving,selected,role,false)
			if not painted:
				row["visual_type"]="SBD";row["heading"]=rad_to_deg(travel_heading)
				AircraftArt.paint(self,row,Vector2(0,-lift),display_height*2.2,animation_time)
		else:TransportArt.paint(self,row,Vector2(0,-lift),display_height*1.8,travel_heading,animation_time,moving,selected,role,clock<fire_until)
		# The small occupant is one visible body from the transported company.
		if display_height>=16:ArtV2.paint(self,identity,"deploy",animation_time+phase,entity_id,display_height*.42,Vector2(display_height*.2,-display_height*.15-lift),facing_left,Color(1,1,1,alpha))
	elif vehicle and defeated_at<0:
		var row:Dictionary=public_row.duplicate();row["art_version"]="tactical-art-v2";row["kind"]="gunship" if physical=="air" else "amphibious_vehicle" if physical=="amphibious" else "armor"
		TransportArt.paint(self,row,Vector2(0,-lift),display_height*1.9,travel_heading,animation_time,moving,selected,role,clock<fire_until)
		ArtV2.paint(self,identity,body_state,animation_time+phase,entity_id,display_height*.45,Vector2(display_height*.16,-display_height*.15-lift),facing_left,Color(1,1,1,alpha))
	else:
		var pose_time:float=age if defeated_at>=0 else clock-fire_started if body_state=="fire" else animation_time+phase
		ArtV2.paint(self,identity,body_state,pose_time,int(public_row.get("pose_seed",entity_id)),display_height,Vector2(0,-lift),facing_left,Color(1,1,1,alpha))
		if state_name=="parachuting":_draw_parachute(lift)
	if defeated_at<0:
		var width:float=clampf(display_height*.68,10,30);var at:=Vector2(-width*.5,4-lift)
		draw_line(at,at+Vector2(width,0),Color(.08,.15,.16,.7),2)
		draw_line(at,at+Vector2(width*hp_ratio,0),Color("b9e5bb") if friendly else Color("efa295"),2)
		WeaponBadge.paint(self,public_row,display_height,selected,lift)
	return true

func visual_lift()->float:
	if not art_v2:return 0
	var lift:float=clampf(float(public_row.get("altitude_m",0))*.1,0,180) if state_name=="parachuting" else display_height*.45 if str(public_row.get("physical_class",""))=="air" and defeated_at<0 else 0
	# An independent gunship lands to load and unload. Its actual altitude,
	# rather than its weapon category, determines whether it is above ground.
	if str(public_row.get("equipment_version","")) in ["tactical-vehicles-v3","tactical-vehicles-v4"] and not str(public_row.get("vehicle_kind","")).is_empty() and bool(public_row.get("air",false)):
		lift=display_height*.45*clampf(float(public_row.get("altitude_m",0))/45.0,0,1) if defeated_at<0 else 0
	var impulse:Dictionary=public_row.get("knockback",{}) if public_row.get("knockback",{}) is Dictionary else {}
	if not impulse.is_empty():
		var elapsed:float=maxf(0,clock-float(impulse.get("tick",clock)))
		var duration:float=maxf(.1,float(impulse.get("duration_s",impulse.get("duration",.7))))
		if elapsed<duration:lift+=sin(elapsed/duration*PI)*minf(display_height*1.8,float(impulse.get("height_m",25))*.5)
	return lift

func _draw_parachute(lift:float)->void:
	var path:String="res://assets/tactical/sprites-v2/parachute.png"
	var tex:Texture2D=ArtV2.texture(path)
	if tex==null:return
	var width:float=display_height*1.85;var top:=Vector2(0,-lift-display_height*1.7)
	var dimensions:Vector2=tex.get_size()/maxf(1,tex.get_size().x)*width
	draw_texture_rect(tex,Rect2(top-Vector2(width*.5,dimensions.y*.5),dimensions),false)
	for signum in [-1,1]:draw_line(top+Vector2(signum*width*.3,dimensions.y*.22),Vector2(signum*display_height*.2,-lift-display_height*.65),Color(.87,.89,.79,.85),.8,true)


