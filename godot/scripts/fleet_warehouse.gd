extends RefCounted
## Physical cargo belongs to a fleet hold or the base, never both.
const Cargo=preload("res://scripts/cargo_service.gd")
var account
func _init(owner):account=owner
func key()->String:
	var ids:Array=account.state.get("sortie_fleet_ids",[]).duplicate()
	if ids.is_empty():ids=[str(account.state.get("active_fleet_id","legacy"))]
	ids.sort()
	return "+".join(PackedStringArray(ids))
func hold(identity:String="")->Dictionary:
	if identity.is_empty():identity=key()
	var registry:Dictionary=account.state.get_or_add("fleet_cargo_v1",{"version":"fleet-cargo-v1","holds":{}})
	var data:Dictionary=registry.holds.get_or_add(identity,{"items":[]})
	var budget:Dictionary=account.cargo_budget()
	data.merge({"cols":int(budget.cols),"rows":int(budget.rows),"usable_cells":int(budget.cells),"max_kg":int(budget.max_kg)},true)
	data["kg"]=weight(data.items)
	return data
static func weight(items:Array)->int:
	var total:=0
	for item in items:total+=int(item.kg)
	return total
func transfer(id:String,from:String)->Dictionary:
	if not account.state.get("active_run",{}).is_empty():return account._fail("返港后可转运物资")
	if from not in ["fleet","base"]:return account._fail("仓库位置无效")
	var service=Cargo.new(account)
	var source:Dictionary=hold() if from=="fleet" else service.stash()
	var target:Dictionary=service.stash() if from=="fleet" else hold()
	var item:Dictionary={}
	for row in source.items:
		if str(row.id)==id:item=row;break
	if item.is_empty():return account._fail("物资已移动")
	if from=="base" and not item.has("loot_id"):return account._fail("旧版物资请在基地出售或拆包，不能带回新海域")
	if target.has("max_kg") and weight(target.items)+int(item.kg)>int(target.max_kg):return account._fail("编队载重不足，请先卸货或增加运输舰")
	var before:Dictionary=account.state.duplicate(true)
	var moved:Dictionary=item.duplicate(true);moved.placement=null
	var position:Variant=service._first_fit(target,moved)
	if position==null:return account._fail("目标仓库空间不足，请先清理或调整编队")
	moved.placement=position;source.items.erase(item);target.items.append(moved)
	return account._commit(before,"已卸至基地" if from=="fleet" else "已装入编队货舱，下次出航携带")
func clean(scope:String,sell:bool=false)->Dictionary:
	if not account.state.get("active_run",{}).is_empty():return account._fail("返港后可清理仓库")
	if scope not in ["fleet","base"]:return account._fail("仓库位置无效")
	var service=Cargo.new(account);var data:Dictionary=hold() if scope=="fleet" else service.stash()
	var before:Dictionary=account.state.duplicate(true);var count:=0;var silver:=0
	if sell:
		for item in data.items.duplicate():
			if Cargo.can_unpack(item):continue
			silver+=int(item.value);count+=1;data.items.erase(item)
		if count==0:return account._fail("没有可出售物资；舰装箱和水手档案会保留")
		account.state.wallet.credits=int(account.state.wallet.credits)+silver
	var ordered:Array=data.items.duplicate();ordered.sort_custom(func(a,b):return a.shape.size()>b.shape.size())
	data.items=[]
	for item in ordered:
		item.placement=null;item.placement=service._first_fit(data,item);data.items.append(item)
	return account._commit(before,"售出%d件，获得%d银币；拆包物资已保留"%[count,silver] if sell else "已按形状自动整理，溢出物资仍保留",{"sold":count,"credits":silver})
func receive(items:Array,active:Dictionary)->void:
	var identity:String=str(active.get("cargo_warehouse_key",key()))
	var target:Dictionary=hold(identity)
	for original in items:
		if not original is Dictionary or original.get("placement")==null:continue
		var item:Dictionary=original.duplicate(true)
		if target.items.any(func(old):return str(old.id)==str(item.id)):continue
		var locked:Dictionary={}
		for old in active.get("cargo_transfer_v1",{}).get("items",[]):
			if str(old.id)==str(item.id):locked=old;break
		item["difficulty"]=str(locked.get("difficulty",active.get("cargo_v4",{}).get("difficulty","calm")))
		target.items.append(item)
func prepare(pickup_namespace:String)->Dictionary:
	var data:Dictionary=hold();var service=Cargo.new(account)
	for item in data.items:
		if not item.has("loot_id") or not Cargo.valid_placement(item.get("placement")) or not service.can_fit(data.items,item,item.placement,int(data.cols),int(data.rows),int(data.usable_cells)):return account._fail("编队货舱有物资尚未归位，请整理或卸至基地")
	if weight(data.items)>int(data.max_kg):return account._fail("编队货舱超重，请卸至基地")
	return {"ok":true,"version":"fleet-cargo-v1","pickup_namespace":pickup_namespace,"items":data.items.duplicate(true)}
