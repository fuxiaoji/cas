extends RefCounted
## New authorization is an explicit recorded command; loading old replays stays read-only.
const VERSION:="cas-extraction-pilot-v3"
const CARGO_COMMANDS:=["cargo_place","cargo_drop","cargo_sort"]
static func command(enabled:bool,policy:String="balanced")->Dictionary:
	return {"op":"extraction_autopilot","enabled":enabled,"policy":policy,"version":VERSION}
static func resume(core,snapshot:Variant)->Dictionary:
	var pilot:Dictionary=core.view.get("salvage",{}).get("expedition",{}).get("autopilot",{})
	if str(pilot.get("version",""))!="cas-extraction-pilot-v2":return {"ok":true,"changed":false}
	var resume_cargo:bool=false
	if not bool(pilot.get("enabled",false)) and str(pilot.get("phase",""))=="manual":
		# Read the final command only. Never round-trip the native snapshot through JSON.
		var saved:Variant=JSON.parse_string(snapshot) if snapshot is String else snapshot
		if saved is Dictionary:
			var history:Array=saved.get("commands",[])
			if not history.is_empty():resume_cargo=str(history.back().get("request",{}).get("op","")) in CARGO_COMMANDS
	if not bool(pilot.get("enabled",false)) and not resume_cargo:return {"ok":true,"changed":false}
	var response:Dictionary=core.request(command(true,str(pilot.get("policy","balanced"))))
	if not response.get("ok",false):return response
	return {"ok":true,"changed":true,"message":"已恢复自动打捞 · 整理货舱不再关闭自动指挥" if resume_cargo else "自动指挥已更新 · 支持连续搜索与安全返航"}
