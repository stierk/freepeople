class_name ReservationPricing
extends RefCounted

## M36: where a villager's order enters the order book, and how far it may give way.
##
## Deliberately free of any crown price
## ------------------------------------
## Nothing in here reads `crown_bid` / `crown_ask`. A villager prices from what they
## themselves know: what they last sold for, what they last paid for food, what their hut's
## recipe turns an input into, and what is in their purse.
##
## That independence is load-bearing, not tidiness. The crown must be able to withdraw from a
## good entirely (docs/BACKLOG.md #4 — a price of "X"), and if villager prices were derived
## from the crown's, withdrawing would leave no price at all. Here it simply removes the
## crown's two standing orders from the book and the remaining villagers keep trading.
##
## The band still exists — it just emerges from MATCHING rather than from these formulas. A
## seller drifting down crosses the crown's standing BUY order at `crown_bid` and is taken
## there; a buyer drifting up runs into the crown's SELL order at `crown_ask`. No formula has
## to know about either edge for that to work.
##
## Opening price vs. walk-away price
## ---------------------------------
## Up to M35 `break_even × (1 + margin)` WAS the asking price, clamped into the crown's band.
## That is what made the market degenerate: `break_even_unit` is
## `cost_of_living × time_since_last_sale` (SimulationManager.recompute_break_even) and
## `time_since_last_sale` resets on every sale, so an actively selling producer's break-even
## sits near 0. As an opening ask that means giving goods away; the clamp hid it by pulling
## him up onto `crown_bid`, exactly where the crown bought him out instantly.
##
## M36 keeps both ingredients — break-even and greed — but reads them as the WALK-AWAY point,
## the way haggling works: you open from what the market last paid you, and your cost is where
## you stop. This also makes the drift self-limiting without a tuning constant: an unsold
## order's `break_even_unit` keeps RISING with `time_since_last_sale` while its price drifts
## DOWN, so the two converge and the concession ends on its own.
##
## The constants of a pricing rule belong to the rule, not to SimulationManager — same reason
## the M35 profession strategies keep their own tuning (see CLAUDE.md, Conventions).

## How far above their remembered price a seller opens. Together with BUY_THRIFT this spans
## the room the two sides have to walk toward each other. It resembles the crown's default
## spread (TradeData.DEFAULT_ASK_FACTOR) on purpose — comparable width makes for a market that
## clears — but it is NOT derived from it: this is haggling behaviour, that is policy.
static var SELL_OPTIMISM: float = Tuning.f("SELL_OPTIMISM", 2.106)
## How far below their remembered price a buyer opens. Mirror of SELL_OPTIMISM.
static var BUY_THRIFT: float = Tuning.f("BUY_THRIFT", 0.4968)
## Multiple of the remembered food price a starving villager will climb to before stopping.
## A ceiling of "their entire purse" is what produced the nonsensical demand readings in the
## M25 price chart (`payer.gold / want`); hunger should make someone pay well over the odds,
## not bid their whole fortune for one meal.
static var HUNGER_CEILING: float = Tuning.f("HUNGER_CEILING", 6.618)
## Floor under every derived value. Keeps a degenerate valuation (an output good priced at 0, a
## recipe with a nonsensical input_amount) from producing a negative bid.
const MIN_VALUE := 0.0


# ---------------------------------------------------------------------------
# The anchor
# ---------------------------------------------------------------------------
#
# Every price below is a multiple of ONE number: `anchor`, the price the market has recently
# been paying for the good (MarketExchange.market_anchor → MarketHistory.recent_deal_price).
# The caller supplies it; nothing in here reads it off an inhabitant.
#
# That is a correction, not a preference. The first M36 version anchored a seller on their own
# `last_sale_unit_price` and opened a fixed multiple above it, which is a feedback loop: sell at
# 2.0 → open at 2.6 → fill → open at 3.38. In a 300-day run one inhabitant spiralled up to 58%
# of all the gold in the settlement while everyone else sat at 2 gold and starved. A shared,
# observed market price cannot be ratcheted by a single participant.
#
# It stays free of crown prices in the sense that matters: it is built from deals that actually
# happened. If the crown withdraws from a good (docs/BACKLOG.md #4) only villager deals remain in
# the chronicle and the anchor keeps working.

## Greed as a multiplier: raises what a seller asks, lowers what a buyer opens with.
## `margin` is [0,1] (inhabitant_data.gd), scaled by the existing MARGIN_SCALE so the M20
## tuning keeps its meaning.
static func _greed_up(inh: InhabitantData) -> float:
	if inh == null:
		return 1.0
	return 1.0 + inh.margin * SimulationManager.MARGIN_SCALE


static func _greed_down(inh: InhabitantData) -> float:
	if inh == null:
		return 1.0
	return maxf(0.0, 1.0 - inh.margin * SimulationManager.MARGIN_SCALE)


# ---------------------------------------------------------------------------
# Sell side
# ---------------------------------------------------------------------------

