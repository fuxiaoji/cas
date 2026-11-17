extends SceneTree
## Inspect the exact imported AtlasTexture regions; no image pixels are edited.
class Gallery extends Control:
	var textures: Dictionary={}
	var font: Font=preload("res://scripts/ui_design.gd").font(500)
	const SPECIES := ["scavenger","spitter","warden","leviathan","aversion","rust_crab","cult_ray"]
	const LABELS := ["拾骸兽","骨帆水母","礁脊守卫","渊喉","憎恶巡游者","锈壳采掘蟹","祭潮鳐"]
	func _draw()->void:
		draw_rect(Rect2(Vector2.ZERO,size),Color("103e50"))
		for column in range(6):
			draw_string(font,Vector2(185+column*204,29),["待机","游动","蓄力","出击","受击","失能"][column],HORIZONTAL_ALIGNMENT_LEFT,-1,18,Color("cbe7e7"))
		for row in range(7):
			var frames: SpriteFrames=preload("res://scripts/enemy_animation.gd").frames_for(SPECIES[row],textures)
			var row_height: float=(size.y-62.0)/7.0
			var y:=36.0+row*row_height
			draw_string(font,Vector2(16,y+row_height*.55),LABELS[row],HORIZONTAL_ALIGNMENT_LEFT,-1,16,Color("ebddbc"))
			for column in range(6):
				var texture: Texture2D=frames.get_frame_texture(preload("res://scripts/enemy_animation.gd").POSES[column],0)
				var rect:=Rect2(Vector2(143+column*204,y),Vector2.ONE*(row_height-4))
				draw_texture_rect(texture,rect,false)
		draw_string(font,Vector2(18,size.y-8),"90°俯视 · 统一朝北 · 原图3×2 Atlas · 实战由公开状态驱动",HORIZONTAL_ALIGNMENT_LEFT,-1,14,Color(.70,.83,.82,.7))

func _initialize()->void:call_deferred("review")
func review()->void:
	var gallery:=Gallery.new();root.add_child(gallery);gallery.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	await process_frame;await process_frame;await RenderingServer.frame_post_draw
	var output:=ProjectSettings.globalize_path("res://../artifacts/godot/expedition-presentation/topdown-seven-species-six-poses.png")
	var saved:=root.get_texture().get_image().save_png(output)
	print("ATLAS_GALLERY "+output+" saved="+str(saved));quit(saved)
