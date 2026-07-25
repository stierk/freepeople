class_name MarketHistory
extends RefCounted

## Rolling trade chronicle of an exchange (MarketExchange), kept separately per good.
##
## Records three event kinds as scatter points plus the support price as a step line:
## - OFFER  (offer):   a producer lists a lot at their asking price (offer()).
## - DEMAND (demand):  a consumer wants to buy; records their willingness to pay
##                     (gold per desired unit) – even when they get nothing.
##                     This makes unmet demand visible, not just completed purchases.
## - DEAL   (trade):   a purchase went through, at the unit price actually paid.
##                     Crown backstop buys count too – without mills the crown is
##                     otherwise the only buyer of grain and the series would stay empty.
## - Support price:    crown_bid per market tick, but only recorded on change. This
##                     produces a step line instead of thousands of identical points.
##
## The chronicle only lives at runtime (not in the save game) and is deliberately capped: past
## MAX_EVENTS the oldest points drop off the back, so a long game doesn't consume unbounded
## memory and the chart shows the more recent past.

enum Kind { OFFER, DEMAND, DEAL }

## Points per good and event kind. Enough for about two game days of dense trading.
const MAX_EVENTS := 300
## Support points of the step line per good.
const MAX_BID_POINTS := 120

## good -> Array of {"day": float, "price": float, "kind": int}
var _events: Dictionary = {}
## good -> Array of {"day": float, "price": float}
var _bids: Dictionary = {}


## Current game day as a decimal number (day 1 starts at 1.0), so points within a
## day spread out horizontally instead of sticking to a single line.
static func current_day() -> float:
	return SimulationManager.sim_time / SimulationManager.DAY_LENGTH_SECONDS + 1.0


func record(good: int, kind: int, price: float) -> void:
	if price < 0.0 or not is_finite(price):
		return
	var list: Array = _events.get(good, [])
	list.append({"day": current_day(), "price": price, "kind": kind})
	while list.size() > MAX_EVENTS:
		list.remove_at(0)
	_events[good] = list


## Records a support point of the step line – but only if the price changed since the last
## point. The player rarely moves the slider, so the line stays lean.
func record_bid(good: int, price: float) -> void:
	if not is_finite(price):
		return
	var list: Array = _bids.get(good, [])
	if not list.is_empty() and absf(list[list.size() - 1]["price"] - price) < 0.001:
		return
	list.append({"day": current_day(), "price": price})
	while list.size() > MAX_BID_POINTS:
		list.remove_at(0)
	_bids[good] = list


func events(good: int) -> Array:
	return _events.get(good, [])


func bid_points(good: int) -> Array:
	return _bids.get(good, [])


func has_data(good: int) -> bool:
	return not events(good).is_empty() or not bid_points(good).is_empty()
