extends Resource
class_name CasPlayerGrowthRules
## Account balance authoring resource. Combat itself still enforces CAS caps.
@export_range(1,20) var commander_max_level:int=20
@export_range(1,10000) var commander_base_xp:int=60
@export_range(0,1000) var commander_step_xp:int=30
@export_range(0,100000) var refit_silver:int=200
@export_range(0,100) var refit_cores:int=2
@export var materials:Array[Dictionary]=[]
@export var ascensions:Array[Dictionary]=[]
@export var gear_types:Array[Dictionary]=[]
func catalog() -> Dictionary:
	return {"materials":materials,"ascensions":ascensions,"gear_types":gear_types}
