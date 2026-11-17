extends RefCounted
## A recording runs in its own native process. The live sortie stays untouched.
const Core=preload("res://scripts/core_bridge.gd")
var previous:Dictionary={}
var record:Dictionary={}
var viewer
var active:bool=false
func open(app,entry:Dictionary)->Dictionary:
	var snapshot:String=str(entry.get("snapshot",""))
	var saved:Variant=JSON.parse_string(snapshot)
	if not saved is Dictionary:return {"ok":false,"message":"录像资料无法读取，原行动已保留。"}
	viewer=Core.new()
	var response:Dictionary=viewer.request({"op":"replay","serialized":snapshot,"tick":0.0})
	if not response.get("ok",false):viewer.close();return response
	previous={"core":app.core,"run":app.run,"campaign_mode":app.campaign_mode,"battle_return_route":app.battle_return_route,"speed":app.speed,"elapsed":app.elapsed}
	record=entry;active=true;app.running=false;app.core=viewer;app.run={};app.campaign_mode=true;app.battle_return_route="home"
	return {"ok":true}
func configure(controller)->void:
	controller.archive_replay=true;controller.replay_mode=true
	controller.replay_save=str(record.snapshot)
	var saved:Dictionary=JSON.parse_string(str(record.snapshot))
	controller.replay_duration=float(saved.get("tick",0));controller.replay_seconds=0;controller.replay_limit=int(ceil(controller.replay_duration))
func restore(app)->void:
	if not active:return
	active=false;app.running=false;viewer.close()
	app.core=previous.core;app.run=previous.run;app.campaign_mode=previous.campaign_mode;app.battle_return_route=previous.battle_return_route;app.speed=previous.speed;app.elapsed=previous.elapsed
	previous.clear();viewer=null
