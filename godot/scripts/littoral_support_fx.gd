extends Control
## Artillery visuals derive only from published launches; never create damage.
const VisualProfile=preload("res://scripts/naval_support_visual_profile.gd")
var source_map
var records:Dictionary={}
var tick:float=0
var previous_tick:float=-1
var phase:float=0
var trauma:float=0
var last_offset:Vector2=Vector2.ZERO
var impacts_seen:Dictionary={}
var strength:float=1
var atlas:Texture2D
const LIMIT:int=256
func _ready()->void:
	mouse_filter=Control.MOUSE_FILTER_IGNORE;clip_contents=true
	if ResourceLoader.exists("res://assets/effects/naval-support-v1.png"):atlas=load("res://assets/effects/naval-support-v1.png")
func observe(data:Dictionary,reset:bool=false)->void:
	var now:float=float(data.get("tick",0))
	if reset or now<previous_tick-.0001:records.clear();impacts_seen.clear();trauma=0
	for shot in data.get("shots",[]):
		if str(shot.get("kind","")) not in ["naval","mortar","anti_ship","air_strike"]:continue
		var key:String=str(shot.get("id",""))
		if records.has(key):continue
		var origin:=Vector2(float(shot.get("x",0)),float(shot.get("y",0)))
		var end:=Vector2(float(shot.get("target_x",origin.x)),float(shot.get("target_y",origin.y)))
		if shot.get("launch_point") is Dictionary:origin=Vector2(float(shot.launch_point.get("x",origin.x)),float(shot.launch_point.get("y",origin.y)))
		if shot.get("impact_point") is Dictionary:end=Vector2(float(shot.impact_point.get("x",end.x)),float(shot.impact_point.get("y",end.y)))
		var flight:float=float(shot.get("flight_seconds",origin.distance_to(end)/maxf(1,float(shot.get("speed",900)))))
		var v2:bool=str(data.get("art_version",""))=="tactical-art-v2"
		var coastal:bool=str(shot.get("tuning_profile",data.get("coastal_tuning","")))=="coastal-combat-v2"
		records[key]={"origin":origin,"end":end,"tick":float(shot.get("tick",float(shot.get("frame",0))*.1)),"flight":maxf(.1,flight),"radius":float(shot.get("blast_radius_m",shot.get("radius",100))),"kind":str(shot.kind),"caliber":float(shot.get("caliber_mm",127)),"v2":v2,"coastal":coastal}
	for key in records.keys():
		var row:Dictionary=records[key]
		if now-float(row.tick)-float(row.flight)>2.0:records.erase(key);impacts_seen.erase(key)
	while records.size()>LIMIT:var key:Variant=records.keys()[0];records.erase(key);impacts_seen.erase(key)
	tick=now;previous_tick=now;queue_redraw()
func _process(delta:float)->void:
	if not is_instance_valid(source_map):return
	phase+=delta
	if source_map.playing:
		tick=minf(previous_tick+.1,tick+delta*source_map.playback_rate)
		for key in records:
			var row:Dictionary=records[key];var age:float=tick-float(row.tick)-float(row.flight)
			if age>=0 and age<.35 and not impacts_seen.has(key):
				impacts_seen[key]=true
				if bool(row.get("coastal",false)):
					# A salvo of eight small shells must not accumulate into a 406 mm kick.
					trauma=maxf(trauma,float(VisualProfile.for_caliber(float(row.caliber)).shake))
					continue
				var power:float=clampf(float(row.caliber)/406.0,.15,1.2) if row.v2 else 1.0
				trauma=minf(1,trauma+(.12+power*.78 if row.v2 else .45 if str(row.kind)=="naval" else .25))
	trauma=maxf(0,trauma-delta*1.8)
	var amplitude:float=trauma*trauma*strength*(0 if source_map.miniature else 9)
	var offset:=Vector2(sin(phase*71),cos(phase*57)) * amplitude
	# Move only this map's visual canvas. Godot converts pointer coordinates
	# through the same transform; world state and all surrounding HUD stay fixed.
	source_map.position+=offset-last_offset;last_offset=offset
	if not records.is_empty() or trauma>0:queue_redraw()
