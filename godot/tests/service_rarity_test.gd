extends SceneTree
const Economy=preload("res://scripts/economy.gd")
const Meta=preload("res://scripts/meta_economy.gd")
var checks:=0
var failures:Array[String]=[]
func _initialize()->void:call_deferred("run")
func check(value:bool,label:String)->void:
	checks+=1
	if not value:failures.append(label);push_error(label)
func run()->void:
	var path:="user://tests/service-rarity-%d.json"%OS.get_process_id()
	var a=Economy.new(path);check(a.load_state().ok,"isolated account")
	var ids:Array=a.formation.duplicate();var first:=str(ids[0])
	a.state.wallet.credits=1000;a.state.wallet.ammo_stock=0;a.state.owned[first].hp=50;a.state.owned[first].ammo=25
	var before:Dictionary=a.state.duplicate(true)
	var preview:Dictionary=a.prepare_service(ids)
	check(preview.ok and preview.cost==580 and preview.repair_cost==100 and preview.ammo_cost==480,"preview sums damage and three ammo packs")
	check(a.state==before,"preview never mutates account")
	check(a.service_all(ids,100,"service-1").ok,"atomic combined service commits")
	check(a.state.wallet.credits==420 and a.state.wallet.ammo_stock==300,"silver charged exactly once and ammo retained until sortie")
	check(a.state.owned[first].hp==100 and a.state.owned[first].ammo==100,"both service repairs and sets plan")
	check(a.service_all(ids,100,"service-1").get("duplicate",false) and a.state.wallet.credits==420,"transaction replay does not charge twice")
	check(not a.service_all([first],100,"service-1").ok,"conflicting request id rejected")
	a.state.owned[first].hp=50;a.state.owned[first].ammo=25;a.state.wallet.ammo_stock=0
	check(a.prepare_service([first],100,"repair").cost==100,"repair does not require ammo stock")
	check(a.service_all([first],100,"","repair").ok and a.state.owned[first].ammo==25 and a.state.wallet.ammo_stock==0,"repair only preserves ammo")
	a.state.owned[first].hp=40
	check(a.service_all([first],100,"","ammo").ok and a.state.owned[first].hp==40 and a.state.owned[first].ammo==100,"ammo only preserves damaged hull")
	a.state.wallet.credits=0;a.state.wallet.ammo_stock=0;before=a.state.duplicate(true)
	check(not a.service_all(ids).ok and a.state==before,"insufficient balance leaves all hulls untouched")
	a.state.active_run={"run_id":"fixture"};check(not a.prepare_service(ids).ok and not a.service_all(ids).ok,"voyage locks preview and mutation")
	a.state.active_run={};check(not a.prepare_service([first,first]).ok and not a.prepare_service(["unknown"]).ok,"duplicate and foreign hull rejected")
	a.state.wallet.credits=1000
	var broken=Economy.new("res://data");broken.state=a.state.duplicate(true);broken.formation.assign(a.formation);before=broken.state.duplicate(true)
	check(not broken.service_all(ids).ok and broken.state==before,"failed disk write rolls back all balances and hulls")
	if FileAccess.file_exists("res://data.tmp"):DirAccess.remove_absolute(ProjectSettings.globalize_path("res://data.tmp"))
	var tiers:Array=a.gear_drop_table();var total:=0
	for tier in tiers:total+=int(tier.weight)
	check(tiers.size()==6 and total==1000 and tiers[5].weight==2,"six explicit tiers with 0.2 percent highest drop")
	var histogram:Dictionary={};var meta=Meta.new(a)
	for i in range(10000):
		var item:Dictionary={"id":"equipment-%d"%i,"kind":"equipment","location":"warehouse"};meta.decorate(item,"gear-v2")
		histogram[int(item.quality)]=int(histogram.get(int(item.quality),0))+1
		if int(item.bonus_bp)>100:failures.append("equipment cap broken")
	check(histogram.size()==6 and int(histogram[1])>int(histogram[2]) and int(histogram[5])>int(histogram[6]),"deterministic weighted distribution includes all six tiers")
	for slot in ["helmsman","gunnery","damage_control","command"]:
		var item:Dictionary={"id":"command-"+slot,"kind":"command","location":"warehouse"};meta.decorate(item,"gear-v2")
		check(int(item.main.bp)+int(item.sub.bp)<=25,"crew budget remains quarter percent "+slot)
	var old:Dictionary={"id":"equipment-legacy","kind":"equipment","location":"warehouse"};meta.decorate(old)
	a.state.item_instances[old.id]=old;var frozen:Dictionary=old.duplicate(true);meta.ensure()
	check(a.state.item_instances[old.id]==frozen,"old item stats and version retained")
	a.save_state();var restored=Economy.new(path);var restored_result:Dictionary=restored.load_state();check(restored_result.ok and restored.state.item_instances[old.id]==JSON.parse_string(JSON.stringify(frozen)),"old item survives application restart")
	var report:Dictionary={"checks":checks,"passed":checks-failures.size(),"failures":failures,"new_tier_sample_10000":histogram}
	var file=FileAccess.open("res://../artifacts/v3/service-rarity.json",FileAccess.WRITE);file.store_string(JSON.stringify(report,"  "));file.close()
	print(JSON.stringify(report));quit(0 if failures.is_empty() else 1)
