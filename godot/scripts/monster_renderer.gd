class_name CasMonsterRenderer
extends RefCounted
## Cosmetic projection of an already visible contact. Never looks up an enemy unit.
static func is_creature(contact: Dictionary) -> bool:
	return str(contact.get("entityKind","")) in ["monster","aberrant"]

static func threatens_fleet(view: Dictionary, warning: Dictionary) -> bool:
	var destination := Vector2(float(warning.get("x",0)),float(warning.get("y",0)))
	var origin := Vector2(float(warning.get("origin_x",destination.x)),float(warning.get("origin_y",destination.y)))
	var radius := float(warning.get("radius",0))+100.0
	for ship in view.get("ships",[]):
		if float(ship.get("hp",0))<=0:continue
		if warning.get("exempt_ship_id")!=null and int(ship.get("id",-1))==int(warning.exempt_ship_id):continue
		var point := Vector2(float(ship.get("x",0)),float(ship.get("y",0)))
		var nearest := Geometry2D.get_closest_point_to_segment(point,origin,destination) if str(warning.get("shape",""))=="capsule" else destination
		if point.distance_to(nearest)<=radius:return true
	return false

static func draw_contact(canvas: CanvasItem,contact: Dictionary,point: Vector2,zoom: float,clock: float,textures: Dictionary,animation: CasEnemyAnimation=null,pose_override: String="",alpha: float=1.0) -> bool:
	var naval := str(contact.get("entityKind", "")) == "naval"
	if not is_creature(contact) and not naval:return false
	var species := str(contact.get("visualType",contact.get("species","scavenger")))
	var boss := bool(contact.get("boss",false))
	var scale := clampf(sqrt(zoom)*.72,.60,1.45)*(1.45 if boss else 1.0)
	var heading := deg_to_rad(float(contact.get("heading",0)))
	var forward := Vector2(sin(heading),-cos(heading))
	var width := 29.0*scale
	var pose := pose_override if not pose_override.is_empty() else (animation.pose(contact,clock) if animation!=null else "idle")
	if naval:
		_draw_naval(canvas, contact, point, heading, scale, clock, alpha)
	else:
		var frames := CasEnemyAnimation.frames_for(species,textures)
		if frames != null and frames.has_animation(pose):
			var texture: Texture2D = frames.get_frame_texture(pose,0)
			var length := (128.0 if boss else 82.0)*scale
			var breathing := 1.0+sin(clock*(3.7 if pose=="swim" else 1.6))*.018
			var pulse := 1.0+sin(clock*11.0)*.025 if pose=="windup" else breathing
			# Every source is authored vertically overhead, nose NORTH. No oblique camera correction.
			canvas.draw_set_transform(point,heading,Vector2(pulse,breathing))
			var blend:Dictionary=animation.transition(contact,clock) if animation!=null else {"from":pose,"mix":1.0}
			if float(blend.mix)<1.0 and frames.has_animation(str(blend.from)):
				_draw_swimming_surface(canvas,frames.get_frame_texture(str(blend.from),0),length,clock,str(blend.from),alpha*(1.0-float(blend.mix)),species,boss)
			_draw_swimming_surface(canvas,texture,length,clock,pose,alpha*float(blend.mix),species,boss)
			canvas.draw_set_transform(Vector2.ZERO)
		else:
			_procedural_body(canvas,point,forward,width,clock,species)
	if pose=="down": return true
	canvas.draw_arc(point,width*.75,0.0,TAU,32,Color(.95,.53,.42,.48),1.2,true)
	if contact.has("health") and contact.has("attack"):
		var fraction := clampf(float(contact.health) / maxf(1.0, float(contact.get("max_health", 1))), 0, 1)
		var bar_width := 70.0 if boss else 46.0
		var bar_at := point + Vector2(-bar_width*.5, maxf(26.0, width*.84))
		canvas.draw_style_box(_health_box(Color(.025,.09,.13,.94)), Rect2(bar_at-Vector2(2,2),Vector2(bar_width+4,8)))
		canvas.draw_style_box(_health_box(Color("edaa83")), Rect2(bar_at,Vector2(bar_width*fraction,4)))
		if str(contact.attack.get("state", "")) == "windup":
			var flag := point+Vector2(width*.8,-width*.7)
			canvas.draw_colored_polygon(PackedVector2Array([flag+Vector2(0,-8),flag+Vector2(7,5),flag+Vector2(-7,5)]),Color("ffd5a3"))
	elif boss:
		var fraction := clampf(float(contact.get("health_fraction",1)),0,1)
		canvas.draw_arc(point,width*.91,PI*.12,PI*.88,24,Color(.16,.15,.19,.8),3.2,true)
		canvas.draw_arc(point,width*.91,PI*.12,PI*.12+PI*.76*fraction,24,Color("e9a27b"),2.0,true)
	return true

