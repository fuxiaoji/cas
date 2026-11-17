extends RefCounted
const TONNAGE="res://data/cargo-tonnage-v1.json"
const LOOT="res://data/loot-v2.json"
const SCENES=["sunken_metropolis","cult_relay","storm_wrecks","thermal_vent","refugee_causeway"]
const SHELLS=["balanced","ap","he"]
const TORPEDOES=["standard","fast","heavy"]
var account
func _init(owner):account=owner
func options()->Dictionary:
	var result:Dictionary=account.state.get("salvage_options",{"difficulty":"calm","environment":"atoll","weather":"auto"}).duplicate(true)
	result["scene"]=str(account.state.get("expedition_v2",{}).get("scene","sunken_metropolis"))
	return result
func set_options(raw:Dictionary)->Dictionary:
	if not account.state.get("active_run",{}).is_empty():return account._fail("返港后可调整海域")
	for key in raw:
		if str(key) not in ["difficulty","environment","weather","scene"]:return account._fail("海域设置字段无效")
	var next:=options();next.merge(raw,true)
	if str(next.difficulty) not in ["calm","standard","hazard"] or str(next.environment) not in ["atoll","fractured","fjord","drowned_city"] or str(next.weather) not in ["auto","clear","rain","fog"]:return account._fail("海域设置无效")
	if str(next.scene) not in SCENES:return account._fail("行动场景无效")
	var before:Dictionary=account.state.duplicate(true)
	account.state.get_or_add("expedition_v2",{})["scene"]=str(next.scene);next.erase("scene");account.state.salvage_options=next
	return account._commit(before,"海域计划已保存")
func expedition_config(fleet:Array)->Dictionary:
	var raw:Dictionary=account.state.get("expedition_v2",{})
	var result:Dictionary={"scene":str(raw.get("scene","sunken_metropolis")),"munitions":{}}
	if str(result.scene) not in SCENES:result.scene="sunken_metropolis"
	for ship in fleet:
		var id:String=str(ship.id)
		var row:Dictionary=raw.get("munitions",{}).get(id,{"shell":"balanced","torpedo":"standard","reserve_reloads":1})
		result.munitions[id]={"shell":str(row.get("shell","balanced")),"torpedo":str(row.get("torpedo","standard")),"reserve_reloads":int(row.get("reserve_reloads",1))}
	return result
func set_expedition_options(raw:Dictionary)->Dictionary:
	if not account.state.get("active_run",{}).is_empty():return account._fail("返港后可更换弹药")
	for key in raw:
		if str(key) not in ["scene","munitions"]:return account._fail("行动配置字段无效")
	var next:Dictionary=account.state.get("expedition_v2",{"scene":"sunken_metropolis","munitions":{}}).duplicate(true)
	if raw.has("scene"):
		if str(raw.scene) not in SCENES:return account._fail("行动场景无效")
		next.scene=str(raw.scene)
	if raw.has("munitions"):
		if not raw.munitions is Dictionary:return account._fail("弹药计划无效")
		for id in raw.munitions:
			if not account.state.get("owned",{}).has(str(id)):return account._fail("只能配置已拥有舰娘")
			var row:Variant=raw.munitions[id]
			if not row is Dictionary or row.size()!=3 or str(row.get("shell","")) not in SHELLS or str(row.get("torpedo","")) not in TORPEDOES:return account._fail("弹种或备雷计划无效")
			var reserve:Variant=row.get("reserve_reloads")
			if not (reserve is int or reserve is float) or float(reserve)!=floor(float(reserve)) or int(reserve) not in [0,1,2]:return account._fail("备雷轮数无效")
			var normalized:Dictionary=row.duplicate(true);normalized.reserve_reloads=int(reserve)
			next.get_or_add("munitions",{})[str(id)]=normalized
	var before:Dictionary=account.state.duplicate(true);account.state.expedition_v2=next
	return account._commit(before,"弹药计划已保存")
func set_loadout(id:String,ammo:int,torpedoes:bool)->Dictionary:
	if not account._can_service(id) or ammo<20 or ammo>100:return account._fail("请选择已拥有舰娘，炮弹20–100份")
	var before:Dictionary=account.state.duplicate(true)
	account.state.owned[id].ammo=ammo
	account.state.get_or_add("cargo_loadouts",{})[id]={"torpedoes":torpedoes}
	return account._commit(before,"装载计划已保存；出航时扣除弹药库存")
func start_config(difficulty:String)->Dictionary:
	var result:=options();result.erase("scene");result.difficulty=difficulty;result["commander_level"]=int(account.player_profile().level)
	result["loadouts"]={}
	for id in account.formation:result.loadouts[id]=account.state.get("cargo_loadouts",{}).get(id,{"torpedoes":true}).duplicate(true)
	return result
