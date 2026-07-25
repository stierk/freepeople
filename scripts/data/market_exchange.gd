class_name MarketExchange
extends RefCounted

## Consignment exchange of a storage yard/granary. Each instance forms its own prices – two
## granaries can therefore price differently.
##
## Price model (custom, two decoupled player prices):
## - **Sell Price** (trade_data.sell_price) = **the crown's sell price to consumers.** At
##   this price the crown gives away its OWN stock (starting stock, bought-up
##   backstop purchases) to buyers. See crown_ask().
## - **Buy Price** (trade_data.buy_price) = **the crown's guaranteed purchase price (support
##   price) to producers.** It is NOT capped by the sell price anymore – the crown
##   may support at a higher price than it resells for (agricultural subsidy). See crown_bid().
##
## Flow (consignment):
## - The producer delivers their goods and lists them as their own price lot at THEIR desired
##   price (reservation price = break-even × (1 + margin), clamped to [support price, sell price]).
##   They are NOT paid yet at this point (offer()).
## - Consumers (eating food, building input, construction sites) take the CHEAPEST lots first
##   and pay the proceeds directly to the lot owner (producer). Crown remainder → treasury.
## - Unsold lots get cheaper with every market tick (price drift), even below
##   production cost – this creates real sell pressure/loss (tick()).
## - If a lot falls to the support price (Buy Price), the crown immediately buys it from the
##   producer out of the treasury; the goods thereby become crown remainder (tick() → _run_crown_backstop).
##
## Crown remainder: the part of community_stock NOT covered by producer lots
## (starting stock, loaded save game, bought-up backstop purchases). It is dynamically handed
## out to consumers at the current sell price (crown_ask).

const EPS := 0.0001
## Price decay of an unsold lot per sim second of waiting (balancing knob).
const DRIFT_PER_SEC := 0.02
## Lowest price a lot can drift to (without a support price it ends here → total loss).
const MIN_OFFER_PRICE := 0.0

# Untyped (BuildingInstance), to avoid a class reference cycle.
var owner = null
var goods: Array = []
## good -> Array of producer lots, sorted ascending by price. Each lot is a
## Dictionary {"price", "qty", "owner", "age"} ("owner" = inhabitant ID of the producer).
var _lots: Dictionary = {}
## M25: trade chronicle for the price chart (offer/demand/deal + support price line).
var history := MarketHistory.new()


func setup(p_owner, p_goods: Array) -> void:
	owner = p_owner
	goods = p_goods
	for g in goods:
		_lots[g] = []


## The crown's sell price to consumers (Sell Price, min 0).
func crown_ask(good: int) -> float:
	var c: float = Goods.BASE_PRICES.get(good, 1.0)
	if owner != null and owner.trade_data != null:
		c = owner.trade_data.sell_price.get(good, c)
	return maxf(0.0, c)


## The crown's guaranteed purchase price to producers (Buy Price, min 0). Deliberately NOT
## capped by crown_ask – a high support price may exceed the sell price.
func crown_bid(good: int) -> float:
	var f: float = Goods.BASE_PRICES.get(good, 1.0)
	if owner != null and owner.trade_data != null:
		f = owner.trade_data.buy_price.get(good, f)
	return maxf(0.0, f)


## Price the next purchased unit would cost: the cheapest available offer
## (crown remainder at the sell price, or the cheapest producer lot). The ask if there's no stock.
func get_price(good: int) -> float:
	_sync(good)
	var stock: float = owner.community_stock.get(good, 0.0) if owner != null else 0.0
	var lots: Array = _lots.get(good, [])
	var lot_total := _lot_total(good)
	var best := INF
	if stock - lot_total > EPS:
		best = crown_ask(good)
	if not lots.is_empty():
		best = minf(best, lots[0]["price"])
	return crown_ask(good) if best == INF else best


## Consignment: the producer (seller) delivers goods into storage and lists them as their own
## price lot at their desired price. They are NOT paid yet – payment only happens
## when a buyer takes the lot (_purchase) or the crown buys it up at the support price
## (tick). Without a seller the goods land directly as crown remainder. Returns the accepted
## amount (< quantity if storage is full).
func offer(good: int, quantity: float, seller) -> float:
	_sync(good)
	var accepted := minf(quantity, owner.stock_space(good))
	if accepted <= 0.0:
		return 0.0
	owner.community_stock[good] = owner.community_stock.get(good, 0.0) + accepted
	if seller != null:
		var ask := _seller_offer_price(good, seller)
		_add_lot(good, ask, accepted, seller.id)
		history.record(good, MarketHistory.Kind.OFFER, ask)
	# seller == null: goods remain ownerless crown remainder (no lot).
	return accepted


