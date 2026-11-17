@tool
extends RefCounted
## Home-only identity-keyed daily poses. Missing SD never falls back to a portrait.
const Art=preload("res://scripts/character_art.gd")
const TacticalArt=preload("res://scripts/tactical_art_v2.gd")
const PATH:String="res://data/home-daily-art-v1.json"
static var units:Dictionary={}
static var source_stamp:int=-1
static var next_refresh_ms:int=0
static var bounds:Dictionary={}

static func entry(id:String)->Dictionary:
	if source_stamp>=0 and Time.get_ticks_msec()<next_refresh_ms:
		var cached:Dictionary=units.get(id,{})
		return cached if bool(cached.get("approved",false)) else {}
	next_refresh_ms=Time.get_ticks_msec()+1000
	var stamp:int=int(FileAccess.get_modified_time(PATH)) if FileAccess.file_exists(PATH) else 0
	if stamp!=source_stamp:
		source_stamp=stamp;units={}
		if stamp>0:
			var data:Variant=JSON.parse_string(FileAccess.get_file_as_string(PATH))
			if data is Dictionary and data.get("units") is Dictionary:units=data.units
	var row:Dictionary=units.get(id,{})
	return row if bool(row.get("approved",false)) else {}

static func sd_path(card:Dictionary)->String:
	for key in ["chibi_generated","chibi","chibi_reference"]:
		var path:String=str(card.get(key,""))
		if not path.is_empty() and ResourceLoader.exists(path):return path
	return ""

static func available(card:Dictionary)->bool:
	var id:String=str(card.get("id",""))
	return not entry(id).get("frames",[]).is_empty() or TacticalArt.available(id) or not sd_path(card).is_empty()

static func state(card:Dictionary,requested:String)->String:
	var animations:Dictionary=entry(str(card.get("id",""))).get("animations",{})
	if not animations.get(requested,[]).is_empty():return requested
	if requested=="walk" and TacticalArt.available(str(card.get("id",""))):return "walk"
	if not animations.get("idle",[]).is_empty():return "idle"
	return "walk" if requested=="walk" and card.get("chibi_animations",{}).has("walk") else "idle"

static func frame(card:Dictionary,requested:String,time:float,seed:int=0)->Dictionary:
	var identity:String=str(card.get("id",""));var row:Dictionary=entry(identity)
	var actual:String=state(card,requested);var sequence:Array=row.get("animations",{}).get(actual,[])
	if not sequence.is_empty():
		var timing:Dictionary=row.get("timing",{}).get(actual,{})
		var index:int=int(floor(maxf(0,time)*maxf(.1,float(timing.get("fps",7 if actual=="walk" else 3)))))
		if actual=="idle":index=mini(1,sequence.size()-1) if fposmod(time+seed*.071,4.2)>4.04 else 0
		elif bool(timing.get("loop",actual in ["walk","idle","blink"])):index=posmod(index,sequence.size())
		else:index=mini(index,sequence.size()-1)
		var chosen:Variant=sequence[index];var frames:Array=row.get("frames",[])
		if chosen is int or chosen is float:
			if int(chosen)>=0 and int(chosen)<frames.size():return frames[int(chosen)]
		else:
			for cell in frames:
				if str(cell.get("name",""))==str(chosen):return cell
	if TacticalArt.available(identity):return TacticalArt.frame(identity,actual,time,seed)
	var path:String=sd_path(card)
	if path.is_empty():return {}
	var animations:Dictionary=card.get("chibi_animations",{});var poses:Dictionary=card.get("chibi_poses",{})
	if animations.get(actual) is Dictionary:
		var animation:Dictionary=animations[actual];var sources:Array=animation.get("frames",[])
		if not sources.is_empty():
			var key:String=str(sources[posmod(int(time*float(animation.get("fps",7))),sources.size())])
			var candidate:String=str(poses.get(key,""))
			if ResourceLoader.exists(candidate):path=candidate
	var texture:Texture2D=Art.texture(path)
	if texture==null:return {}
	if not bounds.has(path):bounds[path]=texture.get_image().get_used_rect()
	var used:Rect2i=bounds[path]
	return {"source":path,"rect":[0,0,texture.get_width(),texture.get_height()],"pivot":[used.position.x+used.size.x*.5,used.end.y],"reference_height":maxi(1,used.size.y),"actual_state":actual}

static func paint(canvas:CanvasItem,card:Dictionary,requested:String,time:float,seed:int,height:float,at:Vector2,flipped:bool)->bool:
	var cell:Dictionary=frame(card,requested,time,seed)
	if cell.is_empty():return false
	var texture:Texture2D=Art.texture(str(cell.get("source","")))
	if texture==null:return false
	var r:Array=cell.get("rect",[]);var p:Array=cell.get("pivot",[])
	if r.size()!=4 or p.size()!=2:return false
	var source:=Rect2(float(r[0]),float(r[1]),float(r[2]),float(r[3]));var factor:float=height/maxf(1,float(cell.get("reference_height",source.size.y)))
	var destination:=Rect2(at-Vector2(float(p[0]),float(p[1]))*factor,source.size*factor)
	if flipped:destination.position.x=at.x+(float(p[0])-source.size.x)*factor;destination.size.x=-destination.size.x
	canvas.draw_texture_rect_region(texture,destination,source)
	return true
