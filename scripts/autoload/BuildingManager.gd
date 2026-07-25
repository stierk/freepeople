extends Node

signal building_constructed(building_id: int)

const PROFESSION_TO_BUILDING_TYPE := {
	InhabitantData.Profession.WOODCUTTER: BuildingDef.BuildingType.WOODCUTTER_HUT,
	InhabitantData.Profession.SAWMILL_WORKER: BuildingDef.BuildingType.SAWMILL_HUT,
	InhabitantData.Profession.QUARRY_WORKER: BuildingDef.BuildingType.QUARRY_HUT,
	InhabitantData.Profession.FARMER: BuildingDef.BuildingType.FARMER_HUT,
	InhabitantData.Profession.MILLER: BuildingDef.BuildingType.WINDMILL,
	InhabitantData.Profession.BAKER: BuildingDef.BuildingType.BAKERY,
	InhabitantData.Profession.HUNTER: BuildingDef.BuildingType.HUNTER_HUT,  # M29
}

## M14/M17: building types that have player-editable buy/sell prices and a
## tax rate (TradeData).
const TRADE_BUILDING_TYPES: Array[BuildingDef.BuildingType] = [
	BuildingDef.BuildingType.STORAGE_YARD,
	BuildingDef.BuildingType.GRANARY,
	BuildingDef.BuildingType.TREASURY,
]

## M20: which goods an exchange (storage/granary) carries.
const STORAGE_GOODS: Array = [Goods.GoodType.WOOD, Goods.GoodType.PLANKS, Goods.GoodType.STONE]
const GRANARY_GOODS: Array = [Goods.GoodType.FOOD, Goods.GoodType.GRAIN, Goods.GoodType.FLOUR]
## The Town Hall acts as storage yard + granary in one and therefore carries all goods.
const TOWN_HALL_GOODS: Array = [
	Goods.GoodType.WOOD, Goods.GoodType.PLANKS, Goods.GoodType.STONE,
	Goods.GoodType.FOOD, Goods.GoodType.GRAIN, Goods.GoodType.FLOUR,
]

const BUILDING_DEF_PATHS := {
	BuildingDef.BuildingType.STORAGE_YARD: "res://resources/data/building_defs/storage_yard.tres",
	BuildingDef.BuildingType.GRANARY: "res://resources/data/building_defs/granary.tres",
	BuildingDef.BuildingType.TREASURY: "res://resources/data/building_defs/treasury.tres",
	BuildingDef.BuildingType.MARKET: "res://resources/data/building_defs/market.tres",
	BuildingDef.BuildingType.WOODCUTTER_HUT: "res://resources/data/building_defs/woodcutter_hut.tres",
	BuildingDef.BuildingType.SAWMILL_HUT: "res://resources/data/building_defs/sawmill_hut.tres",
	BuildingDef.BuildingType.QUARRY_HUT: "res://resources/data/building_defs/quarry_hut.tres",
	BuildingDef.BuildingType.FARMER_HUT: "res://resources/data/building_defs/farmer_hut.tres",
	BuildingDef.BuildingType.TOWN_HALL: "res://resources/data/building_defs/town_hall.tres",
	BuildingDef.BuildingType.WINDMILL: "res://resources/data/building_defs/windmill.tres",
	BuildingDef.BuildingType.BAKERY: "res://resources/data/building_defs/bakery.tres",
	BuildingDef.BuildingType.HUNTER_HUT: "res://resources/data/building_defs/hunter_hut.tres",  # M29
}

var buildings: Array[BuildingInstance] = []

var _next_id: int = 0
var _def_cache: Dictionary = {}


func get_building_def(type: BuildingDef.BuildingType) -> BuildingDef:
	if not _def_cache.has(type):
		_def_cache[type] = load(BUILDING_DEF_PATHS[type])
	return _def_cache[type]


