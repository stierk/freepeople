extends Node

enum SpeedMode { PAUSED, NORMAL, FAST, FASTEST }
const SPEED_MULTIPLIERS := {
	SpeedMode.PAUSED: 0.0,
	SpeedMode.NORMAL: 1.0,
	SpeedMode.FAST: 2.0,
	SpeedMode.FASTEST: 5.0,
}

# --- Produktionskonstanten (M7) ---
const RESOURCE_SEARCH_RADIUS := 6
const RESOURCE_DEPLETION_PER_HARVEST := 0.1
const PRODUCTION_RETRY_DELAY := 1.0

# --- Terrain-Regeneration ---
const RESOURCE_REGEN_INTERVAL := 5.0
const RESOURCE_REGEN_AMOUNT := 0.05
const RESOURCE_REGEN_CHANCE := 0.3

# --- Debug-Logging ---
const DEBUG_LOG_INTERVAL := 15.0

# --- M17/M18: Tageslänge (1 Tag = 60s Echtzeit bei normaler Geschwindigkeit) ---
const DAY_LENGTH_SECONDS := 60.0

# --- M8/M18: Markt + Nahrung + Bevölkerung ---
## M18: 1 Nahrung pro Bewohner und Mahlzeit; 3 Mahlzeiten pro Tag (DAY_LENGTH_SECONDS/3).
const FOOD_PER_INHABITANT_PER_TICK := 1.0
const FOOD_CONSUMPTION_INTERVAL := DAY_LENGTH_SECONDS / 3.0
const HUNGER_MARKET_THRESHOLD := 0.5
const FOOD_PER_MARKET_VISIT := 3.0
const POP_GROWTH_FOOD_THRESHOLD := 25.0
const POP_GROWTH_INTERVAL := 45.0
const POP_MAX := 32
const TITHE_SALE_INTERVAL := 30.0
## M18: nach so vielen in Folge verpassten Mahlzeiten (= 1 Tag "starved" + 1 weitere
## verpasste Mahlzeit) verhungert ein Bewohner.
const STARVATION_DEATH_MEALS := 4

## Markt-Handel: ab dieser Lagermenge gilt ein Gut als "Überschuss" und wird verkauft
const MARKET_SURPLUS_THRESHOLD := {
	Goods.GoodType.WOOD: 30.0,
	Goods.GoodType.PLANKS: 30.0,
	Goods.GoodType.STONE: 30.0,
}
const MARKET_SELL_FRACTION := 0.2
const MARKET_FOOD_IMPORT_SHARE := 0.5

const BUILDING_TYPE_TO_TERRAIN := {
	BuildingDef.BuildingType.WOODCUTTER_HUT: TileRuntimeData.TerrainType.FOREST,
	BuildingDef.BuildingType.QUARRY_HUT: TileRuntimeData.TerrainType.STONE,
}

const PROFESSION_TO_GOOD := {
	InhabitantData.Profession.WOODCUTTER: Goods.GoodType.WOOD,
	InhabitantData.Profession.SAWMILL_WORKER: Goods.GoodType.PLANKS,
	InhabitantData.Profession.QUARRY_WORKER: Goods.GoodType.STONE,
	InhabitantData.Profession.FARMER: Goods.GoodType.FOOD,
}

var speed_mode: SpeedMode = SpeedMode.NORMAL
var sim_time: float = 0.0

var _resource_regen_accum: float = 0.0
var _debug_log_accum: float = 0.0
var _food_consumption_accum: float = 0.0
var _pop_growth_accum: float = 0.0
var _tithe_accum: float = 0.0
var _market_price_accum: float = 0.0
var _daily_tax_accum: float = 0.0


