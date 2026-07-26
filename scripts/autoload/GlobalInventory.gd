## GlobalInventory – M8
## Central autoload: the crown's gold pool, resource aggregate, UI signals.
## All UI components connect to these signals for live updates.
extends Node

signal gold_changed(new_amount: float)
signal resources_changed()
signal population_changed(new_count: int)

## Gold pool of the crown (tithe income lands here)
var gold: float = 1000.0


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


## M18: resets the crown's gold pool for a restart.
func reset_state() -> void:
	gold = 1000.0


# ---------------------------------------------------------------------------
# Resource aggregate – aggregated over ALL constructed buildings
# ---------------------------------------------------------------------------

## Sum of all community_stock[good] over all constructed buildings.
func get_community_total(good: int) -> float:
	var total := 0.0
	for b: BuildingInstance in BuildingManager.buildings:
		if b.is_constructed:
			total += b.community_stock.get(good, 0.0)
	return total


## Sum of this good's crown remainder across all exchanges (uncovered community_stock that
## belongs to the crown). M26: previously summed from the dead crown_stock (always 0) – now
## the real crown remainder from the exchanges (MarketExchange.crown_remainder).
func get_crown_total(good: int) -> float:
	var total := 0.0
	for b: BuildingInstance in BuildingManager.buildings:
		if b.is_constructed and b.exchange != null:
			total += b.exchange.crown_remainder(good)
	return total


## Short alias: food from the granary's community_stock.
func get_food() -> float:
	var granary := BuildingManager.get_granary()
	if granary == null:
		return 0.0
	return granary.community_stock.get(Goods.GoodType.FOOD, 0.0)


## Snapshot: {GoodType → community_total} for all goods (for UI/debug).
func snapshot_community() -> Dictionary:
	var result: Dictionary = {}
	for g: int in Goods.GoodType.values():
		result[g] = get_community_total(g)
	return result


## Snapshot: {GoodType → crown_total} for all goods.
func snapshot_crown() -> Dictionary:
	var result: Dictionary = {}
	for g: int in Goods.GoodType.values():
		result[g] = get_crown_total(g)
	return result


# ---------------------------------------------------------------------------
# Signals for UI updates (called by SimulationManager)
# ---------------------------------------------------------------------------

func notify_resources_changed() -> void:
	resources_changed.emit()


func notify_population_changed(count: int) -> void:
	population_changed.emit(count)
