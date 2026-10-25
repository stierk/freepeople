class_name UrgencyStrategy
extends ProfessionStrategy

## M35: the M34 demand-relative algorithm, moved out of EconomyManager unchanged. This is the
## default strategy and the benchmark baseline — its behaviour must stay byte-identical to the
## pre-extraction build, so treat edits here as a NEW strategy rather than a tweak to this one.
##
## M34: the fixed TARGET_* stock levels are gone. Measuring "instantaneous stock vs. a constant"
## was wrong in BOTH directions and produced the observed roster freeze:
##   - GRAIN/FLOUR are intermediates. Whether their stock is 0 or 500 says nothing about whether
##     anyone needs more — a mill eating grain as fast as it arrives looks identical to no farmers
##     at all.
##   - FOOD sat at 1150 against TARGET_FOOD = 120, so `scarce_FOOD` read 0 on every row of a
##     60-day run while the stock drained 1138 → 221 with zero domestic production. A large pile
##     with no producers is not abundance.
## Urgency is now demand-relative: how far short of actual demand production is running
## (flow), and how many days of cover the stock represents (cover). See urgency_of().

## How many days of consumption the stock should cover before a good counts as comfortable.
var TARGET_COVER_DAYS: float = Tuning.f("TARGET_COVER_DAYS", 3.317)
## Weight of the flow term. Below 1.0 so a pure production deficit tops out short of 1.0 and an
## imminent stock-out (the cover term) can still outrank it.
var FLOW_WEIGHT: float = Tuning.f("FLOW_WEIGHT", 0.6794)
## Absolute floor buffer for goods with intrinsic terminal demand, used only while measured and
## installed demand are still ~0 (world start). Deliberately NOT applied to pure intermediates:
## giving GRAIN/FLOUR a constant fallback target is exactly what pinned FARMER/MILLER at urgency
## 1.0 with an empty buffer nobody was waiting on.
## Tuning keys: TERMINAL_MIN_BUFFER.WOOD / .STONE / .FOOD.
var TERMINAL_MIN_BUFFER: Dictionary = {
	Goods.GoodType.WOOD: Tuning.f("TERMINAL_MIN_BUFFER.WOOD", 10.17),
	Goods.GoodType.STONE: Tuning.f("TERMINAL_MIN_BUFFER.STONE", 16.55),
	Goods.GoodType.FOOD: Tuning.f("TERMINAL_MIN_BUFFER.FOOD", 44.5),
}
## An input good inherits this share of its downstream good's urgency, so the food chain staffs
## itself back-to-front from real end-product scarcity while the direct producer of the scarce
## good always stays strictly more attractive.
var CHAIN_PROPAGATION: float = Tuning.f("CHAIN_PROPAGATION", 0.4657)
const DOWNSTREAM_GOOD := {
	Goods.GoodType.GRAIN: Goods.GoodType.FLOUR,
	Goods.GoodType.FLOUR: Goods.GoodType.FOOD,
}
## Above this urgency a good counts as genuinely scarce (is_good_scarce → the retention guard in
## SimulationManager._check_market_profitability). Deliberately between "merely derived interest"
## (a chain-propagated 0.7 × 0.8 = 0.56, then 0.39 two stages up) and "own flow deficit"
## (FLOW_WEIGHT = 0.8), so the guard protects a producer whose good is actually in deficit and
## never one whose good is only fashionable upstream.
var SCARCE_URGENCY_THRESHOLD: float = Tuning.f("SCARCE_URGENCY_THRESHOLD", 0.6458)
## Over how many game days an unfinished building's outstanding material cost is spread when it is
## counted as demand. Longer = construction competes less with the food chain for labour. Tuned by
## sweep at --turbo-seed=42; see _installed_demand_rate.
var BUILD_DEMAND_DAYS: float = Tuning.f("BUILD_DEMAND_DAYS", 2.724)

var RANDOM_TIEBREAK: float = Tuning.f("RANDOM_TIEBREAK", 0.2693)

## M31: profession scoring is now ADDITIVE (appeal = scarcity + profit + baseline) instead of the
## old multiplicative `urgency × price`. The old formula was a hard gate: a good sitting at/above
## its target had urgency 0, so `score = 0 × price = 0` — no price/subsidy could ever wake a
## non-scarce profession, and with WOOD/STONE starting far above target every one of the initial
## colonists picked FARMER (the only scarce good, GRAIN). The additive form lets a raised Sell
## price contribute even when the good isn't scarce, and a small idle baseline plus a per-worker
## crowding penalty spreads surplus labor across professions instead of piling onto one.
var PROFIT_WEIGHT: float = Tuning.f("PROFIT_WEIGHT", 0.6511)    # gentle: an above-base Sell price/subsidy lifts a profession, scarcity still leads
var IDLE_BASELINE: float = Tuning.f("IDLE_BASELINE", 0.2089)   # floor every available profession keeps at 0 scarcity so surplus labor can spread
var CROWD_WEIGHT: float = Tuning.f("CROWD_WEIGHT", 0.3455)     # per-existing-worker penalty (~halves a profession's appeal every 2 workers)

