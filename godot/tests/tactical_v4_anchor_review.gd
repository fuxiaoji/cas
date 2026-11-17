extends "res://tests/tactical_v3_anchor_review.gd"
## New 27-identity frames are tested separately from the frozen v3 receipt.
const V4_OUTPUT:String="res://../artifacts/island-war-v4/anchors/"
func run()->void:
	check(DisplayServer.get_name()!="headless","new anchor review uses actual GPU")
	if not failures.is_empty():return finish([])
	root.size=Vector2i(1600,900);root.content_scale_size=Vector2i(1600,900)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(V4_OUTPUT))
	var raw:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/island-war-v4.json"))
	var cases:Array=[]
	check(raw.cards.size()==28,"all 28 tactical identities are in the core export")
	for card in raw.cards:
		var id:String=str(card.id);var unit:Dictionary=Art.entry(id)
		check(Art.available(id),"approved own-identity SD available "+id)
		var seen:Dictionary={};var referenced:Dictionary={}
		for state in ["idle","walk","fire","hurt","search","fall","defeated","deploy","parachuting"]:
			var sequence:Array=unit.get("animations",{}).get(state,[])
			for index in sequence:referenced[int(index)]=true
			for slot in range(sequence.size()):
				var time:float=3.6 if state=="idle" and slot>0 else (slot+.05)/(9.0 if state=="walk" else 7.0)
				var chosen:Dictionary=Art.frame(id,state,time,slot)
				var index:int=unit.frames.find(chosen)
				if index<0 or seen.has(index):continue
				seen[index]=true;cases.append({"id":id,"state":state,"time":time,"seed":slot,"frame":index})
		check(seen.size()==referenced.size(),"all active battle animation frames are reachable "+id)
		check(unit.get("animations",{}).get("defeated",[]).size()>=3,"at least three fixed distinct fallen poses "+id)
	var board:=Board.new();board.size=Vector2(1600,900);root.add_child(board)
	var results:Array=[]
	for page in range(ceili(cases.size()/16.0)):
		board.marks=false;board.cases=cases.slice(page*16,mini(cases.size(),page*16+16));board.queue_redraw();await frames();RenderingServer.force_draw(false)
		var pixels:Image=root.get_texture().get_image()
		for i in range(board.cases.size()):
			var item:Dictionary=board.cases[i];var base:=Vector2i((i%4)*400,floori(i/4.0)*220)
			var error:float=0;var changed:int=0
			for y in range(200):
				for x in range(200):
					var left:Color=pixels.get_pixel(base.x+x,base.y+y);var right:Color=pixels.get_pixel(base.x+399-x,base.y+y)
					error+=absf(left.r-right.r)+absf(left.g-right.g)+absf(left.b-right.b)
					var backdrop:=Color("173d47")
					if absf(left.r-backdrop.r)+absf(left.g-backdrop.g)+absf(left.b-backdrop.b)>.03:changed+=1
			var mean:float=error/120000.0
			check(mean<.0015 and changed>60,"ground-pivot GPU reflection %s frame %d error %.6f"%[item.id,item.frame,mean])
			results.append({"unit":item.id,"frame":item.frame,"state":item.state,"mean_rgb_error":mean,"foreground_pixels":changed})
		board.marks=true;board.queue_redraw();await frames();RenderingServer.force_draw(false)
		check(root.get_texture().get_image().save_png(ProjectSettings.globalize_path(V4_OUTPUT+"ground-anchors-%02d.png"%page))==OK,"save marked GPU anchor page %d"%page)
	board.queue_free();await frames();finish(results)
func finish(results:Array)->void:
	var report:Dictionary={"ok":failures.is_empty(),"checks":checks,"failures":failures,"frames":results.size(),"samples":results,"scope":"27 approved own identities, active battle frame reachability, three or more fixed fallen variants, and actual GPU horizontal reflection about the same authored pivot. Home daily frames and native movement are tested separately; old v3 evidence remains untouched."}
	FileAccess.open(V4_OUTPUT+"anchor-receipt.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"));print(JSON.stringify({"ok":report.ok,"checks":checks,"failures":failures,"frames":results.size()}));quit(0 if failures.is_empty() else 1)
