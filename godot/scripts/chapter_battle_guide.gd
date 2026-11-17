extends Control
## A companion to the real battle controller. It observes accepted commands and public observations.
const Design=preload("res://scripts/ui_design.gd")
var app
var stage_id:=""
var step_id:=""
var collapsed:=false
var clock:=0.0
var action:Callable
var learned_entities:Dictionary={}
func _goal()->String:
	return str(preload("res://scripts/chapter_story_data.gd").stage(stage_id).get("goal_type",{"c1-breakout":"reach","c1-salvage":"archive","c1-boss":"boss"}.get(stage_id,"reach")))
static func attach(owner)->Control:
	var canon:bool=str(owner.run.get("context",{}).get("canon_version",""))=="story-canon-v2" and owner.core.view.has("chapter")
	if str(owner.run.get("mode",""))!="story_chapter" and not canon:return null
	if owner.battle_controller==null or owner.battle_controller.replay_mode:return null
	var guide=load("res://scenes/ui/chapter_battle_guide.tscn").instantiate()
	guide.app=owner;guide.stage_id=str(owner.core.view.get("chapter",{}).get("stageId",""))
	owner.page.add_child(guide);guide.bind();return guide
func bind()->void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);mouse_filter=Control.MOUSE_FILTER_IGNORE
	theme=Design.theme()
	$Card.add_theme_stylebox_override("panel",Design.box(Color(.97,.985,.98,.97),7,Color(.65,.82,.82)))
	var ring:=Design.box(Color(0,0,0,0),6,Color("efcb7d"));ring.set_border_width_all(3);$Focus.add_theme_stylebox_override("panel",ring)
	Design.apply_button($Card/Action,true);Design.apply_button($Card/Collapse,false,true);Design.apply_button($Reopen,false,true)
	$Card/Action.pressed.connect(func():if action.is_valid():action.call();_observe())
	$Card/Collapse.pressed.connect(func():collapsed=true;$Card.hide();$Focus.hide();$Reopen.show())
	$Reopen.pressed.connect(func():collapsed=false;$Reopen.hide();$Card.show();_observe())
	_observe()
func _process(delta:float)->void:
	clock+=delta
	if clock<.12:return
	clock=0.0
	if not is_instance_valid(app) or app.screen!="battle":return
	if is_instance_valid(app.modal):$Focus.hide();return
	_observe()
func _set_step(key:String,title:String,body:String,button:String,callback:Callable,target:String="")->void:
	step_id=key;set_meta("chapter_guide_step",key)
	$Card/Title.text=title;$Card/Body.text=body;$Card/Action.text=button;$Card/Action.visible=not button.is_empty();action=callback
	$Card/Chapter.text={"c1-breakout":"弗莱彻 · 雾线突围","c1-salvage":"拉姆森 · 失声信标","c1-boss":"帕金斯 · 渊喉"}.get(stage_id,"第五驱逐小队")
	$Card.visible=not collapsed;$Reopen.visible=collapsed
	$Focus.hide()
	if collapsed or target.is_empty():return
	for control in app.page.find_children("*","Button",true,false):
		if control.is_visible_in_tree() and control.text==target:
			$Focus.position=control.get_global_rect().position-global_position-Vector2(5,5)
			$Focus.size=control.size+Vector2(10,10);$Focus.show();return