## M29: the hunter competes with the baker for the same food urgency signal (both
## produce FOOD). This factor slightly dampens the hunter's weight so the reliable food chain
## (farmer→miller→baker) stays preferred at equal scarcity and hunting complements it instead
## of displacing it. Early in the game (no bakery yet) the hunter is still the obvious
## food source, because BAKER isn't a candidate at all then.
## M34: applied to the URGENCY term only, no longer to the whole appeal. Multiplying the whole
## appeal also shrank IDLE_BASELINE to 0.12, which made HUNTER the only profession whose floor sat
## BELOW the 0.15 RANDOM_TIEBREAK — a lottery it was rigged to lose (measured: 0 hunters in 41
## days, appeal_HUNTER 0.080 vs 0.150 for everyone else). The intent was always "at equal food
## scarcity prefer the reliable chain", i.e. a scarcity tilt, not a floor penalty.
var HUNT_FOOD_WEIGHT: float = Tuning.f("HUNT_FOOD_WEIGHT", 0.6927)

## Meals per game day == DAY_LENGTH_SECONDS / FOOD_CONSUMPTION_INTERVAL. Day length itself lives on
## EconomyManager, which needs it for the flow ring too.
var MEALS_PER_DAY: float = Tuning.f("MEALS_PER_DAY", 3.103)
## Below this a demand rate counts as "no demand at all" rather than a division by ~zero.
const FLOW_EPS := 0.01

## M31: GRAIN is only useful once a mill consumes it (farmer→miller→baker). Before any WINDMILL
## exists, farming is premature: raw grain has no consumer and sells to the crown for less than the
## FOOD a farmer must buy, so a settlement of pure grain-farmers bankrupts itself while nobody
## produces food.
## M34: the explicit FARMER_NO_CHAIN_FACTOR is gone. demand_rate(GRAIN) is 0 while no windmill is
## constructed, so grain's own urgency is already 0 and FARMER is left with only the chain-
## propagated share of FLOUR/FOOD urgency — the same damping, but continuous and self-lifting as
## mills appear, instead of a hard constant. Keeping both would have double-damped farming and
## re-broken the chain the way M27 describes.


func strategy_name() -> String:
	return "urgency"


func assign_profession_for_new_inhabitant() -> InhabitantData.Profession:
	return pick_best_profession(InhabitantData.Profession.NONE)


## M20/M31: chooses the most attractive profession — the crowding-adjusted appeal from
## profession_scores() plus a small random tie-break. `exclude` skips a profession (e.g. the
## current one during a market-driven job switch).
func pick_best_profession(exclude: InhabitantData.Profession = InhabitantData.Profession.NONE) -> InhabitantData.Profession:
	var scores := profession_scores(exclude)
	var best := InhabitantData.Profession.WOODCUTTER
	var best_score := -1.0
	for profession: InhabitantData.Profession in scores:
		var score: float = scores[profession] + randf() * RANDOM_TIEBREAK
		if score > best_score:
			best_score = score
			best = profession
	return best