func budget(fleet:Array)->Dictionary:
	var registry:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(TONNAGE))
	var cells:=16+int(account.player_profile().level)*2;var ships:Array=[]
	var refs:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/ship-reference.json")).get("ships",{})
	for row in fleet:
		var id:String=str(row.id);var kind:String=str(row.get("type","DD"));var source:Dictionary=registry.ships.get(id,{})
		var tons:=int(source.get("tons",registry.fallback.get(kind,2000)))
		var transport:bool=kind in ["APD","AP","AK","AO","AE"] or str(source.get("cargo_role",""))=="transport"
		var has_torpedo:bool=refs.get(id,{}).get("base",{}).get("torpedo")!=null
		var light:int=(100-int(row.get("ammo",100)))/25
		var no_torp:bool=has_torpedo and not bool(account.state.get("cargo_loadouts",{}).get(id,{}).get("torpedoes",true))
		var share:=maxi(2,int(floor(sqrt(float(tons)/1000.0)))*2)+(12 if transport else 0)+light+(4 if no_torp else 0)
		var active:Dictionary=account.state.get("active_run",{})
		var new_rules:bool=active.is_empty() or str(active.get("gameplay_profile","")) in ["cas-adventure-v2","cas-adventure-v3"]
		if new_rules and has_torpedo and not no_torp:share-=2*int(account.state.get("expedition_v2",{}).get("munitions",{}).get(id,{}).get("reserve_reloads",1))
		cells+=share;ships.append({"id":id,"name":str(row.get("name",id)),"tons":tons,"source":source.get("source","未核吨位：使用独立载货预算假定"),"cells":share,"transport":transport,"torpedoes":not no_torp,"has_torpedoes":has_torpedo,"ammo":int(row.get("ammo",100))})
	return {"cols":8,"rows":int(ceil(float(cells)/8.0)),"cells":cells,"max_kg":cells*55,"ships":ships,"search_seconds":int({"calm":8,"standard":12,"hazard":16}.get(str(options().difficulty),8))}
func stash()->Dictionary:
	var result:Dictionary=account.state.get_or_add("cargo_stash",{"version":"cargo-stash-v1","items":[]})
	result["cols"]=10;result["rows"]=4+int(account.player_profile().level)
	return result
static func item_cells(item:Dictionary,placement:Array)->Array:
	var shape:Array=item.get("shape",[[0,0]])
	var max_x:=0;var max_y:=0
	for point in shape:max_x=maxi(max_x,int(point[0]));max_y=maxi(max_y,int(point[1]))
	var result:Array=[];var rotation:=int(placement[2])%4
	for point in shape:
		var p:Array=point.duplicate()
		if rotation==1:p=[max_y-int(point[1]),int(point[0])]
		elif rotation==2:p=[max_x-int(point[0]),max_y-int(point[1])]
		elif rotation==3:p=[int(point[1]),max_x-int(point[0])]
		result.append([int(placement[0])+int(p[0]),int(placement[1])+int(p[1])])
	return result
func can_fit(items:Array,item:Dictionary,p:Array,cols:int,rows:int,usable_cells:int=-1)->bool:
	var cells:=item_cells(item,p)
	for point in cells:
		if int(point[0])<0 or int(point[1])<0 or int(point[0])>=cols or int(point[1])>=rows:return false
		if usable_cells>=0 and int(point[1])*cols+int(point[0])>=usable_cells:return false
	for other in items:
		if str(other.id)==str(item.id) or other.get("placement")==null:continue
		for point in item_cells(other,other.placement):
			if cells.has(point):return false
	return true
func _first_fit(data:Dictionary,item:Dictionary)->Variant:
	for y in range(int(data.rows)):
		for x in range(int(data.cols)):
			for r in range(4):
				if can_fit(data.items,item,[x,y,r],int(data.cols),int(data.rows),int(data.get("usable_cells",-1))):return [x,y,r]
	return null
func receive(items:Array,active:Dictionary)->void:
	if active.has("cargo_transfer_v1"):
		load("res://scripts/fleet_warehouse.gd").new(account).receive(items,active)
		return
	var data:=stash()
	for original in items:
		if not original is Dictionary or original.get("placement")==null:continue
		var item:Dictionary=original.duplicate(true);item.id=str(active.run_id)+":"+str(item.id)
		if data.items.any(func(old):return str(old.id)==str(item.id)):continue
		item["difficulty"]=str(active.get("cargo_v4",{}).get("difficulty","calm"));item.placement=null
		item.placement=_first_fit(data,item);data.items.append(item)
static func catalog_item(id:String)->Dictionary:
	var catalog:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(LOOT))
	for item in catalog.get("items",[]):
		if str(item.id)==id:return item
	return {}
static func art_path(item:Dictionary)->String:
	var illustration:String="res://assets/items/salvage-v3/"+str(item.get("loot_id",""))+".png"
	if ResourceLoader.exists(illustration):return illustration
	var path:String="res://assets/items/expedition/"+str(item.get("loot_id",""))+".svg"
	return path if ResourceLoader.exists(path) else "res://assets/items/"+str(item.get("kind","scrap"))+".png"