func _observe()->void:
	if bool(get_meta("enemy_details_open",false)):hide();return
	show()
	if app.core.view.get("result")!=null:
		var won:bool=str(app.core.view.result.get("winner",""))=="allies" and bool(app.core.view.result.get("primary",false))
		_set_step("finished","行动目标已完成" if won else "本次行动已结束","所有人的行动都已记录。返回章节路线后，继续新解锁的故事。" if won else "回到章节路线后，可以重新挑战这次行动。完成目标，才能继续后面的故事。","",Callable());return
	var native_chapter:Dictionary=app.core.view.get("chapter",{})
	if str(native_chapter.get("missionProfile",""))=="canon-missions-v3":
		_observe_canon(native_chapter)
		return
	var evidence:Dictionary=app.economy.state.get("active_run",{}).get("evidence",{})
	var events:Array=app.core.view.get("chapter",{}).get("events",[])
	var route:bool=bool(evidence.get("followAccepted",false)) or bool(evidence.get("syncAccepted",false))
	if app.core.view.get("salvage",{}).has("adventure") and not app.sea.planned.is_empty() and not app.battle_controller.preview.get("valid",false):
		var reason:=str(app.battle_controller.preview.get("error","航点暂不可用"))
		if reason.contains("航速"):
			_set_step("route_speed","受损后，先调整航速",reason,"按可用航速重新预览",_preview_available_speed);return
	if not route:
		if app.selection_kind!="ship":
			var approach:="点击左下角第一张舰娘卡片。选中后，航线将交给她所在的编队。"
			if app.core.view.get("salvage",{}).has("adventure"):
				approach={"c1-breakout":"前方是雾礁水道。点击左下第一张舰娘卡片，沿开阔海面接近返航灯。","c1-salvage":"前方是半淹城市。点击左下第一张舰娘卡片，沿运河靠近档案信标。","c1-boss":"前方是狭长峡湾。点击左下第一张舰娘卡片，保持转向余地，别挤进预警区。"}.get(stage_id,approach)
			_set_step("select","先选中你的舰队",approach,"",Callable());return
		if app.sea.planned.is_empty():
			_set_step("plot","把航路画在海上","先点“准备画航线”，再在海面点出航点。可分段绕开岛岸；草稿还不会让舰队移动。","准备画航线",func():app.battle_controller.choose_route("follow"));return
		_set_step("commit","检查完，再下达命令","金色预览是待确认的航路。点下方“下达航线”，编队才会照此航行。","",Callable(),"下达航线");return
	if _goal()=="boss" and int(app.core.view.get("tick",0))==0 and not bool(evidence.get("gunOrdered",false)):
		_boss(evidence);return
	if int(app.core.view.get("tick",0))==0:
		var tempo:="点右上“开始”。本关已加快航行与加速，先用1×时间观察；调整航线时可暂停。" if app.core.view.get("salvage",{}).has("adventure") else "点右上“开始”。想调整命令时可随时暂停；倍率在右侧速度按钮里。"
		_set_step("time","让海上的时间开始流动",tempo,"",Callable(),"开始");return
	if _entity_lesson():return
	if _goal()=="archive" and not events.has("archive_recovered"):
		_archive();return
	if _goal()=="boss":
		_boss(evidence);return
	if _goal()=="reach" and not events.has("beacon_reached"):
		_set_step("beacon","先找到返航灯","沿海图航行，接近公布的突破信标。定位只移动镜头，不会替你移动舰队。","定位信标",_locate_beacon);return
	var salvage:Dictionary=app.core.view.get("salvage",{})
	if salvage.get("extracting") is Dictionary:
		_set_step("extract_wait","保持集结，等待撤离","让所有还能航行的舰艇留在同一归航水域内，继续航行直到撤离读条结束。","",Callable());return
	_set_step("extract","把每个人带回去","所有可航行舰艇进入归航水域后，选中撤离区，点下方“开始撤离”。只到达这里不会自动离开。","定位并选择归航区",_locate_exit,"开始撤离")

