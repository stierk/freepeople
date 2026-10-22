class_name MarketExchange
extends RefCounted

## Double-auction order book of a storage yard/granary. Each instance forms its own prices –
## two granaries can therefore price differently.
##
## M36: replaces the M20 consignment model. Previously a producer listed a lot at a price
## clamped into the crown's band and consumers took the cheapest lot; the crown ran as a
## special case in the purchase loop and as a backstop sweep. With the default band being a
## single point (buy price == sell price == base price up to M35) every lot landed exactly on
## the crown's bid and the backstop bought it out within one market tick, so every trade was
## villager → crown → villager and no price could form. See docs/GAME_DESIGN.md §M36.
##
## Price model
## -----------
## - Villagers post SELL and BUY orders priced from what they themselves know
##   (ReservationPricing – deliberately free of any crown price). Sellers open high and give
##   way downward, buyers open low and climb.
## - **The crown is no longer a special case.** It appears as two standing orders at the edges
##   of its band: BUY at `crown_bid` (the support price, funded by the treasury) and SELL at
##   `crown_ask` (its own remaining stock). They never drift and never negotiate.
## - A villager order therefore only meets the crown once no villager beats it — pure price
##   priority, no grace timer needed. That the band exists at all is a consequence of these two
##   orders being in the book, not of any formula: remove them (docs/BACKLOG.md #4, the crown
##   withdrawing from a good) and the remaining villagers keep trading.
##
## Settlement
## ----------
## Between two villagers the trade settles at the MIDPOINT of bid and ask – they met each other
## halfway, so they split the surplus. If the crown is one side it settles at the crown's own
## price: it does not haggle.
##
## Goods and presence
## ------------------
## Goods live in the owner building's `community_stock` throughout. A fill moves gold
## immediately but only *reserves* the goods for the buyer (`BuildingInstance.reserved`), who
## collects them the next time they are physically at the building. A buyer who IS present
## posts a marketable order (priced at their walk-away point) and drains the reservation on the
## spot, which reproduces the pre-M36 behaviour of buying straight off the shelf.

const EPS := 0.0001
## Price concession of a resting order per sim second of waiting (balancing knob). Applies to
## both sides now: sellers come down by this much, buyers go up by it.
var DRIFT_PER_SEC: float = Tuning.f("DRIFT_PER_SEC", 0.02)
## How many recent deals `market_anchor` averages over. Long enough that one outlier trade
## cannot move the settlement's price level, short enough to follow a real shift in scarcity.
var ANCHOR_SAMPLE: int = Tuning.i("ANCHOR_SAMPLE", 10)

# Untyped (BuildingInstance), to avoid a class reference cycle.
var owner = null
var goods: Array = []
## good -> {"buy": Array[MarketOrder] (best/highest first), "sell": Array[MarketOrder]
## (best/lowest first)}. Crown orders are NOT kept here – they are synthesised per match from
## the current trade_data, so moving the price slider takes effect immediately.
var _book: Dictionary = {}
## M25: trade chronicle for the price chart (offer/demand/deal + support price line).
var history := MarketHistory.new()


func setup(p_owner, p_goods: Array) -> void:
	owner = p_owner
	goods = p_goods
	for g in goods:
		_book[g] = {"buy": [], "sell": []}


# ---------------------------------------------------------------------------
# Crown prices (the player's two levers)
# ---------------------------------------------------------------------------

## The crown's sell price to consumers (Sell Price, min 0).
func crown_ask(good: int) -> float:
	var c: float = Goods.BASE_PRICES.get(good, 1.0)
	if owner != null and owner.trade_data != null:
		c = owner.trade_data.sell_price.get(good, c)
	return maxf(0.0, c)


## The crown's guaranteed purchase price to producers (Buy Price, min 0). Deliberately NOT
## capped by crown_ask – a high support price may exceed the sell price (agricultural subsidy).
func crown_bid(good: int) -> float:
	var f: float = Goods.BASE_PRICES.get(good, 1.0)
	if owner != null and owner.trade_data != null:
		f = owner.trade_data.buy_price.get(good, f)
	return maxf(0.0, f)


