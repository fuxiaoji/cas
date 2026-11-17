extends RefCounted
## Individually editable AtlasTexture assets with a safe editor placeholder.
static func texture(id:String,gear:bool=false) -> Texture2D:
	var path:="res://assets/%s/icons/%s.tres"%["gear" if gear else "growth",id]
	if ResourceLoader.exists(path):return load(path) as Texture2D
	var fallback:="res://assets/items/equipment.png" if gear else "res://assets/items/alloy.png"
	return load(fallback) as Texture2D if ResourceLoader.exists(fallback) else null
static func icon(parent:Control,id:String,size:=88,gear:=false) -> TextureRect:
	var node:=TextureRect.new()
	node.texture=texture(id,gear);node.custom_minimum_size=Vector2(size,size)
	node.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;node.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	parent.add_child(node);return node