func _observe_canon(chapter:Dictionary)->void:
	# These are saved native action predicates. Looking at a marker, dismissing a
	# hint or opening cargo never manufactures the next completed tutorial step.
	if _canon_recovery_hint():return
	if _canon_torpedo_hint():return
	var step:Dictionary={}
	for candidate in chapter.get("tutorialSteps",[]):
		if not bool(candidate.get("done",false)):
			step=candidate
			break
	if step.is_empty():
		_set_step("canon_wait","目标已完成，确认返航","保持时间推进，等待实际战报。若还在海上，按归航区提示完成撤离。","",Callable())
		return
	var ident:String=str(step.get("id",step.get("action","current")))
	var raw_action:String=str(step.get("action",""))
	var kind:String={"search_salvage":"search","salvage_extract":"extract","gun":"focus_fire"}.get(raw_action,raw_action)
	if kind=="route":kind="rally" if ident=="rally" else "escort" if ident=="escort" else "move"
	var label:String=str(step.get("label","完成海图上的当前目标"))
	var title:String=label
	var body:String=""
	var button:String="定位当前目标"
	var callback:Callable=func():_locate_canon_step(step)
	var focus:String=""
	var salvage:Dictionary=app.core.view.get("salvage",{})
	match kind:
		"move":
			if app.selection_kind!="ship":
				title="先选中要指挥的编队"
				body="点下方舰娘卡，或先定位领舰。每个编队都有自己的航线。"
				button="定位并选择领舰"
			elif app.sea.planned.is_empty():
				title="为她们画出一条航路"
				body="点“准备画航线”，再在海面点出航点。绕开岛岸，草稿还不会让舰队移动。"
				button="准备画航线"
				callback=func():app.battle_controller.choose_route("follow")
			else:
				title="确认航线，再开始航行"
				body="金色航线只是预览。点“下达航线”，再点右上“开始”；随时可以暂停修改。"
				button="";callback=Callable();focus="下达航线"
		"evade":
			title="先离开攻击落点"
			body="海面的预警是将要命中的位置。暂停，画一条离开它的航线，再继续时间。"
			button="定位攻击预警"
		"escort":
			title="护送船也需要自己的航线"
			body="选中人类避难船，为她画去返航灯的航线。驱逐小队与神通分路掩护，别挤在慢船前面。"
			button="定位并选择避难船"
		"search":
			title="靠近遗迹，开始搜索"
			body="选中标记遗迹，靠近并减速，再点“打捞残骸”。搜索到的物资还没有装进船。"
			button="定位并选择遗迹";focus="打捞残骸"
			if salvage.get("search") is Dictionary:
				title="搜索中，先守住周围"
				body="继续推进时间，等物资逐件显现。受到威胁可以撤开，不必为读条硬扛。"
				button="";callback=Callable();focus=""
		"cargo_place":
			title="亲手把档案装进货舱"
			body="从左侧把档案拖入空格，放得下才松手。R旋转，也可双击快速装入。只有入舱才算带走。"
			button="打开航次货舱";callback=app.cargo_manifest
		"rally":
			title="最后一艘也要回来"
			body="逐个选编队，驶入同一个撤离圈。别漏下神通；有避难船时，她们也必须到齐。"
			button="定位归航区";callback=_locate_exit
		"extract":
			title="集结以后，主动撤离"
			body="选中归航区，点“开始撤离”，继续推进时间。到达圆圈本身不会自动结束航次。"
			button="选择归航区";callback=_locate_exit;focus="开始撤离"
			if salvage.get("extracting") is Dictionary:
				title="保持集结，等接驳完成"
				body="所有存活舰艇保持在同一撤离区，继续推进时间。不要让队尾又驶出接驳范围。"
				button="";callback=Callable();focus=""
		"focus_fire":
			title="把炮火指向真正的威胁"
			body="拖“炮”到敌人可下炮令；拖“雷”后停留瞄准，避开友舰扇区再松手。默认炮击掩护已开，雷击由你决定。"
			button="定位敌方接触";callback=_locate_contact
		"boss_phase":
			title="守住距离，观察新的攻击"
			body="留意首领下一阶段的预警，边回避边保持火力。需要时暂停或调低倍速。"
			button="定位首领";callback=_locate_contact
		"victory":
			title="让这次行动真正完成"
			body="保持时间推进和有效火力，完成海图目标。提示不能替代胜利，也不会替你发放物资。"
			button="";callback=Callable()
		_:
			body=label
	_set_step("canon_"+ident,title,body,button,callback,focus)
	set_meta("canon_native_step",ident)
	set_meta("canon_native_action",kind)
	set_meta("canon_native_command",raw_action)
	var tutorial:Dictionary=chapter.get("tutorial",{})
	$Card/Chapter.text="第五小队 · "+str(chapter.get("title","实战引导"))+"  "+str(int(tutorial.get("completeSteps",0))+1)+" / "+str(tutorial.get("totalSteps",chapter.get("tutorialSteps",[]).size()))

func _locate_canon_step(step:Dictionary)->void:
	var point:Variant=step.get("point")
	if point is Dictionary:_pan(app.sea.pos(point))
	if step.has("ruin_id"):
		for row in app.core.view.get("salvage",{}).get("ruins",[]):
			if int(row.get("id",-1))==int(step.ruin_id):
				app.select_object("ruin",row)
				return
	if str(step.get("action","")) not in ["move","route"]:return
	for ship in app.core.view.get("ships",[]):
		if float(ship.get("hp",0))<=0:continue
		if step.has("ship_id") and int(ship.id)!=int(step.ship_id):continue
		if step.has("fleet_id") and int(ship.get("fleet",-1))!=int(step.fleet_id):continue
		app.select_object("ship",ship)
		_pan(Vector2(float(ship.x),float(ship.y)))
		return

