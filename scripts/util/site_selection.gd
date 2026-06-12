class_name SiteSelection
extends RefCounted

const SITE_SAMPLE_COUNT := 10
const CANDIDATE_RADIUS := 3
const NEAREST_RESOURCE_PREFILTER := 5

const NEIGHBOR_DIRS: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]

const ALPHA := {
	InhabitantData.Profession.WOODCUTTER: 1.0,
	InhabitantData.Profession.SAWMILL_WORKER: 0.3,
	InhabitantData.Profession.QUARRY_WORKER: 1.0,
	InhabitantData.Profession.FARMER: 1.0,
}
const BETA := {
	InhabitantData.Profession.WOODCUTTER: 0.7,
	InhabitantData.Profession.SAWMILL_WORKER: 1.2,
	InhabitantData.Profession.QUARRY_WORKER: 0.7,
	InhabitantData.Profession.FARMER: 0.7,
}

var world_grid
var building_manager


func _init(p_world_grid, p_building_manager) -> void:
	world_grid = p_world_grid
	building_manager = p_building_manager


func find_best_site(profession: InhabitantData.Profession) -> Vector2i:
	var resource_cells := _get_relevant_resource_cells(profession)
	var storage := _get_relevant_storage(profession)
	if storage == null or resource_cells.is_empty():
		return Vector2i(-1, -1)

	var alpha: float = ALPHA[profession]
	var beta: float = BETA[profession]

	var best_cell := Vector2i(-1, -1)
	var best_score := -INF

	for cell in _sample_candidate_cells(resource_cells):
		if not world_grid.is_walkable(cell) or world_grid.get_tile(cell).building_id != -1:
			continue

		var dist_resource := _nearest_resource_path_cost(cell, resource_cells)
		var dist_storage: float = world_grid.path_cost(cell, storage.cell)
		if dist_resource == INF or dist_storage == INF:
			continue

		var score := -alpha * dist_resource - beta * dist_storage
		if score > best_score:
			best_score = score
			best_cell = cell

	return best_cell


func _get_relevant_resource_cells(profession: InhabitantData.Profession) -> Array:
	match profession:
		InhabitantData.Profession.WOODCUTTER:
			return _cells_with_resource(TileRuntimeData.TerrainType.FOREST)
		InhabitantData.Profession.QUARRY_WORKER:
			return _cells_with_resource(TileRuntimeData.TerrainType.STONE)
		InhabitantData.Profession.FARMER:
			return _farmland_cells()
		InhabitantData.Profession.SAWMILL_WORKER:
			var storage = building_manager.get_storage_yard()
			return [storage.cell] if storage != null else []
		_:
			return []


func _get_relevant_storage(profession: InhabitantData.Profession) -> BuildingInstance:
	if profession == InhabitantData.Profession.FARMER:
		return building_manager.get_granary()
	return building_manager.get_storage_yard()


func _cells_with_resource(terrain: TileRuntimeData.TerrainType) -> Array:
	var cells: Array = []
	var map_size: Vector2i = world_grid.MAP_SIZE
	for y in range(map_size.y):
		for x in range(map_size.x):
			var cell := Vector2i(x, y)
			var tile = world_grid.get_tile(cell)
			if tile.terrain == terrain and tile.resource_amount > 0.0:
				cells.append(cell)
	return cells


func _farmland_cells() -> Array:
	var cells: Array = []
	var map_size: Vector2i = world_grid.MAP_SIZE
	for y in range(map_size.y):
		for x in range(map_size.x):
			var cell := Vector2i(x, y)
			if world_grid.get_tile(cell).terrain != TileRuntimeData.TerrainType.GRASS:
				continue
			if _is_adjacent_to(cell, TileRuntimeData.TerrainType.FOREST) \
					or _is_adjacent_to(cell, TileRuntimeData.TerrainType.STONE) \
					or _is_adjacent_to(cell, TileRuntimeData.TerrainType.WATER):
				continue
			cells.append(cell)
	return cells


func _is_adjacent_to(cell: Vector2i, terrain: TileRuntimeData.TerrainType) -> bool:
	for dir in NEIGHBOR_DIRS:
		var n: Vector2i = cell + dir
		if world_grid.is_valid_cell(n) and world_grid.get_tile(n).terrain == terrain:
			return true
	return false


func _sample_candidate_cells(resource_cells: Array) -> Array:
	var candidates: Array = []
	for i in range(SITE_SAMPLE_COUNT):
		var origin: Vector2i = resource_cells[randi() % resource_cells.size()]
		var candidate := origin + Vector2i(
			randi_range(-CANDIDATE_RADIUS, CANDIDATE_RADIUS),
			randi_range(-CANDIDATE_RADIUS, CANDIDATE_RADIUS)
		)
		if world_grid.is_valid_cell(candidate):
			candidates.append(candidate)
	return candidates


func _nearest_resource_path_cost(cell: Vector2i, resource_cells: Array) -> float:
	var sorted_cells := resource_cells.duplicate()
	sorted_cells.sort_custom(func(a, b):
		var diff_a: Vector2i = a - cell
		var diff_b: Vector2i = b - cell
		var da := diff_a.x * diff_a.x + diff_a.y * diff_a.y
		var db := diff_b.x * diff_b.x + diff_b.y * diff_b.y
		return da < db
	)

	var best_cost := INF
	for i in range(mini(NEAREST_RESOURCE_PREFILTER, sorted_cells.size())):
		var cost: float = world_grid.path_cost(cell, sorted_cells[i])
		if cost < best_cost:
			best_cost = cost
	return best_cost