func _process(delta: float) -> void:
	var mult: float = SPEED_MULTIPLIERS[speed_mode]
	if mult == 0.0:
		return
	var sim_delta := delta * mult
	sim_time += sim_delta

	_process_buildings(sim_delta)

	for inhabitant in GameState.inhabitants:
		_process_movement(inhabitant, sim_delta)

	for inhabitant in GameState.inhabitants:
		_process_inhabitant_state(inhabitant, sim_delta)

	_resource_regen_accum += sim_delta
	if _resource_regen_accum >= RESOURCE_REGEN_INTERVAL:
		_resource_regen_accum -= RESOURCE_REGEN_INTERVAL
		_regenerate_resources()

	_food_consumption_accum += sim_delta
	if _food_consumption_accum >= FOOD_CONSUMPTION_INTERVAL:
		_food_consumption_accum -= FOOD_CONSUMPTION_INTERVAL
		_process_food_consumption()

	_pop_growth_accum += sim_delta
	if _pop_growth_accum >= POP_GROWTH_INTERVAL:
		_pop_growth_accum -= POP_GROWTH_INTERVAL
		_process_population_growth()

	_tithe_accum += sim_delta
	if _tithe_accum >= TITHE_SALE_INTERVAL:
		_tithe_accum -= TITHE_SALE_INTERVAL
		_process_tithe_sale()

	_market_price_accum += sim_delta
	if _market_price_accum >= MarketData.PRICE_UPDATE_INTERVAL:
		_market_price_accum -= MarketData.PRICE_UPDATE_INTERVAL
		_update_market_prices()

	_daily_tax_accum += sim_delta
	if _daily_tax_accum >= DAY_LENGTH_SECONDS:
		_daily_tax_accum -= DAY_LENGTH_SECONDS
		_process_daily_tax()

	_debug_log_accum += sim_delta
	if _debug_log_accum >= DEBUG_LOG_INTERVAL:
		_debug_log_accum -= DEBUG_LOG_INTERVAL
		_print_stock_summary()


# ---------------------------------------------------------------------------
# M7: Gebäude-Produktions-Tick
# ---------------------------------------------------------------------------
func _process_buildings(delta: float) -> void:
	for building in BuildingManager.buildings:
		if not building.is_constructed:
			continue
		var def := building.def
		if def.output_interval <= 0.0 or def.output_good < 0:
			continue

		if def.input_good >= 0:
			var storage := BuildingManager.get_storage_yard()
			if storage == null:
				continue
			if storage.community_stock.get(def.input_good, 0.0) < def.input_amount:
				continue

		var terrain_cell := Vector2i(-1, -1)
		if BUILDING_TYPE_TO_TERRAIN.has(def.type):
			var terrain: TileRuntimeData.TerrainType = BUILDING_TYPE_TO_TERRAIN[def.type]
			terrain_cell = _find_resource_cell_near(building.cell, terrain)
			if terrain_cell == Vector2i(-1, -1):
				continue

		building.production_timer -= delta
		if building.production_timer > 0.0:
			continue

		building.production_timer = def.output_interval

		if def.input_good >= 0:
			var storage := BuildingManager.get_storage_yard()
			storage.withdraw_community(def.input_good, def.input_amount)

		if terrain_cell != Vector2i(-1, -1):
			var tile := WorldGrid.get_tile(terrain_cell)
			tile.resource_amount = maxf(0.0, tile.resource_amount - RESOURCE_DEPLETION_PER_HARVEST)

		var prev: float = building.output_stock.get(def.output_good, 0.0)
		building.output_stock[def.output_good] = prev + def.output_amount

		print("[M7:Produktion] %s erzeugt %.1f %s  (Puffer: %.1f)" % [
			def.display_name, def.output_amount,
			Goods.GoodType.keys()[def.output_good], building.output_stock[def.output_good],
		])
		GlobalInventory.notify_resources_changed()