static func can_unpack(item:Dictionary)->bool:
	if item.has("loot_id"):return str(catalog_item(str(item.loot_id)).get("use","sell"))=="unpack"
	return str(item.get("kind","")) in ["equipment","command"]
static func validate_receipt(raw:Variant,loot:Dictionary,success:bool,difficulty:String="",allow_v2:bool=false,carried:Array=[])->bool:
	if not raw is Array:return false
	var counts:Dictionary={"scrap":0,"alloy":0,"equipment":0,"command":0};var seen:Dictionary={}
	var shapes:Dictionary={"scrap":[[0,0],[1,0]],"alloy":[[0,0],[1,0],[0,1],[1,1]],"equipment":[[0,0],[0,1],[1,1]],"command":[[0,0],[1,0],[2,0]]}
	var weights:Dictionary={"scrap":55,"alloy":120,"equipment":90,"command":35}
	if raw.size()>(96 if allow_v2 else 60):return false
	for item in raw:
		if not item is Dictionary or not counts.has(str(item.get("kind",""))):return false
		var kind:String=str(item.kind);var id:String=str(item.get("id",""))
		var expected_shape:Array=shapes[kind];var expected_kg:int=weights[kind]
		if item.has("loot_id"):
			if not allow_v2 or difficulty not in ["calm","standard","hazard"]:return false
			var spec:Dictionary=catalog_item(str(item.loot_id))
			if spec.is_empty() or str(spec.kind)!=kind:return false
			expected_shape=spec.shape;expected_kg=int(spec.kg)
			var factor:int={"calm":10,"standard":14,"hazard":19}[difficulty]
			var prior:Dictionary={}
			for old in carried:
				if str(old.get("id",""))==id:prior=old;break
			if not prior.is_empty():
				for field in ["loot_id","kind","name","value","kg"]:
					if str(item.get(field,""))!=str(prior.get(field,"")):return false
			elif float(item.get("value",-1))!=floor(float(spec.value)*factor/10.0):return false
		elif int(item.get("value",0))<1 or int(item.get("value",0))>1000:return false
		if id.is_empty() or seen.has(id) or not item.get("shape") is Array or item.shape.size()!=expected_shape.size() or float(item.get("kg",-1))!=float(expected_kg):return false
		# JSON numbers arrive as floats. Compare exact coordinate values, not Array element types.
		for i in range(item.shape.size()):
			if not item.shape[i] is Array or item.shape[i].size()!=2:return false
			for axis in range(2):
				if not (item.shape[i][axis] is int or item.shape[i][axis] is float) or float(item.shape[i][axis])!=float(expected_shape[i][axis]):return false
		seen[id]=true
		if item.get("placement")==null:continue
		if not valid_placement(item.placement):return false
		counts[kind]=int(counts[kind])+1
	if success:
		for kind in counts:
			if int(counts[kind])!=int(loot.get(kind,0)):return false
	return true
static func valid_placement(p:Variant)->bool:
	if not p is Array or p.size()!=3:return false
	for value in p:
		if not (value is int or value is float) or not is_finite(float(value)) or float(value)!=floor(float(value)) or float(value)<0:return false
	return int(p[2]) in [0,1,2,3]
func place_stash(id:String,p:Array,scope:String="base")->Dictionary:
	if not account.state.get("active_run",{}).is_empty():return account._fail("海上行动期间不能整理母港仓库")
	var data:Dictionary=load("res://scripts/fleet_warehouse.gd").new(account).hold() if scope=="fleet" else stash();var item:Dictionary={}
	for row in data.items:
		if str(row.id)==id:item=row;break
	if item.is_empty() or not valid_placement(p) or not can_fit(data.items,item,p,int(data.cols),int(data.rows),int(data.get("usable_cells",-1))):return account._fail("该位置放不下物资")
	var before:Dictionary=account.state.duplicate(true);item.placement=p.duplicate()
	return account._commit(before,"仓库位置已保存")
func consume(id:String,scope:String="base")->Dictionary:
	if not account.state.get("active_run",{}).is_empty():return account._fail("返港后可处理仓库物资")
	var data:Dictionary=load("res://scripts/fleet_warehouse.gd").new(account).hold() if scope=="fleet" else stash();var item:Dictionary={}
	for row in data.items:
		if str(row.id)==id:item=row;break
	if item.is_empty():return account._fail("物资已处理")
	var before:Dictionary=account.state.duplicate(true)
	var unpack:bool=can_unpack(item)
	if unpack:
		var tier:=str(item.get("difficulty","calm"));account._create_item(str(item.kind),"gear-v3"+("-t2" if tier=="standard" else "-t3" if tier=="hazard" else ""));account.state.inventory[item.kind]=int(account.state.inventory.get(item.kind,0))+1
	else:account.state.wallet.credits=int(account.state.wallet.credits)+int(item.value)
	data.items.erase(item)
	return account._commit(before,"舰装/水手已拆包入库" if unpack else "物资已兑换银币")