func _canon_recovery_hint()->bool:
	if app.battle_controller!=null and is_instance_valid(app.sea) and not app.sea.planned.is_empty() and not bool(app.battle_controller.preview.get("valid",false)):
		var reason:String=str(app.battle_controller.preview.get("error",""))
		if reason.contains("纵队") or reason.contains("重整") or reason.contains("航向不一致"):
			_canon_reform_hint(reason)
			return true
		if reason.contains("航速"):
			var available:float=_current_available_speed()
			if available<4.0:
				_set_step("canon_route_detach","受损舰已低于共同航速","当前编队不足4节，不能强行下航线。打开舰况选受损舰“脱队”，分别安排撤离；不会把她留在海上。","查看受损舰况",_show_slowest_ship,"脱队")
				return true
			_set_step("canon_route_speed","受损了，先核对可用航速",reason,"按可用航速重新预览",_preview_available_speed)
			return true
		if not reason.is_empty():
			_set_step("canon_route_blocked","这条草稿还不能下达",reason+"。暂停后调整航点，绕开陆地与危险接触。","继续调整航线",func():app.battle_controller.choose_route("follow"))
			return true
	for fleet in app.core.view.get("fleets",[]):
		if not str(fleet.get("notice","")).contains("因航行危险停止"):continue
		var has_live_ship:bool=app.core.view.get("ships",[]).any(func(ship):return int(ship.get("fleet",-1))==int(fleet.id) and float(ship.get("hp",0))>0)
		if not has_live_ship:continue
		var stopped:Dictionary={"action":"route","fleet_id":int(fleet.id)}
		var editing:bool=app.battle_controller!=null and int(app.battle_controller.fleet_id)==int(fleet.id) and is_instance_valid(app.sea) and not app.sea.planned.is_empty()
		_set_step("canon_danger_stop","有编队因危险停航","“"+str(fleet.get("name","这支编队"))+"”已停下。先暂停、选中她，重画绕开实体的航线，再确认下达。","" if editing else "暂停并选择这支编队",func():
			app.running=false
			_locate_canon_step(stopped),"下达航线" if editing else "")
		return true
	return false

func _canon_reform_hint(reason:String)->void:
	var preview:Dictionary=app.battle_controller.reform
	if preview.is_empty():
		_set_step("canon_reform_preview","先把舰队重新排成纵队",reason+"。暂停后预览重整，确认合法再下令；继续时间等待各舰对齐。","预览重整纵队",_preview_current_reform)
	elif bool(preview.get("valid",false)):
		_set_step("canon_reform_commit","重整航路已核对","打开编队面板，点“下达重整”。继续推进时间，让各舰完成转向，再重画返航线。","打开编队面板",func():_open_tactical_drawer("fleet"),"下达重整")
	else:
		_set_step("canon_reform_unavailable","这次重整仍不合法",str(preview.get("error",reason))+"。可查看受损或离列舰，手动“脱队”后分别返航；每艘存活舰都要带回。","查看受损舰况",_show_slowest_ship,"脱队")

func _open_tactical_drawer(tab:String)->void:
	app.battle_controller.tab=tab
	if app.battle_controller.hud!=null:app.battle_controller.hud.set_drawer(true)
	app.battle_controller.rebuild()

func _preview_current_reform()->void:
	app.running=false
	_open_tactical_drawer("fleet")
	app.battle_controller.preview_reform()

func _current_available_speed()->float:
	var available:float=float(app.battle_controller.cruise)
	for fleet in app.core.view.get("fleets",[]):
		if int(fleet.get("id",-1))==int(app.battle_controller.fleet_id):available=minf(available,float(fleet.get("maxSpeed",available)))
	for ship in app.core.view.get("ships",[]):
		if float(ship.get("hp",0))<=0 or int(ship.get("fleet",-1))!=int(app.battle_controller.fleet_id):continue
		available=minf(available,float(ship.get("systems",{}).get("maxSpeed",available)))
	return available

func _show_slowest_ship()->void:
	app.running=false
	var lowest:float=INF
	var selected:Dictionary={}
	for ship in app.core.view.get("ships",[]):
		if float(ship.get("hp",0))<=0 or int(ship.get("fleet",-1))!=int(app.battle_controller.fleet_id):continue
		var max_speed:float=float(ship.get("systems",{}).get("maxSpeed",INF))
		if max_speed<lowest:lowest=max_speed;selected=ship
	if not selected.is_empty():app.select_object("ship",selected)
	_open_tactical_drawer("ship")

