extends RefCounted
## Local presentation only: no simulation RNG, world transforms, commands or time-scale writes.
const Art=preload("res://scripts/character_art.gd")
var pulses:Array[Dictionary]=[]
var history:Array[Dictionary]=[]
var offset:=Vector2.ZERO
var strength:float=.75
var clock:float=0.0
var references:Dictionary={}
var catalog:Dictionary={}

func _init()->void:
	var source:Variant=JSON.parse_string(FileAccess.get_file_as_string("res://data/ship-reference.json"))
	if source is Dictionary:references=source.get("ships",{})
	var rows:Variant=JSON.parse_string(FileAccess.get_file_as_string("res://data/ships.json"))
	if rows is Dictionary:
		for card in rows.get("ships",[]):catalog[str(card.id)]=card

func reset()->void:
	pulses.clear();offset=Vector2.ZERO
	Art.clear_pose_events(catalog)

func firing_ship(event:Dictionary,view:Dictionary)->Dictionary:
	var id:Variant=event.get("ownShip",event.get("own_ship",null))
	for ship in view.get("ships",[]):
		if id!=null and str(ship.id)==str(id):return ship
	var matches:Array[Dictionary]=[]
	var text:=str(event.get("text",""))
	for ship in view.get("ships",[]):
		var name:=str(ship.get("name",""))
		if not name.is_empty() and (text.begins_with(name+" ·") or text.begins_with(name+" ") or text.begins_with(name+"：")):matches.append(ship)
	return matches[0] if matches.size()==1 else {}

func caliber_mm(ship:Dictionary)->float:
	# Prefer the identity already published to this seat, never a hidden contact/class representative.
	var resolved:Dictionary=Art.resolve(catalog,ship,false)
	var identity:=str(resolved.get("identity",""))
	var record:Dictionary=references.get(identity,references.get(str(ship.get("classId","")),{}))
	var caliber:=float(record.get("base",{}).get("gun",{}).get("caliber_mm",0))
	if caliber>0:return caliber
	# An own generic hull can publish its class without a character identity. Use a class
	# only when every matching registered card agrees on caliber; do not assign its portrait.
	var class_id:=str(ship.get("classId",""))
	var calibers:Dictionary={}
	if not class_id.is_empty():
		for card in catalog.values():
			if str(card.get("profile",""))!=class_id and str(card.get("class_id",""))!=class_id:continue
			var value:=float(references.get(str(card.id),{}).get("base",{}).get("gun",{}).get("caliber_mm",0))
			if value>0:calibers[value]=true
	return float(calibers.keys()[0]) if calibers.size()==1 else 0.0

func fire_profile(caliber:float)->Dictionary:
	if caliber<=0:return {"tier":"unknown","power":3.0,"duration":.19,"frequency":27.0}
	if caliber<=139:
		var t:=clampf((caliber-75)/64,0,1)
		return {"tier":"light","power":lerpf(1.8,3.2,t),"duration":lerpf(.12,.18,t),"frequency":lerpf(40,32,t)}
	if caliber<=219:
		var t:=clampf((caliber-140)/79,0,1)
		return {"tier":"medium","power":lerpf(4.4,6.3,t),"duration":lerpf(.22,.29,t),"frequency":lerpf(28,23,t)}
	if caliber<=349:
		var t:=clampf((caliber-220)/129,0,1)
		return {"tier":"heavy","power":lerpf(6.5,8.4,t),"duration":lerpf(.30,.39,t),"frequency":lerpf(23,19,t)}
	var t:=clampf((caliber-350)/110,0,1)
	return {"tier":"capital","power":lerpf(9,11,t),"duration":lerpf(.40,.48,t),"frequency":lerpf(18,14,t)}

func fire(ship:Dictionary,event:Dictionary,weight:float=1.0)->void:
	var resolved:Dictionary=Art.resolve(catalog,ship,false)
	Art.trigger_pose(resolved.get("card",{}),"fire",.28)
	var caliber:=caliber_mm(ship)
	var profile:=fire_profile(caliber)
	var point:=Vector2(float(event.get("x",ship.get("x",0))),float(event.get("y",ship.get("y",0))))
	var angle:=deg_to_rad(float(ship.get("heading",0)))
	var direction:=Vector2(sin(angle),-cos(angle))
	_add("fire",point,profile,float(profile.power)*weight,-direction,caliber,str(ship.get("id","")))

func hurt(ship:Dictionary,fraction:float)->void:
	if fraction>0.0:
		var resolved:Dictionary=Art.resolve(catalog,ship,false)
		Art.trigger_pose(resolved.get("card",{}),"hit",.32)
	var power:=clampf(3.6+sqrt(maxf(fraction,0.0))*14.0,3.6,11.0)
	var profile:Dictionary={"tier":"damage","duration":.22+minf(.2,fraction),"frequency":24.0}
	_add("damage",Vector2(float(ship.get("x",0)),float(ship.get("y",0))),profile,power,Vector2(.6,.8),0,str(ship.get("id","")))

func _add(kind:String,point:Vector2,profile:Dictionary,power:float,direction:Vector2,caliber:float,id:String)->void:
	# Turrets in a salvo share one recoil. Rapid events still have bounded, decaying feedback.
	for pulse in pulses:
		if str(pulse.kind)==kind and str(pulse.ship)==id and float(pulse.age)<.065:
			pulse.power=maxf(float(pulse.power),power);return
	var item:Dictionary={"kind":kind,"point":point,"age":0.0,"duration":float(profile.duration),"frequency":float(profile.frequency),"power":power,"direction":direction,"tier":str(profile.tier),"caliber_mm":caliber,"ship":id}
	pulses.append(item)
	while pulses.size()>8:pulses.pop_front()
	history.append(item.duplicate(true))
	if history.size()>64:history.pop_front()

func advance(delta:float)->Vector2:
	clock+=maxf(delta,0)
	var total:=Vector2.ZERO
	for pulse in pulses:
		pulse.age=float(pulse.age)+maxf(delta,0)
		var t:=clampf(float(pulse.age)/float(pulse.duration),0,1)
		var envelope:=pow(1-t,2.0)
		var phase:=float(pulse.age)*float(pulse.frequency)*TAU
		var direction:Vector2=pulse.direction
		var wave:=direction*(.55*cos(phase)+.35*exp(-t*9.0))+Vector2(-direction.y,direction.x)*.32*sin(phase*1.37)
		total+=wave*float(pulse.power)*envelope
	pulses=pulses.filter(func(pulse):return float(pulse.age)<float(pulse.duration))
	offset=total.limit_length(11.0)*clampf(strength,0,1)
	return offset