## Whether the crown currently stands on each side of the book — the single place the player's
## buy/sell toggles (TradeData.buy_disabled / sell_disabled) are honoured. Villager-to-villager
## trade is unaffected either way.
func crown_sells(good: int) -> bool:
	return not _crown_disabled("sell_disabled", good) and crown_ask(good) >= 0.0


func crown_buys(good: int) -> bool:
	return not _crown_disabled("buy_disabled", good) and crown_bid(good) > 0.0


func _crown_disabled(side: String, good: int) -> bool:
	return owner != null and owner.trade_data != null and owner.trade_data.get(side).get(good, false)


# ---------------------------------------------------------------------------
# Book queries
# ---------------------------------------------------------------------------

## What this good has recently been changing hands for here — the single number every villager
## order is priced from (see ReservationPricing). Falls back to the base price until something
## has actually traded, so a fresh exchange still produces sane opening prices.
func market_anchor(good: int) -> float:
	var p := history.recent_deal_price(good, ANCHOR_SAMPLE)
	return p if p > 0.0 else float(Goods.BASE_PRICES.get(good, 1.0))


## Price the next purchased unit would cost: the best ask in the book, crown included.
func get_price(good: int) -> float:
	_sync(good)
	var best := INF
	var sells: Array = _sells(good)
	if not sells.is_empty():
		best = sells[0].price
	if crown_sells(good) and crown_remainder(good) > EPS:
		best = minf(best, crown_ask(good))
	return crown_ask(good) if best == INF else best


## Best price a seller could currently get here: the highest bid in the book, crown included.
## Used by MarketManager to route sellers to the exchange where the money actually is.
func best_bid(good: int) -> float:
	_sync(good)
	var best := -INF
	var buys: Array = _buys(good)
	if not buys.is_empty():
		best = buys[0].price
	if crown_buys(good):
		best = maxf(best, crown_bid(good))
	return 0.0 if best == -INF else best


## M37: how much of this good a buyer could get here right now – villager SELL orders plus the
## crown's remainder, the latter only while the crown sells it.
func buyable(good: int) -> float:
	_sync(good)
	return _sell_total(good) + (crown_remainder(good) if crown_sells(good) else 0.0)


## This good's crown remainder: community stock covered neither by a villager SELL order nor by
## a reservation already paid for. Public for telemetry (GlobalInventory.get_crown_total).
func crown_remainder(good: int) -> float:
	var stock: float = owner.community_stock.get(good, 0.0) if owner != null else 0.0
	return maxf(0.0, stock - _sell_total(good) - _reserved_total(good))


# ---------------------------------------------------------------------------
# Posting orders
# ---------------------------------------------------------------------------

## Consignment delivery: the producer puts goods into storage and posts a resting SELL order
## for them. They are NOT paid until it fills. Without a seller the goods land directly as
## crown remainder (no order). Returns the accepted amount (< quantity if storage is full).
func offer(good: int, quantity: float, seller) -> float:
	var accepted := minf(quantity, owner.stock_space(good))
	if accepted <= 0.0:
		return 0.0
	owner.community_stock[good] = owner.community_stock.get(good, 0.0) + accepted
	if seller != null:
		var open := ReservationPricing.seller_open(seller, market_anchor(good))
		var floor_price := ReservationPricing.seller_floor(seller)
		_post(MarketOrder.make(MarketOrder.Side.SELL, good, MarketOrder.OwnerKind.VILLAGER,
			seller.id, accepted, open, floor_price))
		history.record(good, MarketHistory.Kind.OFFER, open)
		# M34: domestic production, for EconomyManager's flow-based urgency. Deliberately only
		# when there IS a seller – ownerless crown remainder is stock appearing, not the
		# settlement producing, and counting it would mask the deficit urgency is meant to detect.
		EconomyManager.note_production(good, accepted)
		_match(good)
	return accepted


