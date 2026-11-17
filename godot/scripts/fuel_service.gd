extends RefCounted
const TONNAGE="res://data/cargo-tonnage-v1.json"
var account
func _init(owner):account=owner
func ensure()->void:
	account.state.wallet.get_or_add("fuel",2400)
func preview(fleet:Array)->Dictionary:
	ensure()
	var registry:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(TONNAGE))
	var rate:=0;var rows:Array=[]
	for ship in fleet:
		var id:String=str(ship.id);var spec:Dictionary=registry.ships.get(id,{})
		var tons:int=int(spec.get("tons",registry.fallback.get(str(ship.get("type","DD")),2000)))
		var consumption:int=maxi(1,int(ceil(float(tons)/1000.0)))
		rate+=consumption;rows.append({"id":id,"name":str(ship.get("name",id)),"tons":tons,"per_minute":consumption,"registered":not spec.is_empty()})
	var capacity:int=maxi(1,rate*12)
	var percent:int=clampi(int(account.state.get("fuel_load_percent",100)),1,100)
	return {"capacity":capacity,"recommended":capacity,"initial":maxi(1,int(ceil(capacity*percent/100.0))),"percent":percent,"per_minute":rate,"per_ship":rows,"stock":int(account.state.wallet.fuel)}
func configure(percent:int)->Dictionary:
	if not account.state.get("active_run",{}).is_empty():return account._fail("返港后可调整油料")
	if percent<1 or percent>100:return account._fail("装油比例须为1–100%")
	var before:Dictionary=account.state.duplicate(true);account.state.fuel_load_percent=percent
	return account._commit(before,"出航装油计划已保存")
func purchase(count:int=100)->Dictionary:
	ensure()
	if not account.state.get("active_run",{}).is_empty() or count<1 or count>10000:return account._fail("返港后可购买油料")
	var cost:=count*3
	if int(account.state.wallet.credits)<cost:return account._fail("银币不足")
	var before:Dictionary=account.state.duplicate(true)
	account.state.wallet.credits=int(account.state.wallet.credits)-cost;account.state.wallet.fuel=int(account.state.wallet.fuel)+count
	return account._commit(before,"油料%d已入库 · 消耗%d银币"%[count,cost])
