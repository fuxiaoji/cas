@tool
extends RefCounted
## Original transparent vehicle artwork. Pure presentation; never changes world positions.
const Token=preload("res://scripts/tactical_type_token.gd")
static var catalogue:Dictionary={}
static var textures:Dictionary={}
static var vehicle_v3_catalogue:Dictionary={}
static func screen_offsets(rows:Array,projector:Callable,spacing:float=62)->Dictionary:
	# Separate equipment sharing one observed carrier lane. Thin links retain the
	# exact public position; no offset enters commands, paths, collisions or range.
	var offsets:Dictionary={};var sorted:Array=rows.duplicate();sorted.sort_custom(func(a,b):return int(a.id)<int(b.id))
	for row in sorted:
		var id:int=int(row.id)
		if offsets.has(id):continue
		var center:Vector2=projector.call(Vector2(float(row.x),float(row.y)));var cluster:Array=[]
		for other in sorted:
			if not offsets.has(int(other.id)) and center.distance_to(projector.call(Vector2(float(other.x),float(other.y))))<spacing+10:cluster.append(other)
		for index in range(cluster.size()):offsets[int(cluster[index].id)]=Vector2((index-(cluster.size()-1)*.5)*spacing,0)
	return offsets
static func _load()->void:
	if not catalogue.is_empty():return
	var path:String="res://data/transport-variants-v3.json"
	if FileAccess.file_exists(path):
		var data:Variant=JSON.parse_string(FileAccess.get_file_as_string(path))
		if data is Dictionary:catalogue=data.get("units",{})
static func family(row:Dictionary)->String:
	var kind:String=str(row.get("transport_kind",row.get("kind","")))
	if kind in ["gunship","transport_helicopter","attack_helicopter","air"]:return "helicopter"
	if kind in ["ifv","armor","tank"]:return "amphibious_vehicle"
	if kind in ["fast_boat","armored_boat","heavy_lander"]:return "landing_craft"
	return kind
static func specification(row:Dictionary,heading:float=0)->Dictionary:
	if str(row.get("equipment_version","")) in ["tactical-vehicles-v3","tactical-vehicles-v4"]:
		var authored:Dictionary=specification_v3(row,heading)
		if not authored.is_empty():return authored
	_load()
	var id:String=str(row.get("unit_id",row.get("company_id","")))
	var entry:Dictionary=catalogue.get(id,{})
	# V2 vehicles are shared equipment classes, not a unique combat asset per MCP.
	var kind:String=family(row)
	if str(row.get("art_version",""))=="tactical-art-v2":
		var equipment:String=str(row.get("transport_kind",row.get("kind","")))
		# Reuse original equipment drawings by a shared class, never by this
		# woman's identity. Capabilities come exclusively from the native model.
		var common:Dictionary={"landing_craft":"MCP-034","fast_boat":"MCP-011","armored_boat":"MCP-116","heavy_lander":"MCP-184","transport_helicopter":"MCP-240","helicopter":"MCP-240","attack_helicopter":"MCP-027","gunship":"MCP-027","amphibious_vehicle":"MCP-022","armor":"MCP-103","ifv":"MCP-103","tank":"MCP-103"}
		entry=catalogue.get(str(common.get(equipment,"")),{})
	if kind not in ["landing_craft","amphibious_vehicle","helicopter"]:return {}
	var stage:String=str(row.get("stage",""))
	var deployed:bool=stage in ["landing","deploying","unloading"]
	var destination:Variant=row.get("target")
	if destination is Dictionary and not bool(row.get("returning",false)):
		deployed=Vector2(float(row.get("x",0)),float(row.get("y",0))).distance_to(Vector2(float(destination.get("x",0)),float(destination.get("y",0))))<180
	var hp:float=float(row.get("hp",1));var maximum:float=maxf(.001,float(row.get("max_hp",hp)))
	if not entry.is_empty() and str(entry.get("default_kind",""))==kind:
		var frame:String="deploying" if deployed and kind!="helicopter" else "intact"
		if hp/maximum<.35 and entry.get("frames",{}).has("damaged"):frame="damaged"
		var intact:Dictionary=entry.frames.get("intact",{})
		var opaque:Array=intact.get("alpha_bbox_128",[0,0,397,397])
		var reference:float=float(entry.frames[frame].get("scale_reference",maxf(float(opaque[2])-float(opaque[0]),float(opaque[3])-float(opaque[1]))))
		return {"path":entry.atlas,"frame":entry.frames[frame],"scale_reference":reference,"family":kind,"exclusive":true,"length":entry.get("display_length",80),"rotor":kind=="helicopter","identity":id}
	var path:String="res://assets/tactical/transport/transport-atlas-v3.png"
	if not ResourceLoader.exists(path):return {}
	var texture:Texture2D=_texture(path);var cell:Vector2=texture.get_size()/3
	var column:int={"landing_craft":0,"amphibious_vehicle":1,"helicopter":2}[kind]
	var line:int=2 if hp/maximum<.35 else 1 if deployed and kind!="helicopter" else 0
	return {"path":path,"frame":{"region":[column*cell.x,line*cell.y,cell.x,cell.y],"anchor":[cell.x*.5,cell.y*.5]},"family":kind,"exclusive":false,"length":80,"rotor":kind=="helicopter","identity":id}
