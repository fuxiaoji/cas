@tool
extends RefCounted
## Formation identity comes from the registered unit, never this sortie's body count.
const SYMBOLS:Dictionary={"brigade":"X","division":"XX","regiment":"III","battalion":"II","company":"I"}
const NAMES:Dictionary={"brigade":"旅","division":"师","regiment":"团","battalion":"营","company":"连"}
static func resolve(metadata:Dictionary)->Dictionary:
	var echelon:String=str(metadata.get("formation_echelon",metadata.get("echelon",""))).to_lower()
	var label:String=str(metadata.get("designation",metadata.get("formation_label","")))
	if not SYMBOLS.has(echelon):
		echelon=""
		for candidate in ["division","brigade","regiment","battalion","company"]:
			if label.contains(str(NAMES[candidate])):echelon=candidate;break
	return {"echelon":echelon,"symbol":str(SYMBOLS.get(echelon,"")),"label":label}
static func symbol(echelon:String)->String:return str(SYMBOLS.get(echelon,""))