func register_building(def: BuildingDef, cell: Vector2i) -> BuildingInstance:
	var instance := BuildingInstance.new()
	instance.id = _next_id
	_next_id += 1
	instance.def = def
	instance.cell = cell
	# M21: start the repair clock at creation (only relevant for occupied work huts).
	instance.last_repaired_day = SimulationManager.get_current_day()
	# M8: a market immediately gets its pricing data
	if def.type == BuildingDef.BuildingType.MARKET:
		instance.market_data = MarketData.new()
	# M14/M17: storage yard/granary/treasury get editable trade data
	if def.type in TRADE_BUILDING_TYPES:
		instance.trade_data = TradeData.new()
	# M20: storage yard/granary get their own exchange (order book).
	if def.type == BuildingDef.BuildingType.STORAGE_YARD:
		instance.exchange = MarketExchange.new()
		instance.exchange.setup(instance, STORAGE_GOODS)
	elif def.type == BuildingDef.BuildingType.GRANARY:
		instance.exchange = MarketExchange.new()
		instance.exchange.setup(instance, GRANARY_GOODS)
	# The Town Hall acts as storage yard + granary in one: its own exchange across all
	# goods, but NO TradeData. This keeps floor == ceil == base price, so it buys and
	# sells at a fixed average price and has no adjustable min/max bounds.
	# It additionally carries the global economic policy (subsidy/tariff, basic income).
	elif def.type == BuildingDef.BuildingType.TOWN_HALL:
		instance.exchange = MarketExchange.new()
		instance.exchange.setup(instance, TOWN_HALL_GOODS)
		instance.policy = PolicyData.new()
	buildings.append(instance)
	return instance


func get_building(id: int) -> BuildingInstance:
	for b in buildings:
		if b.id == id:
			return b
	return null


func get_buildings_by_type(type: BuildingDef.BuildingType) -> Array:
	return buildings.filter(func(b): return b.def.type == type)


## M11: accounts for multi-cell footprints (b.cell = top-left corner).
func get_building_at_cell(cell: Vector2i) -> BuildingInstance:
	for b in buildings:
		var size := b.def.footprint_size
		if cell.x >= b.cell.x and cell.x < b.cell.x + size.x \
				and cell.y >= b.cell.y and cell.y < b.cell.y + size.y:
			return b
	return null


## M12: free starter building. As long as neither a storage yard nor a granary
## exists, the Town Hall serves as a fallback storage for wood/stone/food.
func get_town_hall() -> BuildingInstance:
	var list := get_buildings_by_type(BuildingDef.BuildingType.TOWN_HALL)
	return list[0] if not list.is_empty() else null


func get_storage_yard() -> BuildingInstance:
	var list := get_buildings_by_type(BuildingDef.BuildingType.STORAGE_YARD)
	if not list.is_empty():
		return list[0]
	return get_town_hall()


## Does a real storage building exist? (Unlike get_storage_yard, which falls back to
## the Town Hall.) Used to block SAWMILL_WORKER selection and site search
## as long as no storage yard stands yet – otherwise sawmills would get
## built around the Town Hall.
func has_storage_yard() -> bool:
	return not get_buildings_by_type(BuildingDef.BuildingType.STORAGE_YARD).is_empty()


## True if at least one finished building of this type is occupied – i.e. actually
## producing. This lets downstream food-chain professions (miller/baker) already get recruited
## while their input buffer is briefly empty, as long as the previous stage keeps supplying.
func has_active_producer(type: BuildingDef.BuildingType) -> bool:
	for b in buildings:
		if b.def.type == type and b.is_constructed and not b.occupants.is_empty():
			return true
	return false


## M27: does a FULLY built (not derelict, not under construction) building of this
## type exist, regardless of CURRENT occupancy? Weaker than has_active_producer() only in
## the occupancy condition – deliberately used for EconomyManager's miller/baker eligibility:
## has_active_producer() checks occupancy AT THIS EXACT FRAME, which caused a pure
## timing problem under high profession-switch churn (farm house briefly unoccupied while
## the inhabitant is en route/switching) – miller/baker were then never considered a
## candidate despite the food chain existing, and the chain never got going. Unlike a
## naive "does it exist at all" check, is_constructed remains mandatory: a derelict ruin
## (is_constructed=false, but still present in buildings – see _derelict_building) does NOT
## count, otherwise a permanently abandoned hut would keep attracting miller/baker forever; and
## a construction site just started (registered but not yet finished) also doesn't
## count, otherwise a miller could get recruited before the first harvest.
func has_building_of_type(type: BuildingDef.BuildingType) -> bool:
	for b in buildings:
		if b.def.type == type and b.is_constructed:
			return true
	return false


func get_granary() -> BuildingInstance:
	var list := get_buildings_by_type(BuildingDef.BuildingType.GRANARY)
	if not list.is_empty():
		return list[0]
	return get_town_hall()


func get_treasury() -> BuildingInstance:
	var list := get_buildings_by_type(BuildingDef.BuildingType.TREASURY)
	return list[0] if not list.is_empty() else null


## M13/M14: returns the storage building responsible for a specific good
## (food -> granary, everything else -> storage yard; each with a Town Hall fallback).
func get_storage_for_good(good: int) -> BuildingInstance:
	# The food chain (grain, flour, finished food) is stored in the granary.
	if good == Goods.GoodType.FOOD or good == Goods.GoodType.GRAIN or good == Goods.GoodType.FLOUR:
		return get_granary()
	return get_storage_yard()