static func _draw_naval(canvas: CanvasItem,contact: Dictionary,point: Vector2,heading: float,scale: float,clock: float,alpha: float) -> void:
	var vessel := str(contact.get("vessel_type", "unknown"))
	var length := (68.0 if vessel=="ca" else (58.0 if vessel=="cl" else 48.0))*scale
	var beam := length*(.18 if vessel=="dd" else .22)
	canvas.draw_set_transform(point,heading)
	var hull := PackedVector2Array([Vector2(0,-length*.53),Vector2(-beam*.45,-length*.29),Vector2(-beam*.5,length*.32),Vector2(-beam*.30,length*.48),Vector2(beam*.30,length*.48),Vector2(beam*.5,length*.32),Vector2(beam*.45,-length*.29)])
	canvas.draw_colored_polygon(hull,Color(.17,.23,.28,alpha))
	var outline := hull.duplicate();outline.append(hull[0])
	canvas.draw_polyline(outline,Color(.91,.57,.42,alpha),1.3,true)
	canvas.draw_rect(Rect2(-beam*.28,-length*.15,beam*.56,length*.38),Color(.36,.39,.38,alpha))
	canvas.draw_rect(Rect2(-beam*.30,-length*.12,beam*.60,length*.12),Color(.63,.61,.51,alpha))
	for y in [-.30,.28]:
		var turret := Vector2(0,float(y)*length)
		canvas.draw_circle(turret,beam*.30,Color(.52,.50,.43,alpha))
		canvas.draw_line(turret,turret+Vector2(0,-length*.14),Color(.78,.72,.58,alpha),maxf(1.2,scale*1.4),true)
	for y in [.08,.18]:
		canvas.draw_circle(Vector2(0,length*float(y)),beam*.18,Color(.12,.16,.19,alpha))
	# A small readiness light uses only the public weapon cooldown.
	if contact.has("attack") and alpha>.5:
		var ready := str(contact.attack.get("state",""))=="approach"
		canvas.draw_circle(Vector2(beam*.60,0),2.2,Color("f4bf7a") if ready else Color(.61,.66,.68,.65))
	canvas.draw_set_transform(Vector2.ZERO)

static func draw_defeated(map: Control,view: Dictionary,clock: float,textures: Dictionary) -> void:
	for record in view.get("salvage",{}).get("defeated_entities",[]):
		var age := float(int(view.get("tick",0))-int(record.get("death_tick",0)))
		if age<0.0 or age>5.0:continue
		var contact: Dictionary=record.duplicate()
		if str(contact.get("species",""))=="leviathan":contact["boss"]=true
		draw_contact(map,contact,map.project(map.pos(record)),map.zoom,clock,textures,null,"down",clampf(1.0-age/5.0,0,1)*.75)