# ---------------------------------------------------------------------------
# M8: Nahrungsverbrauch
# ---------------------------------------------------------------------------
func _process_food_consumption() -> void:
	var granary := BuildingManager.get_granary()
	if granary == null:
		return
	var pop := GameState.inhabitants.size()
	if pop == 0:
		return

	var food_available: float = granary.community_stock.get(Goods.GoodType.FOOD, 0.0)
	var total_needed := FOOD_PER_INHABITANT_PER_TICK * pop
	var hunger_recovery := 0.0

	if food_available >= total_needed:
		hunger_recovery = 1.0
		granary.community_stock[Goods.GoodType.FOOD] = food_available - total_needed
	elif food_available > 0.0:
		hunger_recovery = food_available / total_needed
		granary.community_stock[Goods.GoodType.FOOD] = 0.0

	var starved: Array[int] = []
	for inh: InhabitantData in GameState.inhabitants:
		if hunger_recovery >= 1.0:
			inh.hunger = maxf(0.0, inh.hunger - 0.1)
			inh.missed_meals = 0
		else:
			inh.hunger = minf(1.0, inh.hunger + (1.0 - hunger_recovery) * 0.15)
			inh.missed_meals += 1
			if inh.missed_meals >= STARVATION_DEATH_MEALS:
				starved.append(inh.id)
		if inh.hunger >= HUNGER_MARKET_THRESHOLD and inh.state == InhabitantData.State.WORKING:
			_start_market_trip(inh)

	for id in starved:
		print("[M18:Tod] Bewohner %d ist verhungert." % id)
		GameState.remove_inhabitant(id)

	GlobalInventory.notify_resources_changed()


# ---------------------------------------------------------------------------
# M8: Bevölkerungswachstum
# ---------------------------------------------------------------------------
func _process_population_growth() -> void:
	if GameState.population_count() >= POP_MAX:
		return
	var granary := BuildingManager.get_granary()
	if granary == null:
		return
	var food: float = granary.community_stock.get(Goods.GoodType.FOOD, 0.0)
	if food < POP_GROWTH_FOOD_THRESHOLD:
		return

	granary.community_stock[Goods.GoodType.FOOD] = food - 5.0

	var town_hall := BuildingManager.get_town_hall()
	var spawn_cell: Vector2i
	if town_hall != null:
		spawn_cell = town_hall.cell + Vector2i(1, town_hall.def.footprint_size.y)
	else:
		spawn_cell = WorldGrid.MAP_SIZE / 2

	var inh := GameState.add_inhabitant(spawn_cell)
	GlobalInventory.notify_population_changed(GameState.population_count())
	print("[M8:Bevoelkerung] Bewohner %d spawnt. Gesamt: %d" % [inh.id, GameState.population_count()])


# ---------------------------------------------------------------------------
# M8: Zehnt-Verkauf
# ---------------------------------------------------------------------------
func _process_tithe_sale() -> void:
	var buildings_to_check: Array = [BuildingManager.get_storage_yard(), BuildingManager.get_granary()]
	var total_gold := 0.0

	for building: BuildingInstance in buildings_to_check:
		if building == null:
			continue
		for good: int in building.crown_stock.keys():
			var amount: float = building.crown_stock.get(good, 0.0)
			if amount <= 0.0:
				continue
			var price: float = Goods.BASE_PRICES.get(good, 1.0)
			total_gold += amount * price
			building.crown_stock[good] = 0.0

	if total_gold > 0.0:
		GlobalInventory.add_gold(total_gold)
		print("[M8:Zehnt] Verkauft fuer %.1f Gold. Gesamt: %.1f" % [total_gold, GlobalInventory.gold])


# ---------------------------------------------------------------------------
# M17: Tägliche Kopfsteuer (Schatzkammer)
# ---------------------------------------------------------------------------
func _process_daily_tax() -> void:
	var tax := BuildingManager.get_daily_tax()
	if tax <= 0.0:
		return

	var total := 0.0
	for inh: InhabitantData in GameState.inhabitants:
		var pay := minf(inh.gold, tax)
		inh.gold -= pay
		total += pay

	if total > 0.0:
		GlobalInventory.add_gold(total)
		print("[M17:Steuer] %.1f Gold Kopfsteuer eingenommen." % total)