static func specification_v3(row:Dictionary,heading:float=0)->Dictionary:
	if vehicle_v3_catalogue.is_empty():
		var path:String="res://data/tactical-vehicles-v3.json"
		if not FileAccess.file_exists(path):return {}
		var raw:Variant=JSON.parse_string(FileAccess.get_file_as_string(path))
		if raw is Dictionary:vehicle_v3_catalogue=raw.get("vehicles",{})
		var expansion:String="res://data/tactical-vehicles-v4.json"
		if FileAccess.file_exists(expansion):
			var extra:Variant=JSON.parse_string(FileAccess.get_file_as_string(expansion))
			if extra is Dictionary:vehicle_v3_catalogue.merge(extra.get("vehicles",{}),true)
	var kind:String=str(row.get("vehicle_kind",row.get("transport_kind",row.get("kind",""))))
	kind=str({"armor":"tank","ifv":"amphibious_vehicle","gunship":"attack_helicopter","helicopter":"transport_helicopter","parachute_aircraft":"transport_aircraft"}.get(kind,kind))
	var item:Dictionary=vehicle_v3_catalogue.get(kind,{})
	if item.is_empty():return {}
	var ordinal:int=posmod(int(floor((heading+PI*.25)/(PI*.5))),4)
	var key:String=["N","E","S","W"][ordinal]
	var frame:Dictionary=item.get("frames",{}).get(key,{})
	if frame.is_empty():return {}
	return {"path":str(item.get("atlas","")),"frame":frame,"scale_reference":float(frame.get("scale_reference",640)),"family":"emplacement" if kind=="aa_turret" else "aircraft" if kind=="transport_aircraft" else "helicopter" if kind in ["attack_helicopter","transport_helicopter"] else "amphibious_vehicle" if kind in ["tank","amphibious_vehicle","self_propelled_gun","amphibious_wheeled_ifv","amphibious_tracked_gun"] else "landing_craft","exclusive":true,"length":item.get("length_m",12),"rotor":kind in ["attack_helicopter","transport_helicopter"],"identity":str(row.get("unit_id","")),"rotation":wrapf(heading-ordinal*PI*.5,-PI,PI),"equipment_kind":kind,"direction":key}
static func _texture(path:String)->Texture2D:
	if not textures.has(path):textures[path]=load(path)
	return textures[path]
static func paint(canvas:CanvasItem,row:Dictionary,at:Vector2,length:float,heading:float,clock:float,moving:bool,selected:bool=false,role:String="infantry",firing:bool=false)->bool:
	var spec:Dictionary=specification(row,heading)
	if spec.is_empty() or not ResourceLoader.exists(str(spec.path)):return false
	var frame:Dictionary=spec.frame;var raw:Array=frame.region;var pivot:Array=frame.anchor
	var region:=Rect2(float(raw[0]),float(raw[1]),float(raw[2]),float(raw[3]))
	var factor:float=length/maxf(1,maxf(region.size.x,region.size.y))
	# Normalize by the measured opaque body, preserving the authored pivot.
	if spec.has("scale_reference"):factor=length/maxf(1,float(spec.scale_reference))
	elif frame.has("alpha_bbox_128"):
		var box:Array=frame.alpha_bbox_128
		factor=length/maxf(1,maxf(float(box[2])-float(box[0]),float(box[3])-float(box[1])))
	var target:=Rect2(-Vector2(float(pivot[0]),float(pivot[1]))*factor,region.size*factor)
	# The sprite is authored in four directions; wake and firing effects always
	# follow the actual heading, independently of the selected image frame.
	canvas.draw_set_transform(at,heading)
	if selected:canvas.draw_arc(Vector2.ZERO,length*.52,0,TAU,28,Color("f1dda1"),2,true)
	if (spec.family=="landing_craft" or (str(spec.get("equipment_kind","")) in ["amphibious_vehicle","amphibious_wheeled_ifv","amphibious_tracked_gun"] and (bool(row.get("waterborne",false)) or str(row.get("movement_domain",""))=="water"))) and moving:
		for index in range(3):
			var y:float=length*(.38+index*.13)+fposmod(clock*18,8)
			canvas.draw_arc(Vector2(0,y),length*(.2+index*.04),PI*1.1,PI*1.9,12,Color(.8,1,1,.35-index*.08),1.4,true)
	var health:float=float(row.get("hp",1))/maxf(.001,float(row.get("max_hp",row.get("hp",1))))
	var tint:Color=Color("e4b1a4") if str(row.get("side","allies"))=="axis" else Color.WHITE
	canvas.draw_set_transform(at,float(spec.get("rotation",heading)))
	canvas.draw_texture_rect_region(_texture(spec.path),target,region,tint*Color(1,.83,.76) if health<.35 else tint)
	canvas.draw_set_transform(at,heading)
	if health<.35:
		canvas.draw_circle(Vector2(length*.16,length*.22),length*.075,Color(.17,.21,.23,.45))
		canvas.draw_circle(Vector2(length*.2,length*.13),length*.09,Color(.2,.22,.24,.28))
	if bool(spec.rotor):
		var angle:float=clock*36
		var blade:Vector2=Vector2.from_angle(angle)*length*.44
		canvas.draw_line(-blade,blade,Color(.12,.2,.22,.55),2.1,true)
		blade=blade.rotated(PI*.5);canvas.draw_line(-blade,blade,Color(.68,.82,.81,.42),1.6,true)
	if firing:
		var muzzle:=Vector2(0,-length*.42)
		canvas.draw_circle(muzzle,5,Color(1,.9,.55,.7));canvas.draw_line(muzzle,muzzle+Vector2(0,-12),Color("fff0b4"),3,true)
	canvas.draw_set_transform(Vector2.ZERO)
	if not bool(spec.exclusive):Token.paint(canvas,Rect2(at+Vector2(length*.2,length*.1),Vector2(26,18)),role,"friendly",selected)
	return true
