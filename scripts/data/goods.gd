class_name Goods
extends RefCounted

# GRAIN/FLOUR sind Zwischenprodukte der Nahrungskette: Bauer erntet GRAIN →
# Windmühle mahlt zu FLOUR → Bäckerei backt FOOD. Neue Werte werden ans Ende
# gehängt, damit bestehende Spielstände (Enum als Int gespeichert) gültig bleiben.
enum GoodType { WOOD, PLANKS, STONE, FOOD, GRAIN, FLOUR }

const BASE_PRICES := {
	GoodType.WOOD: 2.0,
	GoodType.PLANKS: 4.0,
	GoodType.STONE: 3.0,
	GoodType.FOOD: 2.0,
	GoodType.GRAIN: 1.0,
	GoodType.FLOUR: 1.5,
}

## M18: englische Anzeigenamen für UI-Texte (HUD, BuildMenu, InfoPanel).
const DISPLAY_NAMES := {
	GoodType.WOOD: "Wood",
	GoodType.PLANKS: "Planks",
	GoodType.STONE: "Stone",
	GoodType.FOOD: "Food",
	GoodType.GRAIN: "Grain",
	GoodType.FLOUR: "Flour",
}
