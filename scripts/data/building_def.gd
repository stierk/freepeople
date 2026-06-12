class_name BuildingDef
extends Resource

enum BuildingType {
	STORAGE_YARD, GRANARY, TREASURY, MARKET,
	WOODCUTTER_HUT, SAWMILL_HUT, QUARRY_HUT, FARMER_HUT, ROAD
}

@export var type: BuildingType = BuildingType.STORAGE_YARD
@export var display_name: String = ""
@export var footprint_size: Vector2i = Vector2i(1, 1)
@export var sprite_atlas_region: Rect2i = Rect2i(0, 0, 16, 16)
@export var max_capacity: int = 2
@export var build_time_seconds: float = 0.0
@export var is_player_placeable: bool = false
@export var build_cost_gold: float = 0.0
@export var storage_capacity: Dictionary = {}
