extends Node

signal building_constructed(building_id: int)

const PROFESSION_TO_BUILDING_TYPE := {
	InhabitantData.Profession.WOODCUTTER: BuildingDef.BuildingType.WOODCUTTER_HUT,
	InhabitantData.Profession.SAWMILL_WORKER: BuildingDef.BuildingType.SAWMILL_HUT,
	InhabitantData.Profession.QUARRY_WORKER: BuildingDef.BuildingType.QUARRY_HUT,
	InhabitantData.Profession.FARMER: BuildingDef.BuildingType.FARMER_HUT,
}

const BUILDING_DEF_PATHS := {
	BuildingDef.BuildingType.STORAGE_YARD: "res://resources/data/building_defs/storage_yard.tres",
	BuildingDef.BuildingType.GRANARY: "res://resources/data/building_defs/granary.tres",
	BuildingDef.BuildingType.TREASURY: "res://resources/data/building_defs/treasury.tres",
	BuildingDef.BuildingType.MARKET: "res://resources/data/building_defs/market.tres",
	BuildingDef.BuildingType.WOODCUTTER_HUT: "res://resources/data/building_defs/woodcutter_hut.tres",
	BuildingDef.BuildingType.SAWMILL_HUT: "res://resources/data/building_defs/sawmill_hut.tres",
	BuildingDef.BuildingType.QUARRY_HUT: "res://resources/data/building_defs/quarry_hut.tres",
	BuildingDef.BuildingType.FARMER_HUT: "res://resources/data/building_defs/farmer_hut.tres",
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
	buildings.append(instance)
	return instance


func get_building(id: int) -> BuildingInstance:
	for b in buildings:
		if b.id == id:
			return b
	return null


func get_buildings_by_type(type: BuildingDef.BuildingType) -> Array:
	return buildings.filter(func(b): return b.def.type == type)


func get_building_at_cell(cell: Vector2i) -> BuildingInstance:
	for b in buildings:
		if b.cell == cell:
			return b
	return null


func get_storage_yard() -> BuildingInstance:
	var list := get_buildings_by_type(BuildingDef.BuildingType.STORAGE_YARD)
	return list[0] if not list.is_empty() else null


func get_granary() -> BuildingInstance:
	var list := get_buildings_by_type(BuildingDef.BuildingType.GRANARY)
	return list[0] if not list.is_empty() else null


func get_treasury() -> BuildingInstance:
	var list := get_buildings_by_type(BuildingDef.BuildingType.TREASURY)
	return list[0] if not list.is_empty() else null


func get_market() -> BuildingInstance:
	var list := get_buildings_by_type(BuildingDef.BuildingType.MARKET)
	return list[0] if not list.is_empty() else null


func get_understaffed_hut(profession: InhabitantData.Profession) -> BuildingInstance:
	var building_type: BuildingDef.BuildingType = PROFESSION_TO_BUILDING_TYPE[profession]
	for b in buildings:
		if b.def.type == building_type and b.is_constructed and b.occupants.size() < b.def.max_capacity:
			return b
	return null
