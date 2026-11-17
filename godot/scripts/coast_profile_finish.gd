extends SceneTree
## Complete only the explicitly separate, newly generated coastal QA profile.
const Economy=preload("res://scripts/economy.gd")
const Home=preload("res://scripts/home_service.gd")
const Resources=preload("res://scripts/test_account_resources.gd")
const PATH:String="res://../artifacts/world3d-integration-20261116/player.json"
var failures:Array[String]=[]
func _initialize()->void:call_deferred("run")
func run()->void:
	var account=Economy.new(ProjectSettings.globalize_path(PATH))
	if not account.load_state().get("ok",false):quit(1);return
	var home=Home.new(account)
	for row in home.latest_units():home._own_unit(str(row.id))
	for key in Home.RESOURCE_NAMES:home.state().resources[key]=Home.RESOURCE_CAP
	for kind in Home.BUILDINGS:
		if home.state().buildings.any(func(row):return str(row.kind)==str(kind)):continue
		var built:bool=false
		for cell in home.geometry_v4().get("construction_grid",{}).get("buildable_cells",[]):
			var at:=Vector2i(int(cell.x),int(cell.y))
			if home.building_at(at).is_empty() and home.place(str(kind),at).get("ok",false):built=true;break
		if not built:failures.append("place "+str(kind))
	for building in home.state().buildings:
		while home.upgrade(str(building.id)).get("ok",false):pass
	for key in Home.RESOURCE_NAMES:home.state().resources[key]=Home.RESOURCE_CAP
	Resources.apply(account)
	# QA island grant uses legal native addresses near HQ, rather than scattering
	# test facilities across the legacy 12x9 scan. No campaign clear is awarded.
	if not account.state.get("coastal_qa_profile",{}).get("compact_base",false):
		var old:Array=home.state().buildings.duplicate(true)
		var headquarters:Dictionary={}
		for building in old:
			if str(building.kind)=="hq":headquarters=building;break
		if not headquarters.is_empty():
			home.state().buildings=[headquarters]
			var cells:Array=home.geometry_v4().get("construction_grid",{}).get("buildable_cells",[]).duplicate()
			var middle:=Vector2(float(headquarters.cell.x),float(headquarters.cell.y))
			cells.sort_custom(func(a,b):return Vector2(float(a.x),float(a.y)).distance_squared_to(middle)<Vector2(float(b.x),float(b.y)).distance_squared_to(middle))
			for building in old:
				if str(building.kind)=="hq":continue
				for cell in cells:
					var at:=Vector2i(int(cell.x),int(cell.y))
					if not home.building_at(at).is_empty():continue
					if home.geometry_candidate_v4(str(building.kind),at).get("ok",false):building.cell={"x":at.x,"y":at.y};home.state().buildings.append(building);break
			if home.state().buildings.size()!=old.size():failures.append("compact legal base retained every facility")
	if account.state.get("progression",{}).get("first_voyage_canon") is Dictionary:
		account.state.progression.first_voyage_canon.active=false
	account.state["coastal_qa_profile"]={"version":"coastal-play-20261116","isolated":true,"all_published_units":27,"story_and_tutorial_not_forged":true}
	account.state.coastal_qa_profile["compact_base"]=true
	if not account.save_state().get("ok",false):failures.append("save")
	var report:Dictionary={"passed":failures.is_empty(),"failures":failures,"units":home.state().units.size(),"buildings":home.state().buildings.size(),"hq_level":home.development().level(),"profile":ProjectSettings.globalize_path(PATH),"normal_account_written":false}
	var file=FileAccess.open("res://../artifacts/world3d-integration-20261116/profile-receipt.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"  "));file.close();print("COAST_PROFILE ",JSON.stringify(report));quit(0 if failures.is_empty() else 1)
