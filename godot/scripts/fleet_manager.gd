extends RefCounted
## Saved fleet compositions are unlimited. A ship may have several saved assignments,
## but can only deploy once in a sortie. All changes share the account save boundary.
const SECRETARY_HORIZONTAL_RANGE := Vector2(-1200,1200)
const SECRETARY_VERTICAL_RANGE := Vector2(-900,700)
var account

func _init(owner) -> void:
	account = owner
	ensure()

func ensure() -> void:
	if not account.state.has("fleet_book"):
		account.state.fleet_book = [{"id":"fleet-1","name":"第一舰队","ships":account.state.get("formation",[]).duplicate()}]
		account.state.active_fleet_id = "fleet-1"
		account.state.sortie_fleet_ids = ["fleet-1"]
	account.state.get_or_add("harbor",{"secretary":"","scale":1.0})

func rows() -> Array:
	return account.state.fleet_book.duplicate(true)

func active() -> Dictionary:
	for row in account.state.fleet_book:
		if str(row.id)==str(account.state.get("active_fleet_id","")): return row.duplicate(true)
	return account.state.fleet_book[0].duplicate(true) if not account.state.fleet_book.is_empty() else {}

func selected(id: String) -> bool:
	return account.state.get("sortie_fleet_ids",[]).has(id)

func groups() -> Array:
	var output: Array=[]
	for row in account.state.fleet_book:
		if selected(str(row.id)) and not row.ships.is_empty(): output.append(row.duplicate(true))
	return output

func _blocked() -> bool:
	return not account.state.get("active_run",{}).is_empty()

func _save(previous: Dictionary, message: String) -> Dictionary:
	var seen: Array[String]=[]
	for row in groups():
		for identity in row.ships:
			var id:=str(identity)
			if seen.has(id):
				account.state=previous
				return {"ok":false,"message":"同一舰娘不能同时随两个编队出航，请调整出航勾选。"}
			seen.append(id)
	account.state.formation=seen.duplicate()
	account._sync_formation()
	return account._commit(previous,message)

func activate(id: String) -> Dictionary:
	var previous: Dictionary=account.state.duplicate(true)
	for row in account.state.fleet_book:
		if str(row.id)==id:
			account.state.active_fleet_id=id
			return account._commit(previous,"已切换编辑舰队")
	return {"ok":false,"message":"未找到该舰队"}

func create(name: String="") -> Dictionary:
	if _blocked(): return {"ok":false,"message":"海上行动期间不能调整编队"}
	var previous: Dictionary=account.state.duplicate(true)
	var id:="fleet-%d-%d"%[Time.get_ticks_usec(),account.state.fleet_book.size()]
	account.state.fleet_book.append({"id":id,"name":name.strip_edges() if not name.strip_edges().is_empty() else "舰队 %d"%(account.state.fleet_book.size()+1),"ships":[]})
	account.state.active_fleet_id=id
	return account._commit(previous,"新编队已建立，可自由添加舰娘")

func rename(id: String, name: String) -> Dictionary:
	if _blocked(): return {"ok":false,"message":"海上行动期间不能调整编队"}
	if name.strip_edges().is_empty(): return {"ok":false,"message":"请填写舰队名称"}
	var previous: Dictionary=account.state.duplicate(true)
	for row in account.state.fleet_book:
		if str(row.id)==id:
			row.name=name.strip_edges().left(32)
			return account._commit(previous,"舰队名称已保存")
	return {"ok":false,"message":"未找到该舰队"}

func erase(id: String) -> Dictionary:
	if _blocked(): return {"ok":false,"message":"海上行动期间不能调整编队"}
	if account.state.fleet_book.size()<=1: return {"ok":false,"message":"请至少保留一个编队"}
	var previous: Dictionary=account.state.duplicate(true)
	for i in range(account.state.fleet_book.size()):
		if str(account.state.fleet_book[i].id)==id:
			account.state.fleet_book.remove_at(i)
			account.state.sortie_fleet_ids.erase(id)
			if str(account.state.active_fleet_id)==id: account.state.active_fleet_id=account.state.fleet_book[0].id
			return _save(previous,"编队已移除，舰娘仍在舰库")
	return {"ok":false,"message":"未找到该舰队"}

func select(id: String, on: bool) -> Dictionary:
	if _blocked(): return {"ok":false,"message":"海上行动期间不能调整出航舰队"}
	var found:=false
	for row in account.state.fleet_book:
		if str(row.id)==id:
			found=true
			if on and row.ships.is_empty(): return {"ok":false,"message":"空编队不能出航，请先添加舰娘"}
	if not found: return {"ok":false,"message":"未找到该舰队"}
	var previous: Dictionary=account.state.duplicate(true)
	if on and not selected(id): account.state.sortie_fleet_ids.append(id)
	if not on: account.state.sortie_fleet_ids.erase(id)
	return _save(previous,"已更新本次出航舰队")

func set_members(ids: Array) -> Dictionary:
	if _blocked(): return {"ok":false,"message":"海上行动期间不能调整编队"}
	var unique: Array[String]=[]
	for value in ids:
		var id:=str(value)
		if unique.has(id) or not account.state.owned.has(id) or not account._cards.get(id,{}).get("playable",false):
			return {"ok":false,"message":"只能编入已拥有且未重复的舰娘"}
		unique.append(id)
	var previous: Dictionary=account.state.duplicate(true)
	var editing:=active()
	for row in account.state.fleet_book:
		if str(row.id)==str(editing.get("id","")):
			row.ships=unique
			if unique.is_empty(): account.state.sortie_fleet_ids.erase(str(row.id))
			elif account.state.sortie_fleet_ids.is_empty(): account.state.sortie_fleet_ids.append(str(row.id))
			return _save(previous,"编队成员已保存")
	return {"ok":false,"message":"请先建立舰队"}

func toggle_member(id: String) -> Dictionary:
	var ids: Array=active().get("ships",[]).duplicate()
	if ids.has(id): ids.erase(id)
	else: ids.append(id)
	return set_members(ids)

func secretary(id: String, scale: float, position: Variant = null) -> Dictionary:
	if not account.state.owned.has(id): return {"ok":false,"message":"只能选择已拥有的舰娘担任秘书舰"}
	var previous: Dictionary=account.state.duplicate(true)
	var display:Dictionary=account.state.get("harbor",{}).duplicate(true)
	display.secretary=id
	display.scale=clampf(scale,.6,1.5)
	if position is Vector2:
		display.x=clampf(position.x,SECRETARY_HORIZONTAL_RANGE.x,SECRETARY_HORIZONTAL_RANGE.y)
		display.y=clampf(position.y,SECRETARY_VERTICAL_RANGE.x,SECRETARY_VERTICAL_RANGE.y)
	account.state.harbor=display
	return account._commit(previous,"秘书舰展示已保存")
