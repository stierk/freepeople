## SaveLoadManager – M10
## Persistiert den gesamten Spielzustand (Welt, Gebäude, Bewohner, Krone) als JSON
## unter user://savegame.json. World.gd reagiert auf das game_loaded-Signal und
## baut die Visuals (Tiles/Gebäude-/Bewohner-Nodes) neu auf.
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
	print("[M10:AutoSave] Auto-save aktiviert (alle %ds)." % AUTO_SAVE_INTERVAL)


func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)


## M18: setzt das Spiel komplett zurück (Speicherstand löschen, alle Manager
## zurücksetzen, Szene neu laden). Wird vom Neustart-Button in HUD und
## GameOverPanel verwendet.
func restart_game() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(SAVE_PATH)

	GlobalInventory.reset_state()
	GameState.reset_state()
	BuildingManager.reset_state()
	SimulationManager.reset_state()

	get_tree().reload_current_scene()


# ---------------------------------------------------------------------------
# Speichern
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
		push_error("SaveLoadManager: Konnte Speicherdatei nicht öffnen (%s)" % SAVE_PATH)
		return
	file.store_string(JSON.stringify(data))
	file.close()
	print("[M10:Save] Spiel gespeichert (%s)" % SAVE_PATH)
	game_saved.emit()


func _serialize_tiles() -> Array:
	var result: Array = []
	result.resize(WorldGrid.tiles.size())
	for i in range(WorldGrid.tiles.size()):
		var tile: TileRuntimeData = WorldGrid.tiles[i]
		# M19: Weizen-Felder (Stufe, Timer, Besitzer) mitspeichern.
		result[i] = [tile.terrain, tile.path_type, tile.wear, tile.resource_amount,
			tile.crop_stage, tile.crop_timer, tile.crop_field_owner]
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
			"crown_stock": _stringify_keys(b.crown_stock),
			"output_stock": _stringify_keys(b.output_stock),
			"occupants": b.occupants.duplicate(),
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
		})
	return result


func _stringify_keys(dict: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for key in dict.keys():
		result[str(key)] = dict[key]
	return result


# ---------------------------------------------------------------------------
# Laden
# ---------------------------------------------------------------------------
func load_game() -> void:
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		push_error("SaveLoadManager: Keine Speicherdatei gefunden (%s)" % SAVE_PATH)
		return

	var text := file.get_as_text()
	file.close()

	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("SaveLoadManager: Speicherdatei ist beschädigt.")
		return

	_deserialize(parsed)
	print("[M10:Load] Spiel geladen (%s)" % SAVE_PATH)
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

	# M18: ein gespeicherter Spielstand mit Bevölkerung 0 bedeutet Game Over.
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
		# M19: Weizen-Felder (abwärtskompatibel zu alten Spielständen ohne diese Felder).
		if entry.size() > 6:
			tile.crop_stage = entry[4] as TileRuntimeData.CropStage
			tile.crop_timer = entry[5]
			tile.crop_field_owner = int(entry[6])
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
	b.crown_stock = _intify_keys(entry.get("crown_stock", {}))
	b.output_stock = _intify_keys(entry.get("output_stock", {}))

	b.occupants = []
	for occ in entry.get("occupants", []):
		b.occupants.append(int(occ))

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

	# Bewegungs-/Lieferzustände werden nicht persistiert (kein Pfad gespeichert) –
	# Bewohner werden anhand ihres Heimatgebäudes in einen sicheren Zustand versetzt
	# und planen ihre nächste Route bei Bedarf neu.
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