## Immediate direct sale to the crown at the support price, paid instantly out of the treasury.
## For emergencies (a hungry, broke inhabitant needs cash right now for food) – a resting order
## would let them starve. Returns the accepted amount.
func sell_to_crown_now(good: int, quantity: float, seller) -> float:
	if not crown_buys(good):
		return 0.0
	var accepted := minf(quantity, owner.stock_space(good))
	if accepted <= 0.0:
		return 0.0
	var price := crown_bid(good)
	owner.community_stock[good] = owner.community_stock.get(good, 0.0) + accepted
	history.record(good, MarketHistory.Kind.DEAL, price, MarketHistory.Deal.CROWN_BUYS)
	RunRecorder.record_trade(good, accepted, RunRecorder.Party.CROWN)
	if seller != null:
		EconomyManager.note_production(good, accepted)  # M34: see offer()
	var payout := minf(price * accepted, GlobalInventory.gold)
	if payout > 0.0 and GlobalInventory.spend_gold(payout) and seller != null:
		_credit_seller(seller, price, payout)
	# M26: subsidy/tariff also applies to direct sales.
	_apply_subsidy(seller, accepted, BuildingManager.get_subsidy(good))
	return accepted


## Consumes goods (building material, repair, profession raw material) for a buyer who is
## PHYSICALLY PRESENT: posts a marketable BUY at their walk-away price, matches at once and
## hands over whatever filled. `max_price` caps that walk-away point (the caller's own ceiling);
## nothing is left resting, so the trip either yields goods or does not, exactly as before M36.
func consume(good: int, quantity: float, payer = null, max_price: float = INF) -> float:
	return _buy_now(good, quantity, payer, max_price)["taken"]


## A hungry inhabitant buys food, present at the granary. Returns {"taken", "unit_price"}.
func buy_food(good: int, quantity: float, payer) -> Dictionary:
	var result := _buy_now(good, quantity, payer, INF)
	var taken: float = result["taken"]
	var cost: float = result["cost"]
	var unit := (cost / taken) if taken > 0.0 else get_price(good)
	return {"taken": taken, "unit_price": unit}


## Shared path for a present buyer. The ceiling comes from ReservationPricing (food: hunger
## ceiling; raw material: what the recipe makes it worth), further capped by `max_price` and
## always by the buyer's own gold.
func _buy_now(good: int, want: float, payer, max_price: float) -> Dictionary:
	_sync(good)
	if payer == null or want <= EPS:
		return {"taken": 0.0, "cost": 0.0}
	var prices := _buyer_prices(good, payer)
	var ceiling: float = minf(prices["ceiling"], max_price)
	if ceiling <= 0.0:
		# A bid of zero is not demand, it is inability to pay, and charting it drew a permanent
		# band of points along the x axis (every broke inhabitant, every tick they stood at the
		# counter). Whoever cannot bid does not appear in the demand series.
		return {"taken": 0.0, "cost": 0.0}
	# The chart gets the OPENING bid, not the ceiling below. The ceiling is a walk-away point —
	# for food it is three times the going rate (HUNGER_CEILING) — so plotting it put the demand
	# cloud permanently above the supply cloud and made it look as though buyers would outbid
	# every seller. Supply plots asking prices, so demand has to plot bids for the two to be
	# comparable at all. Throttled per inhabitant and market tick: this runs every frame while
	# they stand at the counter.
	history.record_demand(good, payer.id, minf(prices["open"], ceiling))
	# Marketable: priced AT the walk-away point, so it crosses everything affordable right now.
	var order := MarketOrder.make(MarketOrder.Side.BUY, good, MarketOrder.OwnerKind.VILLAGER,
		payer.id, want, ceiling, ceiling)
	_post(order)
	_match(good)
	_withdraw(order)  # a present buyer leaves nothing behind; resting bids go through post_resting_buy
	return collect_reserved(payer, good, want)


