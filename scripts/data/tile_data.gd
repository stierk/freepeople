class_name TileRuntimeData
extends RefCounted

enum TerrainType { GRASS, FOREST, STONE, WATER }
enum PathType { NONE, DESIRE_PATH, ROAD }

var terrain: TerrainType = TerrainType.GRASS
var path_type: PathType = PathType.NONE
var wear: float = 0.0
var resource_amount: float = 1.0
var building_id: int = -1
