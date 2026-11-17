extends Node2D
## Retained geometry, only transforms and health change with observations.
var body:=Sprite2D.new()
var hull:=Line2D.new()
var health_back:=Polygon2D.new()
var health:=Polygon2D.new()
var row:Dictionary={}
var kind:String=""
var world_from:=Vector2.ZERO
var world_to:=Vector2.ZERO
var world_now:=Vector2.ZERO
var height:=60.0
var animation:SpriteFrames
var pose:String="swim"
func _init()->void:
	add_child(hull);hull.width=2;hull.default_color=Color("9ce4d3");add_child(body)
	for bar in [health_back,health]:
		bar.polygon=PackedVector2Array([Vector2.ZERO,Vector2(34,0),Vector2(34,3),Vector2(0,3)]);bar.position=Vector2(-17,30);add_child(bar)
	health_back.color=Color(.025,.12,.16,.7);health.color=Color("efa77f")
func configure(next:Dictionary,next_kind:String,texture:Texture2D,extent:float)->void:
	row=next;kind=next_kind;height=extent
	if body.texture!=texture:body.texture=texture
	if texture!=null:body.scale=Vector2.ONE*(extent/maxf(texture.get_height(),1))
	body.position=Vector2(0,-extent*.43) if kind=="ship" else Vector2.ZERO
	var hostile:bool=kind=="contact"
	pose="windup" if str(next.get("attack",{}).get("state",""))=="windup" else "hurt" if bool(next.get("display_hurt",false)) else "swim"
	if hostile:health.scale.x=clampf(float(next.get("health_fraction",float(next.get("health",1))/maxf(1,float(next.get("max_health",1))))),0,1)
	health_back.visible=hostile;health.visible=hostile
	hull.visible=kind in ["ship","shell","torpedo"]
	if kind=="ship":hull.points=PackedVector2Array([Vector2(0,-6),Vector2(0,6)])
	elif kind in ["shell","torpedo"]:
		var heavy:bool=float(next.get("display_caliber",0))>=200
		hull.points=PackedVector2Array([Vector2(0,-9 if kind=="torpedo" else -11 if heavy else -6),Vector2(0,4)]);hull.default_color=Color("99f2dd") if kind=="torpedo" else Color("ffe1a0");hull.width=3 if kind=="torpedo" or heavy else 2
	body.visible=texture!=null
func place(at:Vector2,clock:float)->void:
	position=at;var heading:float=deg_to_rad(float(row.get("heading",0)));hull.rotation=heading
	if kind=="contact":
		body.rotation=heading;body.scale.y=body.scale.x*(1.0+sin(clock*4.0+float(hash(row.get("id",""))%101))*.018)
		if animation!=null and animation.has_animation(pose):
			var count:int=animation.get_frame_count(pose)
			if count>0:body.texture=animation.get_frame_texture(pose,int(clock*animation.get_animation_speed(pose)+float(hash(row.get("id",""))%17))%count)
	elif kind=="ship":body.position.y=-height*.43-(absf(sin(clock*5.5+float(row.get("id",1))))*2.8 if float(row.get("speed",0))>1 else sin(clock*1.8)*.5)