## Standing bid left behind by a buyer who has decided they need something and is on their way.
## Opens low (ReservationPricing.*_open) and climbs toward their walk-away point as it waits, so
## it can be met by a villager seller long before its owner arrives — the pre-M36 model had no
## way to express demand at all except by standing at the counter, which is why the crown ended
## up the counterparty to almost everything.
##
## Replaces any bid this inhabitant already has resting here for the same good: `pick_best_market`
## may route them elsewhere next time, and stale bids would otherwise pile up and keep buying
## goods their owner never comes to collect.
func post_resting_buy(good: int, qty: float, buyer, hut) -> void:
	if buyer == null or qty <= EPS or not goods.has(good):
		return
	withdraw_resting_buy(good, buyer.id)
	var prices := _buyer_prices(good, buyer, hut)
	var open: float = prices["open"]
	var ceiling: float = prices["ceiling"]
	# Same rule as _buy_now: somebody who cannot bid anything has no demand to express. Posting a
	# zero order would also sit at the bottom of the book forever without ever being fillable.
	if ceiling <= 0.0 or open <= 0.0:
		return
	_post(MarketOrder.make(MarketOrder.Side.BUY, good, MarketOrder.OwnerKind.VILLAGER,
		buyer.id, qty, open, ceiling))
	history.record_demand(good, buyer.id, open)


func withdraw_resting_buy(good: int, buyer_id: int) -> void:
	var buys: Array = _buys(good)
	for i in range(buys.size() - 1, -1, -1):
		if buys[i].owner_id == buyer_id:
			buys.remove_at(i)


## Everything this inhabitant has resting here, on either side. Called when they change trade or
## die – a stale order would keep trading on behalf of someone who no longer wants it.
func withdraw_all_for(inhabitant_id: int) -> void:
	for good in goods:
		withdraw_resting_buy(good, inhabitant_id)
		var sells: Array = _sells(good)
		for i in range(sells.size() - 1, -1, -1):
			if sells[i].owner_id == inhabitant_id:
				sells.remove_at(i)
		_release_reservation(inhabitant_id, good)


## Hands a dead or departed inhabitant's paid-for goods back to the crown. Without this they
## would sit in `reserved` forever: still counted in community_stock, but discounted from
## crown_remainder and from every seller's available space – permanently out of the market.
func _release_reservation(inhabitant_id: int, good: int) -> void:
	var per_inh: Dictionary = owner.reserved.get(inhabitant_id, {})
	if not per_inh.has(good):
		return
	per_inh.erase(good)
	if per_inh.is_empty():
		owner.reserved.erase(inhabitant_id)
	else:
		owner.reserved[inhabitant_id] = per_inh


## What this buyer opens at and where they stop, from their own knowledge only. Single source for
## both numbers: the resting-bid path needs the pair, and the at-the-counter path needs the
## ceiling to order at and the opening to report as demand. Computing them in two places is how
## they drift apart.
##
## `hut` may be null — it is only consulted for the raw-material case, and is looked up from the
## buyer when not supplied.
func _buyer_prices(good: int, payer, hut = null) -> Dictionary:
	var anchor := market_anchor(good)
	if good == Goods.GoodType.FOOD:
		return {
			"open": ReservationPricing.food_open(payer, anchor),
			"ceiling": ReservationPricing.food_ceiling(payer, anchor),
		}
	if hut == null and payer != null:
		hut = BuildingManager.get_building(payer.home_building_id)
	if hut != null and hut.def != null and hut.def.input_good == good:
		return {
			"open": ReservationPricing.input_open(payer, hut),
			"ceiling": ReservationPricing.input_ceiling(payer, hut),
		}
	# Building material and repairs have no recipe behind them: the buyer's purse is the limit.
	# Unchanged from M36 — the opening price below is new, but it is reported, never charged.
	var ceiling: float = payer.gold if payer != null else 0.0
	return {
		"open": ReservationPricing.material_open(payer, anchor, ceiling),
		"ceiling": ceiling,
	}


