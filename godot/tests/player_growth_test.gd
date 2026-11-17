extends SceneTree
const Economy=preload("res://scripts/economy.gd")
const Meta=preload("res://scripts/meta_economy.gd")
var failures:Array[String]=[]
var checks:=0
func _initialize()->void:call_deferred("run")
func check(value:bool,title:String)->void:
	checks+=1
	if not value:failures.append(title);push_error(title)
func run()->void:
	var path:="user://tests/player-growth-%d.json"%OS.get_process_id()
	var e=Economy.new(path);e.load_state()
	var id:=str(e.formation[0]);var ship:Dictionary=e.state.owned[id]
	check(e.player_profile().level==1 and e.material_catalog().size()==6,"new commander and material bins")
	check(e.mission_catalog("resources").size()==12 and e.mission_catalog("resources").filter(func(row):return row.unlocked).size()==4,"four resource families in three unlock tiers")
	check(not e.preview_sortie(42,false,{"kind":"resources","id":"training-t2"}).ok,"locked tier cannot launch via direct API")
	var before:Dictionary=e.state.duplicate(true)
	var earned:Dictionary=e.grant_player_xp("first",450)
	check(earned.level==4 and e.grant_player_xp("first",450).xp==0,"commander threshold and duplicate source")
	check(e._commit(before,"test first victory").ok,"commander reward shares save transaction")
	ship.level=10;ship.xp=360;e.state.wallet.core_t1=10;e.state.wallet.credits=5000
	check(not e.train_material(id,1).ok,"cap blocks training before breakthrough")
	var wallet:Dictionary=e.wallet()
	var ascent:Dictionary=e.ascend_ship(id,"ascend-one")
	check(ascent.ok and e.growth_profile(id).level_cap==20 and int(ship.level)>10,"breakthrough consumes banked experience")
	check(int(e.wallet().core_t1)==int(wallet.core_t1)-4 and int(e.wallet().credits)==int(wallet.credits)-400,"breakthrough displayed costs debited")
	check(e.ascend_ship(id,"ascend-one").get("duplicate",false),"breakthrough retry cannot debit twice")
	e.state.wallet.training_t3=2;e.state.wallet.credits=5000
	var xp_before:=int(ship.xp);var materials_before:=int(e.wallet().training_t3)
	check(e.train_material(id,3,1,"high-train").ok and int(e.wallet().training_t3)==materials_before-1,"high tier training uses actual material")
	check(e.train_material(id,3,1,"high-train").get("duplicate",false) and int(e.wallet().training_t3)==materials_before-1,"training request replay idempotent")
	e.state.wallet.core_t1=6;var t2:=int(e.wallet().core_t2)
	check(e.fuse_material("core_t1",2).ok and int(e.wallet().core_t2)==t2+2 and int(e.wallet().core_t1)==0,"core synthesis three to one")
	check(not e.fuse_material("core_t3").ok and not e.fuse_material("core_t1",-1).ok,"invalid synthesis cannot mint materials")
	var item:String=e._create_item("equipment");e.state.inventory.equipment=int(e.state.inventory.equipment)+1
	e.state.wallet.core_t1=10;e.state.wallet.credits=5000
	var quality:=int(e.state.item_instances[item].quality);var budget:=int(e.state.item_instances[item].bonus_bp)
	check(e.refit_equipment(item,"propulsion","refit-one").ok,"selectable propulsion refit")
	check(int(e.state.item_instances[item].quality)==quality and int(e.state.item_instances[item].bonus_bp)==budget,"refit preserves rarity and total power budget")
	check(e.assign_item(id,"equipment",item).ok,"typed equipment assignment")
	var profile:Dictionary=e.growth_profile(id)
	check(float(profile.bonuses.speed)>float(profile.bonuses.hp) and is_equal_approx(float(profile.bonuses.hp),float(profile.bonuses.firepower)),"propulsion has a real exclusive speed benefit")
	var frozen:Dictionary=e.state.duplicate(true);var prior_path:String=e.save_path
	e.save_path="res://data/player-growth.tres/impossible"
	check(not e.refit_equipment(item,"bulkhead").ok and e.state==frozen,"failed storage rolls back refit costs and item")
	e.save_path=prior_path
	e.save_state();var restored=Economy.new(path);restored.load_state()
	check(restored.player_profile().level==4 and restored.state.item_instances[item]==JSON.parse_string(JSON.stringify(e.state.item_instances[item])),"commander and typed gear survive restart")
	var old=Economy.new("user://tests/player-old-%d.json"%OS.get_process_id());old.load_state()
	old.state.erase("commander");old.state.erase("ascension_initialized");old.state.owned[id].erase("ascension");old.state.owned[id].level=25
	Meta.new(old).ensure();var migrated:Dictionary=old.state.duplicate(true);Meta.new(old).ensure()
	check(old.player_profile().level==6 and old.growth_profile(id).level_cap==30 and old.state==migrated,"old high level migration preserves progress once")
	var meta=Meta.new(e)
	for tier in [2,3]:
		var valid:=true
		for index in range(100):
			var gear:Dictionary={"id":"tier-%d-%d"%[tier,index],"kind":"equipment","location":"warehouse"}
			meta.decorate(gear,"gear-v3-t%d"%tier)
			valid=valid and int(gear.quality)>=tier and int(gear.quality)<=6 and int(gear.bonus_bp)<=100 and str(gear.gear_type) in ["fire_control","propulsion","bulkhead","balanced","ballistics"]
		check(valid,"resource tier %d improves minimum rarity without breaking gear caps"%tier)
	var report:Dictionary={"checks":checks,"passed":checks-failures.size(),"failures":failures}
	var f=FileAccess.open("res://../artifacts/growth/player-growth.json",FileAccess.WRITE);f.store_string(JSON.stringify(report,"  "));f.close()
	print(JSON.stringify(report));quit(0 if failures.is_empty() else 1)