func _canon_torpedo_hint()->bool:
	if not is_instance_valid(app.sea):return false
	var pending:Dictionary=app.sea.gesture
	if pending.is_empty() or str(pending.get("weapon",""))!="torpedo":return false
	var aim:Dictionary=pending.get("aim",{})
	if bool(aim.get("friendly",false)):
		_set_step("canon_torpedo_safety","友舰可能进入雷迹","先别发射。右键或Esc取消，换射向或让友军让开；没有安全扇区就继续用舰炮。","",Callable())
	elif not pending.has("anchor"):
		_set_step("canon_torpedo_aim","在目标上停留，等推荐射向","把“雷”拖到可用敌方接触上，稍停片刻。瞄准完成以后，再检查扇区和友舰位置。","",Callable())
	else:
		_set_step("canon_torpedo_release","检查雷迹，再松手发射","射界、装填与射向都有效时才能发射。避开已知友舰后松手；右键或Esc随时取消。","",Callable())
	return true
func _archive()->void:
	var salvage:Dictionary=app.core.view.get("salvage",{})
	if salvage.get("collecting") is Dictionary:
		_set_step("search_wait","搜索时也要保持警戒","推进时间，让打捞读条完成。受到攻击会中断；中断后可以再次搜索同一残骸。","",Callable());return
	var ruin:Dictionary={}
	for row in salvage.get("ruins",[]):
		if int(row.id)==int(app.core.view.get("chapter",{}).get("objective",{}).get("archiveRuinId",1)):ruin=row
	if ruin.is_empty():
		_set_step("find_archive","还没有看见档案信标","继续探索。只会标出本席已发现的残骸，不会显示未发现的目标。","",Callable());return
	var closest:=INF;var slow:=false
	for ship in app.core.view.get("ships",[]):
		if float(ship.get("hp",0))<=0:continue
		var distance:float=Vector2(float(ship.x),float(ship.y)).distance_to(app.sea.pos(ruin.get("p",{})))
		closest=minf(closest,distance)
		if distance<750.0 and float(ship.speed)<=8.0:slow=true
	if closest>=750.0:
		_set_step("approach_archive","先靠近，再搜索","把航路画到档案残骸750米内。定位后仍需你下达航线；靠近时把航速降到8节以下。","定位档案残骸",_locate_archive);return
	if not slow:
		_set_step("slow_search","慢下来，才能把它捞起","舰队已靠近残骸。至少一艘船要在750米内、现速不超过8节，才能开始打捞。","编队减速至6节",func():app.issue({"op":"speed","fleet":app.first_fleet(),"speed":6}));return
	if app.selection_kind!="ruin" or int(app.selected.get("id",-1))!=int(app.core.view.get("chapter",{}).get("objective",{}).get("archiveRuinId",1)):
		_set_step("select_archive","选择那座旧信标","选择残骸后，下方会出现“打捞残骸”操作。","选择档案残骸",_locate_archive);return
	_set_step("collect_archive","亲手带回这份档案","点下方“打捞残骸”，然后继续推进时间。货舱里的档案仍要随舰队撤离才算完成行动。","",Callable(),"打捞残骸")
func _boss(evidence:Dictionary)->void:
	var telegraphs:Array=app.core.view.get("salvage",{}).get("telegraphs",[])
	if not telegraphs.is_empty():
		_set_step("boss_evade","离开将要落下的攻击","海面上的预警圈是已经公布的落点。暂停，画出离开它的航线，再继续时间；它不会跟着你移动。","定位攻击预警",func():_pan(app.sea.pos(telegraphs[0])));return
	if app.core.view.get("contacts",[]).is_empty():
		_set_step("boss_find","岛后还藏着一个敌影","绕过岛岸，保持射线和舰队间距。尚未发现的敌人不会出现在教学里。","准备调整航路",func():app.battle_controller.choose_route("follow"));return
	if not bool(evidence.get("gunOrdered",false)):
		_set_step("boss_fire","尝试下达一次炮击","从选中舰艇旁的“炮”标记拖向敌方接触，再松开。射界与装填满足后才会开火；右键或Esc可取消。","定位敌方接触",_locate_contact);return
	for fleet in app.core.view.get("fleets",[]):
		if not bool(fleet.get("ai",{}).get("gun",true)):
			_set_step("boss_handover","把持续火力交还给队友","手动炮击会接管该编队的自动炮击授权。想专心指挥航路时，可以明确交还炮击；舰队不会替你接管移动。","恢复舰队自动炮击",_handover_guns);return
	_set_step("boss_fight","火力与回避，要一起指挥","炮击命令已下达。保持射线，留意新预警与阶段变化；击败本关首领后才会结算。","定位首领",_locate_contact)

