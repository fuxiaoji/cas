extends RefCounted
## Disposable own-island simulation. Never enters an account transaction.
const Core=preload("res://scripts/core_bridge.gd")
var previous:Dictionary={}
var simulator
var active:bool=false
var terminal:Dictionary={}
func open(app,request:Dictionary)->Dictionary:
	if str(request.get("version","")) not in ["cas-island-war-v2","cas-island-war-v3","cas-island-war-v4","cas-island-war-coastal-v1"] or str(request.get("mode",""))!="exercise" or request.get("defender",{}).is_empty():
		return {"ok":false,"message":"演习需要完整的己方攻击部队与驻防配置。"}
	simulator=Core.new()
	var response:Dictionary=simulator.request(request)
	if not response.get("ok",false):simulator.close();return response
	previous={"core":app.core,"run":app.run,"campaign_mode":app.campaign_mode,"battle_return_route":app.battle_return_route,"speed":app.speed,"elapsed":app.elapsed,"last_receipt":app.last_receipt,"selected":app.selected,"selection_kind":app.selection_kind,"checkpoint_tick":app.tide_checkpoint_tick}
	active=true;app.running=false;app.core=simulator;app.run={};app.campaign_mode=true;app.battle_return_route="home";app.elapsed=0
	return {"ok":true}
func restore(app)->void:
	if not active:return
	active=false;app.running=false
	if simulator!=null:simulator.close()
	app.core=previous.core;app.run=previous.run;app.campaign_mode=previous.campaign_mode;app.battle_return_route=previous.battle_return_route;app.speed=previous.speed;app.elapsed=previous.elapsed;app.last_receipt=previous.last_receipt
	app.selected=previous.selected;app.selection_kind=previous.selection_kind;app.tide_checkpoint_tick=previous.checkpoint_tick
	previous.clear();simulator=null
func finish(app)->void:
	if not active:return
	app.running=false;terminal=app.core.view.get("island_war",{}).duplicate(true)
	var training:Variant=app.core.view.get("littoral",{}).get("training")
	var is_training:bool=training is Dictionary
	var layer:Control=app.open_modal("联合兵种训练 · 已结束" if is_training else "自家攻防演习 · 已结束",func():app.close_home_exercise())
	app.label(layer,"本次推演已结束",400,255,790,65,36)
	app.label(layer,("训练目标已完成。" if bool(training.get("complete",false)) else "尚有训练目标未完成，可以再次练习。") if is_training else "设施、部队整备和所有资源均保留。",400,340,790,60,24)
	app.button(layer,"返回海岛",400,455,790,70,app.close_home_exercise,true)