## Immediate direct sale to the crown at the support price (Buy Price), paid instantly out of
## the treasury. For emergencies (a hungry, broke inhabitant needs cash right now for
## food) – consignment would let them starve. The goods go into storage as crown remainder;
## if the treasury is empty they're still accepted (proceeds then partial/0). Returns the
## accepted amount.
func sell_to_crown_now(good: int, quantity: float, seller) -> float:
	_sync(good)
	var accepted := minf(quantity, owner.stock_space(good))
	if accepted <= 0.0:
		return 0.0
	var price := crown_bid(good)
	owner.community_stock[good] = owner.community_stock.get(good, 0.0) + accepted
	history.record(good, MarketHistory.Kind.DEAL, price)
	RunRecorder.record_trade(good, accepted)
	var payout := minf(price * accepted, GlobalInventory.gold)
	if payout > 0.0 and GlobalInventory.spend_gold(payout) and seller != null:
		seller.gold += payout
		seller.last_sale_unit_price = price
		seller.time_since_last_sale = 0.0
		if seller.node_ref != null:
			seller.node_ref.show_gold_delta(payout)
	# M26: subsidy/tariff also applies to direct sales (one good, one call – fetch the rate directly).
	_apply_subsidy(seller, accepted, BuildingManager.get_subsidy(good))
	return accepted


## Consumes goods (building material, repair, profession raw material). Takes the cheapest
## lots first, limited by the payer's OWN budget (M31: no crown shortfall cover here, unlike
## the old behavior – an inhabitant who can't afford it simply doesn't get it) and by
## `max_price`, a personal price ceiling/willingness to pay (see
## SimulationManager._willingness_to_pay: starts at the fair market price, rises toward the
## buyer's wealth the longer they've waited). Returns the amount taken.
func consume(good: int, quantity: float, payer = null, max_price: float = INF) -> float:
	return _purchase(good, quantity, payer, payer != null, max_price)["taken"]


## A hungry inhabitant (payer) buys food: cheapest lots first, limited by their
## budget (free/discounted lots first → even broke inhabitants can take free
## food). Returns {"taken", "unit_price"}.
func buy_food(good: int, quantity: float, payer) -> Dictionary:
	var result := _purchase(good, quantity, payer, true)
	var taken: float = result["taken"]
	var cost: float = result["cost"]
	var unit := (cost / taken) if taken > 0.0 else get_price(good)
	return {"taken": taken, "unit_price": unit}


