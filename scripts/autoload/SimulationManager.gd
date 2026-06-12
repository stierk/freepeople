extends Node

enum SpeedMode { PAUSED, NORMAL, FAST, FASTEST }
const SPEED_MULTIPLIERS := {
	SpeedMode.PAUSED: 0.0,
	SpeedMode.NORMAL: 1.0,
	SpeedMode.FAST: 2.0,
	SpeedMode.FASTEST: 3.0,
}

const PRODUCTION_TIME := 12.0
const HARVEST_AMOUNT := 1.0
const PRODUCTION_RETRY_DELAY := 1.0
const RESOURCE_DEPLETION_PER_HARVEST := 0.1
const RESOURCE_SEARCH_RADIUS := 6

const RESOURCE_REGEN_INTERVAL := 5.0
const RESOURCE_REGEN_AMOUNT := 0.05
const RESOURCE_REGEN_CHANCE := 0.3

const PROFESSION_TO_GOOD := {
	InhabitantData.Profession.WOODCUTTER: Goods.GoodType.WOOD,
	InhabitantData.Profession.SAWMILL_WORKER: Goods.GoodType.PLANKS,
	InhabitantData.Profession.QUARRY_WORKER: Goods.GoodType.STONE,
	InhabitantData.Profession.FARMER: Goods.GoodType.FOOD,
}

const PROFESSION_TO_RESOURCE_TERRAIN := {
	InhabitantData.Profession.WOODCUTTER: TileRuntimeData.TerrainType.FOREST,
	InhabitantData.Profession.QUARRY_WORKER: TileRuntimeData.TerrainType.STONE,
}

var speed_mode: SpeedMode = SpeedMode.NORMAL
var sim_time: float = 0.0

var _resource_regen_accum: float = 0.0


func _process(delta: float) -> void:
	var mult: float = SPEED_MULTIPLIERS[speed_mode]
	if mult == 0.0:
		return
	var sim_delta := delta * mult
	sim_time += sim_delta

	for inhabitant in GameState.inhabitants:
		_process_movement(inhabitant, sim_delta)

	for inhabitant in GameState.inhabitants:
		_process_inhabitant_state(inhabitant, sim_delta)

	_resource_regen_accum += sim_delta
	if _resource_regen_accum >= RESOURCE_REGEN_INTERVAL:
		_resource_regen_accum -= RESOURCE_REGEN_INTERVAL
		_regenerate_resources()


func _process_movement(inhabitant: InhabitantData, delta: float) -> void:
	if inhabitant.path.is_empty() or inhabitant.path_index >= inhabitant.path.size():
		return

	var target: Vector2 = inhabitant.path[inhabitant.path_index]
	var speed_mult := WorldGrid.get_speed_multiplier(inhabitant.cell)
	var speed := inhabitant.move_speed_base * speed_mult
	var to_target := target - inhabitant.world_pos
	var step := speed * delta

	if to_target.length() <= step:
		inhabitant.world_pos = target
		inhabitant.path_index += 1
		var new_cell := WorldGrid.world_to_cell(inhabitant.world_pos)
		if new_cell != inhabitant.cell:
			inhabitant.cell = new_cell
			WorldGrid.register_step(new_cell)
	else:
		inhabitant.world_pos += to_target.normalized() * step

	if inhabitant.node_ref:
		inhabitant.node_ref.position = inhabitant.world_pos


func _process_inhabitant_state(inhabitant: InhabitantData, delta: float) -> void:
	match inhabitant.state:
		InhabitantData.State.SEEKING_SITE:
			_handle_seeking_site(inhabitant)
		InhabitantData.State.MOVING_TO_BUILD:
			_handle_moving_to_build(inhabitant)
		InhabitantData.State.BUILDING:
			_handle_building(inhabitant, delta)
		InhabitantData.State.WORKING:
			_handle_working(inhabitant, delta)
		InhabitantData.State.DELIVERING:
			_handle_delivering(inhabitant)
		InhabitantData.State.RETURNING:
			_handle_returning(inhabitant)
		_:
			pass


func _handle_seeking_site(inhabitant: InhabitantData) -> void:
	if inhabitant.profession == InhabitantData.Profession.NONE:
		inhabitant.profession = EconomyManager.assign_profession_for_new_inhabitant()

	var existing_hut := BuildingManager.get_understaffed_hut(inhabitant.profession)
	if existing_hut != null:
		existing_hut.occupants.append(inhabitant.id)
		inhabitant.home_building_id = existing_hut.id
		inhabitant.path = WorldGrid.find_path(inhabitant.cell, existing_hut.cell)
		inhabitant.path_index = 0
		inhabitant.state = InhabitantData.State.MOVING_TO_BUILD
		return

	var site := SiteSelection.new(WorldGrid, BuildingManager).find_best_site(inhabitant.profession)
	if site == Vector2i(-1, -1):
		return

	inhabitant.target_site_cell = site
	inhabitant.path = WorldGrid.find_path(inhabitant.cell, site)
	inhabitant.path_index = 0
	inhabitant.state = InhabitantData.State.MOVING_TO_BUILD


func _handle_moving_to_build(inhabitant: InhabitantData) -> void:
	if not inhabitant.path.is_empty() and inhabitant.path_index < inhabitant.path.size():
		return

	var home := BuildingManager.get_building(inhabitant.home_building_id)
	if home != null and home.is_constructed:
		inhabitant.production_timer = PRODUCTION_TIME
		inhabitant.state = InhabitantData.State.WORKING
		return

	var building_type: BuildingDef.BuildingType = BuildingManager.PROFESSION_TO_BUILDING_TYPE[inhabitant.profession]
	var def := BuildingManager.get_building_def(building_type)
	var hut := BuildingManager.register_building(def, inhabitant.target_site_cell)
	hut.is_constructed = false
	hut.occupants.append(inhabitant.id)
	inhabitant.home_building_id = hut.id
	WorldGrid.set_building_footprint(hut.cell, hut.id, true)
	hut.construction_timer = def.build_time_seconds
	inhabitant.state = InhabitantData.State.BUILDING


