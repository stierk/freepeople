class_name TileRuntimeData
extends RefCounted

enum TerrainType { GRASS, FOREST, STONE, WATER }
enum PathType { NONE, DESIRE_PATH, ROAD }
## M19: Wachstumsstufen von Weizen. Eine Pflanze durchläuft drei sichtbare
## Wachstumsstufen (STAGE_1 → STAGE_2 → STAGE_3), bevor sie geerntet werden kann.
## STAGE_3 ist erntereif; wird sie nicht geerntet, verdorrt sie (DEAD) und
## verschwindet danach wieder.
enum CropStage { NONE, STAGE_1, STAGE_2, STAGE_3, DEAD }

var terrain: TerrainType = TerrainType.GRASS
var path_type: PathType = PathType.NONE
var wear: float = 0.0
var resource_amount: float = 1.0
var building_id: int = -1

## M19: aktuelle Weizen-Wachstumsstufe auf diesem Feld (NONE = kein Weizen).
var crop_stage: CropStage = CropStage.NONE
## M19: Zeit (Sim-Sekunden) in der aktuellen Wachstumsstufe.
var crop_timer: float = 0.0
## M19: ID der Bauernhütte, der dieses Feld gehört (-1 = kein Ackerland). Felder
## sind vom Wegverschleiß ausgenommen, damit Bauern ihre Felder nicht zertrampeln.
var crop_field_owner: int = -1
