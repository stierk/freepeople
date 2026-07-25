## SaveLoadManager – M10
## Persists the entire game state (world, buildings, inhabitants, crown) as JSON
## under user://savegame.json. World.gd reacts to the game_loaded signal and
## rebuilds the visuals (tile/building/inhabitant nodes).
extends Node

signal game_loaded
signal game_saved

const SAVE_PATH := "user://savegame.json"
const SAVE_VERSION := 1
const AUTO_SAVE_INTERVAL := 60.0


func _ready() -> void:
	var timer := Timer.new()
	timer.wait_time = AUTO_SAVE_INTERVAL
	timer.autostart = true
	timer.timeout.connect(save_game)
	add_child(timer)
	print("[M10:AutoSave] Auto-save enabled (every %ds)." % AUTO_SAVE_INTERVAL)


func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)


## M18: fully resets the game (delete save game, reset all managers,
## reload the scene). Used by the restart button in the HUD and
## GameOverPanel.
func restart_game() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(SAVE_PATH)

	GlobalInventory.reset_state()
	GameState.reset_state()
	BuildingManager.reset_state()
	SimulationManager.reset_state()
	# Fresh recording files for the new run (the previous run gets flushed).
	RunRecorder.start_new_run()

	get_tree().reload_current_scene()


# ---------------------------------------------------------------------------
# Saving
# ---------------------------------------------------------------------------
func save_game() -> void:
	var data := {
		"version": SAVE_VERSION,
		"sim_time": SimulationManager.sim_time,
		"speed_mode": SimulationManager.speed_mode,
		"gold": GlobalInventory.gold,
		"next_building_id": BuildingManager.get_next_id(),
		"next_inhabitant_id": GameState.get_next_inhabitant_id(),
		"tiles": _serialize_tiles(),
		"buildings": _serialize_buildings(),
		"inhabitants": _serialize_inhabitants(),
	}

	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_error("SaveLoadManager: could not open save file (%s)" % SAVE_PATH)
		return
	file.store_string(JSON.stringify(data))
	file.close()
	print("[M10:Save] Game saved (%s)" % SAVE_PATH)
	game_saved.emit()


func _serialize_tiles() -> Array:
	var result: Array = []
	result.resize(WorldGrid.tiles.size())
	for i in range(WorldGrid.tiles.size()):
		var tile: TileRuntimeData = WorldGrid.tiles[i]
		# M19: also save wheat fields (stage, timer, owner).
		# M29: last_hunted_day appended at the end (backward compatible, see _deserialize_tiles).
		result[i] = [tile.terrain, tile.path_type, tile.wear, tile.resource_amount,
			tile.crop_stage, tile.crop_timer, tile.crop_field_owner, tile.biome,
			tile.last_hunted_day]
	return result


func _serialize_buildings() -> Array:
	var result: Array = []
	for b: BuildingInstance in BuildingManager.buildings:
		var entry := {
			"id": b.id,
			"type": b.def.type,
			"cell": [b.cell.x, b.cell.y],
			"is_constructed": b.is_constructed,
			"construction_timer": b.construction_timer,
			"production_timer": b.production_timer,
			"community_stock": _stringify_keys(b.community_stock),
			"output_stock": _stringify_keys(b.output_stock),
			"occupants": b.occupants.duplicate(),
			"last_repaired_day": b.last_repaired_day,
			"needs_repair": b.needs_repair,
			"is_derelict": b.is_derelict,
			"pending_build_cost": _stringify_keys(b.pending_build_cost),
		}
		if b.market_data != null:
			entry["market_data"] = {
				"prices": _stringify_keys(b.market_data.prices),
				"demand_counter": _stringify_keys(b.market_data.demand_counter),
				"supply_counter": _stringify_keys(b.market_data.supply_counter),
			}
		if b.trade_data != null:
			entry["trade_data"] = {
				"buy_price": _stringify_keys(b.trade_data.buy_price),
				"sell_price": _stringify_keys(b.trade_data.sell_price),
				"daily_tax": b.trade_data.daily_tax,
			}
		# M20: Town Hall policy (subsidy/tariff, basic income). Open exchange orders
		# are deliberately not persisted (like paths – rebuilt during play).
		if b.policy != null:
			entry["policy"] = {
				"subsidy": _stringify_keys(b.policy.subsidy),
				"basic_income": b.policy.basic_income,
			}
		result.append(entry)
	return result


