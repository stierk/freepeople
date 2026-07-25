extends Node

## M27: TARGET_FOOD raised from 20 to 80. A turbo test run showed: with the old, low
## target, urgency (_urgency) for BAKER stayed near 0 as long as the stock (which rests on
## an initial cushion for a long time) stayed above 20 – the profession only got picked once
## the stock was nearly exhausted (too late: building a bakery + accumulating flour takes several
## days of lead time that were then missing). A higher target makes BAKER attractive much earlier.
## M27: raised further from 80 to 120 – a series of turbo test runs (identical code,
## only different random starting conditions) still showed variance in how early the
## BAKER profession becomes attractive enough to be staffed stably; a higher target shifts the
## urgency threshold even earlier, before the food buffer becomes critical.
const TARGET_FOOD := 120.0
const TARGET_GRAIN := 15.0
const TARGET_FLOUR := 15.0
const TARGET_WOOD := 10.0
const TARGET_PLANKS := 10.0
const TARGET_STONE := 10.0

## M31: stock target per good (mirrors the per-profession TARGET_* above), so a profitability
## check can tell whether a good is currently scarce (needed) vs. glutted. See is_good_scarce().
const GOOD_TARGETS := {
	Goods.GoodType.GRAIN: TARGET_GRAIN,
	Goods.GoodType.WOOD: TARGET_WOOD,
	Goods.GoodType.STONE: TARGET_STONE,
	Goods.GoodType.FLOUR: TARGET_FLOUR,
	Goods.GoodType.FOOD: TARGET_FOOD,
	Goods.GoodType.PLANKS: TARGET_PLANKS,
}

const RANDOM_TIEBREAK := 0.15

## M31: profession scoring is now ADDITIVE (appeal = scarcity + profit + baseline) instead of the
## old multiplicative `urgency × price`. The old formula was a hard gate: a good sitting at/above
## its target had urgency 0, so `score = 0 × price = 0` — no price/subsidy could ever wake a
## non-scarce profession, and with WOOD/STONE starting far above target every one of the initial
## colonists picked FARMER (the only scarce good, GRAIN). The additive form lets a raised Sell
## price contribute even when the good isn't scarce, and a small idle baseline plus a per-worker
## crowding penalty spreads surplus labor across professions instead of piling onto one.
const PROFIT_WEIGHT := 0.5    # gentle: an above-base Sell price/subsidy lifts a profession, scarcity still leads
const IDLE_BASELINE := 0.15   # floor every available profession keeps at 0 scarcity so surplus labor can spread
const CROWD_WEIGHT := 0.5     # per-existing-worker penalty (~halves a profession's appeal every 2 workers)

## M29: the hunter competes with the baker for the same food urgency signal (both
## produce FOOD). This factor slightly dampens the hunter's weight so the reliable food chain
## (farmer→miller→baker) stays preferred at equal scarcity and hunting complements it instead
## of displacing it. Early in the game (no bakery yet) the hunter is still the obvious
## food source, because BAKER isn't a candidate at all then.
const HUNT_FOOD_WEIGHT := 0.8

## M31: GRAIN is only useful once a mill consumes it (farmer→miller→baker). Before any WINDMILL
## exists, farming is premature: raw grain has no consumer and sells to the crown for less than the
## FOOD a farmer must buy, so a settlement of pure grain-farmers bankrupts itself while nobody
## produces food. This factor damps FARMER appeal until a mill stands, so early labor flows to food
## producers (hunter needs only forest). It is NOT zero — a few farmers still spawn, build farmer
## huts, and thereby let millers (and then a windmill) be recruited, which lifts the damping and
## lets farming scale up once grain actually has demand.
const FARMER_NO_CHAIN_FACTOR := 0.35


func assign_profession_for_new_inhabitant() -> InhabitantData.Profession:
	return pick_best_profession(InhabitantData.Profession.NONE)


