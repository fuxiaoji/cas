extends RefCounted
## One resolver for every page and battlefield. Never infer a personal identity from a class.
static var textures:Dictionary={}
# The cache owns only recent images; visible Controls keep their own references.
const TEXTURE_CACHE_LIMIT:int=32
static var texture_access:Dictionary={}
static var access_sequence:int=0
# Verified from empress-augusta-bay.json English source names and roster-crosswalk.
# These are display transliterations; they do not alter historical scenario data.
const NAME_ALIASES={"奥兹本":"IBS-U-USN-CF-AUSBURNE","斯坦利":"IBS-U-USN-STANLY","富特":"IBS-U-USN-FOOTE","丹佛":"IBS-U-USN-UNNAMED-T01-R29"}

static func clean(value:Variant) -> String:
	var name:=str(value).strip_edges().to_lower()
	for prefix in ["uss ","ijn ","hms ","hmas "]:
		name=name.trim_prefix(prefix)
	return name.trim_suffix("号").replace(" ","").replace("·","")

static func resolve(cards:Dictionary, ship:Dictionary, allow_representative:=true) -> Dictionary:
	var identity:=str(ship.get("characterId",ship.get("identity",ship.get("character",""))))
	if cards.has(identity): return {"card":cards[identity],"identity":identity,"representative":false,"mapping":"exact_identity"}
	var name:=clean(ship.get("name",""))
	if NAME_ALIASES.has(name) and cards.has(NAME_ALIASES[name]):
		var alias_id:String=NAME_ALIASES[name]
		return {"card":cards[alias_id],"identity":alias_id,"representative":false,"mapping":"verified_source_alias"}
	var matches:Array=[]
	if not name.is_empty():
		for card in cards.values():
			if clean(card.get("name",""))==name: matches.append(card)
	if matches.size()==1:
		return {"card":matches[0],"identity":str(matches[0].id),"representative":false,"mapping":"registered_exact_name"}
	if not allow_representative: return {"card":{},"identity":"","representative":false,"mapping":"unmapped"}
	var class_id:=str(ship.get("classId",ship.get("class","")))
	var candidates:Array=[]
	for card in cards.values():
		if str(card.get("profile",""))==class_id or str(card.get("class_id",""))==class_id: candidates.append(card)
	candidates.sort_custom(func(a,b):return str(a.id)<str(b.id))
	for candidate in candidates:
		if clean(candidate.get("name",""))==clean(candidate.get("class","")):
			return {"card":candidate,"identity":str(candidate.id),"representative":true,"mapping":"class_representative"}
	if not candidates.is_empty(): return {"card":candidates[0],"identity":str(candidates[0].id),"representative":true,"mapping":"class_representative"}
	return {"card":{},"identity":"","representative":false,"mapping":"unmapped"}

static func projection(card:Dictionary) -> Dictionary:
	for field in ["chibi_generated","chibi","chibi_reference","portrait"]:
		var path:=str(card.get(field,""))
		if not path.is_empty() and ResourceLoader.exists(path):
			return {"path":path,"kind":"portrait_miniature" if field=="portrait" else "reference_sd" if field=="chibi_reference" or path.contains("/chibis/") else "generated_chibi"}
	return {"path":"","kind":"none"}

static func texture(path:String) -> Texture2D:
	if path.is_empty() or not ResourceLoader.exists(path):return null
	access_sequence+=1;texture_access[path]=access_sequence
	if not textures.has(path):
		textures[path]=load(path)
		while textures.size()>TEXTURE_CACHE_LIMIT:
			var oldest:String="";var sequence:int=access_sequence+1
			for key in textures:
				if int(texture_access.get(key,0))<sequence:oldest=key;sequence=int(texture_access.get(key,0))
			textures.erase(oldest);texture_access.erase(oldest)
	return textures[path]

static func pose_texture(card:Dictionary, state:String="idle", phase:float=0.0) -> Texture2D:
	var poses:Dictionary=card.get("chibi_poses",{})
	var animations:Dictionary=card.get("chibi_animations",{})
	var pose:=state
	if animations.has(state):
		var animation:Dictionary=animations[state]
		var frames:Array=animation.get("frames",[])
		if not frames.is_empty():
			var frame:=int(floor(maxf(phase,0.0)*maxf(float(animation.get("fps",1.0)),0.01)))%frames.size()
			pose=str(frames[frame])
	if poses.has(pose):
		var source:=texture(str(poses[pose]))
		if source!=null:return source
	return texture(str(projection(card).path))

static func trigger_pose(card:Dictionary, state:String, duration:float=0.3) -> void:
	var poses:Dictionary=card.get("chibi_poses",{})
	if not poses.has(state) or texture(str(poses[state]))==null:return
	var identity:=str(card.get("id",""))
	if identity.is_empty():return
	card["_chibi_pose_event"]={"state":state,"until_ms":Time.get_ticks_msec()+int(maxf(duration,0.0)*1000.0)}

static func clear_pose_events(registry:Dictionary={}) -> void:
	for card:Variant in registry.values():
		if card is Dictionary:card.erase("_chibi_pose_event")

static func active_pose(card:Dictionary, moving:bool=false) -> String:
	var explicit:=str(card.get("chibi_pose",""))
	if not explicit.is_empty():return explicit
	if card.has("_chibi_pose_event"):
		var event:Dictionary=card["_chibi_pose_event"]
		if Time.get_ticks_msec()<int(event.until_ms):return str(event.state)
		card.erase("_chibi_pose_event")
	return "walk" if moving else "idle"

static func draw(canvas:Control, card:Dictionary, at:Vector2, height:float, moving:=false, phase:=0.0) -> bool:
	var source:=pose_texture(card,active_pose(card,moving),phase)
	if source==null:return false
	var extent:=source.get_size()*(height/source.get_height())
	var lift:=absf(sin(phase*5.5))*3.0 if moving else sin(phase*1.8)*.5
	canvas.draw_texture_rect(source,Rect2(at-Vector2(extent.x*.5,extent.y+8+lift),extent),false)
	return true

static func visual_card(card:Dictionary, registry:Dictionary={})->Dictionary:
	var current:Dictionary=registry.get(str(card.get("id","")),{})
	if current.is_empty():return card
	# Only visual fields are substituted; battle IDs and numerical fields remain
	# the data supplied by the original consumer.
	var result:Dictionary=card.duplicate()
	for field in ["portrait","chibi","chibi_generated","chibi_poses","chibi_animations","atlas","animation_manifest","appearance_id"]:
		if current.has(field):result[field]=current[field]
	return result
