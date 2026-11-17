extends "res://tests/canon_story_v2_review.gd"
## Integration contract fixture only. This does NOT audit the authored chapters;
## actual missions, account commits, UI loading and resume remain production code.
func graph()->bool:
	var entry:Dictionary={"id":"contract-intro","kind":"dialogue","title":"合同检查","lines":[{"speaker":"fletcher","text":"这是隔离测试用的对话。","actors":["fletcher"]}],"actors":["fletcher"],"next":"contract-breakout"}
	var nodes:Array=[entry]
	var stages:Array=[
		{"id":"contract-breakout","action_type":"native_battle","native_stage":"c1-breakout","next":"contract-tour"},
		{"id":"contract-tour","action_type":"harbor_tour","next":"contract-growth"},
		{"id":"contract-growth","action_type":"growth","next":"contract-salvage"},
		{"id":"contract-salvage","action_type":"salvage_tutorial","native_stage":"c1-salvage","protocol_identity":Service.PROTOCOL,"next":"contract-confiscate"},
	]
	for node in stages:
		node["kind"]="action";node["title"]=str(node.id);node["objective"]="进行真实操作";node["seed"]=6109;nodes.append(node)
	nodes.append({"id":"contract-confiscate","kind":"dialogue","title":"征收","protocol_event":"confiscate","lines":[{"text":"协议交付。"},{"text":"记录同一份实物。"}],"next":"contract-sea"})
	var lessons:Array=[
		{"id":"contract-sea","action_type":"littoral_sea","next":"contract-land"},
		{"id":"contract-land","action_type":"littoral_landing","next":"contract-combined"},
		{"id":"contract-combined","action_type":"littoral_combined","next":"contract-build"},
		{"id":"contract-build","action_type":"home_build","next":"contract-garrison"},
		{"id":"contract-garrison","action_type":"home_garrison","next":"contract-return"},
	]
	for node in lessons:node["kind"]="action";node["title"]=str(node.id);node["seed"]=42;nodes.append(node)
	nodes.append({"id":"contract-return","kind":"dialogue","title":"归还","protocol_event":"return","lines":[{"text":"原协议归还。"},{"text":"请完成唯一同步。"}],"next":"contract-fixed"})
	nodes.append({"id":"contract-fixed","kind":"action","title":"唯一同步","action_type":"fixed_recruit","next":"contract-defense"})
	nodes.append({"id":"contract-defense","kind":"action","title":"完成迎敌","action_type":"island_defense","seed":42,"next":"contract-complete"})
	nodes.append({"id":"contract-complete","kind":"complete"})
	Data.cache["chapter-01"]={"id":"chapter-01","title":"运行时合同夹具","version":"chapter-01-canon-v2","entry":"contract-intro","cast":{"fletcher":{"name":"弗莱彻","ship_id":"IBS-U-USN-FLETCHER"}},"scenes":nodes}
	for id in ["chapter-02","chapter-03"]:Data.cache[id]={"id":id,"title":"合同占位章","version":id+"-canon-v2","entry":"complete","scenes":[{"id":"complete","kind":"complete"}]}
	records.append({"authored_content_audited":false,"fixture":"contract only; no authored JSON written"})
	return super.graph()
