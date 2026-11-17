extends RefCounted
## Content unlocks and ascension live in the account transaction, never in historical cards.
var account
var config:Dictionary
var rules=preload("res://data/player-growth.tres")
func _init(owner) -> void:
	account=owner;config=rules.catalog()
func ensure() -> void:
	if account.state.is_empty():return
	if not account.state.has("commander"):
		var old_level:=0
		for ship in account.state.owned.values():old_level=maxi(old_level,int(ship.level))
		account.state["commander"]={"level":6 if old_level>=20 else 3 if old_level>=10 else 1,"xp":0,"claims":{}}
	for key in ["training_t2","training_t3","core_t1","core_t2","core_t3"]:account.state.wallet.get_or_add(key,0)
	if not bool(account.state.get("ascension_initialized",false)):
		for ship in account.state.owned.values():ship.get_or_add("ascension",2 if int(ship.level)>20 else 1 if int(ship.level)>10 else 0)
		account.state.wallet.core_t1=int(account.state.wallet.core_t1)+2
		account.state["ascension_initialized"]=true
	for ship in account.state.owned.values():ship.get_or_add("ascension",0)
func profile() -> Dictionary:
	ensure()
	var saved:Dictionary=account.state.commander
	var level:=clampi(int(saved.level),1,rules.commander_max_level)
	return {"level":level,"max_level":rules.commander_max_level,"xp":int(saved.xp),"xp_next":0 if level==rules.commander_max_level else rules.commander_base_xp+level*rules.commander_step_xp,"unlocks":[{"level":1,"name":"基础资源海域","open":true},{"level":3,"name":"进阶资源 / 一阶突破","open":level>=3},{"level":6,"name":"深层资源 / 二阶突破","open":level>=6}],"scope":"指挥官等级解锁内容，不直接改变舰艇属性"}
func grant(key:String,amount:int) -> Dictionary:
	ensure()
	var saved:Dictionary=account.state.commander
	if amount<=0 or bool(saved.claims.get(key,false)):return {"xp":0,"duplicate":true}
	var before:=int(saved.level)
	saved.xp=int(saved.xp)+amount
	while int(saved.level)<rules.commander_max_level and int(saved.xp)>=rules.commander_base_xp+int(saved.level)*rules.commander_step_xp:
		saved.xp=int(saved.xp)-(rules.commander_base_xp+int(saved.level)*rules.commander_step_xp);saved.level=int(saved.level)+1
	if int(saved.level)>=rules.commander_max_level:saved.xp=0
	saved.claims[key]=true
	return {"xp":amount,"level_before":before,"level":int(saved.level)}
func cap(ship:Dictionary) -> int:
	return mini(30,10+clampi(int(ship.get("ascension",0)),0,2)*10)
func materials() -> Array:
	ensure();var rows:Array=[]
	for raw in config.materials:
		var row:Dictionary=raw.duplicate(true);row["owned"]=int(account.state.wallet.get(str(row.id),0));rows.append(row)
	return rows
func ascent_preview(id:String) -> Dictionary:
	ensure()
	if not account.state.owned.has(id):return account._fail("请先获得该舰娘")
	var ship:Dictionary=account.state.owned[id]
	var stage:=int(ship.ascension)
	if stage>=2:return {"ok":true,"maxed":true,"message":"已完成全部突破","cap":30}
	var recipe:Dictionary=config.ascensions[stage]
	var enough:=int(account.state.wallet.credits)>=int(recipe.credits)
	for key in recipe.materials:enough=enough and int(account.state.wallet.get(key,0))>=int(recipe.materials[key])
	var ready:bool=int(ship.level)>=cap(ship) and int(profile().level)>=int(recipe.player_level) and enough and account.state.active_run.is_empty()
	return {"ok":true,"maxed":false,"stage":stage,"level":int(ship.level),"cap":cap(ship),"next_cap":cap(ship)+10,"required_player_level":int(recipe.player_level),"credits":int(recipe.credits),"materials":recipe.materials.duplicate(true),"enough":enough,"ready":ready}
