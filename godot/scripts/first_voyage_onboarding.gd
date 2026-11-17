extends RefCounted
## Only an explicitly created future profile opts in. Missing markers on an old
## save never imply a new player, even when that account has no completed sortie.
const VERSION:String="first-voyage-canon-v1"
const KEY:String="first_voyage_canon"
const Story=preload("res://scripts/canon_story_service.gd")

static func mark_new_profile(state:Dictionary)->void:
	state.get_or_add("progression",{})[KEY]={"version":VERSION,"active":true,"started":false}

static func pending(account)->bool:
	var marker:Dictionary=account.state.get("progression",{}).get(KEY,{})
	return str(marker.get("version",""))==VERSION and bool(marker.get("active",false))

static func prepare_route(account,fallback:String="title")->Dictionary:
	if not pending(account):return {"ok":true,"route":fallback,"redirected":false}
	# A live sea/land mission owns resume. Entering the story reader here would
	# strand the player behind its real-action gate or change another voyage.
	if not account.state.get("active_run",{}).is_empty():return {"ok":true,"route":fallback,"redirected":false,"active_voyage":true}
	var previous:Dictionary=account.state.duplicate(true)
	var service=Story.new(account)
	service.ensure()
	var marker:Dictionary=account.state.progression[KEY]
	var first:Dictionary=service.state().chapters.get("chapter-01",{})
	if bool(first.get("complete",false)):
		marker.active=false
		var finished:Dictionary=account._commit(previous,"初次航程已完成")
		finished.merge({"route":fallback,"redirected":false})
		return finished
	# Never select another chapter or replace its saved node. The marker is only
	# written by new_profile; this guard also makes an imported profile harmless.
	if str(service.state().selected)!="chapter-01":
		marker.active=false
		var imported:Dictionary=account._commit(previous,"保留已有章节位置")
		imported.merge({"route":fallback,"redirected":false})
		return imported
	marker.started=true
	var result:Dictionary=account._commit(previous,"从第一章继续初次航程")
	result.merge({"route":"canon_story" if result.get("ok",false) else fallback,"redirected":bool(result.get("ok",false))})
	return result
