extends Control
## One trace per published shot. No animation timer produces a shot or a hit.
const LIMIT:int=192
var source_map
var records:Dictionary={}
var simulation_tick:float=0
var observed_tick:float=0
func _ready()->void:mouse_filter=Control.MOUSE_FILTER_IGNORE;clip_contents=true
func observe(data:Dictionary,reset:bool=false)->void:
	var now:float=float(data.get("tick",0))
	if reset or now<observed_tick:records.clear()
	observed_tick=now;simulation_tick=now
	if str(data.get("equipment_version","")) not in ["tactical-vehicles-v3","tactical-vehicles-v4"]:records.clear();return
	for shot in data.get("shots",[]):
		var model:String=str(shot.get("weapon_id",""))
		var weapon:String=str(shot.get("weapon_family_id",model))
		if model.is_empty() or str(shot.get("kind","")) in ["naval","mortar","air_strike"]:continue
		var key:String=str(shot.get("id",""))
		if records.has(key):continue
		var start:=Vector2(float(shot.get("x",0)),float(shot.get("y",0)))
		var end:=Vector2(float(shot.get("target_x",start.x)),float(shot.get("target_y",start.y)))
		var flight:float=maxf(.06,float(shot.get("flight_seconds",start.distance_to(end)/maxf(1,float(shot.get("speed",1200))))))
		records[key]={"start":start,"end":end,"tick":float(shot.get("tick",now)),"flight":flight,"weapon":weapon,"weapon_id":model,"radius":float(shot.get("blast_radius",0))}
	for key in records.keys():
		if now-float(records[key].tick)>float(records[key].flight)+.25:records.erase(key)
	while records.size()>LIMIT:records.erase(records.keys()[0])
	queue_redraw()
func _process(delta:float)->void:
	if not is_instance_valid(source_map) or not source_map.playing or records.is_empty():return
	simulation_tick=minf(observed_tick+.1,simulation_tick+delta*source_map.playback_rate);queue_redraw()
func _draw()->void:
	if not is_instance_valid(source_map) or source_map.miniature:return
	for record in records.values():
		var age:float=simulation_tick-float(record.tick)
		if age<0 or age>float(record.flight)+.18:continue
		var from:Vector2=source_map.project(record.start);var to:Vector2=source_map.project(record.end)
		if not Rect2(from,Vector2.ZERO).expand(to).grow(20).intersects(Rect2(Vector2.ZERO,size)):continue
		var progress:float=clampf(age/float(record.flight),0,1)
		var weapon:String=str(record.weapon)
		var grenade:bool=weapon in ["grenade","demolition_charge"]
		var rocket:bool="rocket" in weapon or "rpg" in weapon or "missile" in weapon
		var sniper:bool="sniper" in weapon
		var at:Vector2=from.lerp(to,progress)
		var trail:Vector2=from.lerp(to,maxf(0,progress-(.2 if rocket else .06)))
		if grenade:
			var arc_height:float=clampf(from.distance_to(to)*.25,18,60)
			at.y-=sin(progress*PI)*arc_height
			var previous:float=maxf(0,progress-.14)
			trail=from.lerp(to,previous)-Vector2(0,sin(previous*PI)*arc_height)
		var color:=Color("f4ae62") if rocket else Color("d7f3ff") if sniper else Color("ffe8a3")
		if progress<1:
			if rocket:draw_line(trail,at,Color(.78,.75,.63,.42),4,true)
			draw_line(trail,at,color,2 if rocket else 1.5 if sniper else 1,true)
			draw_circle(at,3 if grenade else 2.3 if rocket else 1,color)
		elif age-float(record.flight)<.14:
			var alpha:float=1-(age-float(record.flight))/.14
			var blast:float=clampf(source_map.project(record.end+Vector2(float(record.radius),0)).distance_to(to),4,90) if grenade else 8 if rocket else 3
			draw_arc(to,2+(1-alpha)*blast,0,TAU,24,Color(color,alpha),2 if grenade else 1.2,true)
