extends SceneTree
## GPU reflection around a fixed ground point, over every active approved frame.
## No source pixels, anchors, entity positions or account data are modified.
const Art=preload("res://scripts/tactical_art_v2.gd")
const OUTPUT:String="res://../artifacts/island-war-v3/presentation/"
var checks:int=0
var failures:Array[String]=[]
class Board extends Control:
	var cases:Array=[]
	var marks:bool=false
	func _draw()->void:
		draw_rect(Rect2(Vector2.ZERO,size),Color("173d47"))
		for i in range(cases.size()):
			var item:Dictionary=cases[i];var base:=Vector2((i%4)*400,floori(i/4.0)*220)
			for flipped in [false,true]:
				var ground:Vector2=base+Vector2(300 if flipped else 100,170)
				Art.paint(self,str(item.id),str(item.state),float(item.time),int(item.seed),80,ground,flipped)
				if marks:
					draw_line(ground-Vector2(7,0),ground+Vector2(7,0),Color("ffe681"),1)
					draw_line(ground-Vector2(0,7),ground+Vector2(0,7),Color("ffe681"),1)
			if marks:draw_string(ThemeDB.fallback_font,base+Vector2(8,211),"%s / %s / frame %d"%[item.id,item.state,item.frame],HORIZONTAL_ALIGNMENT_LEFT,390,15,Color("e8e2c9"))
func _initialize()->void:call_deferred("run")
func check(value:bool,message:String)->void:
	checks+=1
	if not value:failures.append(message);push_error(message)
func frames()->void:
	for i in range(3):await process_frame
func run()->void:
	check(DisplayServer.get_name()!="headless","anchor review uses actual GPU")
	if not failures.is_empty():return finish([])
	root.size=Vector2i(1600,900);root.content_scale_size=Vector2i(1600,900)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	var raw:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/tactical-art-v2.json"))
	var cases:Array=[]
	for unit in raw.units:
		var seen:Dictionary={};var referenced:Dictionary={}
		for state in unit.animations:
			var sequence:Array=unit.animations[state]
			for index in sequence:referenced[int(index)]=true
			for slot in range(sequence.size()):
				var time:float=3.6 if state=="idle" and slot>0 else (slot+.05)/(9.0 if state=="walk" else 7.0)
				var chosen:Dictionary=Art.frame(str(unit.id),str(state),time,slot)
				var index:int=unit.frames.find(chosen)
				if index<0 or seen.has(index):continue
				seen[index]=true;cases.append({"id":unit.id,"state":state,"time":time,"seed":slot,"frame":index})
		check(seen.size()==referenced.size(),"every active approved animation frame is reached "+str(unit.id))
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
					var left:Color=pixels.get_pixel(base.x+x,base.y+y)
					var right:Color=pixels.get_pixel(base.x+399-x,base.y+y)
					error+=absf(left.r-right.r)+absf(left.g-right.g)+absf(left.b-right.b)
					var backdrop:=Color("173d47")
					if absf(left.r-backdrop.r)+absf(left.g-backdrop.g)+absf(left.b-backdrop.b)>.03:changed+=1
			var mean:float=error/(40000.0*3.0)
			check(mean<.0015 and changed>60,"ground-pivot GPU reflection %s frame %d error %.6f"%[item.id,item.frame,mean])
			results.append({"unit":item.id,"frame":item.frame,"state":item.state,"mean_rgb_error":mean,"foreground_pixels":changed})
		board.marks=true;board.queue_redraw();await frames();RenderingServer.force_draw(false)
		check(root.get_texture().get_image().save_png(ProjectSettings.globalize_path(OUTPUT+"ground-anchors-%02d.png"%page))==OK,"save GPU anchor page %d"%page)
	board.queue_free();await frames();finish(results)
func finish(results:Array)->void:
	var report:Dictionary={"ok":failures.is_empty(),"checks":checks,"failures":failures,"frames":results.size(),"samples":results,"scope":"Actual GPU horizontal reflection around the same ground point for every active approved frame, with marked contact sheets. Unused archived poses are excluded. Asset alignment only; actual native motion and camera tests are separate."}
	FileAccess.open(OUTPUT+"anchor-receipt.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"));print(JSON.stringify({"ok":report.ok,"checks":checks,"failures":failures,"frames":results.size()}));quit(0 if failures.is_empty() else 1)
