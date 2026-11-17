extends SceneTree
## Deliberately separate test grant for the new map; never migrates a player save.
const Economy=preload("res://scripts/economy.gd")
const Home=preload("res://scripts/home_service.gd")
const ROOT:String="res://../artifacts/coastal-rebuild-20261116/"
const PATH:String=ROOT+"player.json"
var failures:Array[String]=[]
func _initialize()->void:call_deferred("run")
func run()->void:
	if OS.get_environment("CAS_COASTAL_V1")!="1":push_error("New coast flag required");quit(1);return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(ROOT))
	var account=Economy.new(ProjectSettings.globalize_path(PATH))
	if not FileAccess.file_exists(PATH):
		DirAccess.copy_absolute(ProjectSettings.globalize_path("res://../artifacts/world3d-integration-20261116/player.json"),ProjectSettings.globalize_path(PATH))
	if not account.load_state().get("ok",false):quit(1);return
	var home=Home.new(account)
	if not account.state.get("coastal_rebuild_v1",{}).get("prepared",false):
		home.state().buildings=[];home.state().seed=714;home.state().unlocked=true
		var view:Dictionary=home.geometry_v4()
		if not view.get("ok",false):push_error(str(view));quit(1);return
		var grid:Dictionary=view.construction_grid
		var origin:=Vector2(float(grid.origin.x),float(grid.origin.y));var spacing:float=float(grid.cell_size_m)
		var cells:Array=grid.buildable_cells.duplicate(true)
		cells.sort_custom(func(a,b):return (origin+(Vector2(float(a.x),float(a.y))+Vector2(.5,.5))*spacing).distance_squared_to(Vector2(14600,13045))<(origin+(Vector2(float(b.x),float(b.y))+Vector2(.5,.5))*spacing).distance_squared_to(Vector2(14600,13045)))
		for kind:String in Home.BUILDINGS:
			for key:String in Home.RESOURCE_NAMES:home.state().resources[key]=Home.RESOURCE_CAP
			var built:bool=false
			for raw:Dictionary in cells:
				var cell:=Vector2i(int(raw.x),int(raw.y))
				if home.building_at(cell).is_empty() and home.place(kind,cell).get("ok",false):built=true;break
			if not built:failures.append("No valid construction plot for "+kind);continue
			var building:Dictionary=home.state().buildings[-1]
			while home.upgrade(str(building.id)).get("ok",false):pass
		account.state["coastal_rebuild_v1"]={"prepared":failures.is_empty(),"map":"demo-coast-714","independent_test_grant":true,"old_map_migrated":false}
	for key:String in Home.RESOURCE_NAMES:home.state().resources[key]=Home.RESOURCE_CAP
	account.state.active_run={}
	if not account.save_state().get("ok",false):failures.append("Save new test profile")
	var report:Dictionary={"passed":failures.is_empty(),"failures":failures,"profile":ProjectSettings.globalize_path(PATH),"buildings":home.state().buildings.size(),"units":home.state().units.size(),"normal_account_written":false}
	var file=FileAccess.open(ROOT+"profile.json",FileAccess.WRITE);file.store_string(JSON.stringify(report,"  "));file.close();print("COASTAL_PROFILE ",JSON.stringify(report));quit(0 if failures.is_empty() else 1)
