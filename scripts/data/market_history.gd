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

## M36: who stood on the other side of a DEAL, and in which direction. Drives the two-tone deal
## marker in MarketChartPlot, so the chart shows at a glance whether the settlement is trading
## with itself or merely funnelling everything through the crown — the exact question the whole
## order-book milestone turns on.
enum Deal { VILLAGER, CROWN_SELLS, CROWN_BUYS }

## Points per good and event kind. Enough for about two game days of dense trading.
const MAX_EVENTS := 300
## Support points of the step line per good.
const MAX_BID_POINTS := 120

## good -> Array of {"day": float, "price": float, "kind": int}
var _events: Dictionary = {}
## good -> Array of {"day": float, "price": float} — the crown's buy price (support price) …
var _bids: Dictionary = {}
## … and its sell price. Same shape, same cap, drawn as a second step line.
var _asks: Dictionary = {}
## M36: good -> {inhabitant_id: sim_time of their last recorded demand}. Backs the throttle in
## record_demand; entries older than the throttle window are pruned there, so this never holds
## more than roughly one row per living inhabitant.
var _last_demand: Dictionary = {}


## Current game day as a decimal number (day 1 starts at 1.0), so points within a
## day spread out horizontally instead of sticking to a single line.
static func current_day() -> float:
	return SimulationManager.sim_time / SimulationManager.DAY_LENGTH_SECONDS + 1.0


## `party` only carries meaning for Kind.DEAL; OFFER and DEMAND leave it at the default.
func record(good: int, kind: int, price: float, party: int = Deal.VILLAGER) -> void:
	if price < 0.0 or not is_finite(price):
		return
	var list: Array = _events.get(good, [])
	list.append({"day": current_day(), "price": price, "kind": kind, "party": party})
	while list.size() > MAX_EVENTS:
		list.remove_at(0)
	_events[good] = list


## M36: records a DEMAND point, at most one per inhabitant, good and market tick.
##
## The buy-side call sites (`MarketExchange._buy_now`, reached from `_handle_fetching_materials`
## and `_handle_fetching_input`) are state handlers: they run every tick for as long as the
## inhabitant stands at the counter. Somebody who wants a good but cannot yet afford it therefore
## re-states the same bid dozens of times a second. Unthrottled that buried the OFFER and DEAL
## series — a single stuck buyer can fill the whole MAX_EVENTS ring on their own and push
## everything else out of the chart.
##
## Throttling rather than dropping the repeat on purpose: unmet demand is exactly what this series
## was added to show (see the header), so the point has to keep being made — just once per beat
## instead of once per frame.
##
## Returns true when the point was actually recorded.
func record_demand(good: int, owner_id: int, price: float) -> bool:
	if price <= 0.0 or not is_finite(price):
		return false
	var now: float = SimulationManager.sim_time
	var window: float = MarketManager.MARKET_TICK_INTERVAL
	var per_owner: Dictionary = _last_demand.get(good, {})
	var last: float = per_owner.get(owner_id, -INF)
	if now - last < window:
		return false
	# Prune anyone whose entry is already stale (they would pass the check anyway), so a long run
	# does not accumulate a row per inhabitant who has since died.
	for id in per_owner.keys():
		if now - float(per_owner[id]) >= window:
			per_owner.erase(id)
	per_owner[owner_id] = now
	_last_demand[good] = per_owner
	record(good, Kind.DEMAND, price)
	return true


## Records a point of the crown's BUY step line (the support price it guarantees producers).
func record_bid(good: int, price: float) -> void:
	_record_step(_bids, good, price)


## M36: the crown's SELL step line (what it charges consumers). The two lines together are the
## band villager orders live in, so showing only one of them left the chart unreadable: a marker
## above the support line could equally be a bargain or an overpayment.
func record_ask(good: int, price: float) -> void:
	_record_step(_asks, good, price)


## Appends to a step line – but only if the price changed since the last point. The player rarely
## moves a slider, so the lines stay lean and draw as steps rather than thousands of identical
## points.
func _record_step(store: Dictionary, good: int, price: float) -> void:
	if not is_finite(price):
		return
	var list: Array = store.get(good, [])
	if not list.is_empty() and absf(list[list.size() - 1]["price"] - price) < 0.001:
		return
	list.append({"day": current_day(), "price": price})
	while list.size() > MAX_BID_POINTS:
		list.remove_at(0)
	store[good] = list


## M36: mean price of the last `count` completed deals for this good — what the market is
## actually paying right now, across ALL sellers. Returns 0.0 while nothing has traded yet.
##
## This is the anchor every villager prices from. It deliberately reads the shared chronicle
## rather than an individual's own `last_sale_unit_price`: anchoring a seller on their OWN last
## price while opening a fixed multiple above it is a feedback loop, and it wrecked the economy
## — one inhabitant ratcheted their price up sale after sale until they held 58% of all gold in
## the settlement and everyone else starved at 2 gold (measured, seed 42, day 90).
func recent_deal_price(good: int, count: int) -> float:
	var list: Array = _events.get(good, [])
	var sum := 0.0
	var n := 0
	for i in range(list.size() - 1, -1, -1):
		if list[i]["kind"] != Kind.DEAL:
			continue
		sum += list[i]["price"]
		n += 1
		if n >= count:
			break
	return (sum / n) if n > 0 else 0.0


func events(good: int) -> Array:
	return _events.get(good, [])


func bid_points(good: int) -> Array:
	return _bids.get(good, [])


func ask_points(good: int) -> Array:
	return _asks.get(good, [])


func has_data(good: int) -> bool:
	return not events(good).is_empty() \
		or not bid_points(good).is_empty() \
		or not ask_points(good).is_empty()
