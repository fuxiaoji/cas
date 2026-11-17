extends RefCounted
## One invoice, one atomic account transaction; the voyage owns actual ammo consumption.
static func open(app, service:String="both") -> void:
	var ids:Array=[]
	for row in app.economy.roster():ids.append(str(row.id))
	var preview:Dictionary=app.economy.prepare_service(ids,100,service)
	if not bool(preview.get("ok",false)):
		app.notify(preview);return
	var titles:Dictionary={"repair":"一键维修","ammo":"一键补给","both":"一键整备"}
	var layer:Control=app.open_modal(str(titles.get(service,"一键整备")))
	app.label(layer,"为已拥有的 %d 位舰娘整备"%ids.size(),390,230,800,45,26)
	var damaged:=0
	for row in preview.ships:
		if int(row.hp_before)<100 or int(row.repair_cost)>0:damaged+=1
	if service!="ammo":
		app.label(layer,"修复 %d 位舰娘"%damaged,390,310,480,45,24)
		app.label(layer,"%d 银币"%int(preview.repair_cost),950,310,250,45,24)
	if service!="repair":
		app.label(layer,"弹药库存 %d → %d"%[int(preview.ammo_stock_before),int(preview.ammo_stock_after)],390,380,680,42,23)
		app.label(layer,"补给 %d 份 · %d 银币"%[int(preview.ammo_purchase),int(preview.ammo_cost)],390,430,800,42,23)
		app.label(layer,"装载计划设为每舰100份，出航时按部署舰队扣除。",390,493,800,52,20,app.MUTED)
	else:
		app.label(layer,"维修恢复耐久及航行能力。",390,400,800,52,22,app.MUTED)
	app.label(layer,"合计 %d 银币"%int(preview.cost),390,580,490,50,27)
	var request_id:="port-service-%s-%s"%[Time.get_unix_time_from_system(),Time.get_ticks_usec()]
	var commit:Button=app.button(layer,"确认整备" if bool(preview.affordable) else "银币不足",850,636,350,65,func():
		var result:Dictionary=app.economy.service_all(ids,100,request_id,service)
		app.close_modal()
		app.show_page(app.screen)
		app.notify(result),true)
	commit.name="ConfirmFleetService"
	commit.disabled=not bool(preview.affordable)
