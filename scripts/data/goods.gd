class_name Goods
extends RefCounted

# GRAIN/FLOUR are intermediate products of the food chain: the farmer harvests GRAIN →
# the windmill grinds it into FLOUR → the bakery bakes FOOD. New values are appended at the
# end so existing save games (enum stored as int) stay valid.
enum GoodType { WOOD, PLANKS, STONE, FOOD, GRAIN, FLOUR }

const BASE_PRICES := {
	GoodType.WOOD: 2.0,
	GoodType.PLANKS: 4.0,
	GoodType.STONE: 3.0,
	GoodType.FOOD: 2.0,
	GoodType.GRAIN: 1.0,
	GoodType.FLOUR: 1.5,
}

## M18: English display names for UI text (HUD, BuildMenu, InfoPanel).
const DISPLAY_NAMES := {
	GoodType.WOOD: "Wood",
	GoodType.PLANKS: "Planks",
	GoodType.STONE: "Stone",
	GoodType.FOOD: "Food",
	GoodType.GRAIN: "Grain",
	GoodType.FLOUR: "Flour",
}