# ---------------------------------------------------------------------------
# M8: Markt nimmt Waren, verteilt Nahrung, aktualisiert Preise
# ---------------------------------------------------------------------------
func _update_market_prices() -> void:
	var storage := BuildingManager.get_storage_yard()
	var granary := BuildingManager.get_granary()
	for market: BuildingInstance in BuildingManager.get_buildings_by_type(BuildingDef.BuildingType.MARKET):
		if market.market_data == null:
			continue
		_process_market_trade(market.market_data, storage, granary)
		market.market_data.update_prices()


## Verkauft überschüssige Waren aus dem Lagerplatz zu Marktpreisen gegen Gold
## und importiert dafür Nahrung in den Kornspeicher (Markt nimmt Waren, verteilt Nahrung).
func _process_market_trade(md: MarketData, storage: BuildingInstance, granary: BuildingInstance) -> void:
	if storage == null:
		return

	var revenue := 0.0
	for good: int in MARKET_SURPLUS_THRESHOLD.keys():
		var amount: float = storage.community_stock.get(good, 0.0)
		var threshold: float = MARKET_SURPLUS_THRESHOLD[good]
		if amount <= threshold:
			continue
		var sell_amount: float = (amount - threshold) * MARKET_SELL_FRACTION
		storage.community_stock[good] = amount - sell_amount
		var price: float = BuildingManager.get_sell_price(good)
		revenue += sell_amount * price
		md.record_sale(good, sell_amount)

	if revenue <= 0.0:
		return

	var food_budget := revenue * MARKET_FOOD_IMPORT_SHARE
	GlobalInventory.add_gold(revenue - food_budget)

	if granary != null:
		var food_price: float = BuildingManager.get_buy_price(Goods.GoodType.FOOD)
		var food_amount: float = food_budget / food_price
		granary.community_stock[Goods.GoodType.FOOD] = granary.community_stock.get(Goods.GoodType.FOOD, 0.0) + food_amount
		md.record_purchase(Goods.GoodType.FOOD, food_amount)
		print("[M8:Markt] Waren fuer %.1f Gold verkauft, %.1f Nahrung importiert." % [revenue - food_budget, food_amount])
	else:
		GlobalInventory.add_gold(food_budget)

	GlobalInventory.notify_resources_changed()


# ---------------------------------------------------------------------------
# M8: Marktbesuch starten
# ---------------------------------------------------------------------------
func _start_market_trip(inhabitant: InhabitantData) -> void:
	var market := BuildingManager.get_market()
	if market == null:
		return
	inhabitant.path = WorldGrid.find_path(inhabitant.cell, market.cell)
	inhabitant.path_index = 0
	inhabitant.state = InhabitantData.State.MARKET_TRIP


# ---------------------------------------------------------------------------
# Bewegung
# ---------------------------------------------------------------------------
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