## Core purchase routine: takes up to `want` units, always the cheapest available source
## (crown remainder at the sell price, or the cheapest producer lot) first. With
## `limit_to_budget` (food, building/repair/raw-material) the amount is capped by the buyer's
## gold. `max_price` (M31) additionally excludes any source priced above it – a personal
## willingness-to-pay ceiling; since sources are considered cheapest-first, once the cheapest
## remaining one exceeds it nothing cheaper is left, so the loop stops. The proceeds are
## booked immediately: crown remainder → treasury; producer lot → its owner, where the buyer
## pays what they can and the crown covers any shortfall (only relevant when `limit_to_budget`
## is false). Returns {"taken", "cost"} (cost = nominal value).
func _purchase(good: int, want: float, payer, limit_to_budget: bool, max_price: float = INF) -> Dictionary:
	_sync(good)
	# Record demand BEFORE reconciling against stock: willingness to pay per
	# desired unit applies even when storage is empty and the buyer comes away empty-handed.
	# This unmet demand is exactly what the chart should show.
	if payer != null and want > EPS:
		history.record(good, MarketHistory.Kind.DEMAND, payer.gold / want)
	var stock: float = owner.community_stock.get(good, 0.0)
	want = minf(want, stock)
	if want <= 0.0:
		return {"taken": 0.0, "cost": 0.0}
	var lots: Array = _lots.get(good, [])
	var crown_qty := maxf(0.0, stock - _lot_total(good))
	var crown_price := crown_ask(good)
	var sub_rate := BuildingManager.get_subsidy(good)  # M26: once per purchase (perf)
	var budget: float = payer.gold if payer != null else INF
	var taken := 0.0
	var cost := 0.0
	while want > EPS:
		var have_lot := not lots.is_empty()
		var lot_price: float = lots[0]["price"] if have_lot else INF
		# M31: strict `<` (was `<=`) — at an EQUAL price, prefer the producer's lot over crown
		# remainder, so inhabitant food/goods sellers (esp. hunters/bakers) actually get the sale
		# and money keeps circulating among inhabitants instead of leaking into the crown treasury.
		# The crown cushion is still used when it is strictly cheaper, or when no lot exists.
		var use_crown := crown_qty > EPS and (not have_lot or crown_price < lot_price)
		if not use_crown and not have_lot:
			break
		var price: float = crown_price if use_crown else lot_price
		if price > max_price:
			# M31: cheapest remaining source is already too expensive for the buyer's current
			# willingness to pay - crown price is fixed and lots only get pricier from here, so
			# nothing left in this loop will be cheaper. Whatever was taken so far stands.
			break
		var src_qty: float = crown_qty if use_crown else lots[0]["qty"]
		var q := minf(src_qty, want)
		if limit_to_budget and price > 0.0 and budget < INF:
			q = minf(q, budget / price)
		if q <= EPS:
			break
		var portion := q * price
		var payer_pays: float = portion if payer == null else minf(portion, maxf(0.0, budget))
		if use_crown:
			# Crown remainder: the buyer pays (as much as they can) to the treasury.
			GlobalInventory.add_gold(payer_pays)
			crown_qty -= q
		else:
			# Producer lot: the owner gets the full proceeds; a shortfall from the
			# buyer is covered by the crown (as far as its gold allows).
			var from_crown := 0.0
			var shortfall := portion - payer_pays
			if shortfall > EPS:
				from_crown = minf(shortfall, GlobalInventory.gold)
				if from_crown > 0.0:
					GlobalInventory.spend_gold(from_crown)
			var lot_seller = _credit_lot_owner(lots[0]["owner"], price, payer_pays + from_crown)
			_apply_subsidy(lot_seller, q, sub_rate)  # M26
			lots[0]["qty"] -= q
			if lots[0]["qty"] <= EPS:
				lots.remove_at(0)
		if payer != null and payer_pays > 0.0:
			payer.gold -= payer_pays
			budget -= payer_pays
			if payer.node_ref != null:
				payer.node_ref.show_gold_delta(-payer_pays)
		history.record(good, MarketHistory.Kind.DEAL, price)
		RunRecorder.record_trade(good, q)
		taken += q
		cost += portion
		want -= q
	if taken > 0.0:
		owner.community_stock[good] = stock - taken
	return {"taken": taken, "cost": cost}


## Credits the lot owner (producer) with the sale proceeds and records the price/time
## of sale (resets time_since_last_sale → break-even drops). Ownerless lots
## (owner < 0) or an owner that no longer exists flow to the crown. Returns the
## resolved producer (or null for crown remainder), so the caller can apply the subsidy
## without looking up the inhabitant a second time (hot purchase loop).
func _credit_lot_owner(owner_id: int, unit_price: float, amount: float):
	if owner_id < 0:
		if amount > 0.0:
			GlobalInventory.add_gold(amount)
		return null
	var seller = GameState.get_inhabitant(owner_id)
	if seller == null:
		if amount > 0.0:
			GlobalInventory.add_gold(amount)
		return null
	if amount > 0.0:
		seller.gold += amount
		seller.last_sale_unit_price = unit_price
		seller.time_since_last_sale = 0.0
		if seller.node_ref != null:
			seller.node_ref.show_gold_delta(amount)
	return seller


## M26: applies the Town Hall subsidy/tariff to a producer sale. Positive = subsidy:
## the crown pays the producer extra per unit out of the global gold pool
## (GlobalInventory), capped by its balance. Negative = tariff: the crown deducts from the
## producer per unit (at most their available gold) and collects it. Ownerless
## crown remainder (seller == null) is excluded – only real producers are subsidized/taxed.
## `rate` (= BuildingManager.get_subsidy(good)) is fetched by the caller ONCE per purchase
## upfront, instead of scanning the Town Hall again per unit in the hot purchase loop.
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


## A producer's desired price (reservation price): break-even × (1+margin), clamped to
## [support price, sell price]. Never below the support price (the crown guarantees it anyway),
## never above the sell price – unless the support price exceeds it, then the support price applies.
func _seller_offer_price(good: int, seller) -> float:
	var bid := crown_bid(good)
	var high := maxf(crown_ask(good), bid)
	if seller == null:
		return high
	SimulationManager.recompute_break_even(seller)
	var desired: float = seller.break_even_unit * (1.0 + seller.margin * SimulationManager.MARGIN_SCALE)
	return clampf(desired, bid, high)