# ---------------------------------------------------------------------------
# Matching
# ---------------------------------------------------------------------------

## Crosses the book until nothing reaches anything any more.
##
## The order of the three cases below IS the rule, and it is the whole point of M36:
## **two villagers get first refusal, even when the crown offers a better price.**
##
## Price priority (serve whoever is cheapest, crown included) reads as the obviously correct
## thing and is what the first M36 version did. It made the crown the counterparty to
## *everything*: measured over a 100-day run, `tradevol_villager` was exactly 0.0 for the first
## 57 days and only became non-zero on the day the treasury hit 0. The crown starts holding
## practically the settlement's whole food stock (817 of 835 at day 58) and offers it at
## `crown_ask` forever, so no villager can ever be the cheapest seller — and the moment one
## drifts low enough to be interesting, the crown's own bid buys them out first.
##
## M35 avoided this by accident: it clamped every villager ask to exactly `crown_ask` and then
## preferred the villager lot on a TIE (the M31 rule). That is a tie the villager wins. Ranking
## by price turns the same situation into a race the crown wins. This restores the intent
## without needing the clamp — which is what let villager prices form freely again.
##
## It also matches the fiction: the crown is the safety net, not a competitor (see CLAUDE.md).
## And it makes docs/BACKLOG.md #4 (the crown withdrawing from a good) a degenerate case of the
## same rule rather than a special case.
func _match(good: int) -> void:
	_sync(good)
	var guard := 0
	while guard < 512:
		guard += 1
		var v_buy: MarketOrder = _best_affordable_buy(good)
		var v_sell: MarketOrder = _best_sell(good)

		# 1. Villager to villager, whenever their prices cross.
		if v_buy != null and v_sell != null and v_buy.price >= v_sell.price - EPS:
			var price := _settlement_price(v_buy, v_sell)
			var qty := minf(v_buy.quantity, v_sell.quantity)
			qty = minf(qty, _affordable(v_buy, price))
			if qty <= EPS:
				break
			_settle(good, qty, price, v_buy, v_sell)
			continue

		# 2. Crown as the buyer of last resort: a producer nobody wants to buy from.
		var c_bid := crown_bid(good)
		if v_sell != null and crown_buys(good) and c_bid >= v_sell.price - EPS:
			var qty_b := minf(v_sell.quantity, GlobalInventory.gold / c_bid)
			if qty_b > EPS:
				_settle(good, qty_b, c_bid, null, v_sell)
				continue

		# 3. Crown as the seller of last resort: a buyer no producer can supply.
		var c_ask := crown_ask(good)
		if v_buy != null and crown_sells(good) and v_buy.price >= c_ask - EPS:
			var qty_s := minf(v_buy.quantity, crown_remainder(good))
			qty_s = minf(qty_s, _affordable(v_buy, c_ask))
			if qty_s > EPS:
				_settle(good, qty_s, c_ask, v_buy, null)
				continue
		break


## Price two crossing villager orders settle at.
##
## The order that has been RESTING sets the price; the one that just arrived accepts it — normal
## exchange behaviour, and `age` already tells us which is which. Only when both have been
## waiting and drifted into each other do they split the difference, because then they really did
## meet halfway.
##
## Splitting the difference unconditionally overcharges badly: a buyer standing at the counter
## posts a marketable order at their WALK-AWAY price (for food, three times the going rate), so
## against a resting ask of 2.6 the midpoint would be 4.3 — the hungriest inhabitants would pay
## the most, which is the opposite of what the drift is meant to do.
func _settlement_price(buy_order: MarketOrder, sell_order: MarketOrder) -> float:
	if absf(buy_order.age - sell_order.age) <= EPS:
		return (buy_order.price + sell_order.price) * 0.5
	return sell_order.price if sell_order.age > buy_order.age else buy_order.price