func _handle_building(inhabitant: InhabitantData, delta: float) -> void:
	var hut := BuildingManager.get_building(inhabitant.home_building_id)
	if hut.is_constructed:
		inhabitant.state = InhabitantData.State.WORKING
		return

	hut.construction_timer -= delta
	if hut.construction_timer <= 0.0:
		hut.is_constructed = true
		BuildingManager.building_constructed.emit(hut.id)
		inhabitant.production_timer = PRODUCTION_TIME
		inhabitant.state = InhabitantData.State.WORKING


func _handle_working(inhabitant: InhabitantData, delta: float) -> void:
	inhabitant.production_timer -= delta
	if inhabitant.production_timer > 0.0:
		return

	match inhabitant.profession:
		InhabitantData.Profession.SAWMILL_WORKER:
			_produce_sawmill(inhabitant)
		InhabitantData.Profession.FARMER:
			_produce_simple(inhabitant, Goods.GoodType.FOOD, BuildingManager.get_granary())
		_:
			_produce_from_terrain(inhabitant)


func _produce_from_terrain(inhabitant: InhabitantData) -> void:
	var terrain: TileRuntimeData.TerrainType = PROFESSION_TO_RESOURCE_TERRAIN[inhabitant.profession]
	var hut := BuildingManager.get_building(inhabitant.home_building_id)
	var resource_cell := _find_resource_cell_near(hut.cell, terrain)
	if resource_cell == Vector2i(-1, -1):
		inhabitant.production_timer = PRODUCTION_RETRY_DELAY
		return

	var tile := WorldGrid.get_tile(resource_cell)
	tile.resource_amount = maxf(0.0, tile.resource_amount - RESOURCE_DEPLETION_PER_HARVEST)

	_produce_simple(inhabitant, PROFESSION_TO_GOOD[inhabitant.profession], BuildingManager.get_storage_yard())


func _produce_sawmill(inhabitant: InhabitantData) -> void:
	var storage := BuildingManager.get_storage_yard()
	var available: float = storage.community_stock.get(Goods.GoodType.WOOD, 0.0)
	if available < HARVEST_AMOUNT:
		inhabitant.production_timer = PRODUCTION_RETRY_DELAY
		return

	storage.withdraw_community(Goods.GoodType.WOOD, HARVEST_AMOUNT)
	_produce_simple(inhabitant, Goods.GoodType.PLANKS, storage)


func _produce_simple(inhabitant: InhabitantData, good: int, target: BuildingInstance) -> void:
	inhabitant.inventory[good] = inhabitant.inventory.get(good, 0.0) + HARVEST_AMOUNT
	inhabitant.path = WorldGrid.find_path(inhabitant.cell, target.cell)
	inhabitant.path_index = 0
	inhabitant.state = InhabitantData.State.DELIVERING


func _find_resource_cell_near(origin: Vector2i, terrain: TileRuntimeData.TerrainType) -> Vector2i:
	var best := Vector2i(-1, -1)
	var best_dist := INF

	for dy in range(-RESOURCE_SEARCH_RADIUS, RESOURCE_SEARCH_RADIUS + 1):
		for dx in range(-RESOURCE_SEARCH_RADIUS, RESOURCE_SEARCH_RADIUS + 1):
			var cell := origin + Vector2i(dx, dy)
			if not WorldGrid.is_valid_cell(cell):
				continue
			var tile := WorldGrid.get_tile(cell)
			if tile.terrain != terrain or tile.resource_amount <= 0.0:
				continue
			var dist := dx * dx + dy * dy
			if dist < best_dist:
				best_dist = dist
				best = cell

	return best


func _handle_delivering(inhabitant: InhabitantData) -> void:
	if not inhabitant.path.is_empty() and inhabitant.path_index < inhabitant.path.size():
		return

	var good: int = PROFESSION_TO_GOOD[inhabitant.profession]
	var amount: float = inhabitant.inventory.get(good, 0.0)
	var target := _get_delivery_target(inhabitant.profession)
	target.deliver(good, amount)
	inhabitant.inventory[good] = 0.0

	var hut := BuildingManager.get_building(inhabitant.home_building_id)
	inhabitant.path = WorldGrid.find_path(inhabitant.cell, hut.cell)
	inhabitant.path_index = 0
	inhabitant.state = InhabitantData.State.RETURNING


func _handle_returning(inhabitant: InhabitantData) -> void:
	if not inhabitant.path.is_empty() and inhabitant.path_index < inhabitant.path.size():
		return

	inhabitant.production_timer = PRODUCTION_TIME
	inhabitant.state = InhabitantData.State.WORKING


func _get_delivery_target(profession: InhabitantData.Profession) -> BuildingInstance:
	if profession == InhabitantData.Profession.FARMER:
		return BuildingManager.get_granary()
	return BuildingManager.get_storage_yard()


func _regenerate_resources() -> void:
	for y in range(WorldGrid.MAP_SIZE.y):
		for x in range(WorldGrid.MAP_SIZE.x):
			var cell := Vector2i(x, y)
			var tile := WorldGrid.get_tile(cell)
			if tile.terrain != TileRuntimeData.TerrainType.FOREST and tile.terrain != TileRuntimeData.TerrainType.STONE:
				continue
			if tile.resource_amount >= 1.0:
				continue
			if randf() < RESOURCE_REGEN_CHANCE:
				tile.resource_amount = minf(1.0, tile.resource_amount + RESOURCE_REGEN_AMOUNT)
