extends RefCounted
## Navigation tests wait for the same transient input barrier as a player.
## A deadline catches a broken animation rather than disabling or bypassing it.
static func wait_for_route(tree:SceneTree,app:Node) -> void:
	var active:Node=app.get("page_transition") if is_instance_valid(app) else null
	var seconds:float=maxf(float(active.get("duration"))+.6,1.2) if is_instance_valid(active) else 1.2
	var deadline:=Time.get_ticks_msec()+int(seconds*1000.0)
	while is_instance_valid(app) and Time.get_ticks_msec()<deadline:
		var transition:Node=app.get("page_transition")
		if not is_instance_valid(transition) or not transition.is_busy():break
		await tree.process_frame
	await tree.process_frame
