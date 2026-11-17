extends SceneTree
## Isolated real-core resource voyage plus transaction boundary and weekly-cap checks.
const Economy=preload("res://scripts/economy.gd")
const Meta=preload("res://scripts/meta_economy.gd")
const Core=preload("res://scripts/core_bridge.gd")
var checks:=0
var failures:Array[String]=[]
func _initialize()->void:call_deferred("_run")
func check(value:bool,name:String)->void:
	checks+=1
	if not value:failures.append(name);push_error(name)
func _run()->void:
	var path:="user://tests/meta-core-%d.json"%OS.get_process_id()
	var e=Economy.new(path)
	check(e.load_state().ok,"profile created")
	var ship:=str(e.formation[0])
	var wallet:Dictionary=e.wallet()
	check(int(wallet.origins)==320 and int(wallet.stamina)==120,"initial earned resource and stamina")
	var bought:Dictionary=e.purchase("origins-ticket",1,"exchange-1")
	check(bought.ok and int(e.wallet().origins)==160 and int(e.wallet().tickets)==int(wallet.tickets)+1,"origin conversion actually grants ticket")
	check(e.purchase("origins-ticket",1,"exchange-1").get("duplicate",false) and int(e.wallet().origins)==160,"conversion idempotent")
	check(not e.payment_status().get("enabled",true),"payment cannot mint currency")
	check(e.set_formation([ship]).ok and e.train(ship).ok,"owned training uses silver and materials")
	check(int(e.state.owned[ship].mastery)==0 and int(e.state.owned[ship].level)==1,"purchased experience never grants mastery")
	var before:Dictionary=e.wallet()
	var prepared:Dictionary=e.preview_sortie(42,false,{"kind":"resources","id":"equipment"})
	check(prepared.ok and int(e.wallet().stamina)==int(before.stamina) and int(e.wallet().ammo_stock)==int(before.ammo_stock),"preview leaves assets unchanged")
	var native:Dictionary=e.native_start(prepared)
	check(native.content=="salvage-v3" and native.owned_growth=="cas-owned-growth-v1","versioned growth snapshot")
	var core=Core.new()
	check(core.request({"op":"new_salvage","seed":42,"start":native}).ok,"real native preflight")
	var run:Dictionary=e.begin_sortie(42,false,{"kind":"resources","id":"equipment"})
	check(run.ok and int(e.wallet().stamina)==int(before.stamina)-10,"stamina paid once on commit")
	check(core.request({"op":"new_salvage","seed":42,"start":e.native_start(run)}).ok,"frozen voyage recreated")
	check(core.request({"op":"route","fleet":1,"mode":"follow","speed":6,"points":[{"x":3000,"y":2200}]}).ok,"actual movement accepted")
	check(core.request({"op":"step","seconds":60}).ok,"actual voyage advances")
	check(core.request({"op":"salvage_collect","ruin":1}).ok,"reachable generated ruin collected")
	core.request({"op":"step","seconds":6})
	check(core.view.salvage.loot.get("equipment",0)==1,"resource-stage real cargo")
	var saved:Dictionary=core.request({"op":"save"})
	check(e.save_sortie(JSON.stringify(saved.data)).ok,"world snapshot saved with account")
	var reload=Economy.new(path)
	check(reload.load_state().ok and int(reload.wallet().stamina)==int(e.wallet().stamina),"resume does not recharge stamina")
	check(core.request({"op":"load","save":JSON.parse_string(reload.resume_sortie().snapshot)}).ok,"real-core resume")
	check(core.request({"op":"salvage_extract","exit":0}).ok,"actual extraction requested")
	core.request({"op":"step","seconds":12})
	check(core.view.salvage.extracted,"actual extraction ended successfully")
	var receipt:Dictionary={"run_id":run.run_id,"success":core.view.salvage.extracted,"loot":core.view.salvage.loot,"ships":core.view.salvage.ships}
	var outcome:Dictionary=reload.settle_sortie(receipt)
	check(outcome.ok and int(reload.state.inventory.equipment)==1,"real returned gear awarded")
	check(int(reload.state.owned[ship].mastery)>=1 and int(reload.wallet().origins)==int(before.origins)+10,"actual participation mastery and mission reward")
	var mastery:=int(reload.state.owned[ship].mastery)
	check(reload.settle_sortie(receipt).get("duplicate",false) and int(reload.state.owned[ship].mastery)==mastery,"mastery and rewards settle exactly once")
	var inventory:Array=reload.gear_inventory(ship,"equipment")
	check(inventory.size()==1 and inventory.all(func(row):return str(row.get("gear_type","")) in ["fire_control","propulsion","bulkhead","balanced","ballistics"] and int(row.bonus_bp)<=100 and row.drop_table_version=="gear-v3"),"typed extracted gear within declared cap")
	check(reload.assign_item(ship,"equipment",str(inventory[0].id)).ok,"real extracted equipment installed")
	var bonus:Dictionary=reload.growth_profile(ship).bonuses
	check(float(bonus.hp)>1 and float(bonus.hp)<1.07,"growth shows actual modest bonus")
	check(reload.assign_item(ship,"equipment","").ok and reload.gear_inventory(ship,"equipment").size()==1,"uninstall returns same unique instance")
	# Explicit account fixture only for week-limit/clock boundaries; no invented core outcome.
	var meta=Meta.new(reload)
	var task:Dictionary=meta.mission({"kind":"ladder","id":"ladder-3000"})
	var active:Dictionary={"content":"salvage-v2","mode":"salvage","mission":task}
	var awards:Array=[]
	for i in range(4):awards.append(int(meta.settle(active,true,[]).origins))
	check(awards==[80,80,80,0],"weekly ladder origins capped at three, repeat still allowed")
	check(meta.mission_catalog("ladder").all(func(row):return int(row.remaining)==0),"weekly cap shared across all point budgets")
	reload.state.stamina={"value":50,"at":2000}
	check(meta.stamina(1000).value==50 and meta.stamina(2480).value==51,"backward clock gives no stamina and exact interval gives one")
	var request:Dictionary={"op":"new_campaign","id":"CAMP-ALLIES-02","difficulty":"story","groups":[{"position":0,"ships":[ship]}]}
	var campaign:Dictionary=reload.campaign_growth(request)
	check(campaign.ok and core.request(campaign.request).ok,"owned campaign uses same authoritative snapshot API")
	check(core.view.has("ownedGrowth"),"owned exercise explicitly labelled in core view")
	core.close()
	var legacy=Economy.new("user://tests/meta-legacy-%d.json"%OS.get_process_id())
	legacy.load_state();legacy.state.item_instances={};legacy.state.item_sequence=0
	legacy.state.inventory.equipment=2;legacy.state.owned[ship].equipment="equipment"
	Meta.new(legacy).ensure()
	check(legacy.state.item_instances.size()==3 and legacy.gear_inventory(ship,"equipment").size()==3,"legacy aggregate and equipped inventory migrate without losing assets")
	var legacy_ids: Array=legacy.state.item_instances.keys()
	Meta.new(legacy).ensure()
	check(legacy.state.item_instances.keys()==legacy_ids,"legacy migration is repeatable without reroll or duplication")
	var report:Dictionary={"checks":checks,"passed":checks-failures.size(),"failures":failures,"real_resource_run":run.run_id,"actual_mastery":mastery}
	var file=FileAccess.open("res://../artifacts/meta-economy-core.json",FileAccess.WRITE);file.store_string(JSON.stringify(report,"  "));file.close()
	print(JSON.stringify(report));quit(0 if failures.is_empty() else 1)