func _serialize_inhabitants() -> Array:
	var result: Array = []
	for inh: InhabitantData in GameState.inhabitants:
		result.append({
			"id": inh.id,
			"profession": inh.profession,
			"home_building_id": inh.home_building_id,
			"cell": [inh.cell.x, inh.cell.y],
			"world_pos": [inh.world_pos.x, inh.world_pos.y],
			"inventory": _stringify_keys(inh.inventory),
			"gold": inh.gold,
			"hunger": inh.hunger,
			"missed_meals": inh.missed_meals,
			"production_timer": inh.production_timer,
			"margin": inh.margin,
			"last_sale_unit_price": inh.last_sale_unit_price,
			"last_food_unit_price": inh.last_food_unit_price,
			"time_since_last_sale": inh.time_since_last_sale,
			"unprofitable_streak": inh.unprofitable_streak,
			# M28: evolutionary traits (see inhabitant_data.gd).
			"trait_speed": inh.trait_speed,
			"trait_strength": inh.trait_strength,
			"trait_frugality": inh.trait_frugality,
			"trait_diligence": inh.trait_diligence,
			"trait_resilience": inh.trait_resilience,
		})
	return result


func _stringify_keys(dict: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for key in dict.keys():
		result[str(key)] = dict[key]
	return result


# ---------------------------------------------------------------------------
# Loading
# ---------------------------------------------------------------------------
func load_game() -> void:
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		push_error("SaveLoadManager: no save file found (%s)" % SAVE_PATH)
		return

	var text := file.get_as_text()
	file.close()

	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("SaveLoadManager: save file is corrupted.")
		return

	_deserialize(parsed)
	print("[M10:Load] Game loaded (%s)" % SAVE_PATH)
	game_loaded.emit()


func _deserialize(data: Dictionary) -> void:
	SimulationManager.sim_time = data.get("sim_time", 0.0)
	SimulationManager.speed_mode = data.get("speed_mode", SimulationManager.SpeedMode.NORMAL) as SimulationManager.SpeedMode

	GlobalInventory.gold = data.get("gold", 100.0)

	_deserialize_tiles(data.get("tiles", []))
	WorldGrid.setup_astar()

	BuildingManager.buildings.clear()
	for entry: Dictionary in data.get("buildings", []):
		BuildingManager.buildings.append(_deserialize_building(entry))
	BuildingManager.set_next_id(data.get("next_building_id", 0))

	GameState.inhabitants.clear()
	for entry: Dictionary in data.get("inhabitants", []):
		GameState.inhabitants.append(_deserialize_inhabitant(entry))
	GameState.set_next_inhabitant_id(data.get("next_inhabitant_id", 0))

	for b: BuildingInstance in BuildingManager.buildings:
		WorldGrid.set_building_footprint_rect(b.cell, b.def.footprint_size, b.id, true)

	GlobalInventory.gold_changed.emit(GlobalInventory.gold)
	GlobalInventory.notify_resources_changed()
	GlobalInventory.notify_population_changed(GameState.population_count())

	# M18: a saved game with population 0 means game over.
	if GameState.inhabitants.is_empty():
		GameState.game_over.emit(SimulationManager.get_current_day())


func _deserialize_tiles(tiles_data: Array) -> void:
	var tiles: Array = []
	tiles.resize(tiles_data.size())
	for i in range(tiles_data.size()):
		var entry: Array = tiles_data[i]
		var tile := TileRuntimeData.new()
		tile.terrain = entry[0] as TileRuntimeData.TerrainType
		tile.path_type = entry[1] as TileRuntimeData.PathType
		tile.wear = entry[2]
		tile.resource_amount = entry[3]
		# M19: wheat fields (backward compatible with old saves without these fields).
		if entry.size() > 6:
			tile.crop_stage = entry[4] as TileRuntimeData.CropStage
			tile.crop_timer = entry[5]
			tile.crop_field_owner = int(entry[6])
		if entry.size() > 7:
			tile.biome = int(entry[7])
		# M29: hunting cooldown (backward compatible with saves without this field).
		if entry.size() > 8:
			tile.last_hunted_day = int(entry[8])
		tiles[i] = tile
	WorldGrid.tiles = tiles
	WorldGrid.rebuild_crop_cells()


func _deserialize_building(entry: Dictionary) -> BuildingInstance:
	var b := BuildingInstance.new()
	b.id = entry["id"]
	b.def = BuildingManager.get_building_def(entry["type"] as BuildingDef.BuildingType)

	var cell: Array = entry["cell"]
	b.cell = Vector2i(cell[0], cell[1])

	b.is_constructed = entry.get("is_constructed", true)
	b.construction_timer = entry.get("construction_timer", 0.0)
	b.production_timer = entry.get("production_timer", 0.0)
	b.community_stock = _intify_keys(entry.get("community_stock", {}))
	# M26: crown_stock removed – old save games may still contain the key, it is ignored.
	b.output_stock = _intify_keys(entry.get("output_stock", {}))

	b.occupants = []
	for occ in entry.get("occupants", []):
		b.occupants.append(int(occ))

	b.last_repaired_day = int(entry.get("last_repaired_day", 0))
	b.needs_repair = entry.get("needs_repair", false)
	b.is_derelict = entry.get("is_derelict", false)
	b.pending_build_cost = _intify_keys(entry.get("pending_build_cost", {}))

	if entry.has("market_data"):
		var md_entry: Dictionary = entry["market_data"]
		var md := MarketData.new()
		md.prices = _intify_keys(md_entry.get("prices", {}))
		md.demand_counter = _intify_keys(md_entry.get("demand_counter", {}))
		md.supply_counter = _intify_keys(md_entry.get("supply_counter", {}))
		b.market_data = md

	if entry.has("trade_data"):
		var td_entry: Dictionary = entry["trade_data"]
		var td := TradeData.new()
		td.buy_price = _intify_keys(td_entry.get("buy_price", {}))
		td.sell_price = _intify_keys(td_entry.get("sell_price", {}))
		td.daily_tax = td_entry.get("daily_tax", 0.0)
		b.trade_data = td

	# M20: restore Town Hall policy (or create fresh for old save games).
	if entry.has("policy"):
		var p_entry: Dictionary = entry["policy"]
		var p := PolicyData.new()
		p.subsidy = _intify_keys(p_entry.get("subsidy", {}))
		p.basic_income = p_entry.get("basic_income", 0.0)
		b.policy = p
	elif b.def.type == BuildingDef.BuildingType.TOWN_HALL:
		b.policy = PolicyData.new()

	# M20: rebuild the exchange (floor/ceiling from the just-loaded TradeData).
	if b.def.type == BuildingDef.BuildingType.STORAGE_YARD:
		b.exchange = MarketExchange.new()
		b.exchange.setup(b, BuildingManager.STORAGE_GOODS)
	elif b.def.type == BuildingDef.BuildingType.GRANARY:
		b.exchange = MarketExchange.new()
		b.exchange.setup(b, BuildingManager.GRANARY_GOODS)
	elif b.def.type == BuildingDef.BuildingType.TOWN_HALL:
		# Town Hall = storage yard + granary in one (fixed average price, no TradeData).
		b.exchange = MarketExchange.new()
		b.exchange.setup(b, BuildingManager.TOWN_HALL_GOODS)

	return b


func _deserialize_inhabitant(entry: Dictionary) -> InhabitantData:
	var inh := InhabitantData.new()
	inh.id = entry["id"]
	inh.profession = entry.get("profession", InhabitantData.Profession.NONE) as InhabitantData.Profession
	inh.home_building_id = entry.get("home_building_id", -1)

	var cell: Array = entry["cell"]
	inh.cell = Vector2i(cell[0], cell[1])

	var pos: Array = entry["world_pos"]
	inh.world_pos = Vector2(pos[0], pos[1])

	inh.inventory = _intify_keys(entry.get("inventory", {}))
	inh.gold = entry.get("gold", 0.0)
	inh.hunger = entry.get("hunger", 0.0)
	inh.missed_meals = entry.get("missed_meals", 0)
	inh.production_timer = entry.get("production_timer", 0.0)
	# M20: market economy metrics (backward compatible; margin otherwise random).
	inh.margin = entry.get("margin", randf())
	inh.last_sale_unit_price = entry.get("last_sale_unit_price", 0.0)
	inh.last_food_unit_price = entry.get("last_food_unit_price", Goods.BASE_PRICES[Goods.GoodType.FOOD])
	inh.time_since_last_sale = entry.get("time_since_last_sale", 0.0)
	inh.unprofitable_streak = entry.get("unprofitable_streak", 0)
	# M28: evolutionary traits (backward compatible; otherwise random like margin above).
	inh.trait_speed = entry.get("trait_speed", randf())
	inh.trait_strength = entry.get("trait_strength", randf())
	inh.trait_frugality = entry.get("trait_frugality", randf())
	inh.trait_diligence = entry.get("trait_diligence", randf())
	inh.trait_resilience = entry.get("trait_resilience", randf())
	inh.recompute_derived_stats()

	# Movement/delivery state is not persisted (no path saved) –
	# inhabitants are put into a safe state based on their home building
	# and plan their next route again as needed.
	var home := BuildingManager.get_building(inh.home_building_id)
	if home == null:
		inh.state = InhabitantData.State.SEEKING_SITE
	elif not home.is_constructed:
		inh.state = InhabitantData.State.BUILDING
	else:
		inh.state = InhabitantData.State.WORKING

	return inh


func _intify_keys(dict: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for key in dict.keys():
		result[int(key)] = dict[key]
	return result