## How much of `order` its owner can actually pay for at `price`.
func _affordable(order: MarketOrder, price: float) -> float:
	if price <= 0.0:
		return order.quantity
	var buyer = GameState.get_inhabitant(order.owner_id)
	return (buyer.gold / price) if buyer != null else 0.0


## Books one fill. `buy_order` / `sell_order` are null on whichever side the crown stands.
func _settle(good: int, qty: float, price: float, buy_order, sell_order) -> void:
	var value := qty * price
	var seller = GameState.get_inhabitant(sell_order.owner_id) if sell_order != null else null
	var buyer = GameState.get_inhabitant(buy_order.owner_id) if buy_order != null else null

	# --- money ---
	if sell_order == null:
		# Crown sells its remainder: the buyer pays the treasury.
		if buyer != null:
			_charge(buyer, value)
		GlobalInventory.add_gold(value)
	elif buy_order == null:
		# Crown buys at the support price out of the treasury.
		var payout := minf(value, GlobalInventory.gold)
		if payout > 0.0 and GlobalInventory.spend_gold(payout):
			_credit_seller(seller, price, payout)
	else:
		if buyer != null:
			_charge(buyer, value)
		_credit_seller(seller, price, value)
	# M26: only real producers are subsidised/taxed, never crown remainder.
	if sell_order != null:
		_apply_subsidy(seller, qty, BuildingManager.get_subsidy(good))

	# --- goods ---
	if sell_order != null:
		sell_order.quantity -= qty
		if sell_order.quantity <= EPS:
			_withdraw(sell_order)
	if buy_order != null:
		# Stays physically in community_stock but is set aside for the buyer until they come
		# past; crown_remainder() and _sync() both discount it. It only leaves stock on pickup
		# (collect_reserved), so goods are never in two places at once.
		_reserve(buy_order.owner_id, good, qty, value)
		EconomyManager.note_consumption(good, qty)
		buy_order.quantity -= qty
		if buy_order.quantity <= EPS:
			_withdraw(buy_order)
	# else: the crown bought – the goods stay put and simply become crown remainder.

	# Villager-to-villager only when BOTH sides are inhabitant orders — that is exactly the
	# channel M36 exists to open, so it is the number the milestone is judged on. The chart wants
	# the direction too (which side the crown was on), the telemetry only whether it was involved.
	var deal_party: int
	if buy_order != null and sell_order != null:
		deal_party = MarketHistory.Deal.VILLAGER
	elif sell_order == null:
		deal_party = MarketHistory.Deal.CROWN_SELLS
	else:
		deal_party = MarketHistory.Deal.CROWN_BUYS
	history.record(good, MarketHistory.Kind.DEAL, price, deal_party)
	RunRecorder.record_trade(good, qty,
		RunRecorder.Party.VILLAGER if deal_party == MarketHistory.Deal.VILLAGER \
		else RunRecorder.Party.CROWN)


# ---------------------------------------------------------------------------
# Money helpers
# ---------------------------------------------------------------------------

func _charge(buyer, amount: float) -> void:
	if amount <= 0.0:
		return
	buyer.gold -= amount
	if buyer.node_ref != null:
		buyer.node_ref.show_gold_delta(-amount)


func _credit_seller(seller, unit_price: float, amount: float) -> void:
	if seller == null:
		if amount > 0.0:
			GlobalInventory.add_gold(amount)  # order of an inhabitant who no longer exists
		return
	if amount > 0.0:
		seller.gold += amount
		if seller.node_ref != null:
			seller.node_ref.show_gold_delta(amount)
	# Resets the break-even clock: see ReservationPricing.seller_floor.
	seller.last_sale_unit_price = unit_price
	seller.time_since_last_sale = 0.0


