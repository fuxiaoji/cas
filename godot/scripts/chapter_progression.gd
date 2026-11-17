extends RefCounted
## Chapter fiction has its own progress and rewards. The native result alone clears a mission.
const CONTENT = preload("res://scripts/chapter_story_data.gd")
const VERSION := "chapter-01-v1"
var account
var chapter_id:String="chapter-01"
var version:String=VERSION
var state_key:String="chapter1"

func _init(owner,id:String="") -> void:
	account=owner
	chapter_id=str(account.state.get("progression",{}).get("story_chapter_id","chapter-01")) if id.is_empty() else id
	if not CONTENT.FILES.has(chapter_id):chapter_id="chapter-01"
	version=str(CONTENT.data(chapter_id).get("version",VERSION))
	state_key={"chapter-01":"chapter1","chapter-02":"chapter2","chapter-03":"chapter3"}[chapter_id]
	CONTENT.selected_chapter=chapter_id
	_ensure()
func unlocked(id:String)->bool:
	if id=="chapter-01":return true
	var preceding:String="chapter1" if id=="chapter-02" else "chapter2"
	var saved:Dictionary=account.state.progression.get(preceding,{})
	return str(CONTENT.scene(str(saved.get("node",""))).get("kind",""))=="complete"
func select(id:String)->Dictionary:
	if _blocked():return account._fail("请先完成或结束当前海上行动")
	if not CONTENT.FILES.has(id) or not unlocked(id):return account._fail("先完成上一章的故事")
	var previous:Dictionary=account.state.duplicate(true)
	account.state.progression.story_chapter_id=id
	return account._commit(previous,"章节已切换")

func _ensure() -> void:
	account.state.get_or_add("progression",{})
	account.state.progression.get_or_add(state_key,{"version":version,"node":str(CONTENT.data(chapter_id).get("entry","rescue")),"line":0,"seen":[],"choices":{},"cleared":{},"claimed":{},"evidence":{},"records":{},"guide_active":false,"guide_index":0,"guide_seen":[]})
	var saved:Dictionary=account.state.progression[state_key]
	var pages:Array=CONTENT.scene(str(saved.get("node",""))).get("lines",[])
	if not pages.is_empty():saved.line=clampi(int(saved.get("line",0)),0,pages.size()-1)

func _completed_revisit(node:Dictionary)->bool:
	return bool(node.get("longform_extra",false)) and str(scene().get("kind",""))=="complete"

func state() -> Dictionary:
	return account.state.progression[state_key].duplicate(true)

func scene(id: String="") -> Dictionary:
	return CONTENT.scene(str(state().node) if id.is_empty() else id)

func _blocked() -> bool:
	return not account.state.get("active_run",{}).is_empty()

func _advance(chapter: Dictionary,node: Dictionary) -> void:
	if not chapter.seen.has(str(node.id)):chapter.seen.append(str(node.id))
	chapter.node=str(node.get("next","complete"))
	chapter.line=0

func move(action: String,value: String="") -> Dictionary:
	if _blocked():return account._fail("请先保存并完成或结束当前海上行动")
	var previous:Dictionary=account.state.duplicate(true)
	var chapter:Dictionary=account.state.progression[state_key]
	var node:=scene()
	var kind:=str(node.get("kind",""))
	match action:
		"next", "skip":
			if kind!="dialogue":return account._fail("当前节点需要实际行动，不能跳过通关")
			var last:=maxi(0,node.get("lines",[]).size()-1)
			if int(chapter.line)<last:
				chapter.line=last if action=="skip" else int(chapter.line)+1
			elif not node.get("choices",[]).is_empty():return account._fail("请亲自选择这句话")
			else:_advance(chapter,node)
		"choice":
			if kind!="dialogue" or int(chapter.line)<node.get("lines",[]).size()-1:return account._fail("尚未到对话选择")
			var valid:bool=node.get("choices",[]).any(func(row):return str(row.id)==value)
			if not valid:return account._fail("该回答不属于当前对话")
			chapter.choices[str(node.id)]=value
			_advance(chapter,node)
			var branch:=str(node.get("choice_next",{}).get(value,""))
			if not branch.is_empty() and CONTENT.chapter_for_node(branch)==chapter_id:chapter.node=branch
		"guide_skip":
			if kind!="guide":return account._fail("当前没有待选导览")
			_advance(chapter,node)
		"tour":
			chapter.guide_active=true;chapter.guide_index=0
			if kind=="guide":_advance(chapter,node)
		"guide_next":
			if not bool(chapter.guide_active):return account._fail("导览未开启")
			var pages:Array=CONTENT.data(chapter_id).get("guide",[])
			var index:=int(chapter.guide_index)
			if index>=0 and index<pages.size() and not chapter.guide_seen.has(str(pages[index].route)):chapter.guide_seen.append(str(pages[index].route))
			chapter.guide_index=index+1
			if int(chapter.guide_index)>=pages.size():chapter.guide_active=false
		"guide_end":chapter.guide_active=false
		_:return account._fail("未知章节操作")
	return account._commit(previous,"章节进度已保存",{"chapter":state()})

func prepare(stage: String) -> Dictionary:
	if _blocked():return account._fail("请先继续或结束已有航次")
	var node:=CONTENT.stage(stage)
	if node.is_empty() or CONTENT.chapter_for_stage(stage)!=chapter_id:return account._fail("章节关卡不存在")
	if str(state().node)!=str(node.id) and not state().cleared.has(stage) and not _completed_revisit(node):return account._fail("尚未抵达这段故事")
	var native_stage:=str(node.get("native_stage",stage))
	var request:Dictionary={"op":"new_chapter","id":native_stage,"seed":int(node.get("seed",6109)),"gameplay_profile":"cas-adventure-v1"}
	request["intel_profile"]="open-intel-v1"
	return {"ok":true,"request":request,"context":{"mode":"story_chapter","id":stage,"native_stage":native_stage,"chapter_id":chapter_id,"chapter_version":version,"side":"allies","title":str(node.title),"return_route":"story_route"}}