func _exit_tree()->void:
	if is_instance_valid(source_map):source_map.position-=last_offset
func _arc(row:Dictionary,fraction:float)->Vector2:
	var a:Vector2=source_map.project(row.origin);var b:Vector2=source_map.project(row.end)
	var height:float=clampf(a.distance_to(b)*.18,20,140)
	return a.lerp(b,fraction)-Vector2(0,sin(fraction*PI)*height)
func _sprite(index:int,center:Vector2,diameter:float,opacity:float)->void:
	if atlas==null:return
	var cell:=Vector2(atlas.get_size().x/4.0,atlas.get_size().y/2.0)
	var region:=Rect2(Vector2(index%4,index/4)*cell+Vector2(4,4),cell-Vector2(8,8))
	draw_texture_rect_region(atlas,Rect2(center-Vector2.ONE*diameter*.5,Vector2.ONE*diameter),region,Color(1,1,1,opacity))
func blast_outline(row:Dictionary,fraction:float)->PackedVector2Array:
	var points:PackedVector2Array=[]
	for index in range(49):points.append(source_map.project((row.end as Vector2)+Vector2.from_angle(index*TAU/48)*float(row.radius)*fraction))
	return points
func _draw()->void:
	if not is_instance_valid(source_map):return
	var impact_cells:Dictionary={}
	for row in records.values():
		var age:float=tick-float(row.tick);var flight:float=float(row.flight)
		if bool(row.get("coastal",false)):
			_draw_coastal(row,age,flight,impact_cells)
			continue
		var power:float=clampf(float(row.caliber)/406.0,.16,1.2) if row.v2 else .5
		if age<0:continue
		if age<flight:
			var launch_screen:Vector2=source_map.project(row.origin);var impact_screen:Vector2=source_map.project(row.end)
			if not Rect2(launch_screen,Vector2.ZERO).expand(impact_screen).grow(170).intersects(Rect2(Vector2.ZERO,size)):continue
			var t:float=clampf(age/flight,0,1);var trail:PackedVector2Array=[]
			for i in range(9):trail.append(_arc(row,maxf(0,t-.13+float(i)*.13/8)))
			var at:Vector2=_arc(row,t)
			draw_polyline(trail,Color(1,.59,.19,.25),3+power*8,true);draw_polyline(trail,Color(1,.84,.52,.85),1.2+power*2,true)
			draw_circle(at,1.5+power*3.4,Color("fff7d5"))
			if age<.24:draw_circle(source_map.project(row.origin),(5+power*16)*(1-age/.24),Color(1,.87,.57,.8*(1-age/.24)))
		else:
			var since:float=age-flight
			if since>1.8:continue
			var at:Vector2=source_map.project(row.end);var fade:float=1-since/1.8
			# Merge only near-coincident visual bursts; each real projectile keeps its trail.
			var cell:=Vector3i(int(floor(at.x/24)),int(floor(at.y/24)),int(floor((float(row.tick)+flight)*4)))
			if impact_cells.has(cell):continue
			impact_cells[cell]=true
			var radius:float=clampf(source_map.project((row.end as Vector2)+Vector2(float(row.radius),0)).distance_to(at),4 if row.v2 else 12,320 if row.v2 else 72)
			draw_circle(at+Vector2(0,3),radius*.48,Color(.18,.16,.12,.3*fade))
			if since<.16:draw_circle(at,radius*.6*(1-since/.16),Color(1,.97,.78,.7*strength))
			# The expanding front stays within the published blast area.
			if row.v2:draw_polyline(blast_outline(row,minf(1,.35+since*2.1)),Color(.96,.79,.49,fade*.6),1.2+power*3.2,true)
			else:draw_arc(at,radius*(.4+minf(since,.65)*2.1),0,TAU,48,Color(.96,.79,.49,fade*.6),2.8,true)
			if atlas!=null:
				if since<.8:_sprite(2 if since<.1 else 3,at-Vector2(0,radius*.2),radius*(1.35+since),maxf(0,1-since/.8))
				_sprite(4,at+Vector2(0,radius*.12),radius*(1.0+since*.9),fade*.72)
				if since>.15:_sprite(5,at-Vector2(0,since*radius*.55),radius*(.9+since*.7),fade*.56)
				continue
			for i in range(9):
				var angle:float=i*TAU/9+float(row.tick);var direction:=Vector2.from_angle(angle)
				var smoke:Vector2=at+direction*radius*.55*(.3+since)-Vector2(0,since*18)
				draw_circle(smoke,radius*(.12+since*.16),Color(.38,.35,.29,fade*.40))
				if since<.55:draw_line(at+direction*radius*.2,at+direction*radius*(.7+since),Color(1,.74,.32,(.55-since)*1.4),2,true)