func ascend(id:String,request_id:String="") -> Dictionary:
	var replay:Dictionary=account._request(request_id,["ascend_ship",id])
	if not replay.is_empty():return replay
	var preview:=ascent_preview(id)
	if not bool(preview.get("ok",false)):return preview
	if not account._can_service(id):return account._fail("请返港后突破")
	if bool(preview.maxed):return account._fail("已完成全部突破")
	if not bool(preview.ready):return account._fail("需达到当前等级上限、指挥官等级及材料条件")
	var previous:Dictionary=account.state.duplicate(true)
	account.state.wallet.credits=int(account.state.wallet.credits)-int(preview.credits)
	for key in preview.materials:account.state.wallet[key]=int(account.state.wallet.get(key,0))-int(preview.materials[key])
	account.state.owned[id].ascension=int(preview.stage)+1
	# Banked experience is retained at a cap and resumes after breakthrough.
	account._add_xp(account.state.owned[id],0)
	return account._commit(previous,"突破完成 · 等级上限提升至%d"%int(preview.next_cap),{"ascension":int(preview.stage)+1,"cap":int(preview.next_cap)})
func train(id:String,tier:int,count:int=1,request_id:String="") -> Dictionary:
	ensure()
	var replay:Dictionary=account._request(request_id,["train_material",id,tier,count])
	if not replay.is_empty():return replay
	if not account._can_service(id) or tier<1 or tier>3 or count<1 or count>10:return account._fail("请选择有效舰娘与训练记录")
	var ship:Dictionary=account.state.owned[id]
	if int(ship.level)>=cap(ship):return account._fail("已达到当前等级上限，请先突破")
	var mat:Dictionary=config.materials[tier-1]
	var price:=int(mat.xp)*count*5/4
	if int(account.state.wallet.get(str(mat.id),0))<count or int(account.state.wallet.credits)<price:return account._fail("训练记录或银币不足")
	var previous:Dictionary=account.state.duplicate(true)
	account.state.wallet[str(mat.id)]=int(account.state.wallet.get(str(mat.id),0))-count
	account.state.wallet.credits=int(account.state.wallet.credits)-price
	account._add_xp(ship,int(mat.xp)*count)
	return account._commit(previous,"训练完成，超出当前突破上限的经验会保留",{"xp_added":int(mat.xp)*count,"level":int(ship.level)})
func fuse(id:String,count:int=1) -> Dictionary:
	ensure()
	var next:Dictionary={"materials":"training_t2","training_t2":"training_t3","core_t1":"core_t2","core_t2":"core_t3"}
	if not account.state.active_run.is_empty() or not next.has(id) or count<1 or count>100:return account._fail("当前无法合成")
	if int(account.state.wallet.get(id,0))<count*3:return account._fail("需要3份同级材料合成1份上级材料")
	var previous:Dictionary=account.state.duplicate(true)
	account.state.wallet[id]=int(account.state.wallet[id])-count*3
	account.state.wallet[next[id]]=int(account.state.wallet.get(next[id],0))+count
	return account._commit(previous,"材料合成完成")
func refit(instance_id:String,type_id:String,request_id:String="") -> Dictionary:
	ensure()
	var replay:Dictionary=account._request(request_id,["refit_equipment",instance_id,type_id])
	if not replay.is_empty():return replay
	var choices:Array=config.gear_types.filter(func(row):return str(row.id)==type_id)
	var item:Dictionary=account.state.item_instances.get(instance_id,{})
	if not account.state.active_run.is_empty() or choices.is_empty() or str(item.get("kind",""))!="equipment":return account._fail("请返港后选择有效舰装类型")
	if str(item.get("gear_type",""))==type_id:return account._fail("已是此类型")
	if int(account.state.wallet.credits)<rules.refit_silver or int(account.state.wallet.core_t1)<rules.refit_cores:return account._fail("需要%d银币与%d枚基础突破核心"%[rules.refit_silver,rules.refit_cores])
	var previous:Dictionary=account.state.duplicate(true)
	account.state.wallet.credits=int(account.state.wallet.credits)-rules.refit_silver
	account.state.wallet.core_t1=int(account.state.wallet.core_t1)-rules.refit_cores
	var choice:Dictionary=choices[0]
	item["gear_type"]=type_id;item["art_index"]=int(choice.atlas)
	item["name"]=str(item.get("rarity_name",""))+str(choice.name)
	item["main"]={"stat":str(choice.stat),"bp":int(item.bonus_bp)}
	item["sub"]={"stat":"hp","bp":0}
	item["drop_table_version"]="gear-v3"
	return account._commit(previous,"舰装改装完成，品级与强化总量保持不变",{"instance_id":instance_id,"gear_type":type_id})