# ---------------------------------------------------------------------------
# Zustands-Dispatcher
# ---------------------------------------------------------------------------
func _process_inhabitant_state(inhabitant: InhabitantData, delta: float) -> void:
	match inhabitant.state:
		InhabitantData.State.SEEKING_SITE:
			_handle_seeking_site(inhabitant)
		InhabitantData.State.MOVING_TO_BUILD:
			_handle_moving_to_build(inhabitant)
		InhabitantData.State.BUILDING:
			_handle_building(inhabitant, delta)
		InhabitantData.State.WORKING:
			_handle_working(inhabitant)
		InhabitantData.State.DELIVERING:
			_handle_delivering(inhabitant)
		InhabitantData.State.RETURNING:
			_handle_returning(inhabitant)
		InhabitantData.State.MARKET_TRIP:
			_handle_market_trip(inhabitant)
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
	if home != null:
		inhabitant.state = InhabitantData.State.WORKING if home.is_constructed else InhabitantData.State.BUILDING
		return

	# Inzwischen koennte eine andere Person fuer denselben Beruf bereits eine
	# Huette (fertig oder im Bau) mit freiem Platz registriert haben – dieser
	# Bewohner zieht dann dort ein, statt eine eigene Huette danebenzubauen.
	var shared_hut := BuildingManager.get_understaffed_hut(inhabitant.profession)
	if shared_hut != null:
		shared_hut.occupants.append(inhabitant.id)
		inhabitant.home_building_id = shared_hut.id
		inhabitant.path = WorldGrid.find_path(inhabitant.cell, shared_hut.cell)
		inhabitant.path_index = 0
		return

	var building_type: BuildingDef.BuildingType = BuildingManager.PROFESSION_TO_BUILDING_TYPE[inhabitant.profession]
	var def := BuildingManager.get_building_def(building_type)

	# Der zuvor gewaehlte Standort koennte inzwischen von jemand anderem bebaut
	# worden sein - dann neuen Standort suchen statt die bestehende Huette zu ueberbauen.
	if not WorldGrid.is_footprint_buildable(inhabitant.target_site_cell, def.footprint_size):
		inhabitant.state = InhabitantData.State.SEEKING_SITE
		return

	var hut := BuildingManager.register_building(def, inhabitant.target_site_cell)
	hut.is_constructed = false
	hut.occupants.append(inhabitant.id)
	inhabitant.home_building_id = hut.id
	WorldGrid.set_building_footprint_rect(hut.cell, def.footprint_size, hut.id, true)
	hut.construction_timer = def.build_time_seconds
	hut.production_timer = def.output_interval
	_pay_hut_build_cost(def, inhabitant)
	inhabitant.state = InhabitantData.State.BUILDING


## M14: zieht die Baukosten der Hütte aus dem zuständigen Gemeinschaftslager
## (mit Rathaus-Fallback) ab. Reicht der Lagerbestand nicht, zahlt der Bewohner
## den fehlenden Anteil zum aktuellen Einkaufspreis aus eigenem Gold zu.
func _pay_hut_build_cost(def: BuildingDef, inhabitant: InhabitantData) -> void:
	for good: int in def.build_cost.keys():
		var needed: float = def.build_cost[good]
		if needed <= 0.0:
			continue
		var storage := BuildingManager.get_storage_for_good(good)
		var taken := storage.withdraw_community(good, needed) if storage != null else 0.0
		var missing := needed - taken
		if missing <= 0.0:
			continue
		var price := BuildingManager.get_buy_price(good)
		var cost := missing * price
		inhabitant.gold = maxf(0.0, inhabitant.gold - cost)


func _handle_building(inhabitant: InhabitantData, delta: float) -> void:
	var hut := BuildingManager.get_building(inhabitant.home_building_id)
	if hut.is_constructed:
		inhabitant.state = InhabitantData.State.WORKING
		return

	hut.construction_timer -= delta
	if hut.construction_timer <= 0.0:
		hut.is_constructed = true
		BuildingManager.building_constructed.emit(hut.id)
		print("[M7:Bau] %s fertig gebaut (ID=%d)" % [hut.def.display_name, hut.id])
		inhabitant.state = InhabitantData.State.WORKING


func _handle_working(inhabitant: InhabitantData) -> void:
	var hut := BuildingManager.get_building(inhabitant.home_building_id)
	if hut == null:
		return
	var def := hut.def
	if def.output_good < 0:
		return

	var available: float = hut.output_stock.get(def.output_good, 0.0)
	var carry := minf(available, def.carry_capacity)
	if carry <= 0.0:
		return

	hut.output_stock[def.output_good] = available - carry
	inhabitant.inventory[def.output_good] = inhabitant.inventory.get(def.output_good, 0.0) + carry

	var target := _get_delivery_target(inhabitant.profession)
	inhabitant.path = WorldGrid.find_path(inhabitant.cell, target.cell)
	inhabitant.path_index = 0
	inhabitant.state = InhabitantData.State.DELIVERING