func _draw_coastal(row:Dictionary,age:float,flight:float,impact_cells:Dictionary)->void:
	if age<0:return
	var profile:Dictionary=VisualProfile.for_caliber(float(row.caliber))
	if age<flight:
		var start:Vector2=source_map.project(row.origin);var end:Vector2=source_map.project(row.end)
		if not Rect2(start,Vector2.ZERO).expand(end).grow(160).intersects(Rect2(Vector2.ZERO,size)):return
		var t:float=clampf(age/flight,0,1)
		var trail:PackedVector2Array=[]
		var tail:float=minf(.13,.10/maxf(.1,flight))
		for i:int in range(9):trail.append(_arc(row,maxf(0,t-tail+float(i)*tail/8)))
		draw_polyline(trail,Color(1,.65,.30,.24),float(profile.glow_px),true)
		draw_polyline(trail,Color(1,.9,.67,.9),float(profile.core_px),true)
		draw_circle(_arc(row,t),float(profile.shell_px),Color("fff7d5"))
		var flash:float=float(profile.flash_s)
		if age<flash:draw_circle(start,(float(profile.shell_px)*3.0)*(1-age/flash),Color(1,.87,.57,.65*(1-age/flash)))
		return
	var since:float=age-flight;var life:float=float(profile.life_s)
	if since>life:return
	var at:Vector2=source_map.project(row.end)
	var cell:=Vector3i(int(floor(at.x/12)),int(floor(at.y/12)),int(floor((float(row.tick)+flight)*8)))
	if impact_cells.has(cell):return
	impact_cells[cell]=true
	var fade:float=1-since/life
	var published_radius:float=source_map.project((row.end as Vector2)+Vector2(float(row.radius),0)).distance_to(at)
	# Fire/smoke have a screen readability envelope; the terrain-projected ring
	# below remains the actual damage area even at extreme zoom.
	var burst:float=clampf(published_radius,float(profile.burst_min_px),float(profile.burst_max_px))
	var flash:float=float(profile.flash_s)
	draw_circle(at+Vector2(0,2),burst*.35,Color(.18,.16,.12,.22*fade))
	if since<flash:draw_circle(at,burst*.45*(1-since/flash),Color(1,.97,.78,.65*strength))
	if since<life*.6:
		draw_polyline(blast_outline(row,minf(1,.2+since/(life*.35))),Color(.96,.79,.49,fade*.44),float(profile.ring_px),true)
	if atlas!=null:
		if since<life*.45:_sprite(2 if since<flash else 3,at-Vector2(0,burst*.14),burst*(1.0+since/life*.4),maxf(0,1-since/(life*.45)))
		_sprite(4,at+Vector2(0,burst*.10),burst*(.8+since/life*.6),fade*.5)
		if since>flash:_sprite(5,at-Vector2(0,since/life*burst*.4),burst*(.7+since/life*.4),fade*.32)
		return
	for i:int in range(6):
		var direction:=Vector2.from_angle(i*TAU/6+float(row.tick))
		draw_circle(at+direction*burst*.4*since/life-Vector2(0,since*8),burst*(.10+since/life*.12),Color(.38,.35,.29,fade*.35))
