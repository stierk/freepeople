class_name SiteSelection
extends RefCounted

const SITE_SAMPLE_COUNT := 10
const CANDIDATE_RADIUS := 3
const NEAREST_RESOURCE_PREFILTER := 5

## M14/M15: minimum number of free grass cells around a farm house for crop plots.
const CROP_PLOT_MIN_CLEAR := 4

const NEIGHBOR_DIRS: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]

const ALPHA := {
	InhabitantData.Profession.WOODCUTTER: 1.0,
	InhabitantData.Profession.SAWMILL_WORKER: 0.3,
	InhabitantData.Profession.QUARRY_WORKER: 1.0,
	InhabitantData.Profession.FARMER: 1.0,
	InhabitantData.Profession.MILLER: 0.3,
	InhabitantData.Profession.BAKER: 0.3,
	InhabitantData.Profession.HUNTER: 1.0,  # M29: proximity to forest counts heavily (like woodcutter)
}
const BETA := {
	InhabitantData.Profession.WOODCUTTER: 0.7,
	InhabitantData.Profession.SAWMILL_WORKER: 1.2,
	InhabitantData.Profession.QUARRY_WORKER: 0.7,
	InhabitantData.Profession.FARMER: 0.7,
	InhabitantData.Profession.MILLER: 1.2,
	InhabitantData.Profession.BAKER: 1.2,
	InhabitantData.Profession.HUNTER: 0.7,  # M29: distance to the granary counts (like woodcutter)
}

var world_grid
var building_manager


func _init(p_world_grid, p_building_manager) -> void:
	world_grid = p_world_grid
	building_manager = p_building_manager


## M14: accounts for the respective hut's multi-cell footprint as well as
## (for farmers) free crop cells around the hut.
func find_best_site(profession: InhabitantData.Profession) -> Vector2i:
	return find_best_site_scored(profession)["cell"]


## Like find_best_site, but additionally returns the best site's score, so a
## new build can be weighed against reusing an existing hut (M23).
## {"cell": Vector2i(-1,-1), "score": -INF} if no site was found.
func find_best_site_scored(profession: InhabitantData.Profession) -> Dictionary:
	var resource_cells := _get_relevant_resource_cells(profession)
	var storage := _get_relevant_storage(profession)
	if storage == null or resource_cells.is_empty():
		return {"cell": Vector2i(-1, -1), "score": -INF}

	var footprint_size := _get_footprint_size(profession)

	var best_cell := Vector2i(-1, -1)
	var best_score := -INF

	for cell in _sample_candidate_cells(resource_cells):
		if not world_grid.is_footprint_buildable(cell, footprint_size):
			continue
		if profession == InhabitantData.Profession.FARMER \
				and not _has_clear_crop_plots(cell, footprint_size):
			continue

		# Perf: site scoring via cheap Manhattan distances instead of A* path costs.
		# The earlier path-based computation (~60 A* runs per call) was by far the biggest
		# simulation bottleneck (st_SEEKING_SITE ≈ 0.6 s/frame). is_footprint_buildable
		# already filters out unbuildable cells; the exact pathfinding is later handled by the
		# inhabitant while walking there.
		var score := _score_cell(cell, profession, resource_cells, storage)
		if score > best_score:
			best_score = score
			best_cell = cell

	return {"cell": best_cell, "score": best_score}


## Scores a specific site for a profession (higher = better); same metric as in
## find_best_site_scored. -INF if the profession has no viable site there (no
## resource/no responsible storage). For the new-build-vs-reuse weighing (M23).
func score_site(profession: InhabitantData.Profession, cell: Vector2i) -> float:
	var resource_cells := _get_relevant_resource_cells(profession)
	var storage := _get_relevant_storage(profession)
	if storage == null or resource_cells.is_empty():
		return -INF
	return _score_cell(cell, profession, resource_cells, storage)


