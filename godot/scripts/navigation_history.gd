extends RefCounted
## UI history only. Battle snapshots, inventory and chapter progress stay in their services.
const PARENTS={"title":"title","harbor":"title","modes":"harbor","expedition":"modes","formation":"harbor","roster":"harbor","ship_detail":"roster","warehouse":"harbor","shop":"harbor","player":"harbor","recruit":"harbor","settings":"harbor","canon_catalog":"modes","canon_story":"canon_catalog","story_catalog":"modes","story_route":"story_catalog","chapter":"story_route","story":"story_catalog","resources":"modes","ladder":"modes","campaign":"modes","academy":"modes","challenge":"academy","activity":"harbor","mail":"harbor","archives":"harbor","result":"modes","home":"harbor","home_recruit":"home","home_story":"home"}
const TRANSIENT=["battle","result"]
var frames:Array[Dictionary]=[]
func visit(previous:String,next:String,context:Dictionary) -> void:
	if previous==next:return
	if next in ["title","harbor"]:
		frames.clear();return
	if previous.is_empty() or previous in TRANSIENT:return
	frames.append({"route":previous,"context":context.duplicate(true)})
	if frames.size()>64:frames.pop_front()
func previous(current:String,fallback:String="") -> Dictionary:
	while not frames.is_empty():
		var frame:Dictionary=frames.pop_back()
		if str(frame.route)!=current and str(frame.route) not in TRANSIENT:return frame
	return {"route":fallback if not fallback.is_empty() else "modes" if current=="arena" else str(PARENTS.get(current,"harbor")),"context":{}}
func return_to(route:String) -> Dictionary:
	while not frames.is_empty():
		var frame:Dictionary=frames.pop_back()
		if str(frame.route)==route:return frame
	return {"route":route,"context":{}}
