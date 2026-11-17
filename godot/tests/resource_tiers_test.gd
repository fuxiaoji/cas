extends SceneTree
const Economy=preload("res://scripts/economy.gd")
const Core=preload("res://scripts/core_bridge.gd")
var checks:=0
var failures:Array[String]=[]
var runs:Array=[]
func _initialize()->void:call_deferred("run")
func check(value:bool,title:String)->void:
	checks+=1
	if not value:failures.append(title);push_error(title)
func run()->void:
	for tier in [1,2,3]:
		var e=Economy.new("user://tests/resource-tier-%d-%d.json"%[OS.get_process_id(),tier]);e.load_state()
		var identity:=str(e.formation[0]);e.set_formation([identity]);e.grant_player_xp("test-unlock",2000)
		var mission:="training" if tier==1 else "training-t%d"%tier
		var before:Dictionary=e.wallet();var prepared:Dictionary=e.preview_sortie(42,false,{"kind":"resources","id":mission})
		check(prepared.ok,"tier %d account preflight"%tier)
		var core=Core.new();check(core.request({"op":"new_salvage","seed":42,"start":e.native_start(prepared)}).ok,"tier %d native preflight"%tier)
		var run_data:Dictionary=e.begin_sortie(42,false,{"kind":"resources","id":mission})
		check(run_data.ok and int(e.wallet().stamina)==int(before.stamina)-int(prepared.mission.cost_stamina),"tier %d stamina charged once"%tier)
		core.request({"op":"new_salvage","seed":42,"start":e.native_start(run_data)})
		var cache_x:float=[3000.,4800.,5800.][tier-1]
		core.request({"op":"route","fleet":1,"mode":"follow","speed":30,"points":[{"x":cache_x-500,"y":2200}]})
		var collected:=false
		for attempt in range(60):
			if core.request({"op":"salvage_collect","ruin":1}).ok:
				core.request({"op":"step","seconds":6})
				if int(core.view.salvage.loot.get("alloy",0))>0:collected=true;break
			core.request({"op":"step","seconds":10})
			if core.view.get("result")!=null:break
		check(collected,"tier %d real reachable cache collection"%tier)
		var extracted:=false
		for attempt in range(90):
			if core.request({"op":"salvage_extract","exit":0}).ok:
				core.request({"op":"step","seconds":12})
				if bool(core.view.salvage.extracted):extracted=true;break
			core.request({"op":"step","seconds":10})
			if core.view.get("result")!=null:break
		check(extracted,"tier %d real return and extraction"%tier)
		var saved:Dictionary=core.request({"op":"save"})
		check(saved.ok and core.request({"op":"replay","save":saved.data}).ok,"tier %d native replay accepted"%tier)
		var result:Dictionary=e.settle_sortie({"run_id":run_data.run_id,"success":extracted,"loot":core.view.salvage.loot,"ships":core.view.salvage.ships})
		check(result.ok,"tier %d settlement committed"%tier)
		var material:="materials" if tier==1 else "training_t%d"%tier
		check(int(e.wallet().get(material,0))==int(before.get(material,0))+int(prepared.mission.rewards.get(material,0)),"tier %d actual material reward"%tier)
		check(int(result.receipt.rewards.get("commander_xp",0))==[60,90,120][tier-1],"tier %d actual commander XP"%tier)
		runs.append({"tier":tier,"tick":core.view.tick,"cache_x":cache_x,"actual_extraction":extracted,"rewards":result.receipt.rewards})
		core.close()
	var e=Economy.new("user://tests/resource-failure-%d.json"%OS.get_process_id());e.load_state();e.set_formation([str(e.formation[0])])
	var before:Dictionary=e.wallet();var run_data:Dictionary=e.begin_sortie(42,false,{"kind":"resources","id":"training"})
	var core=Core.new();core.request({"op":"new_salvage","seed":42,"start":e.native_start(run_data)})
	for i in range(16):
		core.request({"op":"step","seconds":180})
		if core.view.get("result")!=null:break
	check(core.view.get("result")!=null and not bool(core.view.salvage.extracted),"actual core failure")
	var result:Dictionary=e.settle_sortie({"run_id":run_data.run_id,"success":false,"loot":core.view.salvage.loot,"ships":core.view.salvage.ships})
	check(result.ok and result.receipt.rewards.is_empty() and int(e.wallet().materials)==int(before.materials),"defeat grants no resource or commander reward")
	core.close()
	var report:Dictionary={"checks":checks,"passed":checks-failures.size(),"failures":failures,"runs":runs}
	var file=FileAccess.open("res://../artifacts/growth/resource-tiers.json",FileAccess.WRITE);file.store_string(JSON.stringify(report,"  "));file.close()
	print(JSON.stringify(report));quit(0 if failures.is_empty() else 1)
