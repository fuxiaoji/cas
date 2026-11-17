extends Node
## Seat-authorized cosmetic rounds. Aggregate shell physics and every damage roll stay in Rust.
var sea: Control
var current: Dictionary = {}
var tick := -1
var epoch := -1
var readonly := false
var sample_age := 0.0
var active: Dictionary = {}
var metadata: Dictionary = {}
var seen: Dictionary = {}
var bursts: Array[Dictionary] = []
var splashes: Array[Dictionary] = []
var emitted_secondary := 0

func _process(delta: float) -> void:
	if not is_instance_valid(sea): return
	observe(sea.view, sea.projectile_readonly, sea.projectile_epoch)
	advance(delta)
	if not active.is_empty() or not bursts.is_empty() or not splashes.is_empty(): sea.queue_redraw()

func advance(delta: float) -> void:
	sample_age += maxf(delta, 0.0)
	for burst in bursts:
		burst.age = float(burst.age) + maxf(delta, 0.0)
		if float(burst.age) >= float(burst.duration) and not bool(burst.get("landed",false)):
			burst.landed = true
			_splash(burst.shot, true)
	bursts = bursts.filter(func(item): return float(item.age) < float(item.duration) + .03)
	for splash in splashes: splash.age = float(splash.age) + maxf(delta, 0.0)
	splashes = splashes.filter(func(item): return float(item.age) < float(item.duration))

func _point(row: Dictionary) -> Vector2:
	return Vector2(float(row.get("x",0)), float(row.get("y",0)))

func _reset(view: Dictionary, replay: bool, next_epoch: int) -> void:
	active.clear(); metadata.clear(); seen.clear(); bursts.clear(); splashes.clear()
	tick = int(view.get("tick",0)); epoch = next_epoch
	readonly = replay; sample_age = 0.0
	for shot in view.get("presentation",{}).get("shots",[]): seen[str(shot.get("id",""))] = true

func observe(view: Dictionary, replay: bool = false, epoch_override: int = 0) -> void:
	if view.is_empty():
		if tick >= 0: _reset({}, replay, epoch_override); tick = -1
		return
	var next_tick := int(view.get("tick",0))
	var reset := tick < 0 or next_tick < tick or epoch != epoch_override or readonly != replay
	if reset: _reset(view,replay,epoch_override)
	current = view
	if next_tick != tick: sample_age = 0.0
	metadata.clear()
	for shot in view.get("presentation",{}).get("shots",[]):
		if shot.has("shell_id"): metadata[str(shot.shell_id)] = shot
		var id := str(shot.get("id",""))
		if seen.has(id): continue
		seen[id] = true
		var age := next_tick - int(shot.get("tick",-100))
		if not replay and str(shot.get("battery","")) == "secondary" and age >= 0 and age <= 2 and shot.has_all(["from","to","barrels"]):
			bursts.append({"shot":shot.duplicate(true),"age":0.0,"duration":.34,"landed":false})
			emitted_secondary += 1
	# Only shots actually present in the authorized observation can have a main flight.
	var next_active: Dictionary = {}
	for shell in view.get("shells",[]):
		var id := str(shell.get("id",""))
		var row: Dictionary = shell.duplicate(true)
		row["caliber_mm"] = float(metadata.get(id,{}).get("caliber_mm",0))
		row["render_progress"] = float(active.get(id,{}).get("render_progress",row.get("progress",0)))
		next_active[id] = row
	if not reset and not replay:
		for id in active:
			var shell: Dictionary = active[id]
			if not next_active.has(id) and shell.has("to") and next_tick >= int(shell.get("impactTick",next_tick+1)):
				_splash(shell,false)
	active = next_active
	tick = next_tick
	# Bound retained IDs by the public stream horizon, without dropping active barrels.
	if seen.size() > 2048:
		seen.clear()
		for shot in view.get("presentation",{}).get("shots",[]): seen[str(shot.get("id",""))] = true
	while bursts.size() > 96: bursts.pop_front()
	while splashes.size() > 96: splashes.pop_front()

func _splash(shot: Dictionary, secondary: bool) -> void:
	if not shot.has("to"): return
	splashes.append({"point":_point(shot.to),"barrels":maxi(1,int(shot.get("barrels",1))),"age":0.0,"duration":.36 if secondary else .65,"secondary":secondary,"caliber_mm":float(shot.get("caliber_mm",0)),"heading":_point(shot.to)-_point(shot.get("from",shot.to))})

func profile(mm: float, secondary: bool) -> Dictionary:
	var weight := clampf((mm-75.0)/385.0,0,1) if mm > 0 else .28
	return {"radius":lerpf(1.6,3.1,weight) * (.68 if secondary else 1.0),"tail":lerpf(11,29,weight) * (.62 if secondary else 1.0),"gap":3.6 if secondary else 5.2,"color":Color("b9f3ed") if secondary else Color("ffcf86"),"height":.024 if secondary else .17}

