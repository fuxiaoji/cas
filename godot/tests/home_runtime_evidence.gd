extends RefCounted
static func integral_json(value:Variant)->Variant:
	if value is Dictionary:
		var result:Dictionary={}
		for key in value:result[key]=integral_json(value[key])
		return result
	if value is Array:
		var result:Array=[]
		for item in value:result.append(integral_json(item))
		return result
	if value is float and is_finite(value) and value==floor(value):return int(value)
	return value
static func capture(bridge)->Dictionary:
	bridge.start()
	var pid:int=int(bridge.process.get("pid",0));var output:Array=[]
	OS.execute("powershell.exe",["-NoProfile","-Command","(Get-CimInstance Win32_Process -Filter 'ProcessId=%d').ExecutablePath"%pid],output,true)
	var executable:String="".join(output).strip_edges().replace("\\","/")
	var manifest:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://bin/core-current.json"))
	var installed:String=ProjectSettings.globalize_path("res://bin/"+str(manifest.get("executable",""))).replace("\\","/")
	return {"pid":pid,"actual_executable":executable,"actual_sha256":FileAccess.get_sha256(executable),"override_present":OS.has_environment("CAS_SIM_PATH"),"override":OS.get_environment("CAS_SIM_PATH"),"manifest":manifest,"verified_default":not OS.has_environment("CAS_SIM_PATH") and executable.to_lower()==installed.to_lower() and FileAccess.get_sha256(executable)==str(manifest.get("sha256",""))}
