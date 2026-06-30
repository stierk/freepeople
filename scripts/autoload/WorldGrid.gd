extends Node

signal path_type_changed(cell: Vector2i)
## M19: Feuert wenn sich der Weizenzustand einer Zelle ändert (Pflanzen, Wachsen,
## Ernten, Verdorren) – World.gd zeichnet die betroffene Zelle neu.
signal crop_changed(cell: Vector2i)
## Feuert wenn sich der Geländetyp einer Zelle ändert (gefällter/nachgewachsener
## Baum) – World.gd zeichnet die betroffene Zelle neu.
signal terrain_changed(cell: Vector2i)

const MAP_SIZE := Vector2i(64, 64)
const TILE_SIZE := 16

const SPEED_GRASS := 1.0
const SPEED_DESIRE_PATH := 1.4
const SPEED_ROAD := 1.8
const WEAR_THRESHOLD := 10.0
const WEAR_PER_STEP := 1.0
const WEAR_DECAY_PER_TICK := 0.02

const NEIGHBOR_OFFSETS: Array[Vector2i] = [Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 0), Vector2i(-1, 0)]
## M19: 8er-Nachbarschaft für Pflanz-Regeln (kein Weizen neben Gebäude/Weg).
const NEIGHBOR_OFFSETS_8: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
	Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1),
]

var tiles: Array = []
var astar := AStarGrid2D.new()
## M19: aktive Weizen-Zellen für effizientes Ticken (statt der ganzen Karte).
var crop_cells: Array[Vector2i] = []


func generate_terrain(world_seed: int) -> void:
	tiles = NoiseTerrainGenerator.generate(MAP_SIZE, world_seed)
	crop_cells.clear()


func setup_astar() -> void:
	astar.region = Rect2i(Vector2i.ZERO, MAP_SIZE)
	astar.cell_size = Vector2(TILE_SIZE, TILE_SIZE)
	astar.offset = Vector2(TILE_SIZE / 2.0, TILE_SIZE / 2.0)
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
	astar.default_compute_heuristic = AStarGrid2D.HEURISTIC_MANHATTAN
	astar.default_estimate_heuristic = AStarGrid2D.HEURISTIC_MANHATTAN
	astar.update()

	for y in range(MAP_SIZE.y):
		for x in range(MAP_SIZE.x):
			var cell := Vector2i(x, y)
			astar.set_point_solid(cell, get_tile(cell).terrain == TileRuntimeData.TerrainType.WATER)
			_update_astar_weight(cell)


