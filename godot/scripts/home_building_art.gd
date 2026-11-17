@tool
extends Control
## Original, editable 2.5D facility objects shared by the island and construction cards.
@export_enum("hq","recycler","forge","solar","medical","turret","aa","depot","dock","machine_gun","mortar","anti_ship","repair_tower") var kind:String="hq":
	set(value):kind=value;queue_redraw()
@export_range(1,3) var level:int=1:
	set(value):level=value;queue_redraw()
@export var health:int=100
@export_dir var artwork_directory:String="res://assets/home/buildings"
@export var artwork_anchor:Vector2=Vector2(.5,.72)
static var artwork_cache:Dictionary={}
static var hit_images:Dictionary={}
func _ready()->void:mouse_filter=Control.MOUSE_FILTER_IGNORE;texture_filter=CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS;resized.connect(queue_redraw)
func _draw()->void:paint(self,Vector2(size.x*.5,size.y*.72),minf(size.x*.9,size.y*.95),kind,level,health,artwork_directory,artwork_anchor)
static func artwork(type:String,directory:String="res://assets/home/buildings")->Texture2D:
	var path:String=directory.path_join(type+".png")
	if not ResourceLoader.exists(path):path=directory.path_join(str({"machine_gun":"turret","mortar":"turret","anti_ship":"aa","repair_tower":"medical","warehouse":"depot","cannon":"turret","repair":"medical"}.get(type,type))+".png")
	if not ResourceLoader.exists(path):return null
	if not artwork_cache.has(path):artwork_cache[path]=load(path)
	return artwork_cache[path]
static func hit_test(position:Vector2,at:Vector2,width:float,type:String,directory:String="res://assets/home/buildings",anchor:Vector2=Vector2(.5,.72))->bool:
	var texture:Texture2D=artwork(type,directory)
	var dimensions:Vector2=Vector2(width,width if texture==null else width*texture.get_height()/maxf(1,texture.get_width()))
	var bounds:Rect2=Rect2(at-dimensions*anchor,dimensions)
	if not bounds.has_point(position):return false
	if texture==null:return true
	var key:String=directory.path_join(type)
	if not hit_images.has(key):hit_images[key]=texture.get_image()
	var pixels:Image=hit_images[key];var uv:Vector2=(position-bounds.position)/bounds.size
	return pixels.get_pixel(clampi(int(uv.x*pixels.get_width()),0,pixels.get_width()-1),clampi(int(uv.y*pixels.get_height()),0,pixels.get_height()-1)).a>.05