func validate_start(context: Dictionary,snapshot: Dictionary) -> String:
	if str(context.get("chapter_id",""))!=chapter_id or str(context.get("chapter_version",""))!=version:return "章节上下文身份或版本不符"
	var stage:=str(context.get("id",""))
	var node:=CONTENT.stage(stage)
	if node.is_empty() or CONTENT.chapter_for_stage(stage)!=chapter_id:return "章节关卡不存在"
	if str(state().node)!=str(node.id) and not state().cleared.has(stage) and not _completed_revisit(node):return "尚未抵达这段故事"
	var start:Dictionary=snapshot.get("salvage",{})
	var native_stage:=str(node.get("native_stage",stage))
	if str(context.get("native_stage",stage))!=native_stage:return "章节行动与原核关卡映射不符"
	if str(start.get("chapter_version",""))!=version or str(start.get("mission",{}).get("kind",""))!="chapter" or str(start.get("mission",{}).get("id",""))!=native_stage:return "章节快照与关卡或内容版本不符"
	return ""

func finish(view: Dictionary,serialized: String) -> Dictionary:
	var active:Dictionary=account.state.get("active_run",{})
	if active.is_empty():
		var latest:Dictionary=account.latest_receipt()
		if str(latest.get("mode",""))=="story_chapter":return {"ok":true,"duplicate":true,"message":"章节行动已经结算","receipt":latest}
		return account._fail("没有待结算的章节行动")
	if str(active.get("mode",""))!="story_chapter":return account._fail("当前航次不属于剧情")
	var stage:=str(active.get("stage_id",""))
	var node:=CONTENT.stage(stage)
	if node.is_empty():return account._fail("章节关卡无法识别")
	var native_stage:=str(node.get("native_stage",stage))
	var chapter_view:Dictionary=view.get("chapter",{})
	var terminal:Variant=JSON.parse_string(serialized)
	if not terminal is Dictionary:return account._fail("章节结算缺少可重演原核快照")
	var start:Dictionary=terminal.get("salvage",{})
	var frozen:Variant=JSON.parse_string(str(active.get("snapshot","")))
	if not frozen is Dictionary or start!=frozen.get("salvage",{}) or int(terminal.get("seed",-1))!=int(frozen.get("seed",-2)) or str(terminal.get("version",""))!=str(frozen.get("version","")) or int(terminal.get("tick",-1))!=int(view.get("tick",-2)):return account._fail("章节结算与冻结的出航快照或战况时刻不符")
	if str(active.get("context",{}).get("native_stage",stage))!=native_stage:return account._fail("章节结算与原核关卡映射不符")
	if str(chapter_view.get("chapterVersion",""))!=version or str(chapter_view.get("chapterId",""))!=chapter_id or str(chapter_view.get("stageId",""))!=native_stage or str(start.get("chapter_version",""))!=version or str(start.get("mission",{}).get("id",""))!=native_stage or str(start.get("mission",{}).get("kind",""))!="chapter":return account._fail("章节结算身份或版本不一致，未发奖")
	if str(view.get("variant",""))!=str(active.get("native_variant","")):return account._fail("章节结算想定不一致")
	var result:Variant=view.get("result")
	var status:=str(chapter_view.get("status","active"))
	if not result is Dictionary or status not in ["won","lost"]:return account._fail("真实章节目标尚未结束")
	var success:bool=status=="won" and str(result.get("winner",""))=="allies" and bool(result.get("primary",false))
	var previous:Dictionary=account.state.duplicate(true)
	var chapter:Dictionary=account.state.progression[state_key]
	var grants:Dictionary={}
	var events:Array=chapter_view.get("events",[])
	for event in events:chapter.evidence[str(event)]=true
	chapter.records[stage]={"run_id":str(active.run_id),"success":success,"events":events.duplicate(true),"tick":int(view.get("tick",0))}
	if success:
		chapter.cleared[stage]=true
		if not chapter.claimed.has(stage):
			# Earlier completed saves may revisit inserted scenes without resetting or re-awarding the chapter.
			if not _completed_revisit(node):
				grants=node.get("rewards",{}).duplicate(true)
				for currency in grants:account.state.wallet[currency]=int(account.state.wallet.get(currency,0))+int(grants[currency])
				var growth:Dictionary=account.grant_player_xp("chapter:"+stage,150)
				grants["commander_xp"]=int(growth.get("xp",0))
			chapter.claimed[stage]=true
		if str(chapter.node)==str(node.id):_advance(chapter,node)
	var summary:Dictionary={"run_id":str(active.run_id),"mode":"story_chapter","stage_id":stage,"chapter_id":chapter_id,"title":str(node.title),"success":success,"stars":0,"coins":int(grants.get("credits",0)),"rewards":grants,"loot":{},"lost_loot":{},"ships":[],"xp":0,"borrowed":true,"deployment_ammo":0,"returned_ammo":0,"events":events.duplicate(true),"primary":"章节目标完成，后续对白已解锁" if success else "行动未完成，可重试；未推进剧情或发放通关奖励","return_route":"story_route"}
	account.state.settled[str(active.run_id)]=summary
	account.state.last_receipt_id=str(active.run_id)
	account.state.progression.last_replay={"snapshot":serialized,"context":active.get("context",{}).duplicate(true),"run_id":str(active.run_id)}
	account.state.active_run={}
	return account._commit(previous,"章节行动已结算",{"receipt":summary})
