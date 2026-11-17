@tool
extends RefCounted
## Cinematic head-and-shoulder framing; square expression frames remain intact.
const Fade=preload("res://shaders/story_portrait_fade.gdshader")
static var framed:Dictionary={}
static func portrait(source:Texture2D,identity:String)->Texture2D:
	if source==null or source.get_height()<source.get_width()*1.25:return source
	var cache_key:=str(source.get_instance_id())+":"+identity
	if framed.has(cache_key):
		var existing:Texture2D=framed[cache_key].get_ref()
		if existing!=null:return existing
	# Same face scale as the authored square expression frames. These are camera
	# windows into the original image, not edited or regenerated picture files.
	var fraction:=.42
	var center:=.50
	if identity.contains("perkins"):fraction=.34;center=.51
	elif identity.contains("maury"):fraction=.44;center=.56
	elif identity.contains("lamson"):fraction=.43
	elif identity.contains("baixi"):fraction=.34;center=.49
	elif identity.contains("herald"):fraction=.47;center=.51
	var side:=minf(float(source.get_width()),float(source.get_height())*fraction)
	var left:=clampf(float(source.get_width())*center-side*.5,0.0,float(source.get_width())-side)
	var view:=AtlasTexture.new();view.atlas=source;view.region=Rect2(left,0,side,side)
	view.set_meta("story_side_feather",.035 if identity.contains("baixi") else 0.0)
	# Crops must not retain every full-resolution character ever visited.
	framed[cache_key]=weakref(view)
	if framed.size()>32:
		for key in framed.keys():
			if framed[key].get_ref()==null:framed.erase(key)
	return view

static func fade(actor:TextureRect)->void:
	var material:=actor.material as ShaderMaterial
	if material==null or material.shader!=Fade:
		material=ShaderMaterial.new();material.shader=Fade;actor.material=material
	var texture:=actor.texture
	var region:=Vector4(0,0,1,1)
	if texture is AtlasTexture:
		var extent:Vector2=texture.atlas.get_size()
		region=Vector4(texture.region.position.x/extent.x,texture.region.position.y/extent.y,texture.region.size.x/extent.x,texture.region.size.y/extent.y)
	material.set_shader_parameter("frame_region",region)
	material.set_shader_parameter("side_feather",float(texture.get_meta("story_side_feather",0.0)) if texture!=null else 0.0)

static func slot(actor:TextureRect,index:int,count:int)->void:
	var slots:=maxi(1,count)
	var inset:=.02 if slots>=3 else .035
	actor.anchor_left=(float(index)+inset)/float(slots)
	actor.anchor_right=(float(index)+1.0-inset)/float(slots)
	if slots==1:actor.anchor_left=.2;actor.anchor_right=.8
	actor.anchor_top=.005;actor.anchor_bottom=1.0
	actor.offset_left=0;actor.offset_top=0;actor.offset_right=0;actor.offset_bottom=0
	actor.set_meta("story_rest_top",actor.anchor_top)
	actor.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
	actor.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	actor.mouse_filter=Control.MOUSE_FILTER_IGNORE
	fade(actor)

static func composition(actor:TextureRect,bust:bool)->void:
	actor.set_meta("story_bust",bust)
	actor.anchor_top=.005
	actor.set_meta("story_rest_top",actor.anchor_top)
