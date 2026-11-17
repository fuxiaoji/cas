extends SceneTree
func _initialize()->void:call_deferred("run")
func run()->void:
	var account=load("res://scripts/economy.gd").new()
	var loaded:Dictionary=account.load_state()
	if not loaded.get("ok",false):push_error(str(loaded));quit(1);return
	var path:String=ProjectSettings.globalize_path(account.save_path)
	var backup:String=path+".before-test-grant-2026-11-12"
	if not FileAccess.file_exists(backup):DirAccess.copy_absolute(path,backup)
	var before:Dictionary={"ships":account.state.owned.size(),"formation":account.formation.duplicate(),"active_run":str(account.state.get("active_run",{}).get("run_id",""))}
	var grant:Dictionary=load("res://scripts/test_account_resources.gd").apply(account,true)
	print("CURRENT_TEST_RESOURCES ",JSON.stringify({"ok":grant.get("ok",false),"path":path,"backup":backup,"before":before,"after":{"ships":account.state.owned.size(),"formation":account.formation.duplicate(),"active_run":str(account.state.get("active_run",{}).get("run_id",""))},"wallet":account.wallet()}))
	quit(0 if grant.get("ok",false) else 1)
