class_name Goods
extends RefCounted

enum GoodType { WOOD, PLANKS, STONE, FOOD }

const BASE_PRICES := {
	GoodType.WOOD: 2.0,
	GoodType.PLANKS: 4.0,
	GoodType.STONE: 3.0,
	GoodType.FOOD: 2.0,
}

## M18: englische Anzeigenamen für UI-Texte (HUD, BuildMenu, InfoPanel).
const DISPLAY_NAMES := {
	GoodType.WOOD: "Wood",
	GoodType.PLANKS: "Planks",
	GoodType.STONE: "Stone",
	GoodType.FOOD: "Food",
}