static func _health_box(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(2)
	return style

static func _procedural_body(canvas: CanvasItem,point: Vector2,forward: Vector2,width: float,clock: float,species: String) -> void:
	var across := forward.orthogonal()
	var tint := Color("5a857d")
	if species=="spitter":tint=Color("927996")
	elif species=="warden":tint=Color("577d91")
	elif species=="leviathan":tint=Color("4b697b")
	elif species=="aversion":tint=Color("817d99")
	canvas.draw_circle(point,width*.72,Color(.02,.12,.16,.28))
	# Fins/tendrils move locally; the center and heading remain the observed values.
	var limbs := 5 if species in ["spitter","aversion"] else 3
	for side in [-1.0,1.0]:
		for index in range(limbs):
			var along := (float(index)/float(maxi(limbs-1,1))-.5)*width*1.2
			var base := point+forward*along
			var tip: Vector2 = base+across*width*float(side)*(.66+float(index%2)*.18)-forward*width*.35
			tip += forward*sin(clock*1.5+index)*width*.05
			canvas.draw_colored_polygon(PackedVector2Array([base+forward*width*.18,tip,base-forward*width*.19]),tint.darkened(.18))
	var body := PackedVector2Array()
	for i in range(18):
		var angle := i*TAU/18.0
		var radius := 1.0+.06*sin(angle*5.0)
		body.append(point+forward*cos(angle)*width*radius+across*sin(angle)*width*.43*radius)
	canvas.draw_colored_polygon(body,tint)
	for index in range(4):
		var center := point+forward*(float(index)-1.5)*width*.39
		canvas.draw_colored_polygon(PackedVector2Array([center-forward*width*.21,center-across*width*.34,center+forward*width*.22,center+across*width*.23]),tint.lightened(.1+index*.03))
	var head := point+forward*width*.78
	for side in [-1.0,1.0]:
		canvas.draw_line(head+across*side*width*.20,head+forward*width*.11+across*side*width*.24,Color("f2bc85"),maxf(1.2,width*.065),true)
	if species=="leviathan":
		var tail := PackedVector2Array([point-forward*width*.8,point-forward*width*1.8+across*width*.23*sin(clock),point-forward*width*1.2-across*width*.24])
		canvas.draw_colored_polygon(tail,tint.darkened(.1))
	elif species=="aversion":
		canvas.draw_arc(point,width*.55,0,TAU,24,Color(.90,.62,.83,.72),1.5,true)

static func draw_telegraph(map: Control,entry: Dictionary,tick: int,clock: float) -> void:
	var point: Vector2=map.project(Vector2(float(entry.get("x",0)),float(entry.get("y",0))))
	var radius := float(entry.get("radius",0))
	if radius<=0:return
	var screen_radius: float=point.distance_to(map.project(Vector2(float(entry.get("x",0))+radius,float(entry.get("y",0)))))
	var start := int(entry.get("start_tick",tick))
	var impact := int(entry.get("impact_tick",tick))
	var progress := clampf(float(tick-start)/float(maxi(1,impact-start)),0,1)
	var color := Color("f1a36f") if str(entry.get("kind",""))!="pulse" else Color("dca1d4")
	if str(entry.get("shape", "")) == "capsule":
		var origin: Vector2=map.project(Vector2(float(entry.get("origin_x",entry.get("x",0))),float(entry.get("origin_y",entry.get("y",0)))))
		var direction := (point-origin).normalized()
		if direction.length_squared()<.1:direction=Vector2.UP
		var angle := direction.angle()
		var capsule := PackedVector2Array()
		for index in range(17):
			capsule.append(point+Vector2.from_angle(angle-PI*.5+float(index)*PI/16.0)*screen_radius)
		for index in range(17):
			capsule.append(origin+Vector2.from_angle(angle+PI*.5+float(index)*PI/16.0)*screen_radius)
		map.draw_colored_polygon(capsule,Color(color.r,color.g,color.b,.08+progress*.08))
		capsule.append(capsule[0])
		map.draw_polyline(capsule,color,2.0,true)
		map.draw_line(origin,origin.lerp(point,progress),Color(color.r,color.g,color.b,.55),3.0,true)
		var arrow := point-direction*screen_radius*.5
		map.draw_polyline(PackedVector2Array([arrow-direction.rotated(.65)*12.0,arrow,arrow-direction.rotated(-.65)*12.0]),color,2.0,true)
		_warning_clock(map,origin.lerp(point,.58),impact-tick,color)
		return
	map.draw_circle(point,screen_radius,Color(color.r,color.g,color.b,.055+progress*.055))
	for index in range(24):
		var angle := index*TAU/24.0
		map.draw_arc(point,screen_radius,angle,angle+TAU/36.0,4,Color(color.r,color.g,color.b,.78),1.8,true)
	map.draw_arc(point,screen_radius,-PI*.5,-PI*.5+TAU*progress,64,color,3.0,true)
	var pulse := 1.0+sin(clock*3.0)*.1
	map.draw_line(point-Vector2(5,5)*pulse,point+Vector2(5,5)*pulse,color,1.5,true)
	map.draw_line(point-Vector2(-5,5)*pulse,point+Vector2(-5,5)*pulse,color,1.5,true)
	if entry.has("shape"):_warning_clock(map,point,impact-tick,color)

static func _warning_clock(map: Control,point: Vector2,remaining: int,color: Color) -> void:
	var font: Font=map.get("font")
	if font==null:return
	var caption := "%ds" % maxi(0,remaining)
	map.draw_string_outline(font,point+Vector2(10,-9),caption,HORIZONTAL_ALIGNMENT_LEFT,-1,17,4,Color("123748"))
	map.draw_string(font,point+Vector2(10,-9),caption,HORIZONTAL_ALIGNMENT_LEFT,-1,17,color)

static func _draw_swimming_surface(canvas:CanvasItem,texture:Texture2D,length:float,clock:float,pose:String,alpha:float,species:String,boss:bool=false)->void:
	# A small continuous skin deformation interpolates fins/tail between authored poses.
	# Atlas pixels remain intact; only native mesh vertices move in the local overhead plane.
	if not texture is AtlasTexture:
		canvas.draw_texture_rect(texture,Rect2(Vector2.ONE*-length*.5,Vector2.ONE*length),false,Color(1,1,1,alpha));return
	var atlas:AtlasTexture=texture
	var columns:=6;var rows:=10
	var vertices:=PackedVector3Array();var uv:=PackedVector2Array();var indices:=PackedInt32Array()
	var intensity:=.014 if pose=="swim" else .006
	if pose=="windup":intensity=.004
	if pose in ["down","hurt"]:intensity=.002
	var frequency:=3.8 if pose=="swim" else 1.8
	var seed_phase:=float(abs(species.hash())%19)*.3
	for y in range(rows+1):
		var v:=float(y)/float(rows)
		for x in range(columns+1):
			var u:=float(x)/float(columns)
			var tail:=smoothstep(.36,1.0,v)
			var bend:=sin(clock*frequency+v*5.2+seed_phase)*length*intensity*(.2+tail)
			var fin:=sin(clock*frequency-v*4.0)*length*intensity*absf(u-.5)*.42
			vertices.append(Vector3((u-.5)*length+bend,(v-.5)*length+fin,0))
			uv.append((atlas.region.position+Vector2(u,v)*atlas.region.size)/atlas.atlas.get_size())
	for y in range(rows):
		for x in range(columns):
			var a:=y*(columns+1)+x;var b:=a+columns+1
			indices.append_array(PackedInt32Array([a,b,a+1,a+1,b,b+1]))
	var arrays:Array=[];arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=vertices;arrays[Mesh.ARRAY_TEX_UV]=uv;arrays[Mesh.ARRAY_INDEX]=indices
	var motion_meshes:Dictionary=canvas.get_meta("enemy_motion_meshes",{})
	canvas.set_meta("enemy_motion_meshes",motion_meshes)
	var key:=str(texture.get_instance_id())+(":boss" if boss else ":normal")
	if not motion_meshes.has(key):motion_meshes[key]=ArrayMesh.new()
	var mesh:ArrayMesh=motion_meshes[key];mesh.clear_surfaces();mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	canvas.draw_mesh(mesh,atlas.atlas,Transform2D.IDENTITY,Color(1,1,1,alpha))
