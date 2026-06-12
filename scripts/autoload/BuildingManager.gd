extends Node

signal building_constructed(building_id: int)

const PROFESSION_TO_BUILDING_TYPE := {
	InhabitantData.Profession.WOODCUTTER: BuildingDef.BuildingType.WOODCUTTER_HUT,
	InhabitantData.Profession.SAWMILL_WORKER: BuildingDef.BuildingType.SAWMILL_HUT,
	InhabitantData.Profession.QUARRY_WORKER: BuildingDef.BuildingType.QUARRY_HUT,
	InhabitantData.Profession.FARMER: BuildingDef.BuildingType.FARMER_HUT,
}

## M14/M17: Gebäudetypen, die spielerseitig editierbare An-/Verkaufspreise und einen
## Steuersatz besitzen (TradeData).
const TRADE_BUILDING_TYPES: Array[BuildingDef.BuildingType] = [
	BuildingDef.BuildingType.STORAGE_YARD,
	BuildingDef.BuildingType.GRANARY,
	BuildingDef.BuildingType.TREASURY,
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
	# M8: Markt bekommt sofort seine Preisbildungs-Daten
	if def.type == BuildingDef.BuildingType.MARKET:
		instance.market_data = MarketData.new()
	# M14/M17: Lagerplatz/Kornspeicher/Schatzkammer bekommen editierbare Handelsdaten
	if def.type in TRADE_BUILDING_TYPES:
		instance.trade_data = TradeData.new()
	buildings.append(instance)
	return instance


func get_building(id: int) -> BuildingInstance:
	for b in buildings:
		if b.id == id:
			return b
	return null


func get_buildings_by_type(type: BuildingDef.BuildingType) -> Array:
	return buildings.filter(func(b): return b.def.type == type)


## M11: berücksichtigt mehrzellige Footprints (b.cell = obere linke Ecke).
func get_building_at_cell(cell: Vector2i) -> BuildingInstance:
	for b in buildings:
		var size := b.def.footprint_size
		if cell.x >= b.cell.x and cell.x < b.cell.x + size.x \
				and cell.y >= b.cell.y and cell.y < b.cell.y + size.y:
			return b
	return null


## M12: Free starter building. Solange weder Lagerplatz noch Kornspeicher
## existieren, dient das Rathaus als Fallback-Lager für Holz/Stein/Nahrung.
func get_town_hall() -> BuildingInstance:
	var list := get_buildings_by_type(BuildingDef.BuildingType.TOWN_HALL)
	return list[0] if not list.is_empty() else null


func get_storage_yard() -> BuildingInstance:
	var list := get_buildings_by_type(BuildingDef.BuildingType.STORAGE_YARD)
	if not list.is_empty():
		return list[0]
	return get_town_hall()


func get_granary() -> BuildingInstance:
	var list := get_buildings_by_type(BuildingDef.BuildingType.GRANARY)
	if not list.is_empty():
		return list[0]
	return get_town_hall()


func get_treasury() -> BuildingInstance:
	var list := get_buildings_by_type(BuildingDef.BuildingType.TREASURY)
	return list[0] if not list.is_empty() else null


## M13/M14: liefert das Lagergebäude, das für ein bestimmtes Gut zuständig ist
## (Nahrung -> Kornspeicher, alles andere -> Lagerplatz; jeweils mit Rathaus-Fallback).
func get_storage_for_good(good: int) -> BuildingInstance:
	if good == Goods.GoodType.FOOD:
		return get_granary()
	return get_storage_yard()


func get_market() -> BuildingInstance:
	var list := get_buildings_by_type(BuildingDef.BuildingType.MARKET)
	return list[0] if not list.is_empty() else null


func get_understaffed_hut(profession: InhabitantData.Profession) -> BuildingInstance:
	var building_type: BuildingDef.BuildingType = PROFESSION_TO_BUILDING_TYPE[profession]
	for b in buildings:
		if b.def.type == building_type and b.is_constructed and b.occupants.size() < b.def.max_capacity:
			return b
	return null


## M14/M17: Einkaufspreis (Bewohner zahlt z.B. fuer fehlende Baumaterialien) für ein Gut.
## Fällt auf den Basispreis zurück, falls das zuständige Lagergebäude noch kein TradeData hat.
func get_buy_price(good: int) -> float:
	var building := get_storage_for_good(good)
	if building != null and building.trade_data != null:
		return building.trade_data.buy_price.get(good, Goods.BASE_PRICES[good])
	return Goods.BASE_PRICES[good]


## M17: Verkaufspreis (z.B. Lagerplatz-Holzverkauf an den Markt) für ein Gut.
func get_sell_price(good: int) -> float:
	var building := get_storage_for_good(good)
	if building != null and building.trade_data != null:
		return building.trade_data.sell_price.get(good, Goods.BASE_PRICES[good])
	return Goods.BASE_PRICES[good]


## M17: Tägliche Kopfsteuer (Gold pro Bewohner pro Tag), 0 falls keine Schatzkammer existiert.
func get_daily_tax() -> float:
	var treasury := get_treasury()
	if treasury != null and treasury.trade_data != null:
		return treasury.trade_data.daily_tax
	return 0.0


## M10: Zähler für die nächste Gebäude-ID (für Save/Load).
func get_next_id() -> int:
	return _next_id


func set_next_id(value: int) -> void:
	_next_id = value


## M18: setzt die Gebäudeliste für einen Neustart zurück.
func reset_state() -> void:
	buildings.clear()
	_next_id = 0