## Lowest price a producer will come down to.
##
## Deliberately zero — the same MIN_OFFER_PRICE the M20 consignment model drifted lots to: an
## offer nobody takes ends in a total loss, and the crown's standing bid (if the player set one)
## catches it on the way down long before that.
##
## The first M36 attempt put `break_even × greed` here instead, reasoning that a seller's cost is
## where they walk away. That deadlocks the market, and the 5-seed sweep showed it plainly
## (population 7.2 → ~0.5 at IDENTICAL crown prices, 10-13 of 12 inhabitants starved): the ask
## drifts DOWN while `break_even_unit` — which is `cost_of_living × time_since_last_sale` — drifts
## UP. Once the rising floor passes the crown's bid the two never meet, so the order can never
## clear, and the producer starves sitting on goods nobody is allowed to buy. A floor that grows
## the longer you fail to sell has the sign of desperation backwards.
static func seller_floor(_seller: InhabitantData) -> float:
	return 0.0


## Price a producer's SELL order enters the book at: above what the market last paid them, marked
## up by greed — or their accumulated cost of waiting, if that is higher.
##
## This is where break-even belongs. A producer who has not sold in a long time opens HIGH
## (they have more to recover) and then gives way like everyone else; one who sells constantly
## opens near their remembered price. Same field, same formula as M35, but as the opening ask
## rather than the walk-away point, so it can never block clearing.
static func seller_open(seller: InhabitantData, anchor: float) -> float:
	var open := anchor * _greed_up(seller) * SELL_OPTIMISM
	if seller == null:
		return open
	SimulationManager.recompute_break_even(seller)
	return maxf(open, seller.break_even_unit * _greed_up(seller))


# ---------------------------------------------------------------------------
# Buy side — food
# ---------------------------------------------------------------------------

## Highest price a hungry villager will climb to: a multiple of what food has recently been
## going for, hard-capped by what they actually own. Deliberately no valuation term — hunger
## overrides price sensitivity, and a tighter ceiling would let someone starve with gold in hand.
static func food_ceiling(buyer: InhabitantData, anchor: float) -> float:
	var ceiling := anchor * HUNGER_CEILING
	if buyer == null:
		return ceiling
	return minf(ceiling, buyer.gold)


## Price a food BUY order enters the book at: below the going rate, greedier villagers trying
## harder for a bargain. Never above their own ceiling (a near-broke buyer opens at whatever
## they can afford).
static func food_open(buyer: InhabitantData, anchor: float) -> float:
	var open := anchor * _greed_down(buyer) * BUY_THRIFT
	return minf(open, food_ceiling(buyer, anchor))


# ---------------------------------------------------------------------------
# Buy side — raw material (derived demand)
# ---------------------------------------------------------------------------

## What one unit of the hut's input good is worth to this producer: the value of what it turns
## into, scaled by the recipe ratio (`building_def.gd` carries a single input→output step).
##
## The output's value is what the OUTPUT good currently fetches on the market
## (BuildingManager.get_market_price), not what this particular miller last got for flour. Same
## reason as the sell-side anchor: pricing your input off your own last output price compounds.
static func input_value(hut: BuildingInstance) -> float:
	if hut == null or hut.def == null or hut.def.output_good < 0 or hut.def.input_amount <= 0.0:
		return 0.0
	var output_value: float = BuildingManager.get_market_price(hut.def.output_good)
	return maxf(MIN_VALUE, (output_value * hut.def.output_amount) / hut.def.input_amount)


## Highest price this producer will pay for raw material: what the finished good is worth to
## them, less the margin they want to keep, capped by their purse. A hut that cannot turn the
## input into more value simply stops bidding — a legitimate outcome here, unlike with food.
static func input_ceiling(buyer: InhabitantData, hut: BuildingInstance) -> float:
	var ceiling := input_value(hut) * _greed_down(buyer)
	if buyer == null:
		return ceiling
	return minf(ceiling, buyer.gold)


## Price a raw-material BUY order enters the book at: a fraction of what the input is worth to
## them, so there is room to be outbid and to climb. Never above their own ceiling.
static func input_open(buyer: InhabitantData, hut: BuildingInstance) -> float:
	var ceiling := input_ceiling(buyer, hut)
	return minf(input_value(hut) * BUY_THRIFT, ceiling)


# ---------------------------------------------------------------------------
# Buy side — building material and repairs
# ---------------------------------------------------------------------------

## Opening bid for goods with no recipe and no hunger behind them: building material, repairs.
## Same shape as `food_open` without the hunger term — below the going rate, greedier villagers
## trying harder for a bargain, never above the ceiling the caller passes in.
##
## These purchases had no opening price at all before: the buyer's ceiling was simply their whole
## purse (`MarketExchange._buyer_ceiling`), capped at the till by M31's `_willingness_to_pay`.
## That is still what they PAY — this is only the number that expresses what they are asking for,
## so the chart's demand series can show bids rather than walk-away points.
static func material_open(buyer: InhabitantData, anchor: float, ceiling: float) -> float:
	return minf(anchor * _greed_down(buyer) * BUY_THRIFT, ceiling)
