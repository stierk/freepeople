class_name BuildingDef
extends Resource

# M29: HUNTER_HUT appended at the end (enums are stored as int – only append).
enum BuildingType {
	STORAGE_YARD, GRANARY, TREASURY, MARKET,
	WOODCUTTER_HUT, SAWMILL_HUT, QUARRY_HUT, FARMER_HUT, ROAD,
	TOWN_HALL, WINDMILL, BAKERY, HUNTER_HUT
}

@export var type: BuildingType = BuildingType.STORAGE_YARD
@export var display_name: String = ""
@export var footprint_size: Vector2i = Vector2i(1, 1)
## Source sheet of the building sprite: "base"/"farm"/"vik" (fliegevolge_overworld)
## or "px" (pixelholes MasterSimple, legacy asset).
@export var sprite_sheet: String = "px"
@export var sprite_atlas_region: Rect2i = Rect2i(0, 0, 16, 16)
## Number of horizontal animation frames starting at sprite_atlas_region (1 = static).
## Frame i sits at region.x + i * region.width (e.g. quarry hut forge = 4 ember frames).
@export var anim_frames: int = 1
## Chimney smoke over the building (for producing buildings like windmill/bakery/sawmill).
@export var has_smoke: bool = false
@export var max_capacity: int = 2
@export var build_time_seconds: float = 0.0
@export var is_player_placeable: bool = false
@export var build_cost_gold: float = 0.0
## M13/M14: build cost in goods (Goods.GoodType -> amount), e.g. {0: 20.0} = 20 wood
@export var build_cost: Dictionary = {}
@export var storage_capacity: Dictionary = {}

# Production configuration (M7)
## GoodType value of the produced good (-1 = not a production building)
@export var output_good: int = -1
## Amount produced per cycle
@export var output_amount: float = 1.0
## Seconds per production cycle (0 = not a production building)
@export var output_interval: float = 0.0
## Required input good (-1 = no input needed, e.g. sawmill needs wood)
@export var input_good: int = -1
## Amount of input good per cycle
@export var input_amount: float = 0.0
## How much an inhabitant can carry per transport trip
@export var carry_capacity: float = 1.0
