extends SceneTree
## Only copies are loaded by services; the user's actual files are read-only.
var failures:Array[String]=[]
var checks:int=0
func _initialize()->void:call_deferred("run")
func check(value:bool,message:String)->void:
	checks+=1
	if not value:failures.append(message);push_error(message)
func run()->void:
	var output:String="res://../artifacts/island-war-v4/presentation/"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	var rows:Array=[]
	for suffix in ["",".bak"]:
		var original:String="user://cas_port_v1.json"+suffix
		var hash_before:String=FileAccess.get_sha256(original)
		var data:PackedByteArray=FileAccess.get_file_as_bytes(original)
		var parsed:Variant=JSON.parse_string(data.get_string_from_utf8())
		check(parsed is Dictionary and not parsed.is_empty(),"formal "+suffix+" is actual nonempty JSON")
		var copy:String=output+"formal-copy-%d%s.json"%[OS.get_process_id(),suffix]
		FileAccess.open(copy,FileAccess.WRITE).store_buffer(data)
		var account=load("res://scripts/economy.gd").new(copy)
		var loaded:Dictionary=account.load_state()
		check(loaded.get("ok",false) and not loaded.get("recovered",false),"current economy loads the exact isolated formal copy directly")
		if loaded.get("ok",false):
			var home=load("res://scripts/home_service.gd").new(account)
			check(home.latest_units().size()==27,"current home service reads the full new catalogue with the formal copy")
			check(not account.state.get("owned",{}).is_empty(),"actual owned fleet survives loading")
			rows.append({"source":original,"source_bytes":data.size(),"source_sha256":hash_before,"owned_ships":account.state.get("owned",{}).size(),"commander_level":account.state.get("commander",{}).get("level",0),"has_live_sortie":not account.state.get("active_run",{}).is_empty(),"copy_load_ok":true})
		check(FileAccess.get_sha256(original)==hash_before,"the original formal file remains byte-identical")
	var receipt:Dictionary={"ok":failures.is_empty(),"checks":checks,"failures":failures,"profiles":rows,"scope":"original source files only read; services load separately named copies, which may receive normal migrations"}
	FileAccess.open(output+"formal-profile-receipt.json",FileAccess.WRITE).store_string(JSON.stringify(receipt,"\t"));print(JSON.stringify(receipt));quit(0 if failures.is_empty() else 1)
