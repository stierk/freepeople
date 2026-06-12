extends Node

const FOOD_LOW_THRESHOLD := 20.0
const PLANKS_LOW_THRESHOLD := 10.0
const WOOD_LOW_THRESHOLD := 10.0
const STONE_LOW_THRESHOLD := 10.0


func assign_profession_for_new_inhabitant() -> InhabitantData.Profession:
	var storage := BuildingManager.get_storage_yard()
	var granary := BuildingManager.get_granary()

	var wood: float = storage.community_stock.get(Goods.GoodType.WOOD, 0.0)
	var planks: float = storage.community_stock.get(Goods.GoodType.PLANKS, 0.0)
	var stone: float = storage.community_stock.get(Goods.GoodType.STONE, 0.0)
	var food: float = granary.community_stock.get(Goods.GoodType.FOOD, 0.0)

	if food < FOOD_LOW_THRESHOLD:
		return InhabitantData.Profession.FARMER
	if planks < PLANKS_LOW_THRESHOLD:
		return InhabitantData.Profession.SAWMILL_WORKER
	if wood < WOOD_LOW_THRESHOLD:
		return InhabitantData.Profession.WOODCUTTER
	if stone < STONE_LOW_THRESHOLD:
		return InhabitantData.Profession.QUARRY_WORKER
	return InhabitantData.Profession.WOODCUTTER
