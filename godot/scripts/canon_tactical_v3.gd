extends RefCounted
## Updated teaching is attached to new departures. Existing native runs retain
## their saved version and their own concrete story receipt.
const VERSION:String="cas-island-war-v4"
const LESSONS:Dictionary={"v2c1-landing":"landing","v2c1-combined":"combined_arms","v2c2-land-cooperate":"airborne","v2c3-maintenance-beach":"roles","v2c3-shore-collaboration":"artillery"}
static func enrich(chapter:Dictionary)->void:
	for node in chapter.get("scenes",[]):
		var id:String=str(node.get("id",""))
		if LESSONS.has(id):
			node["tactical_lesson"]=LESSONS[id];node["mechanics_version"]=VERSION
			node["objective"]=str({"landing":"先清岸防，再用快速无甲皮划艇投送；真实撤收每个身体后返航。","weapons":"用轻武器压制步兵，让每连唯一的火箭筒手处理装甲；完成实战后撤收。","combined_arms":"让坦克与步枪身体分别作战，练习两栖车、火炮和武直的真实登载卸载，再把身体与载具安全撤回。","airborne":"保护下降中的伞兵；普通轻武器打飞机低效，打下降中的身体保持正常伤害。","roles":"用指挥和保障增益掩护工兵爆破，配合攻坚手雷、防空炮台与火力标记，完成真实协同后撤收。","artillery":"自行火炮负责远程输出，只有手枪的炮兵身体需要掩护；完成炮援并真实回收。"}.get(LESSONS[id],node.get("objective","")))
			node["objectives"]=[node.objective]
			node["implementation_boundary"]="新出发使用cas-island-war-v4借用训练的真实兵力和目标，增加准备期与循序岸防；已在进行的旧训练保留其版本。叙事地点不等于专门复刻的剧情地形，不改历史海图。"
			if node.get("action") is Dictionary:node.action["objectives"]=[node.objective]
		var replacement:Dictionary={}
		if id=="v2c1-landing-school":replacement={0:"先别急着拖军牌。看岸上那座炮台——皮划艇快，靠岸也卸得快，但它没有装甲。",1:"艇还没沉，坐在里面的人也会受伤？",2:"会。我们用自己的身体承受火力，不会躲进一个公共血条。先用舰炮清掉岸防，再让我带队抢这段岸。",4:"我可以乘直升机绕过去，可那也不是护身符。普通轻武器很难打坏飞机，但降落伞下面的身体一样会中弹。",6:"给她们留出各自走路的地方。先让第一连站稳，再接下一连。"}
		elif id=="v2c1-combined-school":replacement={1:"反坦克连也不是每个人都背火箭筒。每连一位负责打装甲，其余人的轻武器只够自卫。别把她们拿去和步兵硬拼。",2:"射程圈里也不一定打得准。冲锋枪隔远了会把弹药打空；射手步枪在远处稳一些。狙击枪要先停稳，别让她们边跑边往人群里挤。",5:"支援队有支援队的工作。救护和补给带的枪弱一点，才更需要我们把路清出来。",6:"自行火炮留在后面，只有手枪的炮兵由我们掩护。攻坚连从街角贴近，射手留住距离。先把第一步放对，再叫下一连。"}
		for index in replacement:
			if int(index)<node.get("lines",[]).size():node.lines[int(index)]["text"]=replacement[index]
		if id=="v2c1-combined-school" and not bool(node.get("weapon_cadence_dialogue",false)) and node.get("lines",[]).size()>6:
			var burst:Dictionary=node.lines[6].duplicate(true)
			burst["text"]="听，攻坚连是短促的连射，射手那边是一下、一下地点射。同样叫射手步枪，指挥连和精准射手用的也不是同一款。"
			var reload_line:Dictionary=node.lines[2].duplicate(true)
			reload_line["text"]="枪声停了先看弹匣。打得快不代表换弹也快，让另一个连继续掩护，别在换弹的时候一起往前冲。"
			var vehicles:Dictionary=node.lines[6].duplicate(true)
			vehicles["text"]="坦克不是我们其中一个身体变出来的。第22旅上岸是一辆坦克加六个人，车打硬目标，人清近处。要重新登车，把身体卡拖到本连载具，她们会自己走过去。"
			var unloading:Dictionary=node.lines[2].duplicate(true)
			unloading["text"]="两栖车、自行炮和武直也有自己的武器、耐久与弹匣。把卸载卡拖向落点，等载具抵达再下车。空机可以继续支援，已经下机的身体不会跟着它飞走。"
			node.lines.append(burst);node.lines.append(reload_line);node.lines.append(vehicles);node.lines.append(unloading);node["weapon_cadence_dialogue"]=true
		if LESSONS.has(id) and not node.get("lines",[]).is_empty():node.lines[0]["text"]=node.objective
static func request(lesson:String,version:String=VERSION)->Dictionary:
	if version not in ["cas-island-war-v3","cas-island-war-v4"]:return {"ok":false,"message":"训练版本无法识别，尚未开始行动。"}
	var path:String="res://data/tactical-training-v4.json" if version==VERSION else "res://data/tactical-training-v3.json"
	if not FileAccess.file_exists(path):return {"ok":false,"message":"新版武器训练配置尚未就绪，请稍后重试。"}
	var raw:Variant=JSON.parse_string(FileAccess.get_file_as_string(path))
	if not raw is Dictionary:return {"ok":false,"message":"新版训练配置无法读取。"}
	var entry:Dictionary=raw.get("lessons",{}).get(lesson,{})
	var value:Dictionary=entry.get("request",{}).duplicate(true)
	if value.is_empty():return {"ok":false,"message":"这一门武器训练尚未装入。"}
	if str(value.get("version",""))!=version or str(value.get("lesson",""))!=lesson:return {"ok":false,"message":"训练配置与当前课程版本不符。"}
	return {"ok":true,"request":value}