func get_market() -> BuildingInstance:
	var list := get_buildings_by_type(BuildingDef.BuildingType.MARKET)
	return list[0] if not list.is_empty() else null


## Returns a hut (finished or still under construction) with free capacity, so multiple
## inhabitants share a common hut instead of each building their own.
func get_understaffed_hut(profession: InhabitantData.Profession) -> BuildingInstance:
	var building_type: BuildingDef.BuildingType = PROFESSION_TO_BUILDING_TYPE[profession]
	# M21: prefer already-finished and less occupied (freed-up) huts, so
	# abandoned huts get reoccupied before a new one gets built anywhere.
	var best: BuildingInstance = null
	for b in buildings:
		if b.def.type != building_type or b.occupants.size() >= b.def.max_capacity:
			continue
		if best == null or _hut_reuse_score(b) > _hut_reuse_score(best):
			best = b
	return best


## Higher = preferred: a finished hut (+10) and less occupancy (empty ones first).
func _hut_reuse_score(b: BuildingInstance) -> int:
	return (10 if b.is_constructed else 0) - b.occupants.size()


## M22: any work hut with free capacity – across professions. Covers both empty
## (abandoned) huts and derelict ruins. This lets homeless inhabitants take over/restore an
## existing hut instead of building new elsewhere. Finished/empty preferred.
func get_reclaimable_hut() -> BuildingInstance:
	var work_types: Array = PROFESSION_TO_BUILDING_TYPE.values()
	var best: BuildingInstance = null
	for b in buildings:
		if not work_types.has(b.def.type) or b.occupants.size() >= b.def.max_capacity:
			continue
		if best == null or _hut_reuse_score(b) > _hut_reuse_score(best):
			best = b
	return best


## M22: which profession a work hut belongs to (inverse of PROFESSION_TO_BUILDING_TYPE).
## NONE if the type is not a workplace.
func profession_for_building_type(type: BuildingDef.BuildingType) -> InhabitantData.Profession:
	for prof in PROFESSION_TO_BUILDING_TYPE:
		if PROFESSION_TO_BUILDING_TYPE[prof] == type:
			return prof
	return InhabitantData.Profession.NONE


## M14/M17: purchase price (an inhabitant pays this e.g. for missing build materials) for a good.
## Falls back to the base price if the responsible storage building has no TradeData yet.
func get_buy_price(good: int) -> float:
	var building := get_storage_for_good(good)
	if building != null and building.trade_data != null:
		return building.trade_data.buy_price.get(good, Goods.BASE_PRICES[good])
	return Goods.BASE_PRICES[good]


## M17: sell price (e.g. storage yard selling wood to the market) for a good.
func get_sell_price(good: int) -> float:
	var building := get_storage_for_good(good)
	if building != null and building.trade_data != null:
		return building.trade_data.sell_price.get(good, Goods.BASE_PRICES[good])
	return Goods.BASE_PRICES[good]


## M17: daily head tax (gold per inhabitant per day), 0 if no treasury exists.
func get_daily_tax() -> float:
	var treasury := get_treasury()
	if treasury != null and treasury.trade_data != null:
		return treasury.trade_data.daily_tax
	return 0.0


## M20: all exchanges (storage/granary) that carry a specific good.
func get_all_storages_for_good(good: int) -> Array:
	var is_food: bool = good in GRANARY_GOODS
	var type := BuildingDef.BuildingType.GRANARY if is_food else BuildingDef.BuildingType.STORAGE_YARD
	return get_buildings_by_type(type).filter(func(b): return b.exchange != null)


## M20: average current market price of a good across all exchanges
## (for profession-choice weighting/display). Falls back to the base price.
func get_market_price(good: int) -> float:
	var total := 0.0
	var count := 0
	for b in get_all_storages_for_good(good):
		total += b.exchange.get_price(good)
		count += 1
	if count > 0:
		return total / count
	return Goods.BASE_PRICES.get(good, 1.0)


# --- M20: Town Hall policy (subsidy/tariff, basic income) -----------------------
func get_subsidy(good: int) -> float:
	var th := get_town_hall()
	if th != null and th.policy != null:
		return th.policy.subsidy.get(good, 0.0)
	return 0.0


func get_basic_income() -> float:
	var th := get_town_hall()
	if th != null and th.policy != null:
		return th.policy.basic_income
	return 0.0


## M10: counter for the next building ID (for save/load).
func get_next_id() -> int:
	return _next_id


func set_next_id(value: int) -> void:
	_next_id = value


## M18: resets the building list for a restart.
func reset_state() -> void:
	buildings.clear()
	_next_id = 0