## M26: Town Hall subsidy/tariff on a producer sale. Positive = the crown tops the producer up
## per unit out of the global pool; negative = it deducts a tariff (at most their gold).
func _apply_subsidy(seller, qty: float, rate: float) -> void:
	if seller == null or qty <= EPS or absf(rate) <= EPS:
		return
	var amount := rate * qty
	if amount > 0.0:
		var pay := minf(amount, GlobalInventory.gold)
		if pay > 0.0 and GlobalInventory.spend_gold(pay):
			seller.gold += pay
			if seller.node_ref != null:
				seller.node_ref.show_gold_delta(pay)
	else:
		var toll := minf(-amount, seller.gold)
		if toll > 0.0:
			seller.gold -= toll
			GlobalInventory.add_gold(toll)
			if seller.node_ref != null:
				seller.node_ref.show_gold_delta(-toll)


# ---------------------------------------------------------------------------
# Reservations – goods paid for but not yet picked up
# ---------------------------------------------------------------------------

## Sets goods aside for a buyer who has already paid. `value` is carried alongside the quantity
## so the price they actually paid survives until pickup: reconstructing it from the last deal
## in the chronicle would attribute someone else's price to them, and that number feeds
## `last_food_unit_price` — the anchor the whole buy side prices from.
func _reserve(inhabitant_id: int, good: int, qty: float, value: float) -> void:
	var per_inh: Dictionary = owner.reserved.get(inhabitant_id, {})
	var entry: Dictionary = per_inh.get(good, {"qty": 0.0, "value": 0.0})
	entry["qty"] += qty
	entry["value"] += value
	per_inh[good] = entry
	owner.reserved[inhabitant_id] = per_inh


## Hands a buyer goods that are already theirs and takes them out of stock. Returns
## {"taken", "cost"} with the price they really paid, pro-rated if they cannot carry it all.
func collect_reserved(payer, good: int, max_amount: float) -> Dictionary:
	var per_inh: Dictionary = owner.reserved.get(payer.id, {})
	var entry: Dictionary = per_inh.get(good, {"qty": 0.0, "value": 0.0})
	var have: float = entry["qty"]
	var taken := minf(have, max_amount)
	if taken <= EPS:
		return {"taken": 0.0, "cost": 0.0}
	var cost: float = entry["value"] * (taken / have)
	entry["qty"] = have - taken
	entry["value"] -= cost
	if entry["qty"] <= EPS:
		per_inh.erase(good)
	else:
		per_inh[good] = entry
	if per_inh.is_empty():
		owner.reserved.erase(payer.id)
	else:
		owner.reserved[payer.id] = per_inh
	# Only now do the goods physically leave the building.
	owner.community_stock[good] = maxf(0.0, owner.community_stock.get(good, 0.0) - taken)
	return {"taken": taken, "cost": cost}


func _reserved_total(good: int) -> float:
	var total := 0.0
	if owner == null:
		return 0.0
	for per_inh in owner.reserved.values():
		var entry: Dictionary = per_inh.get(good, {"qty": 0.0})
		total += entry["qty"]
	return total


# ---------------------------------------------------------------------------
# Book bookkeeping
# ---------------------------------------------------------------------------

func _buys(good: int) -> Array:
	return _book.get(good, {}).get("buy", [])


func _sells(good: int) -> Array:
	return _book.get(good, {}).get("sell", [])


## Inserts an order, keeping BUY sorted by descending and SELL by ascending price.
func _post(order: MarketOrder) -> void:
	if order.quantity <= 0.0:
		return
	var list: Array = _buys(order.good) if order.side == MarketOrder.Side.BUY else _sells(order.good)
	var i := 0
	if order.side == MarketOrder.Side.BUY:
		while i < list.size() and list[i].price >= order.price:
			i += 1
	else:
		while i < list.size() and list[i].price <= order.price:
			i += 1
	list.insert(i, order)


func _withdraw(order: MarketOrder) -> void:
	var list: Array = _buys(order.good) if order.side == MarketOrder.Side.BUY else _sells(order.good)
	var i := list.find(order)
	if i >= 0:
		list.remove_at(i)


