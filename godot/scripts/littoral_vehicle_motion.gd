extends RefCounted
## One bounded interpolation record per real vehicle. No position enters commands.
var rows:Dictionary={}
var last_tick:float=-1
var interval:float=.1
func observe(observed:Array,tick:float)->void:
	if tick<last_tick-.0001:clear()
	var advanced:bool=tick>last_tick+.00001
	if advanced and last_tick>=0:interval=clampf(tick-last_tick,.01,1)
	var present:Dictionary={}
	for row in observed:
		var id:int=int(row.id);present[id]=true
		var world:=Vector2(float(row.x),float(row.y))
		if not rows.has(id):rows[id]={"start":world,"end":world,"at":world,"fraction":1.0,"heading":deg_to_rad(float(row.get("heading",0))),"target_heading":deg_to_rad(float(row.get("heading",0))),"moving":false}
		elif advanced:
			var state:Dictionary=rows[id];var delta_world:Vector2=world-state.end
			state.start=state.at;state.end=world;state.fraction=0.0;state.moving=delta_world.length_squared()>.001
			if state.moving:state.target_heading=atan2(delta_world.x,delta_world.y)
	for id in rows.keys():
		if not present.has(id):rows.erase(id)
	last_tick=tick
func advance(delta:float,rate:float,playing:bool)->void:
	if not playing:return
	for state in rows.values():
		state.fraction=minf(1,state.fraction+delta*rate/maxf(.01,interval))
		state.at=(state.start as Vector2).lerp(state.end,state.fraction)
		state.heading=lerp_angle(state.heading,state.target_heading,1-exp(-delta*14*minf(rate,2)))
func clear()->void:rows.clear();last_tick=-1