## M34: crowding-adjusted appeal per eligible profession, split out of pick_best_profession.
## DELIBERATELY DETERMINISTIC — no RANDOM_TIEBREAK here — so a caller can read the pure economic
## signal without consuming RNG and shifting a seeded run. Used by pick_best_profession, by
## RunRecorder's appeal_* columns, and by the cross-trade reuse gate in
## SimulationManager._handle_seeking_site.
func profession_scores(exclude: InhabitantData.Profession = InhabitantData.Profession.NONE) -> Dictionary:
	var granary := BuildingManager.get_granary()
	var grain: float = granary.community_stock.get(Goods.GoodType.GRAIN, 0.0)
	var flour: float = granary.community_stock.get(Goods.GoodType.FLOUR, 0.0)

	# Food chain: farmer harvests grain → miller grinds flour → baker bakes food.
	# Miller/baker are recruited as soon as their input good accrues OR the previous stage
	# is actually producing (an occupied farmer/mill). This way the chain doesn't break when
	# the input buffer briefly drops to 0, but no idle mills/bakeries still spring up
	# without any previous stage at all.
	var candidates := {
		InhabitantData.Profession.FARMER: _appeal(Goods.GoodType.GRAIN),
		InhabitantData.Profession.WOODCUTTER: _appeal(Goods.GoodType.WOOD),
		InhabitantData.Profession.QUARRY_WORKER: _appeal(Goods.GoodType.STONE),
	}
	# M27: has_building_of_type() instead of has_active_producer() – the latter requires a hut
	# occupied at EXACTLY this instant, which was a timing problem with frequent profession
	# switches (farm house briefly unoccupied → miller/baker dropped completely out of the
	# candidate list even though the chain itself existed). has_building_of_type() is satisfied
	# by a hut built at any point.
	if grain > 0.0 or BuildingManager.has_building_of_type(BuildingDef.BuildingType.FARMER_HUT):
		candidates[InhabitantData.Profession.MILLER] = _appeal(Goods.GoodType.FLOUR)
	if flour > 0.0 or BuildingManager.has_building_of_type(BuildingDef.BuildingType.WINDMILL):
		candidates[InhabitantData.Profession.BAKER] = _appeal(Goods.GoodType.FOOD)
	# Without a real storage yard, sawmills would get built around the Town Hall via its
	# fallback – not intended. Only assign once a storage yard stands.
	if BuildingManager.has_storage_yard():
		candidates[InhabitantData.Profession.SAWMILL_WORKER] = _appeal(Goods.GoodType.PLANKS)
	# M29: the hunter covers the same food need as the baker but needs no previous chain –
	# just forest. Only recruit if there is forest to hunt (otherwise they'd sit idle permanently).
	if WorldGrid.has_forest():
		candidates[InhabitantData.Profession.HUNTER] = _appeal(Goods.GoodType.FOOD, HUNT_FOOD_WEIGHT)

	candidates.erase(exclude)

	# M31: crowding penalty — divide each profession's appeal by how many inhabitants already hold
	# it, so every additional colonist finds a crowded profession less attractive and the next-best
	# one wins. This is what spreads the roster instead of everyone piling onto the single top score.
	# The excluded profession (a job-switcher's current one) was already erased above, so a switcher
	# is never penalized by the job it is leaving.
	var counts := GameState.count_by_profession()
	var scores: Dictionary = {}
	for profession: InhabitantData.Profession in candidates:
		var crowding: float = 1.0 / (1.0 + CROWD_WEIGHT * float(counts.get(profession, 0)))
		scores[profession] = candidates[profession] * crowding
	return scores


## M31: additive appeal of a profession = scarcity + weighted profit + idle baseline.
## `profit` is how far the effective (Sell) price + subsidy sits ABOVE the good's base price, so a
## raised price/subsidy lifts a profession even when its stock is comfortable (0 scarcity). The
## idle baseline keeps every available profession slightly attractive so the crowding penalty in
## pick_best_profession can divert surplus labor onto otherwise-idle productive work.
## M34: `urgency_scale` weights the scarcity term only (see HUNT_FOOD_WEIGHT) – never the profit
## term or the idle baseline, so a scaled profession keeps the same floor as everyone else.
func _appeal(good: int, urgency_scale: float = 1.0) -> float:
	var profit: float = maxf(0.0, _price_weight(good) - 1.0)
	return urgency_scale * urgency_of(good) + PROFIT_WEIGHT * profit + IDLE_BASELINE


## M34: how badly the settlement needs more of this good, in [0,1]. Two independent signals:
##   flow_gap  – how far production is running short of actual demand. This is what makes a
##               1150-food pile with zero domestic food production read as a deficit rather than
##               as abundance.
##   cover_gap – how far the stock is below TARGET_COVER_DAYS of that demand, i.e. an imminent
##               stock-out even while production keeps up.
## Combined as a probabilistic OR so either alone can raise urgency and the result stays in [0,1].
## An intermediate additionally inherits a damped share of its downstream good's urgency, so the
## chain staffs itself back-to-front from real end-product scarcity — damped by how well this stage
## is already stocked, so once grain covers the installed mills the bottleneck has demonstrably
## moved downstream and FARMER stops being recruited even while FOOD is still scarce.
func urgency_of(good: int) -> float:
	var demand := demand_rate(good)
	var stock := _stock_of(good)
	var flow_gap := 0.0
	var cover_gap := 0.0
	if demand > FLOW_EPS:
		flow_gap = clampf((demand - EconomyManager.supply_rate(good)) / demand, 0.0, 1.0)
		cover_gap = clampf(1.0 - (stock / demand) / TARGET_COVER_DAYS, 0.0, 1.0)
	elif TERMINAL_MIN_BUFFER.has(good):
		# No measurable demand yet (world start): fall back to an absolute floor buffer, but only
		# for goods that are consumed as an end product. Intermediates get nothing here on purpose.
		cover_gap = clampf(1.0 - stock / float(TERMINAL_MIN_BUFFER[good]), 0.0, 1.0)
	var weighted: float = FLOW_WEIGHT * flow_gap
	var own: float = weighted + (1.0 - weighted) * cover_gap
	if DOWNSTREAM_GOOD.has(good):
		var derived: float = CHAIN_PROPAGATION * urgency_of(DOWNSTREAM_GOOD[good]) \
			* (1.0 - _cover_ratio(good))
		own = maxf(own, derived)
	return clampf(own, 0.0, 1.0)