func _handle_delivering(inhabitant: InhabitantData) -> void:
	if not inhabitant.path.is_empty() and inhabitant.path_index < inhabitant.path.size():
		return

	var good: int = PROFESSION_TO_GOOD[inhabitant.profession]
	var amount: float = inhabitant.inventory.get(good, 0.0)
	var target := _get_delivery_target(inhabitant.profession)
	target.deliver(good, amount)
	inhabitant.inventory[good] = 0.0

	print("[M7:Lieferung] Bewohner %d bringt %.1f %s" % [inhabitant.id, amount, Goods.GoodType.keys()[good]])

	var hut := BuildingManager.get_building(inhabitant.home_building_id)
	inhabitant.path = WorldGrid.find_path(inhabitant.cell, hut.cell)
	inhabitant.path_index = 0
	inhabitant.state = InhabitantData.State.RETURNING


func _handle_returning(inhabitant: InhabitantData) -> void:
	if not inhabitant.path.is_empty() and inhabitant.path_index < inhabitant.path.size():
		return
	inhabitant.state = InhabitantData.State.WORKING


# ---------------------------------------------------------------------------
# MARKET_TRIP – M8
# ---------------------------------------------------------------------------
func _handle_market_trip(inhabitant: InhabitantData) -> void:
	if not inhabitant.path.is_empty() and inhabitant.path_index < inhabitant.path.size():
		return

	var granary := BuildingManager.get_granary()
	if granary != null:
		var available: float = granary.community_stock.get(Goods.GoodType.FOOD, 0.0)
		var taken := minf(available, FOOD_PER_MARKET_VISIT)
		granary.community_stock[Goods.GoodType.FOOD] = available - taken
		if FOOD_PER_MARKET_VISIT > 0.0:
			inhabitant.hunger = maxf(0.0, inhabitant.hunger - (taken / FOOD_PER_MARKET_VISIT) * HUNGER_MARKET_THRESHOLD)
		GlobalInventory.notify_resources_changed()

	var hut := BuildingManager.get_building(inhabitant.home_building_id)
	if hut != null:
		inhabitant.path = WorldGrid.find_path(inhabitant.cell, hut.cell)
		inhabitant.path_index = 0
	inhabitant.state = InhabitantData.State.RETURNING


# ---------------------------------------------------------------------------
# Hilfsfunktionen
# ---------------------------------------------------------------------------
func _get_delivery_target(profession: InhabitantData.Profession) -> BuildingInstance:
	if profession == InhabitantData.Profession.FARMER:
		return BuildingManager.get_granary()
	return BuildingManager.get_storage_yard()


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


## M18: aktueller Tag (1-basiert) für HUD-Anzeige und Highscore.
func get_current_day() -> int:
	return int(sim_time / DAY_LENGTH_SECONDS) + 1


## M18: setzt die Simulationszeit/-zähler für einen Neustart zurück.
func reset_state() -> void:
	speed_mode = SpeedMode.NORMAL
	sim_time = 0.0
	_resource_regen_accum = 0.0
	_debug_log_accum = 0.0
	_food_consumption_accum = 0.0
	_pop_growth_accum = 0.0
	_tithe_accum = 0.0
	_market_price_accum = 0.0
	_daily_tax_accum = 0.0


func _print_stock_summary() -> void:
	var storage := BuildingManager.get_storage_yard()
	var granary := BuildingManager.get_granary()
	var wood: float   = storage.community_stock.get(Goods.GoodType.WOOD,   0.0) if storage else 0.0
	var planks: float = storage.community_stock.get(Goods.GoodType.PLANKS, 0.0) if storage else 0.0
	var stone: float  = storage.community_stock.get(Goods.GoodType.STONE,  0.0) if storage else 0.0
	var food: float   = granary.community_stock.get(Goods.GoodType.FOOD,   0.0) if granary else 0.0
	print("[M8:Lager] t=%.0fs | Holz=%.1f Bretter=%.1f Stein=%.1f Nahrung=%.1f | Gold=%.1f | Bev=%d" % [
		sim_time, wood, planks, stone, food,
		GlobalInventory.gold, GameState.population_count()
	])