func is_valid_cell(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < MAP_SIZE.x and cell.y < MAP_SIZE.y


func get_tile(cell: Vector2i) -> TileRuntimeData:
	return tiles[cell.y * MAP_SIZE.x + cell.x]


func is_walkable(cell: Vector2i) -> bool:
	return is_valid_cell(cell) and get_tile(cell).terrain != TileRuntimeData.TerrainType.WATER


func get_speed_multiplier(cell: Vector2i) -> float:
	match get_tile(cell).path_type:
		TileRuntimeData.PathType.ROAD:
			return SPEED_ROAD
		TileRuntimeData.PathType.DESIRE_PATH:
			return SPEED_DESIRE_PATH
		_:
			return SPEED_GRASS


func find_path(from_cell: Vector2i, to_cell: Vector2i) -> PackedVector2Array:
	var start := _resolve_walkable_target(from_cell)
	var target := _resolve_walkable_target(to_cell)
	if start == Vector2i(-1, -1) or target == Vector2i(-1, -1):
		return PackedVector2Array()
	return astar.get_point_path(start, target)


func find_path_cells(from_cell: Vector2i, to_cell: Vector2i) -> Array:
	var start := _resolve_walkable_target(from_cell)
	var target := _resolve_walkable_target(to_cell)
	if start == Vector2i(-1, -1) or target == Vector2i(-1, -1):
		return []
	return Array(astar.get_id_path(start, target))


func _resolve_walkable_target(cell: Vector2i) -> Vector2i:
	if is_valid_cell(cell) and not astar.is_point_solid(cell):
		return cell
	for dir in NEIGHBOR_OFFSETS:
		var n := cell + dir
		if is_valid_cell(n) and not astar.is_point_solid(n):
			return n
	return Vector2i(-1, -1)


func path_cost(from_cell: Vector2i, to_cell: Vector2i) -> float:
	var cells := find_path_cells(from_cell, to_cell)
	if cells.is_empty():
		return INF
	var cost := 0.0
	for cell in cells:
		cost += astar.get_point_weight_scale(cell)
	return cost


func register_step(cell: Vector2i) -> void:
	var tile := get_tile(cell)
	if tile.path_type == TileRuntimeData.PathType.ROAD:
		return
	# M19: Ackerfelder werden nicht zertrampelt – ein Bauer macht keinen Weg quer
	# durch sein eigenes Feld, sondern nur auf dem Weg zu anderen Gebäuden.
	if tile.crop_field_owner != -1:
		return
	tile.wear += WEAR_PER_STEP
	if tile.wear >= WEAR_THRESHOLD and tile.path_type == TileRuntimeData.PathType.NONE:
		tile.path_type = TileRuntimeData.PathType.DESIRE_PATH
		_update_astar_weight(cell)
		path_type_changed.emit(cell)


func decay_wear_tick() -> void:
	for y in range(MAP_SIZE.y):
		for x in range(MAP_SIZE.x):
			var cell := Vector2i(x, y)
			var tile := get_tile(cell)
			if tile.path_type == TileRuntimeData.PathType.ROAD or tile.wear <= 0.0:
				continue
			tile.wear = maxf(0.0, tile.wear - WEAR_DECAY_PER_TICK)
			if tile.wear < WEAR_THRESHOLD and tile.path_type == TileRuntimeData.PathType.DESIRE_PATH:
				tile.path_type = TileRuntimeData.PathType.NONE
				_update_astar_weight(cell)
				path_type_changed.emit(cell)


func set_building_footprint(cell: Vector2i, building_id: int, solid: bool) -> void:
	var tile := get_tile(cell)
	tile.building_id = building_id if solid else -1
	astar.set_point_solid(cell, solid)


## M11: Alle Zellen eines mehrzelligen Footprints (origin = oben links).
func get_footprint_cells(origin: Vector2i, size: Vector2i) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for y in range(size.y):
		for x in range(size.x):
			cells.append(origin + Vector2i(x, y))
	return cells


## M11: Prüft ob ein gesamter mehrzelliger Footprint bebaubar ist
## (alle Zellen gültig, begehbar und unbesetzt).
func is_footprint_buildable(origin: Vector2i, size: Vector2i) -> bool:
	for cell in get_footprint_cells(origin, size):
		if not is_walkable(cell):
			return false
		if get_tile(cell).building_id != -1:
			return false
	return true


## M11: set_building_footprint über alle Zellen eines mehrzelligen Footprints.
func set_building_footprint_rect(origin: Vector2i, size: Vector2i, building_id: int, solid: bool) -> void:
	for cell in get_footprint_cells(origin, size):
		set_building_footprint(cell, building_id, solid)


func world_to_cell(world_pos: Vector2) -> Vector2i:
	return Vector2i(floori(world_pos.x / TILE_SIZE), floori(world_pos.y / TILE_SIZE))


func cell_to_world(cell: Vector2i) -> Vector2:
	return Vector2(cell.x * TILE_SIZE + TILE_SIZE / 2.0, cell.y * TILE_SIZE + TILE_SIZE / 2.0)


func _update_astar_weight(cell: Vector2i) -> void:
	astar.set_point_weight_scale(cell, 1.0 / get_speed_multiplier(cell))


# ---------------------------------------------------------------------------
# M19: Weizen / Ackerbau
# ---------------------------------------------------------------------------

## Markiert begehbare Grasfelder rund um eine Bauernhütte als Ackerland dieser
## Hütte (crop_field_owner = building_id). Felder dürfen nicht auf dem Footprint
## und nicht direkt an einem Gebäude liegen.
func designate_farm_field(origin: Vector2i, size: Vector2i, building_id: int, radius: int) -> void:
	var min_x := origin.x - radius
	var max_x := origin.x + size.x - 1 + radius
	var min_y := origin.y - radius
	var max_y := origin.y + size.y - 1 + radius
	for y in range(min_y, max_y + 1):
		for x in range(min_x, max_x + 1):
			var cell := Vector2i(x, y)
			if not is_valid_cell(cell):
				continue
			var tile := get_tile(cell)
			if tile.terrain != TileRuntimeData.TerrainType.GRASS:
				continue
			if tile.building_id != -1 or tile.crop_field_owner != -1:
				continue
			if _has_adjacent_building(cell):
				continue
			tile.crop_field_owner = building_id


## Darf auf dieser Zelle Weizen gepflanzt werden? Nur auf leerem Gras, nicht auf
## einem Weg, nicht auf/neben einem Gebäude und nicht neben einem Weg.
func is_plantable(cell: Vector2i) -> bool:
	if not is_valid_cell(cell):
		return false
	var tile := get_tile(cell)
	if tile.terrain != TileRuntimeData.TerrainType.GRASS:
		return false
	if tile.path_type != TileRuntimeData.PathType.NONE:
		return false
	if tile.building_id != -1:
		return false
	if tile.crop_stage != TileRuntimeData.CropStage.NONE:
		return false
	for dir in NEIGHBOR_OFFSETS_8:
		var n := cell + dir
		if not is_valid_cell(n):
			continue
		var ntile := get_tile(n)
		if ntile.building_id != -1:
			return false
		if ntile.path_type != TileRuntimeData.PathType.NONE:
			return false
	return true


func _has_adjacent_building(cell: Vector2i) -> bool:
	for dir in NEIGHBOR_OFFSETS_8:
		var n := cell + dir
		if is_valid_cell(n) and get_tile(n).building_id != -1:
			return true
	return false


func plant_crop(cell: Vector2i, owner_id: int) -> void:
	var tile := get_tile(cell)
	tile.crop_stage = TileRuntimeData.CropStage.STAGE_1
	tile.crop_timer = 0.0
	if tile.crop_field_owner == -1:
		tile.crop_field_owner = owner_id
	if not crop_cells.has(cell):
		crop_cells.append(cell)
	crop_changed.emit(cell)


## Setzt eine Weizenzelle auf eine neue Stufe (Wachstum oder Verdorren).
func set_crop_stage(cell: Vector2i, stage: TileRuntimeData.CropStage) -> void:
	var tile := get_tile(cell)
	tile.crop_stage = stage
	tile.crop_timer = 0.0
	crop_changed.emit(cell)


## Entfernt den Weizen einer Zelle vollständig (nach Ernte oder Verfall).
func clear_crop(cell: Vector2i) -> void:
	var tile := get_tile(cell)
	tile.crop_stage = TileRuntimeData.CropStage.NONE
	tile.crop_timer = 0.0
	crop_cells.erase(cell)
	crop_changed.emit(cell)


## Fällt den Baum auf dieser Zelle: Wald → Gras, Ressource verschwindet. Die Zelle
## wird neu gezeichnet (terrain_changed) und steht später für Nachwachsen bereit.
func remove_tree(cell: Vector2i) -> void:
	var tile := get_tile(cell)
	tile.terrain = TileRuntimeData.TerrainType.GRASS
	tile.resource_amount = 0.0
	_update_astar_weight(cell)
	terrain_changed.emit(cell)


## Lässt auf einer freien Graszelle einen neuen Baum wachsen (Wald + volle Ressource).
func grow_tree(cell: Vector2i) -> void:
	var tile := get_tile(cell)
	tile.terrain = TileRuntimeData.TerrainType.FOREST
	tile.resource_amount = 1.0
	_update_astar_weight(cell)
	terrain_changed.emit(cell)


## Anzahl der 8 Nachbarzellen, die Wald sind (für exponentielles Baum-Nachwachsen).
func count_forest_neighbors(cell: Vector2i) -> int:
	var count := 0
	for dir in NEIGHBOR_OFFSETS_8:
		var n := cell + dir
		if is_valid_cell(n) and get_tile(n).terrain == TileRuntimeData.TerrainType.FOREST:
			count += 1
	return count


## M19: nach dem Laden eines Spielstands die Liste aktiver Weizen-Zellen neu aufbauen.
func rebuild_crop_cells() -> void:
	crop_cells.clear()
	for y in range(MAP_SIZE.y):
		for x in range(MAP_SIZE.x):
			var cell := Vector2i(x, y)
			if get_tile(cell).crop_stage != TileRuntimeData.CropStage.NONE:
				crop_cells.append(cell)
