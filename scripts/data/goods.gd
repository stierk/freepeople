class_name Goods
extends RefCounted

enum GoodType { WOOD, PLANKS, STONE, FOOD }

const BASE_PRICES := {
	GoodType.WOOD: 2.0,
	GoodType.PLANKS: 4.0,
	GoodType.STONE: 3.0,
	GoodType.FOOD: 2.0,
}
