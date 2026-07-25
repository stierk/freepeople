extends Node

signal path_type_changed(cell: Vector2i)
## M19: fires when a cell's wheat state changes (planting, growing,
## harvesting, withering) – World.gd redraws the affected cell.
signal crop_changed(cell: Vector2i)
## Fires when a cell's terrain type changes (felled/regrown
## tree) – World.gd redraws the affected cell.
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
## M19: 8-neighborhood for planting rules (no wheat next to a building/path).
const NEIGHBOR_OFFSETS_8: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
	Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1),
]

var tiles: Array = []
var astar := AStarGrid2D.new()
## M19: active wheat cells for efficient ticking (instead of the whole map).
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


## exempt = true: this step causes no wear – used for a farmer crossing their own field
## and (M32) for a woodcutter/hunter moving through forest, so they don't trample away the
## very forest they depend on. All others wear the cell down normally; if that turns it into
## a path, a field loses its status (including wheat) and a forest tile is destroyed.
func register_step(cell: Vector2i, exempt: bool = false) -> void:
	var tile := get_tile(cell)
	if tile.path_type == TileRuntimeData.PathType.ROAD:
		return
	if exempt:
		return
	tile.wear += WEAR_PER_STEP
	if tile.wear >= WEAR_THRESHOLD and tile.path_type == TileRuntimeData.PathType.NONE:
		tile.path_type = TileRuntimeData.PathType.DESIRE_PATH
		# A field trodden too often becomes a trampled path and is then no longer farmland.
		if tile.crop_field_owner != -1:
			tile.crop_field_owner = -1
			if tile.crop_stage != TileRuntimeData.CropStage.NONE:
				clear_crop(cell)
		# M32: a path worn across forest tramples the tree away – the cell turns to plain
		# grass and is no longer forest (not huntable/harvestable anymore).
		if tile.terrain == TileRuntimeData.TerrainType.FOREST:
			tile.terrain = TileRuntimeData.TerrainType.GRASS
			tile.resource_amount = 0.0
			terrain_changed.emit(cell)
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


## M11: all cells of a multi-cell footprint (origin = top-left).
func get_footprint_cells(origin: Vector2i, size: Vector2i) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for y in range(size.y):
		for x in range(size.x):
			cells.append(origin + Vector2i(x, y))
	return cells


## M11: checks whether an entire multi-cell footprint is buildable
## (all cells valid, walkable, and unoccupied).
func is_footprint_buildable(origin: Vector2i, size: Vector2i) -> bool:
	for cell in get_footprint_cells(origin, size):
		if not is_walkable(cell):
			return false
		if get_tile(cell).building_id != -1:
			return false
	return true


## M11: set_building_footprint over all cells of a multi-cell footprint.
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
# M19: wheat / farming
# ---------------------------------------------------------------------------

## Marks grass cells around a farm house as this hut's farmland
## (crop_field_owner = building_id) – including cells directly adjacent to the house.
## Only excluded are non-grass (forest/stone/water), paths, and cells
## already occupied by a building or another field.
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
			if tile.path_type != TileRuntimeData.PathType.NONE:
				continue
			if tile.building_id != -1 or tile.crop_field_owner != -1:
				continue
			tile.crop_field_owner = building_id


## May wheat be planted on this cell? Allowed directly next to the owner's own
## house – only blocked if the cell itself isn't free grass: path, forest/stone
## (not grass), a building, or already planted.
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


## Sets a wheat cell to a new stage (growth or withering).
func set_crop_stage(cell: Vector2i, stage: TileRuntimeData.CropStage) -> void:
	var tile := get_tile(cell)
	tile.crop_stage = stage
	tile.crop_timer = 0.0
	crop_changed.emit(cell)


## Fully removes the wheat from a cell (after harvest or decay).
func clear_crop(cell: Vector2i) -> void:
	var tile := get_tile(cell)
	tile.crop_stage = TileRuntimeData.CropStage.NONE
	tile.crop_timer = 0.0
	crop_cells.erase(cell)
	crop_changed.emit(cell)


## Fells the tree on this cell: forest → grass, resource disappears. The cell
## is redrawn (terrain_changed) and becomes available for regrowth later.
func remove_tree(cell: Vector2i) -> void:
	var tile := get_tile(cell)
	tile.terrain = TileRuntimeData.TerrainType.GRASS
	tile.resource_amount = 0.0
	_update_astar_weight(cell)
	terrain_changed.emit(cell)


## Grows a new tree on a free grass cell (forest + full resource).
func grow_tree(cell: Vector2i) -> void:
	var tile := get_tile(cell)
	tile.terrain = TileRuntimeData.TerrainType.FOREST
	tile.resource_amount = 1.0
	_update_astar_weight(cell)
	terrain_changed.emit(cell)


## Number of the 8 neighbor cells that are forest (for exponential tree regrowth).
func count_forest_neighbors(cell: Vector2i) -> int:
	var count := 0
	for dir in NEIGHBOR_OFFSETS_8:
		var n := cell + dir
		if is_valid_cell(n) and get_tile(n).terrain == TileRuntimeData.TerrainType.FOREST:
			count += 1
	return count


## M29: is there any forest left on the map at all? Early-exits on the first hit –
## used for profession choice (only recruit a hunter if there's forest to hunt).
func has_forest() -> bool:
	for tile in tiles:
		if tile.terrain == TileRuntimeData.TerrainType.FOREST:
			return true
	return false


## M19: after loading a save game, rebuild the list of active wheat cells.
func rebuild_crop_cells() -> void:
	crop_cells.clear()
	for y in range(MAP_SIZE.y):
		for x in range(MAP_SIZE.x):
			var cell := Vector2i(x, y)
			if get_tile(cell).crop_stage != TileRuntimeData.CropStage.NONE:
				crop_cells.append(cell)
