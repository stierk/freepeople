extends Node

## M20: Coordinates all exchanges (MarketExchange per storage/granary). Ticks them on
## a beat, offers the inhabitant API for placing sell orders and choosing the
## best exchange (best net offer minus travel cost).

enum Side { SELL, BUY }

## Sim seconds between two market ticks (matching + price drift + export).
const MARKET_TICK_INTERVAL := 5.0
## Gold deduction per travel cell when choosing an exchange (price vs. walking distance).
const DIST_COST_PER_CELL := 0.05


func tick() -> void:
	for building in _market_buildings():
		if building.exchange != null:
			building.exchange.tick()


## Chooses the cheapest exchange for a good from the inhabitant's point of view: sellers
## maximize revenue minus travel cost, buyers minimize price plus travel cost. Manhattan
## distance as a cheap estimate; the real path is only computed for the chosen target.
func pick_best_market(good: int, from_cell: Vector2i, side: int) -> BuildingInstance:
	var best: BuildingInstance = null
	var best_score := -INF
	for building in _market_buildings():
		if building.exchange == null or not building.is_constructed:
			continue
		if not building.exchange.goods.has(good):
			continue
		# Only send buyers to exchanges that actually have the good in stock. Otherwise the
		# nearest market wins purely on distance – typically the central, but (after building a
		# granary/storage yard) empty Town Hall. The inhabitant would then walk there, buy 0,
		# and starve despite having money, even though goods sit elsewhere.
		if side == Side.BUY and building.community_stock.get(good, 0.0) <= 0.0:
			continue
		# Don't send sellers to full storages – offer() would accept 0 there, the trip wasted.
		if side == Side.SELL and building.stock_space(good) <= 0.0:
			continue
		var dist := absi(from_cell.x - building.cell.x) + absi(from_cell.y - building.cell.y)
		var score: float
		if side == Side.SELL:
			score = _seller_revenue(building.exchange, good) - DIST_COST_PER_CELL * dist
		else:
			score = -(building.exchange.get_price(good) + DIST_COST_PER_CELL * dist)
		if score > best_score:
			best_score = score
			best = building
	if best != null:
		return best
	# Fallback: bisheriges Standard-Lager (mit Rathaus-Fallback).
	return BuildingManager.get_storage_for_good(good)


## Revenue a seller can best achieve at this exchange: the upper bound that
## MarketExchange._seller_offer_price clamps their lot to. The support price (Buy) counts
## equally alongside the sell price (Sell) – the producer doesn't care whether a consumer
## or the crown backstop pays them, as long as more gold comes out in the end.
##
## Deliberately NOT exchange.get_price(): that is the ask (cheapest foreign lot) and thus a
## competitor price, not the seller's own revenue. Going by that would completely ignore the
## player's support price – exactly the bug that sent farmers to the Town Hall despite a high Buy Price.
func _seller_revenue(exchange: MarketExchange, good: int) -> float:
	return maxf(exchange.crown_bid(good), exchange.crown_ask(good))


func _market_buildings() -> Array:
	var result: Array = []
	result.append_array(BuildingManager.get_buildings_by_type(BuildingDef.BuildingType.STORAGE_YARD))
	result.append_array(BuildingManager.get_buildings_by_type(BuildingDef.BuildingType.GRANARY))
	# The Town Hall is also an exchange (storage + granary in one, fixed average price).
	result.append_array(BuildingManager.get_buildings_by_type(BuildingDef.BuildingType.TOWN_HALL))
	return result
