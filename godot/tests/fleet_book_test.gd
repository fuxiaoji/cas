extends SceneTree
const Economy=preload("res://scripts/economy.gd")
const Fleets=preload("res://scripts/fleet_manager.gd")
var checks:=0
var failures:Array[String]=[]
func check(ok:bool,message:String) -> void:
	checks+=1
	if not ok: failures.append(message);push_error(message)
func _initialize() -> void: call_deferred("review")
func review() -> void:
	var path:="user://tests/free-fleets-%d.json"%OS.get_process_id()
	var account=Economy.new(path);account.load_state()
	var manager=Fleets.new(account)
	check(manager.rows().size()==1,"legacy formation migrates to one saved fleet")
	check(manager.groups()[0].ships==account.formation,"migration preserves exact owned identities")
	var ids:Array=[]
	for card in account.catalog:
		if card.get("playable",false):
			account.state.owned[str(card.id)]=account._new_owned(str(card.id));ids.append(str(card.id))
		if ids.size()==15: break
	check(ids.size()==15,"isolated catalogue fixture supplies fifteen distinct owned hulls")
	check(manager.set_members(ids.slice(0,8)).ok,"one fleet accepts more than the former three/five hull limit")
	check(account.formation.size()==8,"eight hulls retained in deployed union")
	check(account.save_state().ok,"large fleet passes account persistence validation")
	var first:String=manager.active().id
	check(manager.create("第二舰队").ok,"create independently saved fleet")
	var second:String=manager.active().id
	check(manager.set_members(ids.slice(8,15)).ok,"second composition accepts seven hulls")
	check(manager.select(second,true).ok,"multiple distinct fleets selected together")
	check(manager.groups().size()==2 and account.formation.size()==15,"two groups deploy fifteen unique identities")
	check(manager.create("候补编队").ok,"third saved fleet")
	var reserve:String=manager.active().id
	check(manager.set_members([ids[0]]).ok,"same hull may appear in an undeployed saved alternative")
	var before:Dictionary=account.state.duplicate(true)
	check(not manager.select(reserve,true).ok,"same owned hull cannot deploy twice")
	check(account.state==before,"duplicate selection rolls back atomically")
	check(manager.rename(reserve,"机动预备队").ok,"rename composition persists")
	for i in range(8): check(manager.create("巡航队%d"%i).ok,"additional saved fleet %d"%i)
	check(manager.rows().size()==11,"no cap on saved compositions")
	check(not manager.select(str(manager.active().id),true).ok,"empty compositions cannot be deployed")
	check(not manager.select("missing",true).ok,"unknown group rejected")
	check(manager.secretary(str(ids[9]),1.35).ok,"owned secretary and scale saved")
	var reload_account=Economy.new(path);check(reload_account.load_state().ok,"account reload")
	var reloaded=Fleets.new(reload_account)
	check(reloaded.rows().size()==11 and reloaded.groups().size()==2,"all groups and deployment choices survive restart")
	check(reload_account.formation.size()==15,"large deployed union survives restart")
	check(str(reload_account.state.harbor.secretary)==str(ids[9]) and is_equal_approx(float(reload_account.state.harbor.scale),1.35),"secretary identity and scale survive restart")
	account.state.active_run={"run_id":"locked-fixture"}
	check(not manager.toggle_member(str(ids[0])).ok and not manager.create().ok and not manager.select(first,false).ok,"active sortie locks composition and deployment changes")
	print("FLEET_BOOK: %d/%d"%[checks-failures.size(),checks])
	var output:=ProjectSettings.globalize_path("res://../artifacts/godot/free-fleets")
	DirAccess.make_dir_recursive_absolute(output)
	var file:=FileAccess.open(output+"/receipt.json",FileAccess.WRITE);file.store_string(JSON.stringify({"checks":checks,"failures":failures,"fixture":"isolated owned catalogue; no production account modified","members":15,"saved_fleets":11},"  "));file.close()
	quit(0 if failures.is_empty() else 1)