## Days of cover the current stock represents, normalised against TARGET_COVER_DAYS. 0 when there
## is no demand at all (nothing to cover).
func _cover_ratio(good: int) -> float:
	var demand := demand_rate(good)
	if demand <= FLOW_EPS:
		return 0.0
	return clampf((_stock_of(good) / demand) / TARGET_COVER_DAYS, 0.0, 1.0)


## Units per game day the settlement wants: the larger of its INSTALLED consuming capacity
## (analytic — a starved mill still declares its appetite, so this is never circular) and its
## recent MEASURED consumption (which is what catches lumpy construction draw on wood/stone).
func demand_rate(good: int) -> float:
	return maxf(_installed_demand_rate(good), EconomyManager.measured_consumption_rate(good))


## Consuming capacity currently standing in the settlement, per game day. Uses is_constructed
## rather than occupancy for the same reason M27 switched to has_building_of_type: occupancy at
## this exact frame flickers with every profession switch.
func _installed_demand_rate(good: int) -> float:
	var per_day := 0.0
	if good == Goods.GoodType.FOOD:
		# Eating. Deliberately excludes births (M37: the parents' food is discretionary); it is booked
		# as measured consumption instead, see SimulationManager._give_birth.
		for inh: InhabitantData in GameState.inhabitants:
			per_day += SimulationManager.FOOD_PER_INHABITANT_PER_TICK \
				* inh.food_need_multiplier() * MEALS_PER_DAY
	for b: BuildingInstance in BuildingManager.buildings:
		if b.def == null:
			continue
		if not b.is_constructed:
			# M34: build materials still owed by an unfinished site or a ruin. This has to be
			# counted analytically, exactly like a starved mill's appetite: construction demand
			# only shows up as MEASURED consumption once someone can actually afford to buy the
			# material, so a settlement too poor to build reads as having no demand for wood or
			# stone at all — which then starves the woodcutter/quarry professions and guarantees
			# the builds keep failing. Amortised over the cover window rather than booked at once,
			# so a burst of sites does not pin the material goods at maximum urgency.
			per_day += float(b.pending_build_cost.get(good, 0.0)) / BUILD_DEMAND_DAYS
			continue
		if b.def.input_good != good or b.def.output_interval <= 0.0:
			continue
		per_day += b.def.input_amount * EconomyManager.DAY_SECONDS / b.def.output_interval
	return per_day


## M31/M34: is this good genuinely in deficit? Used to keep a producer of a scarce good from
## abandoning their post on a drifted price signal – a food producer must not quit during a food
## shortage (that caused a death-spiral oscillation where hunters flipped to an idle baker role and
## food production collapsed). See SimulationManager._check_market_profitability.
## M34: now reads the same urgency signal the recruiting side uses, so pull and hold can no longer
## disagree. The old fixed-target version was structurally asymmetric: GRAIN/FLOUR sat below their
## target often enough that FARMER/MILLER were effectively unfireable, while FOOD at 1150 was never
## below its target so BAKER/HUNTER had no protection at all.
func is_good_scarce(good: int) -> bool:
	return urgency_of(good) >= SCARCE_URGENCY_THRESHOLD


## Current community stock of a good, from the same storage split pick_best_profession uses
## (yard for wood/planks/stone, granary for food/grain/flour; both fall back to the Town Hall).
func _stock_of(good: int) -> float:
	match good:
		Goods.GoodType.WOOD, Goods.GoodType.PLANKS, Goods.GoodType.STONE:
			return BuildingManager.get_storage_yard().community_stock.get(good, 0.0)
		_:
			return BuildingManager.get_granary().community_stock.get(good, 0.0)


func _price_weight(good: int) -> float:
	var base: float = Goods.BASE_PRICES.get(good, 1.0)
	if base <= 0.0:
		return 1.0
	# M20: current market price incl. subsidy/tariff steers profession choice.
	var effective: float = BuildingManager.get_market_price(good) + BuildingManager.get_subsidy(good)
	return maxf(0.0, effective) / base