## M20: chooses the most lucrative scarce profession (urgency × price weight). `exclude`
## skips a profession (e.g. the current one during a market-driven job switch).
func pick_best_profession(exclude: InhabitantData.Profession = InhabitantData.Profession.NONE) -> InhabitantData.Profession:
	var storage := BuildingManager.get_storage_yard()
	var granary := BuildingManager.get_granary()

	var wood: float = storage.community_stock.get(Goods.GoodType.WOOD, 0.0)
	var planks: float = storage.community_stock.get(Goods.GoodType.PLANKS, 0.0)
	var stone: float = storage.community_stock.get(Goods.GoodType.STONE, 0.0)
	var food: float = granary.community_stock.get(Goods.GoodType.FOOD, 0.0)
	var grain: float = granary.community_stock.get(Goods.GoodType.GRAIN, 0.0)
	var flour: float = granary.community_stock.get(Goods.GoodType.FLOUR, 0.0)

	# Food chain: farmer harvests grain → miller grinds flour → baker bakes food.
	# Miller/baker are recruited as soon as their input good accrues OR the previous stage
	# is actually producing (an occupied farmer/mill). This way the chain doesn't break when
	# the input buffer briefly drops to 0, but no idle mills/bakeries still spring up
	# without any previous stage at all.
	# M31: damp FARMER until grain has a downstream consumer (a WINDMILL/mill exists), so the
	# settlement doesn't start as pure grain-farmers producing an intermediate nobody eats.
	var farmer_appeal := _appeal(grain, TARGET_GRAIN, Goods.GoodType.GRAIN)
	if not BuildingManager.has_building_of_type(BuildingDef.BuildingType.WINDMILL):
		farmer_appeal *= FARMER_NO_CHAIN_FACTOR
	var candidates := {
		InhabitantData.Profession.FARMER: farmer_appeal,
		InhabitantData.Profession.WOODCUTTER: _appeal(wood, TARGET_WOOD, Goods.GoodType.WOOD),
		InhabitantData.Profession.QUARRY_WORKER: _appeal(stone, TARGET_STONE, Goods.GoodType.STONE),
	}
	# M27: has_building_of_type() instead of has_active_producer() – the latter requires a hut
	# occupied at EXACTLY this instant, which was a timing problem with frequent profession
	# switches (farm house briefly unoccupied → miller/baker dropped completely out of the
	# candidate list even though the chain itself existed). has_building_of_type() is satisfied
	# by a hut built at any point.
	if grain > 0.0 or BuildingManager.has_building_of_type(BuildingDef.BuildingType.FARMER_HUT):
		candidates[InhabitantData.Profession.MILLER] = _appeal(flour, TARGET_FLOUR, Goods.GoodType.FLOUR)
	if flour > 0.0 or BuildingManager.has_building_of_type(BuildingDef.BuildingType.WINDMILL):
		candidates[InhabitantData.Profession.BAKER] = _appeal(food, TARGET_FOOD, Goods.GoodType.FOOD)
	# Without a real storage yard, sawmills would get built around the Town Hall via its
	# fallback – not intended. Only assign once a storage yard stands.
	if BuildingManager.has_storage_yard():
		candidates[InhabitantData.Profession.SAWMILL_WORKER] = _appeal(planks, TARGET_PLANKS, Goods.GoodType.PLANKS)
	# M29: the hunter covers the same food need as the baker but needs no previous chain –
	# just forest. Only recruit if there is forest to hunt (otherwise they'd sit idle permanently).
	if WorldGrid.has_forest():
		candidates[InhabitantData.Profession.HUNTER] = _appeal(food, TARGET_FOOD, Goods.GoodType.FOOD) * HUNT_FOOD_WEIGHT

	candidates.erase(exclude)

	# M31: crowding penalty — divide each profession's appeal by how many inhabitants already hold
	# it, so every additional colonist finds a crowded profession less attractive and the next-best
	# one wins. This is what spreads the roster instead of everyone piling onto the single top score.
	# The excluded profession (a job-switcher's current one) was already erased above, so a switcher
	# is never penalized by the job it is leaving.
	var counts := GameState.count_by_profession()

	var best := InhabitantData.Profession.WOODCUTTER
	var best_score := -1.0
	for profession: InhabitantData.Profession in candidates:
		var crowding: float = 1.0 / (1.0 + CROWD_WEIGHT * float(counts.get(profession, 0)))
		var score: float = candidates[profession] * crowding + randf() * RANDOM_TIEBREAK
		if score > best_score:
			best_score = score
			best = profession
	return best


## M31: additive appeal of a profession = scarcity + weighted profit + idle baseline.
## `profit` is how far the effective (Sell) price + subsidy sits ABOVE the good's base price, so a
## raised price/subsidy lifts a profession even when its stock is comfortable (0 scarcity). The
## idle baseline keeps every available profession slightly attractive so the crowding penalty in
## pick_best_profession can divert surplus labor onto otherwise-idle productive work.
func _appeal(current: float, target: float, good: int) -> float:
	var profit: float = maxf(0.0, _price_weight(good) - 1.0)
	return _urgency(current, target) + PROFIT_WEIGHT * profit + IDLE_BASELINE


func _urgency(current: float, target: float) -> float:
	return maxf(0.0, target - current) / target


## M31: is this good currently below its stock target (scarce / actively needed)? Used to keep a
## producer of a scarce good from abandoning their post on a drifted price signal – a food
## producer must not quit during a food shortage (that caused a death-spiral oscillation where
## hunters flipped to an idle baker role and food production collapsed). See
## SimulationManager._check_market_profitability.
func is_good_scarce(good: int) -> bool:
	var target: float = GOOD_TARGETS.get(good, 0.0)
	if target <= 0.0:
		return false
	return _stock_of(good) < target


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
