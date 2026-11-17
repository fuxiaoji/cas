extends RefCounted
## Local test currency only. There is deliberately no network, payment SDK or bank information.
const CONFIG="res://data/simulated-store.json"
var account
func _init(owner) -> void:account=owner
func catalog() -> Array:
	var data:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(CONFIG))
	return data.get("packs",[]).duplicate(true)
func orders() -> Array:
	return account.state.get("simulated_store",{}).get("orders",[]).duplicate(true)
func _pack(id:String) -> Dictionary:
	for row in catalog():
		if str(row.id)==id:return row
	return {}
func create_order(pack_id:String,request_id:String="") -> Dictionary:
	var replay:Dictionary=account._request(request_id,["demo_order",pack_id])
	if not replay.is_empty():return replay
	if not account.state.get("active_run",{}).is_empty():return account._fail("请返港后使用模拟充值")
	var pack:=_pack(pack_id)
	if pack.is_empty():return account._fail("补给方案不存在")
	var previous:Dictionary=account.state.duplicate(true)
	var state:Dictionary=account.state.get_or_add("simulated_store",{"version":"local-demo-store-v1","sequence":0,"orders":[]})
	state.sequence=int(state.sequence)+1
	var order:Dictionary={"id":"demo-order-%d"%int(state.sequence),"pack_id":pack_id,"name":pack.name,"origins":int(pack.origins),"price_label":pack.price_label,"status":"pending","simulation":true,"created_at":int(Time.get_unix_time_from_system())}
	state.orders.append(order)
	return account._commit(previous,"模拟订单已创建；尚未发放元词",{"order":order.duplicate(true)})
func complete_order(order_id:String,request_id:String="") -> Dictionary:
	var replay:Dictionary=account._request(request_id,["demo_fulfill",order_id])
	if not replay.is_empty():return replay
	if not account.state.get("active_run",{}).is_empty():return account._fail("请返港后使用模拟充值")
	var order:Dictionary={}
	for row in account.state.get("simulated_store",{}).get("orders",[]):
		if str(row.id)==order_id:order=row;break
	if order.is_empty():return account._fail("找不到模拟订单")
	if not bool(order.get("simulation",false)):return account._fail("订单不是本地模拟订单")
	if str(order.status)=="fulfilled":
		account._pending_request.clear()
		return {"ok":true,"duplicate":true,"message":"这笔模拟补给已到账","order":order.duplicate(true)}
	if str(order.status)!="pending":return account._fail("模拟订单已取消")
	var previous:Dictionary=account.state.duplicate(true)
	account.state.wallet.origins=int(account.state.wallet.get("origins",0))+int(order.origins)
	order.status="fulfilled";order.completed_at=int(Time.get_unix_time_from_system())
	return account._commit(previous,"模拟到账 %d 元词 · 未发生付款"%int(order.origins),{"order":order.duplicate(true),"granted_origins":int(order.origins)})
func cancel_order(order_id:String) -> Dictionary:
	if not account.state.get("active_run",{}).is_empty():return account._fail("请返港后处理模拟订单")
	for row in account.state.get("simulated_store",{}).get("orders",[]):
		if str(row.id)!=order_id:continue
		if str(row.status)!="pending":return account._fail("该订单已经结束")
		var previous:Dictionary=account.state.duplicate(true);row.status="cancelled"
		return account._commit(previous,"模拟订单已取消，没有付款或发放资源")
	return account._fail("找不到模拟订单")
