## GlobalInventory – M8
## Zentraler Autoload: Gold-Kasse der Krone, Ressourcen-Aggregat, UI-Signale.
## Alle UI-Komponenten verbinden sich mit diesen Signalen für Live-Updates.
extends Node

signal gold_changed(new_amount: float)
signal resources_changed()
signal population_changed(new_count: int)

## Gold-Vorrat der Krone (Zehnt-Einnahmen landen hier)
var gold: float = 100.0


# ---------------------------------------------------------------------------
# Gold
# ---------------------------------------------------------------------------

func add_gold(amount: float) -> void:
	gold += amount
	gold_changed.emit(gold)


func spend_gold(amount: float) -> bool:
	if gold < amount:
		return false
	gold -= amount
	gold_changed.emit(gold)
	return true


# ---------------------------------------------------------------------------
# Ressourcen-Aggregat – aggregiert über ALLE konstruierten Gebäude
# ---------------------------------------------------------------------------

## Summe aller community_stock[good] über alle konstruierten Gebäude.
func get_community_total(good: int) -> float:
	var total := 0.0
	for b: BuildingInstance in BuildingManager.buildings:
		if b.is_constructed:
			total += b.community_stock.get(good, 0.0)
	return total


## Summe aller crown_stock[good] über alle konstruierten Gebäude.
func get_crown_total(good: int) -> float:
	var total := 0.0
	for b: BuildingInstance in BuildingManager.buildings:
		if b.is_constructed:
			total += b.crown_stock.get(good, 0.0)
	return total


## Kurz-Alias: Nahrung aus Kornspeicher community_stock.
func get_food() -> float:
	var granary := BuildingManager.get_granary()
	if granary == null:
		return 0.0
	return granary.community_stock.get(Goods.GoodType.FOOD, 0.0)


## Snapshot: {GoodType → community_total} für alle Güter (für UI/Debug).
func snapshot_community() -> Dictionary:
	var result: Dictionary = {}
	for g: int in Goods.GoodType.values():
		result[g] = get_community_total(g)
	return result


## Snapshot: {GoodType → crown_total} für alle Güter.
func snapshot_crown() -> Dictionary:
	var result: Dictionary = {}
	for g: int in Goods.GoodType.values():
		result[g] = get_crown_total(g)
	return result


# ---------------------------------------------------------------------------
# Signale für UI-Updates (von SimulationManager aufgerufen)
# ---------------------------------------------------------------------------

func notify_resources_changed() -> void:
	resources_changed.emit()


func notify_population_changed(count: int) -> void:
	population_changed.emit(count)
