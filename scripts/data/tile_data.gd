class_name TileRuntimeData
extends RefCounted

enum TerrainType { GRASS, FOREST, STONE, WATER }
enum PathType { NONE, DESIRE_PATH, ROAD }
## M19: Wheat growth stages. A plant passes through three visible
## growth stages (STAGE_1 → STAGE_2 → STAGE_3) before it can be harvested.
## STAGE_3 is ripe for harvest; if not harvested it withers (DEAD) and
## then disappears again.
enum CropStage { NONE, STAGE_1, STAGE_2, STAGE_3, DEAD }

var terrain: TerrainType = TerrainType.GRASS
var path_type: PathType = PathType.NONE
var wear: float = 0.0
var resource_amount: float = 1.0
var building_id: int = -1
## Climate zone for the ground visuals: 0 = temperate (green meadow), 1 = steppe (dry grass).
var biome: int = 0

## M19: current wheat growth stage on this field (NONE = no wheat).
var crop_stage: CropStage = CropStage.NONE
## M19: time (sim seconds) spent in the current growth stage.
var crop_timer: float = 0.0
## M19: ID of the farm house this field belongs to (-1 = not farmland). Fields
## are exempt from path wear so farmers don't trample their own fields.
var crop_field_owner: int = -1

## M29: game day this forest cell was last hunted (-1 = never). After a cell is hunted
## (or merely worked), the loot chance is zero for HUNT_REPLENISH_DAYS days; this stops
## multiple hunters in the same forest from blocking each other. Only relevant for FOREST.
var last_hunted_day: int = -1
