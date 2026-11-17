@tool
extends "res://scripts/littoral_land.gd"
## Extraction has its own external header, so reserve only a small map inset.
## Projection and hit testing still use this same invertible area.
func _projection_area()->Rect2:
	if miniature:return super._projection_area()
	return Rect2(Vector2(24,44),Vector2(maxf(1,size.x-48),maxf(1,size.y-68)))