func _progress(shell: Dictionary) -> float:
	var value := float(shell.get("progress",0))
	if not readonly and is_instance_valid(sea) and float(sea.projectile_rate) > 0:
		var duration := maxf(1,float(shell.get("impactTick",1))-float(shell.get("launchTick",0)))
		value += minf(.95,sample_age*float(sea.projectile_rate))/duration
	value = clampf(maxf(value,float(shell.get("render_progress",0))),0,1)
	shell.render_progress = value
	return value

func rounds() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for shell in active.values():
		var has_path: bool = shell.has_all(["from","to"])
		var progress := _progress(shell) if has_path else 0.0
		var count := maxi(1,int(shell.get("barrels",1)))
		for i in range(count):
			rows.append({"shell":shell,"lane":float(i)-float(count-1)*.5,"progress":progress,"secondary":false,"has_path":has_path})
	for burst in bursts:
		var shot: Dictionary = burst.shot
		var count := maxi(1,int(shot.get("barrels",1)))
		for i in range(count):
			rows.append({"shell":shot,"lane":float(i)-float(count-1)*.5,"progress":clampf(float(burst.age)/float(burst.duration),0,1),"secondary":true,"has_path":true})
	return rows

func _geometry(map: Control, round: Dictionary) -> Dictionary:
	var shell: Dictionary = round.shell
	var secondary: bool = round.secondary
	var style := profile(float(shell.get("caliber_mm",0)), secondary)
	var direction := Vector2(sin(deg_to_rad(float(shell.get("heading",0)))),-cos(deg_to_rad(float(shell.get("heading",0)))))
	var point: Vector2 = map.project(_point(shell))
	var ground := point
	if bool(round.has_path):
		var from: Vector2 = map.project(_point(shell.from))
		var to: Vector2 = map.project(_point(shell.to))
		var p: float = round.progress
		direction = (to-from).normalized()
		var perpendicular := Vector2(-direction.y,direction.x)
		# Screen-space fan separates every real barrel; it is not extra simulation scatter.
		var fan := perpendicular * float(round.lane) * float(style.gap) * (.45+.55*sin(p*PI))
		ground = from.lerp(to,p) + fan
		var height: float = minf(80,from.distance_to(to)*float(style.height))
		if shell.has("arcHeightM"):
			var scale_m: float = map.project(Vector2(1,0)).distance_to(map.project(Vector2.ZERO))
			height = minf(120,float(shell.arcHeightM)*scale_m)
		point = ground - Vector2(0,4*height*p*(1-p))
		# Tail follows the tangent of the same public ballistic arc.
		direction = ((to-from)-Vector2(0,4*height*(1-2*p))).normalized()
	return {"point":point,"ground":ground,"direction":direction,"style":style}

func paint(map: Control) -> void:
	for round in rounds():
		var g := _geometry(map,round)
		var shell: Dictionary = round.shell
		var style: Dictionary = g.style
		var friendly := bool(shell.get("own",str(shell.get("side","")) == str(current.get("side","allies")))) if not bool(round.secondary) else true
		var color: Color = style.color if friendly else Color("ff9b87")
		var p: Vector2 = g.point
		var direction: Vector2 = g.direction
		var tail: float = style.tail
		map.draw_line(g.ground-direction*3,g.ground+direction*3,Color(.02,.11,.16,.23),2,true)
		for step in range(3):
			var end := p-direction*tail*float(step)/3
			var start := p-direction*tail*float(step+1)/3
			map.draw_line(start,end,Color(color,.17+.2*(2-step)),float(style.radius)*(.7 if bool(round.secondary) else .9),true)
		map.draw_circle(p,float(style.radius)+1.8,Color(color,.12))
		map.draw_line(p-direction*float(style.radius),p+direction*float(style.radius)*1.4,color,float(style.radius)*1.55,true)
		map.draw_circle(p,float(style.radius)*.56,Color("fffbed"))
	# Secondary flashes are tied to actual new firing IDs, including actual misses.
	for burst in bursts:
		if float(burst.age) < .10:
			var at: Vector2 = map.project(_point(burst.shot.from))
			map.draw_circle(at,4.0*(1-float(burst.age)/.10),Color(.83,1,.98,.65))
	for splash in splashes:
		var t := float(splash.age)/float(splash.duration)
		var center: Vector2 = map.project(splash.point)
		var direction: Vector2 = splash.heading
		direction = Vector2(direction.x,-direction.y).normalized()
		var side := Vector2(-direction.y,direction.x)
		var secondary: bool = splash.secondary
		var style := profile(float(splash.caliber_mm),secondary)
		var weight := clampf((float(splash.caliber_mm)-75.0)/385.0,0,1) if float(splash.caliber_mm)>0 else .28
		var spread := 8.0 if secondary else lerpf(10,19,weight)
		var plume := 8.0 if secondary else lerpf(12,26,weight)
		for i in range(int(splash.barrels)):
			var at := center + side*(float(i)-float(int(splash.barrels)-1)*.5)*float(style.gap)*1.1
			var radius := 3.0+sqrt(t)*spread
			var color := Color(.77,.98,1,(1-t)*(.65 if secondary else .85))
			map.draw_arc(at,radius,0,TAU,20,color,1.0,true)
			map.draw_line(at,at-Vector2(0,sin(t*PI)*plume),color,1.2 if secondary else 2.2,true)