static func polygon(target:CanvasItem,points:Array[Vector2],color:Color)->void:target.draw_colored_polygon(PackedVector2Array(points),color)
static func paint(target:CanvasItem,at:Vector2,width:float,type:String,lv:int=1,hp:int=100,directory:String="res://assets/home/buildings",anchor:Vector2=Vector2(.5,.72))->void:
	var texture:Texture2D=artwork(type,directory)
	if texture!=null:
		var dimensions:Vector2=Vector2(width,width*texture.get_height()/maxf(1,texture.get_width()))
		target.draw_texture_rect(texture,Rect2(at-dimensions*anchor,dimensions),false,Color.WHITE if hp>0 else Color(.55,.59,.55,1));return
	var w:float=width;var dark:Color=Color("325a60");var roof:Color=Color("4d91a0");var wall:Color=Color("ecdfbc");var trim:Color=Color("e6c27e")
	if type in ["forge","medical"]:roof=Color("b86f52")
	if hp<=0:roof=Color("777e75");wall=Color("a6a58e")
	var shadow:Array[Vector2]=[]
	for index in range(24):shadow.append(at+Vector2(cos(index*TAU/24)*w*.55,sin(index*TAU/24)*w*.15+w*.17))
	polygon(target,shadow,Color(.12,.28,.24,.22))
	if type=="solar":
		for index in range(2):
			var p:Vector2=at+Vector2((index-.55)*w*.42,-w*.2)
			target.draw_line(p+Vector2(w*.12,0),p+Vector2(w*.12,w*.29),dark,w*.04)
			polygon(target,[p+Vector2(-w*.11,-w*.25),p+Vector2(w*.24,-w*.19),p+Vector2(w*.18,w*.07),p+Vector2(-w*.17,0)],Color("285c7d"))
			for line in range(1,4):target.draw_line(p+Vector2(-w*.11+line*w*.085,-w*.25+line*w*.014),p+Vector2(-w*.17+line*w*.085,line*w*.017),Color("8bcbd2"),1.1,true)
			target.draw_line(p+Vector2(-w*.14,-w*.11),p+Vector2(w*.21,-w*.05),Color("8bcbd2"),1.1,true)
	elif type in ["turret","aa"]:
		polygon(target,[at+Vector2(-w*.43,w*.12),at+Vector2(-w*.37,-w*.12),at+Vector2(w*.25,-w*.2),at+Vector2(w*.44,w*.03),at+Vector2(w*.12,w*.29)],Color("737f66"))
		polygon(target,[at+Vector2(-w*.37,-w*.12),at+Vector2(-w*.15,-w*.32),at+Vector2(w*.27,-w*.26),at+Vector2(w*.25,-w*.2)],Color("aeb492"))
		target.draw_circle(at+Vector2(0,-w*.17),w*.22,roof)
		for barrel in range(2 if type=="aa" else 1):
			var p:Vector2=at+Vector2((barrel-.4)*w*.12,-w*.2)
			target.draw_line(p,p+Vector2(w*.42,-w*.25),dark,w*.08 if type=="turret" else w*.045,true)
			target.draw_line(p+Vector2(0,-w*.018),p+Vector2(w*.4,-w*.265),Color("93b3ac"),w*.024,true)
	elif type=="dock":
		for beam in range(5):
			var p:Vector2=at+Vector2((beam-2)*w*.18,-w*.08)
			polygon(target,[p,p+Vector2(w*.13,-w*.05),p+Vector2(w*.16,w*.34),p+Vector2(w*.03,w*.39)],Color("ac835b"))
		for post in [-1,1]:target.draw_line(at+Vector2(post*w*.4,-w*.18),at+Vector2(post*w*.4,w*.27),dark,w*.07)
		polygon(target,[at+Vector2(-w*.48,-w*.15),at+Vector2(w*.35,-w*.27),at+Vector2(w*.45,-w*.1),at+Vector2(-w*.4,w*.03)],roof)
	else:
		polygon(target,[at+Vector2(-w*.39,-w*.14),at+Vector2(w*.1,-w*.25),at+Vector2(w*.1,w*.24),at+Vector2(-w*.39,w*.12)],wall)
		polygon(target,[at+Vector2(w*.1,-w*.25),at+Vector2(w*.39,-w*.1),at+Vector2(w*.39,w*.12),at+Vector2(w*.1,w*.24)],wall.darkened(.17))
		polygon(target,[at+Vector2(-w*.48,-w*.15),at+Vector2(-w*.15,-w*.47),at+Vector2(w*.36,-w*.3),at+Vector2(w*.1,-w*.12)],roof.lightened(.13))
		polygon(target,[at+Vector2(w*.1,-w*.12),at+Vector2(w*.36,-w*.3),at+Vector2(w*.48,-w*.08),at+Vector2(w*.12,w*.02)],roof.darkened(.16))
		target.draw_line(at+Vector2(-w*.47,-w*.14),at+Vector2(w*.11,w*.02),trim,w*.04,true)
		target.draw_rect(Rect2(at+Vector2(-w*.15,-w*.04),Vector2(w*.13,w*.22)),dark)
		for window in [-1,1]:target.draw_rect(Rect2(at+Vector2(-w*.23+window*w*.12,-w*.04),Vector2(w*.075,w*.07)),Color("f9e9aa"))
		if type=="medical":
			var p:Vector2=at+Vector2(-w*.08,-w*.29);target.draw_line(p-Vector2(w*.1,0),p+Vector2(w*.1,0),Color("fff9df"),w*.065,true);target.draw_line(p-Vector2(0,w*.1),p+Vector2(0,w*.1),Color("fff9df"),w*.065,true)
		if type=="forge":
			polygon(target,[at+Vector2(w*.18,-w*.2),at+Vector2(w*.18,-w*.58),at+Vector2(w*.32,-w*.58),at+Vector2(w*.32,-w*.14)],Color("7d7060"));target.draw_line(at+Vector2(w*.16,-w*.58),at+Vector2(w*.34,-w*.58),dark,w*.04)
		if type=="depot":
			for index in range(2):
				var p:Vector2=at+Vector2(-w*.4+index*w*.15,w*.09);target.draw_rect(Rect2(p,Vector2(w*.14,w*.14)),Color("b89a64"));target.draw_line(p,p+Vector2(w*.14,w*.14),Color("7e6747"),1.5)
		if type in ["hq","recycler"]:
			var p:Vector2=at+Vector2(-w*.14,-w*.42);target.draw_line(p,p-Vector2(0,w*.36),dark,w*.025,true)
			polygon(target,[p-Vector2(0,w*.36),p+Vector2(w*.25,-w*.29),p-Vector2(0,w*.22)],trim)
	for dot in range(lv):target.draw_circle(at+Vector2((dot-float(lv-1)*.5)*w*.095,w*.34),w*.025,Color("fff0b0"))
