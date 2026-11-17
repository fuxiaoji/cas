@tool
extends RefCounted
## Own-identity, semantic animation frames. Pixels never create another body.
static var catalogue:Dictionary={}
static var textures:Dictionary={}
static var loaded:bool=false
const TEXTURE_LIMIT:int=40
static func entry(id:String)->Dictionary:
	if not loaded:
		loaded=true
		for path in ["res://data/tactical-art-v2.json","res://data/tactical-expansion-art-v4.json"]:
			if not FileAccess.file_exists(path):continue
			var raw:Variant=JSON.parse_string(FileAccess.get_file_as_string(path))
			if not raw is Dictionary:continue
			var units:Variant=raw.get("units",{})
			if units is Dictionary:catalogue.merge(units,true)
			elif units is Array:for unit in units:catalogue[str(unit.get("id",""))]=unit
		var supplement:String="res://data/home-daily-art-v1.json"
		if FileAccess.file_exists(supplement):
			var raw:Variant=JSON.parse_string(FileAccess.get_file_as_string(supplement))
			if raw is Dictionary:
				for identity in raw.get("units",{}):
					var row:Dictionary=raw.units[identity]
					if not str(identity).begins_with("MCP-") or not bool(row.get("approved",false)) or row.get("frames",[]).is_empty():continue
					var item:Dictionary=catalogue.get(identity,{}).duplicate(true)
					item.merge(row,true);item["art_status"]="approved_identity_supplement";catalogue[identity]=item
	return catalogue.get(id,{})
static func available(id:String)->bool:
	var item:Dictionary=entry(id)
	return not item.get("frames",[]).is_empty() and str(item.get("art_status","")).begins_with("approved")
static func frame(id:String,state:String,time:float,seed:int=0)->Dictionary:
	var item:Dictionary=entry(id);var sequence:Array=item.get("animations",{}).get(state,[])
	if sequence.is_empty():sequence=item.get("animations",{}).get("idle",[])
	if sequence.is_empty():return {}
	var slot:int=0
	if state=="defeated":slot=posmod(seed,sequence.size())
	elif state=="idle":slot=mini(1,sequence.size()-1) if fposmod(time,3.7)>3.52 else 0
	elif state in ["walk","fire","search","bolt","heal"]:slot=posmod(int(floor(time*(9 if state=="walk" else 7))),sequence.size())
	elif state=="fall":slot=mini(int(floor(maxf(0,time)*7)),sequence.size()-1)
	var index:int=int(sequence[slot]);var frames:Array=item.get("frames",[])
	return frames[index] if index>=0 and index<frames.size() else {}
static func texture(path:String)->Texture2D:
	if textures.has(path):
		var value:Texture2D=textures[path];textures.erase(path);textures[path]=value;return value
	if not ResourceLoader.exists(path):return null
	var value:Texture2D=load(path)
	while textures.size()>=TEXTURE_LIMIT:textures.erase(textures.keys()[0])
	textures[path]=value;return value
static func paint(canvas:CanvasItem,id:String,state:String,time:float,seed:int,height:float,offset:Vector2,flipped:bool,tint:Color=Color.WHITE)->bool:
	var cell:Dictionary=frame(id,state,time,seed)
	if cell.is_empty():return false
	var tex:Texture2D=texture(str(cell.get("source","")))
	if tex==null:return false
	var rect:Array=cell.rect;var anchor:Array=cell.pivot
	var source:=Rect2(float(rect[0]),float(rect[1]),float(rect[2]),float(rect[3]))
	var factor:float=height/maxf(1,float(cell.reference_height))
	var destination:=Rect2(offset-Vector2(float(anchor[0]),float(anchor[1]))*factor,source.size*factor)
	# Reflect around the authored ground pivot, not the source rectangle centre.
	# Off-centre poses otherwise slide sideways whenever their facing changes.
	if flipped:destination.position.x=offset.x+(float(anchor[0])-source.size.x)*factor;destination.size.x=-destination.size.x
	canvas.draw_texture_rect_region(tex,destination,source,tint);return true