func _best_sell(good: int) -> MarketOrder:
	var sells: Array = _sells(good)
	return sells[0] if not sells.is_empty() else null


## Highest bid whose owner can actually pay for at least a sliver at that price. Skipping the
## broke ones rather than stopping at them keeps a penniless top bidder from blocking the whole
## book; their order stays and can fill again once they have money.
func _best_affordable_buy(good: int) -> MarketOrder:
	for order in _buys(good):
		if order.quantity <= EPS:
			continue
		var buyer = GameState.get_inhabitant(order.owner_id)
		if buyer == null:
			continue
		if order.price <= 0.0 or buyer.gold > EPS:
			return order
	return null


func _sell_total(good: int) -> float:
	var total := 0.0
	for order in _sells(good):
		total += order.quantity
	return total


## Keeps the SELL side ≤ what is physically in stock. Needed because goods can also leave
## outside the book (withdraw_community fallbacks). Trims the most expensive orders first, so
## the more cheaply offered goods survive longest. Also clears out everything belonging to
## inhabitants who no longer exist: their orders AND the goods they had already paid for, which
## would otherwise stay reserved forever and be permanently out of the market.
func _sync(good: int) -> void:
	var sells: Array = _sells(good)
	for i in range(sells.size() - 1, -1, -1):
		if GameState.get_inhabitant(sells[i].owner_id) == null:
			sells.remove_at(i)
	var buys: Array = _buys(good)
	for i in range(buys.size() - 1, -1, -1):
		if GameState.get_inhabitant(buys[i].owner_id) == null:
			buys.remove_at(i)
	if owner != null:
		for inhabitant_id in owner.reserved.keys():
			if GameState.get_inhabitant(inhabitant_id) == null:
				_release_reservation(inhabitant_id, good)
	var stock: float = owner.community_stock.get(good, 0.0) if owner != null else 0.0
	var excess := _sell_total(good) + _reserved_total(good) - stock
	while excess > EPS and not sells.is_empty():
		var last: MarketOrder = sells[sells.size() - 1]
		if last.quantity <= excess + EPS:
			excess -= last.quantity
			sells.remove_at(sells.size() - 1)
		else:
			last.quantity -= excess
			excess = 0.0


# ---------------------------------------------------------------------------
# Market tick
# ---------------------------------------------------------------------------

## Called by MarketManager every MARKET_TICK_INTERVAL: every resting order gives way a little
## (sellers down toward 0, buyers up toward their ceiling), then the book is crossed.
##
## Both limits are fixed for the life of an order. An earlier M36 draft recomputed the seller's
## floor from `break_even_unit` on every tick, which made it climb as the order aged while its
## price fell — the two then crossed without meeting the crown and the order could never clear
## (see ReservationPricing.seller_floor for what that cost).
func tick() -> void:
	var step := DRIFT_PER_SEC * MarketManager.MARKET_TICK_INTERVAL
	for good in goods:
		_sync(good)
		# Advance both crown step lines even without orders, so the chart keeps running while the
		# player adjusts a slider on empty storage. The two together are the band villager orders
		# live in — with only the support price drawn you cannot tell a bargain from an overpayment.
		history.record_bid(good, crown_bid(good))
		history.record_ask(good, crown_ask(good))
		for order in _sells(good):
			order.drift(step, MarketManager.MARKET_TICK_INTERVAL)
		_resort(good, MarketOrder.Side.SELL)
		for order in _buys(good):
			order.drift(step, MarketManager.MARKET_TICK_INTERVAL)
		_resort(good, MarketOrder.Side.BUY)
		_match(good)


func _resort(good: int, side: int) -> void:
	var list: Array = _buys(good) if side == MarketOrder.Side.BUY else _sells(good)
	if side == MarketOrder.Side.BUY:
		list.sort_custom(func(a, b): return a.price > b.price)
	else:
		list.sort_custom(func(a, b): return a.price < b.price)