func _entity_lesson()->bool:
	var salvage:Dictionary=app.core.view.get("salvage",{})
	if not salvage.has("adventure"):return false
	var contacts:Array=app.core.view.get("contacts",[])
	for warning in salvage.get("telegraphs",[]):
		if not preload("res://scripts/monster_renderer.gd").threatens_fleet(app.core.view,warning):continue
		var visible_source:=false
		for contact in contacts:
			if str(contact.get("id",""))==str(warning.get("source_contact","")):visible_source=true;break
		if not visible_source:continue
		var remaining:=maxi(0,int(warning.get("impact_tick",0))-int(app.core.view.get("tick",0)))
		var shape:="长条" if str(warning.get("shape",""))=="capsule" else "圆圈"
		var response:=str(warning.get("counter","离开预警区域"))
		_set_step("boss_evade" if _goal()=="boss" else "entity_evade","%s · %d秒"%[str(warning.get("name","攻击蓄力")),remaining],"%s是实际攻击范围。%s。可先暂停再画航线。"%[shape,response],"定位攻击预警",func():_pan(app.sea.pos(warning)))
		return true
	for contact in contacts:
		if not contact.has("attack"):continue
		var species:=str(contact.get("species",contact.get("visualType","")))
		if learned_entities.has(species):continue
		var attack:Dictionary=contact.attack
		var key:=species
		var description:="%s。%s。点击它可查看血量与下一次攻击。"%[str(attack.get("label","观察它的攻击")),str(attack.get("counter","离开预警区域"))]
		if species=="aversion":description="它不会攻击你所在的旗舰，其他队员仍需要保护。观察它与小队的距离，继续驶向返航信标。"
		_set_step("entity_"+species,"发现实体 · "+str(contact.get("name","异种")),description,"记住攻击方式",func():learned_entities[key]=true)
		return true
	return false
func _handover_guns()->void:
	for fleet in app.core.view.get("fleets",[]):
		var config:Dictionary=fleet.get("ai",{})
		if bool(config.get("gun",true)):continue
		app.issue({"op":"ai","fleet":int(fleet.id),"profile":str(config.get("profile","coord")),"mode":str(config.get("mode","auto")),"move":bool(config.get("move",false)),"gun":true,"torpedo":bool(config.get("torpedo",false))})
func _preview_available_speed()->void:
	var available:float=floorf(_current_available_speed())
	var current:bool=str(app.core.view.get("chapter",{}).get("missionProfile",""))=="canon-missions-v3"
	if current and available<4.0:
		app.notify({"ok":false,"message":"当前共同航速不足4节。先查看受损舰况，可将她脱队并分别安排撤离。"})
		return
	app.battle_controller.cruise=maxf(4.0,available)
	app.battle_controller.refresh_preview()
func _pan(point:Vector2)->void:
	app.sea.pan+=app.sea.size*.5-app.sea.project(point)+app.sea.combat_offset;app.sea.queue_redraw()
func _locate_beacon()->void:
	var point:Variant=app.core.view.get("chapter",{}).get("objective",{}).get("beacon")
	if point is Dictionary:_pan(app.sea.pos(point))
func _locate_exit()->void:
	var rows:Array=app.core.view.get("salvage",{}).get("exits",[])
	if rows.is_empty():return
	var row:Dictionary=rows[0].duplicate(true);row["index"]=0
	_pan(app.sea.pos(row));app.select_object("exit",row)
func _locate_archive()->void:
	for row in app.core.view.get("salvage",{}).get("ruins",[]):
		if int(row.id)==int(app.core.view.get("chapter",{}).get("objective",{}).get("archiveRuinId",1)):_pan(app.sea.pos(row.get("p",{})));app.select_object("ruin",row);return
func _locate_contact()->void:
	var rows:Array=app.core.view.get("contacts",[])
	if rows.is_empty():return
	_pan(app.sea.pos(rows[0]));app.select_object("contact",rows[0])