func _score_cell(cell: Vector2i, profession: InhabitantData.Profession, resource_cells: Array, storage: BuildingInstance) -> float:
	var dist_resource := _nearest_resource_dist(cell, resource_cells)
	var dist_storage: float
	if profession == InhabitantData.Profession.MILLER or profession == InhabitantData.Profession.BAKER:
		# For miller/baker, input and output storage are the same granary, and there may be
		# several. Count distance to the nearest granary (= resource), otherwise a site near a
		# second granary would be measured against the (fixed) first one and lose out.
		dist_storage = dist_resource
	else:
		dist_storage = float(absi(cell.x - storage.cell.x) + absi(cell.y - storage.cell.y))
	return -ALPHA[profession] * dist_resource - BETA[profession] * dist_storage


func _get_footprint_size(profession: InhabitantData.Profession) -> Vector2i:
	var building_type: BuildingDef.BuildingType = building_manager.PROFESSION_TO_BUILDING_TYPE[profession]
	return building_manager.get_building_def(building_type).footprint_size


## M14/M15: checks whether there are enough free grass cells around the footprint for crop plots.
func _has_clear_crop_plots(origin: Vector2i, size: Vector2i) -> bool:
	var clear_count := 0
	for y in range(-1, size.y + 1):
		for x in range(-1, size.x + 1):
			if x >= 0 and x < size.x and y >= 0 and y < size.y:
				continue
			var cell := origin + Vector2i(x, y)
			if not world_grid.is_valid_cell(cell):
				continue
			var tile = world_grid.get_tile(cell)
			if tile.terrain == TileRuntimeData.TerrainType.GRASS and tile.building_id == -1:
				clear_count += 1
	return clear_count >= CROP_PLOT_MIN_CLEAR


func _get_relevant_resource_cells(profession: InhabitantData.Profession) -> Array:
	match profession:
		InhabitantData.Profession.WOODCUTTER, InhabitantData.Profession.HUNTER:
			# M29: the hunter settles near forest like the woodcutter (hunts prey there instead of wood).
			return _cells_with_resource(TileRuntimeData.TerrainType.FOREST)
		InhabitantData.Profession.QUARRY_WORKER:
			return _cells_with_resource(TileRuntimeData.TerrainType.STONE)
		InhabitantData.Profession.FARMER:
			return _farmland_cells()
		InhabitantData.Profession.SAWMILL_WORKER:
			# As long as no real storage yard stands, don't search for a site –
			# otherwise the Town Hall fallback would cause sawmills to be
			# built around the Town Hall.
			if not building_manager.has_storage_yard():
				return []
			var storage = building_manager.get_storage_yard()
			return [storage.cell] if storage != null else []
		InhabitantData.Profession.MILLER, InhabitantData.Profession.BAKER:
			# Miller/baker are built at a granary (that's where their input/output good sits).
			# Allow every granary, so food production can be spread across multiple
			# granaries instead of getting stuck on the one (full) cell.
			var cells: Array = []
			for g in building_manager.get_buildings_by_type(BuildingDef.BuildingType.GRANARY):
				cells.append(g.cell)
			if cells.is_empty():
				# Early game without a real granary: the Town Hall serves as a fallback granary.
				var fallback = building_manager.get_granary()
				if fallback != null:
					cells.append(fallback.cell)
			return cells
		_:
			return []


func _get_relevant_storage(profession: InhabitantData.Profession) -> BuildingInstance:
	if profession == InhabitantData.Profession.FARMER \
			or profession == InhabitantData.Profession.MILLER \
			or profession == InhabitantData.Profession.BAKER \
			or profession == InhabitantData.Profession.HUNTER:  # M29: loot (FOOD) goes to the granary
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


## Cheapest Manhattan distance from `cell` to the nearest resource cell (no A* paths).
## Replaces the earlier path-based variant, which cost ~60 A* runs per site search.
func _nearest_resource_dist(cell: Vector2i, resource_cells: Array) -> float:
	var best := INF
	for rc: Vector2i in resource_cells:
		var dist := float(absi(rc.x - cell.x) + absi(rc.y - cell.y))
		if dist < best:
			best = dist
	return best