## Inserts a producer lot (sorted ascending; same price + same owner
## are merged, to keep the lot list small).
func _add_lot(good: int, price: float, qty: float, owner_id: int) -> void:
	if qty <= 0.0:
		return
	var lots: Array = _lots.get(good, [])
	for lot in lots:
		if lot["owner"] == owner_id and absf(lot["price"] - price) <= EPS:
			lot["qty"] += qty
			return
	var i := 0
	while i < lots.size() and lots[i]["price"] < price - EPS:
		i += 1
	lots.insert(i, {"price": price, "qty": qty, "owner": owner_id, "age": 0.0})
	_lots[good] = lots


## This good's crown remainder: the part of community_stock NOT covered by producer
## lots (starting stock, loaded save game, bought-up backstop purchases). Public for
## telemetry (GlobalInventory.get_crown_total → RunRecorder column "crown remainder").
func crown_remainder(good: int) -> float:
	_sync(good)
	var stock: float = owner.community_stock.get(good, 0.0) if owner != null else 0.0
	return maxf(0.0, stock - _lot_total(good))


func _lot_total(good: int) -> float:
	var total := 0.0
	for lot in _lots.get(good, []):
		total += lot["qty"]
	return total


func _sort_lots(good: int) -> void:
	var lots: Array = _lots.get(good, [])
	lots.sort_custom(func(a, b): return a["price"] < b["price"])


## Keeps the sum of producer lots ≤ community_stock. Needed because goods can also leave
## outside the exchange (withdraw_community fallbacks). Excess is trimmed from the most
## expensive lots first, so more cheaply offered goods expire last.
func _sync(good: int) -> void:
	var lots: Array = _lots.get(good, [])
	if lots.is_empty():
		return
	var stock: float = owner.community_stock.get(good, 0.0) if owner != null else 0.0
	var excess := _lot_total(good) - stock
	while excess > EPS and not lots.is_empty():
		var last: Dictionary = lots[lots.size() - 1]
		if last["qty"] <= excess + EPS:
			excess -= last["qty"]
			lots.remove_at(lots.size() - 1)
		else:
			last["qty"] -= excess
			excess = 0.0


## Market tick (called by MarketManager every MARKET_TICK_INTERVAL): (1) price drift – every
## unsold producer lot gets cheaper, down to MIN_OFFER_PRICE (even below
## break-even). (2) crown support price – lots that have dropped to the purchase price (Buy
## Price) are bought from the producer by the crown out of the treasury.
func tick() -> void:
	for good in goods:
		_sync(good)
		# Advance the support-price step line – even without lots, so the line keeps
		# running when the player adjusts the slider on empty storage.
		history.record_bid(good, crown_bid(good))
		var lots: Array = _lots.get(good, [])
		if lots.is_empty():
			continue
		var drop := DRIFT_PER_SEC * MarketManager.MARKET_TICK_INTERVAL
		for lot in lots:
			lot["age"] += MarketManager.MARKET_TICK_INTERVAL
			lot["price"] = maxf(MIN_OFFER_PRICE, lot["price"] - drop)
		_sort_lots(good)
		_run_crown_backstop(good)


## Crown support price: buys every lot whose price has dropped to ≤ Buy Price from the
## producer at the Buy Price (immediate payment from the treasury). The goods remain in
## community_stock and thereby become crown remainder. With an empty treasury only as much
## is bought up as the gold allows – the rest keeps drifting (the producer bears the loss).
func _run_crown_backstop(good: int) -> void:
	var bid := crown_bid(good)
	if bid <= 0.0:
		return  # no support price set → no buy-ups, goods drift toward 0
	var sub_rate := BuildingManager.get_subsidy(good)  # M26: once per backstop run (perf)
	var lots: Array = _lots.get(good, [])
	while not lots.is_empty():
		var lot: Dictionary = lots[0]
		if lot["price"] > bid + EPS:
			break  # sorted ascending – everything from here is pricier than the support price
		if GlobalInventory.gold <= 0.0:
			break
		var affordable := minf(lot["qty"], GlobalInventory.gold / bid)
		if affordable <= EPS:
			break
		var payout := affordable * bid
		if not GlobalInventory.spend_gold(payout):
			break
		history.record(good, MarketHistory.Kind.DEAL, bid)
		RunRecorder.record_trade(good, affordable)
		var seller = _credit_lot_owner(lot["owner"], bid, payout)
		_apply_subsidy(seller, affordable, sub_rate)  # M26
		lot["qty"] -= affordable
		if lot["qty"] <= EPS:
			lots.remove_at(0)
		# The goods stay in community_stock (now crown remainder) and get sold at crown_ask.
