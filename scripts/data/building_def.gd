class_name BuildingDef
extends Resource

enum BuildingType {
	STORAGE_YARD, GRANARY, TREASURY, MARKET,
	WOODCUTTER_HUT, SAWMILL_HUT, QUARRY_HUT, FARMER_HUT, ROAD,
	TOWN_HALL, WINDMILL, BAKERY
}

@export var type: BuildingType = BuildingType.STORAGE_YARD
@export var display_name: String = ""
@export var footprint_size: Vector2i = Vector2i(1, 1)
## Quell-Sheet des Gebäude-Sprites: "base"/"farm"/"vik" (fliegevolge_overworld)
## oder "px" (pixelholes MasterSimple, Alt-Bestand).
@export var sprite_sheet: String = "px"
@export var sprite_atlas_region: Rect2i = Rect2i(0, 0, 16, 16)
@export var max_capacity: int = 2
@export var build_time_seconds: float = 0.0
@export var is_player_placeable: bool = false
@export var build_cost_gold: float = 0.0
## M13/M14: Baukosten in Gütern (Goods.GoodType -> Menge), z.B. {0: 20.0} = 20 Holz
@export var build_cost: Dictionary = {}
@export var storage_capacity: Dictionary = {}

# Produktionskonfiguration (M7)
## GoodType-Wert des erzeugten Guts (-1 = kein Produktionsgebäude)
@export var output_good: int = -1
## Menge die pro Zyklus erzeugt wird
@export var output_amount: float = 1.0
## Sekunden pro Produktionszyklus (0 = kein Produktionsgebäude)
@export var output_interval: float = 0.0
## Benötigtes Eingangsgut (-1 = kein Input nötig, z.B. Sägewerk braucht Holz)
@export var input_good: int = -1
## Menge des Eingangs-Guts pro Zyklus
@export var input_amount: float = 0.0
## Wie viel ein Bewohner pro Transportfahrt tragen kann
@export var carry_capacity: float = 1.0
