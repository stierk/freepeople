extends Node

enum SpeedMode { PAUSED, NORMAL, FAST, FASTEST }
const SPEED_MULTIPLIERS := {
	SpeedMode.PAUSED: 0.0,
	SpeedMode.NORMAL: 1.0,
	SpeedMode.FAST: 2.0,
	SpeedMode.FASTEST: 5.0,
}

# --- Production constants (M7) ---
const RESOURCE_SEARCH_RADIUS := 6
const RESOURCE_DEPLETION_PER_HARVEST := 0.1
const PRODUCTION_RETRY_DELAY := 1.0

# --- Terrain regeneration ---
const RESOURCE_REGEN_INTERVAL := 5.0
const RESOURCE_REGEN_AMOUNT := 0.05
const RESOURCE_REGEN_CHANCE := 0.3

# --- Tree regrowth (random, exponential with the number of neighboring trees) ---
## Base chance per regen tick that a new tree spontaneously grows on a free grass
## cell (near 0, but not 0). Per adjacent tree the chance rises by
## factor TREE_SPREAD_GROWTH (exponentially), capped at TREE_SPREAD_MAX_CHANCE.
## On occupied cells (building, path, wheat, farmland) the chance is 0.
const TREE_SPREAD_BASE_CHANCE := 0.0001
const TREE_SPREAD_GROWTH := 3.0
const TREE_SPREAD_MAX_CHANCE := 0.25

# --- Debug logging ---
const DEBUG_LOG_INTERVAL := 15.0

# --- M17/M18: day length (1 day = 60s real time at normal speed) ---
const DAY_LENGTH_SECONDS := 60.0

# --- On-site resource harvesting (woodcutter/quarry worker) ---
## Felling a tree takes half a day; it yields 8 wood (= 8 planks
## at the sawmill). The felled tree disappears and can regrow later.
const WOOD_CUT_TIME := DAY_LENGTH_SECONDS * 0.5
# A felled tree yields a full 10 wood. This exceeds one carry load, so the woodcutter
# hauls it home in intervals: whatever fits in the inventory rides along, the rest is
# credited straight to the hut's woodpile (see _handle_gathering) – no wood is ever lost.
const WOOD_PER_TREE := 10.0
## Mining stone takes a quarter day; the rock remains and regenerates.
const STONE_MINE_TIME := DAY_LENGTH_SECONDS * 0.25
const STONE_PER_MINE := 3.0
const STONE_DEPLETION_PER_MINE := 0.34

# --- M19: wheat / farming ---
## Radius (in cells) around a farm house that counts as farmland.
const FARM_FIELD_RADIUS := 3
## Seconds per growth stage (STAGE_1 → STAGE_2 → STAGE_3). 1 day per stage
## (= DAY_LENGTH_SECONDS), so ~3 days until ripe.
const CROP_GROW_INTERVAL := 60.0
## Ripe wheat (STAGE_3) that goes unharvested for 10 days withers. The wide
## harvest window gives a single farmer time to harvest their whole field before
## ripe cells wither unharvested.
const CROP_RIPE_LIFETIME := DAY_LENGTH_SECONDS * 10.0
## Withered wheat disappears after one more day.
const CROP_DEAD_LIFETIME := DAY_LENGTH_SECONDS
## Wheat is updated once per second (not every frame).
const CROP_UPDATE_INTERVAL := 1.0
## Food harvest yield per ripe field.
const CROP_HARVEST_YIELD := 1.0

# --- M29: hunting (hunter) ---
## The hunter walks to a forest cell and hunts prey there. Unlike the woodcutter, they don't
## fell a tree – they only "consume" the cell's prey: after being hunted, the cell is
## prey-free for HUNT_REPLENISH_DAYS days (last_hunted_day stamp on the tile). This
## makes multiple hunters in the same forest block each other.
## X = chance that a fresh (not recently hunted) forest cell contains prey.
const HUNT_SUCCESS_CHANCE := 0.1
## Y = days until a hunted forest cell can carry prey again.
const HUNT_REPLENISH_DAYS := 4
## Hunting duration on-site – shorter than felling a tree (WOOD_CUT_TIME = half a day),
## so a successful hunt feels like "easy food".
const HUNT_TIME := DAY_LENGTH_SECONDS * 0.33
## Food per successful catch at best-case yield (frugality trait = 0.0). With X = 0.1 this
## averages to ~0.5 FOOD per hunting attempt – hunting is a marginal supplement to the farm
## chain; with many hunters the mutual blocking pushes the yield down further.
const FOOD_PER_CATCH := 5.0
## Guaranteed floor of every successful catch – NOT scaled by yield_multiplier(), so a hunter
## always brings back at least this much prey regardless of frugality. Only the remainder
## (FOOD_PER_CATCH - HUNT_FOOD_BASE) shrinks with the frugality yield drawback.
const HUNT_FOOD_BASE := 3.0
## M32: a hunter roams from forest cell to forest cell within one trip, rolling for prey at
## each, until the carry load is full or this many cells have been worked (bounds bad-luck
## trips). Roaming outward from the hut expands the chance of catching prey per outing.
const HUNT_CELLS_PER_TRIP := 5

# --- M8/M18: market + food + population ---
## M18: base need per inhabitant and meal (before the trait multiplier, see
## InhabitantData.food_need_multiplier); 3 meals per day (DAY_LENGTH_SECONDS/3).
## M28: lowered from 1.0 to 0.7 – a carried food stock therefore lasts ~43% longer,
## buy-food trips (and thus downtime + gold need) become noticeably rarer, without
## touching the meal cadence or the hunger/starvation thresholds themselves.
## M35: halved again (0.7 -> 0.35). Everyone eats half as much per meal; the per-inhabitant
## trait spread is untouched, because every consumer multiplies this base with
## InhabitantData.food_need_multiplier() (frugality/speed) before using it.
const FOOD_PER_INHABITANT_PER_TICK := 0.35
const FOOD_CONSUMPTION_INTERVAL := DAY_LENGTH_SECONDS / 3.0
## M22: how little carried food triggers a working inhabitant, at the free decision point
## (target selector in _handle_working), to start a buy-food trip. > 1 meal provides a
## safety cushion so they don't starve on the way to the granary.
const FOOD_RESTOCK_THRESHOLD := 2.0
## Population cap. M37: births are the only growth (the granary-stock growth of M8/M27 is gone).
const POP_MAX := 32

# --- M37: staggered start, houses, sleep, births ---------------------------------------------
## The Town Hall releases the starting colonists one by one instead of all at once, so the player
## can react to each newcomer's job choice with prices before the next one arrives.
const INITIAL_INHABITANT_COUNT := 10
const INITIAL_SPAWN_INTERVAL := 30.0
## Everyone sleeps once per day: at home if they have a house, otherwise rough on the spot
## (InhabitantData.ROUGH_SLEEP_WORK_FACTOR until the next night at home).
const REST_INTERVAL := DAY_LENGTH_SECONDS
const SLEEP_SECONDS := 10.0

# --- M38: going inside buildings -------------------------------------------------------------
## Sim seconds a visitor spends "inside" a storage/market/hut after arriving, hidden by the view.
const VISIT_DWELL_SECONDS := 0.4
const VISIT_STATES := [
	InhabitantData.State.DELIVERING,
	InhabitantData.State.MARKET_TRIP,
	InhabitantData.State.FETCHING_INPUT,
	InhabitantData.State.FETCHING_MATERIALS,
]
## Meals' worth of food carried from the pantry on top of FOOD_RESTOCK_THRESHOLD – so a full
## lunchbox lasts about a day before the next food run home.
const LUNCHBOX_MEALS := 3.0
## Housing decision: a free bed must cut the commute to this fraction to be worth moving...
const HOUSE_MOVE_RATIO := 0.7
## ...and building a new house must save at least this many cells of commute (Manhattan, see
## _commute) – and the builder must hold this multiple of its material cost in gold.
const HOUSE_MIN_SAVING := 8.0
const HOUSE_BUILD_GOLD_FACTOR := 1.2
## How far from the workplace a new house may go (cells, square scan).
const HOUSE_SITE_RADIUS := 8
## Births: two housemates asleep at home, both fed and solvent, each giving food and gold.
const BIRTH_MIN_GOLD := 30.0
const BIRTH_FOOD_EACH := 3.0
const BIRTH_PURSE_FRACTION := 0.2
const BIRTH_COOLDOWN_DAYS := 10
const BIRTH_TRAIT_MUTATION := 0.1
const TITHE_SALE_INTERVAL := 30.0
## M18: after this many consecutive missed meals (= 1 day "starved" + 1 more
## missed meal) an inhabitant starves to death.
const STARVATION_DEATH_MEALS := 4

# --- M20: market economy ---
## Markup factor on the break-even price: reservation = break_even × (1 + margin × MARGIN_SCALE).
const MARGIN_SCALE := 0.5
## M27: raised from 3 to 5 – turbo test runs showed persistent oscillation between professions
## (mainly FARMER↔MILLER↔QUARRY_WORKER) every few weeks, which never gave the food chain
## (farmer→mill→bakery) enough uninterrupted time to establish itself before the next switch
## broke it again. More patience per profession before it's abandoned as unprofitable.
## Number of consecutive unprofitable sales after which an inhabitant switches profession.
const UNPROFITABLE_SWITCH_STREAK := 5
## M28: greed drawback – a greedy inhabitant (high `margin`) overpays on food purchases by
## up to this fraction of the purchase value (the markup flows to the crown treasury). Mirrors
## the benefit (higher sell price, see market_exchange.gd) with a drawback.
const GREED_BUY_PREMIUM_SCALE := 0.25
## A2: if a producer carries their goods undelivered for longer than this time (no
## sales for that long), they deliver a partial load too, instead of waiting for a full carry
## load. Catches the non-hungry farmer who never makes a food trip and would
## otherwise sit on a partial load forever.
const STALE_INVENTORY_SECONDS := DAY_LENGTH_SECONDS

# --- M21/M22: building maintenance (repair) --------------------------------------
## Every REPAIR_INTERVAL_DAYS days a work hut becomes due for repair. An inhabitant of the
## hut then fetches building material from storage (purchase = payment on the spot) and brings it to the hut.
## If that doesn't happen within another REPAIR_GRACE_DAYS days (no material/nobody there),
## it falls derelict and disappears. During the grace period it gets a brown/grey
## color tint (analogous to starving inhabitants).
const REPAIR_INTERVAL_DAYS := 10
const REPAIR_GRACE_DAYS := 10
## A ruin nobody has started restoring is removed this many days after falling derelict.
const RUIN_LIFETIME_DAYS := 10
## M22: repair material cost = this fraction of the build cost (per good, min 1 unit).
const REPAIR_MATERIAL_FRACTION := 0.5
## Only these (occupied) work huts are subject to repair; infrastructure without
## inhabitants (roads, storage, granary, treasury, town hall) is exempt.
const REPAIRABLE_BUILDING_TYPES := [
	BuildingDef.BuildingType.WOODCUTTER_HUT,
	BuildingDef.BuildingType.SAWMILL_HUT,
	BuildingDef.BuildingType.QUARRY_HUT,
	BuildingDef.BuildingType.FARMER_HUT,
	BuildingDef.BuildingType.WINDMILL,
	BuildingDef.BuildingType.BAKERY,
	BuildingDef.BuildingType.HUNTER_HUT,  # M29
	BuildingDef.BuildingType.HOUSE,  # M37: repaired by its richest occupant
]

## M23: scoring bonus (in "site score" units ≈ path cells) with which a fresh
## inhabitant weighs reusing an existing hut against building new. A finished,
## merely empty hut saves the entire build cost → very high bonus (almost always
## preferred). A derelict ruin costs the same building materials as a new build → only a
## moderate bonus (saves build space/prevents sprawl), so a clearly better new
## site still wins.
const REUSE_BONUS_EMPTY := 1000.0
const REUSE_BONUS_DERELICT := 6.0

## M34: how close to the best available appeal another trade must score before its vacant hut may
## capture a colonist. REUSE_BONUS_EMPTY (1000) is compared against score_site values in the
## -5..-60 range, so ANY reclaimable hut always won on score, and _reassign_to_hut_profession then
## overwrote the profession pick_best_profession had just chosen. Measured at --turbo-seed=42:
## appeal_FARMER fell to 0.011 - the LOWEST of every profession - while 8 farmers persisted for the
## whole 60-day run and only 1 job change happened, i.e. the score already said "stop farming" and
## the reclaim silently ignored it. The saved build cost is real, so reuse stays; it just no longer
## outranks the economy. HIGHER = stricter: the threshold is `best_appeal * ratio`, so raising it
## admits fewer trades, which means more profession diversity but more huts left to fall derelict.
const CROSS_TRADE_REUSE_RATIO := 0.6

## Minimum spacing (sim seconds) between two expensive idle searches by the same
## inhabitant (site search, resource/field scan). Without this throttle the
## scans ran every frame as long as an inhabitant found nothing to do – the main bottleneck.
const IDLE_RETRY_INTERVAL := 0.75

## M33: consecutive failed resource searches (woodcutter/quarry worker) before giving up on the
## current spot and forcing a profession switch, bypassing the scarcity guard in
## _check_market_profitability (a good with zero deliveries reads as permanently "scarce",
## which would otherwise block try_switch_unprofitable forever – see _handle_gatherer_working).
## Deliberately real-time bound like IDLE_RETRY_INTERVAL itself (~160 × 0.75s ≈ 2 real minutes),
## not sim-time, so a stuck inhabitant gets unstuck within a bounded wall-clock wait regardless
## of game speed.
const RESOURCE_STALL_RETRIES := 160

## Sim seconds without build progress (no material delivered, build timer stalls), after
## which a stuck build is aborted: the hut remains standing as a reclaimable ruin,
## the inhabitant picks a new profession. Prevents someone from being stuck in the
## build phase forever and starving in the process. Deliberately > a typical build time, so a
## legitimately slow build (often interrupted for food) isn't falsely aborted.
const BUILD_STALL_TIMEOUT := DAY_LENGTH_SECONDS * 0.75

## M31: personal price ceiling (willingness to pay) for building/repair material and profession
## raw material. Starts at the market's fair price (crown_ask) and rises toward the buyer's full
## wealth the longer they wait without progress (build_stall_timer / input_wait_timer), reaching
## full wealth after RESOURCE_PATIENCE_SECONDS (personally paced by resilience/diligence, see
## _resource_patience_seconds). Deliberately shorter than BUILD_STALL_TIMEOUT, so an inhabitant
## has reached full willingness before a stalled build/repair aborts. No fallback beyond that:
## if the ceiling (capped at current gold) still can't afford the cheapest lot, the purchase
## simply fails and the inhabitant keeps waiting – that scarcity is the intended difficulty.
## Base 0.3 day, max factor 1.4 (full resilience, no diligence) → worst case 25.2s, still well
## below BUILD_STALL_TIMEOUT's 45s so even the most patient inhabitant reaches full willingness
## before a stall abort.
const RESOURCE_PATIENCE_SECONDS := DAY_LENGTH_SECONDS * 0.3
const RESILIENCE_PATIENCE_BONUS_MAX := 0.4      # +40% patience at full resilience
const DILIGENCE_IMPATIENCE_PENALTY_MAX := 0.4   # -40% patience at full diligence (wants material NOW)

## Market trade: from this stock amount onward a good counts as "surplus" and is sold
const MARKET_SURPLUS_THRESHOLD := {
	Goods.GoodType.WOOD: 30.0,
	Goods.GoodType.PLANKS: 30.0,
	Goods.GoodType.STONE: 30.0,
}
const MARKET_SELL_FRACTION := 0.2
const MARKET_FOOD_IMPORT_SHARE := 0.5

const BUILDING_TYPE_TO_TERRAIN := {
	BuildingDef.BuildingType.WOODCUTTER_HUT: TileRuntimeData.TerrainType.FOREST,
	BuildingDef.BuildingType.QUARRY_HUT: TileRuntimeData.TerrainType.STONE,
}

const PROFESSION_TO_GOOD := {
	InhabitantData.Profession.WOODCUTTER: Goods.GoodType.WOOD,
	InhabitantData.Profession.SAWMILL_WORKER: Goods.GoodType.PLANKS,
	InhabitantData.Profession.QUARRY_WORKER: Goods.GoodType.STONE,
	InhabitantData.Profession.FARMER: Goods.GoodType.GRAIN,
	InhabitantData.Profession.MILLER: Goods.GoodType.FLOUR,
	InhabitantData.Profession.BAKER: Goods.GoodType.FOOD,
	InhabitantData.Profession.HUNTER: Goods.GoodType.FOOD,  # M29: hunter delivers prey as FOOD
}

## Which terrain type is harvested on-site by which profession (woodcutter → forest,
## quarry worker → stone). These professions no longer produce passively in the hut, but
## walk to the resource, harvest it, and carry it back to the hut.
const PROFESSION_TO_TERRAIN := {
	InhabitantData.Profession.WOODCUTTER: TileRuntimeData.TerrainType.FOREST,
	InhabitantData.Profession.QUARRY_WORKER: TileRuntimeData.TerrainType.STONE,
}

var speed_mode: SpeedMode = SpeedMode.NORMAL
var sim_time: float = 0.0

var _resource_regen_accum: float = 0.0
var _debug_log_accum: float = 0.0
var _food_consumption_accum: float = 0.0
## M37: starting colonists released so far (saved; see INITIAL_SPAWN_INTERVAL).
var initial_spawned: int = 0
var _initial_spawn_accum: float = 0.0
var _market_tick_accum: float = 0.0
var _daily_tax_accum: float = 0.0
var _crop_accum: float = 0.0
## Beat for the RunRecorder's KPI time series (one sample per RECORD_SAMPLE_INTERVAL).
var _record_accum: float = 0.0

## Sim seconds between two KPI snapshots (RunRecorder). A game day is a good
## compromise between resolution and file size for long runs.
const RECORD_SAMPLE_INTERVAL := DAY_LENGTH_SECONDS

# --- Debug performance profiling (temporary, for bottleneck hunting) ---
## Set to true to measure the time per simulation phase every frame and print ~1x/s
## as avg microseconds/frame (in the output log). Will be removed once the
## optimization goals are settled. At false there is practically no extra overhead.
const DEBUG_PERF := false
var _perf_usec: Dictionary = {}
var _perf_frames: int = 0
var _perf_real_accum: float = 0.0
## Summed up per frame from Inhabitant._process (rendering/node cost of the inhabitants).
var _perf_inhabitant_usec: int = 0
## The most recent perf lines, additionally written to a file (user://perf.log),
## in case the output panel isn't visible.
var _perf_log: PackedStringArray = []
const PERF_LOG_PATH := "user://perf.log"

# --- Debug diagnostic "waiting at the Town Hall & starving" (temporary) ---
## Set to true to write a snapshot of all hungry inhabitants to
## user://starve.log about once per second (state, resume_state, home, gold, carried food,
## decision results). Clarifies whether someone with money simply doesn't GO shopping
## (state deadlock) or the market is simply empty. At false, practically free.
const DEBUG_STARVE := false
const STARVE_LOG_PATH := "user://starve.log"
var _starve_accum: float = 0.0
var _starve_log: PackedStringArray = []
var _starve_log_path_printed: bool = false


## Adds the time elapsed since `from_usec` to the phase and returns the current
## clock, so calls can be chained. Nearly free when DEBUG_PERF is off.
func _perf(phase: String, from_usec: int) -> int:
	var now := Time.get_ticks_usec()
	if DEBUG_PERF:
		_perf_usec[phase] = _perf_usec.get(phase, 0) + (now - from_usec)
	return now


## Called by Inhabitant._process to attribute its cost to the perf report.
func report_inhabitant_process_usec(usec: int) -> void:
	if DEBUG_PERF:
		_perf_inhabitant_usec += usec


func _print_perf() -> void:
	var frames: int = maxi(_perf_frames, 1)
	var total := _perf_inhabitant_usec
	var parts: Array = []
	for k in _perf_usec:
		total += int(_perf_usec[k])
		parts.append("%s=%.0f" % [k, float(_perf_usec[k]) / frames])
	parts.append("inhabitant_node=%.0f" % (float(_perf_inhabitant_usec) / frames))
	var line := "[PERF] avg µs/Frame (%d Frames, Pop=%d): %s | Σ=%.0f" % [
		frames, GameState.inhabitants.size(), ", ".join(parts), float(total) / frames]
	print(line)

	# Also write to a file, so the values stay readable even without a visible
	# output panel. Print the absolute path on the first call.
	if _perf_log.is_empty():
		print("[PERF] Log file: %s" % ProjectSettings.globalize_path(PERF_LOG_PATH))
	_perf_log.append(line)
	if _perf_log.size() > 120:  # only keep the most recent ~2 minutes
		_perf_log.remove_at(0)
	var f := FileAccess.open(PERF_LOG_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(_perf_log))
		f.close()


## Diagnostic: writes a snapshot of all hungry inhabitants (missed_meals>=1 OR
## hunger>0) to user://starve.log. For each inhabitant, state and the results of the
## buy-food decision are logged, so "waiting instead of eating" can be unambiguously
## attributed to a cause (empty market vs. state deadlock). Rolling history.
func _write_starve_log() -> void:
	var town_hall := BuildingManager.get_town_hall()
	var has_th := town_hall != null
	var th_cell: Vector2i = town_hall.cell if has_th else Vector2i(-1, -1)
	_starve_log.append("=== t=%.1f Pop=%d ===" % [sim_time, GameState.inhabitants.size()])
	for inh: InhabitantData in GameState.inhabitants:
		if inh.missed_meals < 1 and inh.hunger <= 0.0:
			continue
		var home := BuildingManager.get_building(inh.home_building_id)
		var food: float = inh.inventory.get(Goods.GoodType.FOOD, 0.0)
		var dist: int = (absi(inh.cell.x - th_cell.x) + absi(inh.cell.y - th_cell.y)) if has_th else -1
		var pick := MarketManager.pick_best_market(Goods.GoodType.FOOD, inh.cell, MarketManager.Side.BUY)
		var pick_id: int = pick.id if pick != null else -1
		var pick_stock: float = pick.community_stock.get(Goods.GoodType.FOOD, 0.0) if pick != null else 0.0
		_starve_log.append("#%d state=%s resume=%s home=%d(exists=%s) gold=%.1f food=%.1f missed=%d hunger=%.2f dTH=%d canFood=%s needRun=%s pick=%d stock=%.1f" % [
			inh.id,
			InhabitantData.State.keys()[inh.state],
			InhabitantData.State.keys()[inh.resume_state],
			inh.home_building_id, str(home != null),
			inh.gold, food, inh.missed_meals, inh.hunger, dist,
			str(_can_obtain_food(inh)), str(_needs_food_run(inh)),
			pick_id, pick_stock])
	# Only keep the most recent history (roughly the last ~minutes of activity).
	while _starve_log.size() > 3000:
		_starve_log.remove_at(0)
	if not _starve_log_path_printed:
		print("[STARVE] Log file: %s" % ProjectSettings.globalize_path(STARVE_LOG_PATH))
		_starve_log_path_printed = true
	var f := FileAccess.open(STARVE_LOG_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(_starve_log))
		f.close()


func _process(delta: float) -> void:
	var mult: float = SPEED_MULTIPLIERS[speed_mode]
	if mult == 0.0:
		return
	var sim_delta := delta * mult
	sim_time += sim_delta
	# M34: rotate the production/consumption window on SIM time, so it always spans the same
	# number of game days regardless of the speed setting.
	EconomyManager.advance_flow_clock(sim_delta)

	var t := Time.get_ticks_usec()
	_process_buildings(sim_delta)
	t = _perf("buildings", t)

	for inhabitant in GameState.inhabitants:
		_process_movement(inhabitant, sim_delta)
	t = _perf("movement", t)

	for inhabitant in GameState.inhabitants:
		# Throttle for expensive idle searches: while the timer is still running, the
		# idle handlers (site/resource/field) skip their scan this frame. Deliberately coupled
		# to the REAL frame time (delta), not sim_delta – otherwise the throttle would be
		# practically ineffective at high game speed or low FPS.
		inhabitant.idle_retry_timer -= delta
		# M22: hunger has the highest priority. Two tiers:
		#   1) Emergency (almost no food left, but money available): aborts EVERY state immediately –
		#      even the otherwise non-interruptible ones (GATHERING/DELIVERING/RETURNING/…), so
		#      nobody starves mid-way through a long work cycle despite having money. Carried
		#      goods stay in the inventory and are delivered after the purchase on the next WORKING.
		#   2) Normal: only pause interruptible activities and resume the current state.
		if inhabitant.state != InhabitantData.State.MARKET_TRIP and inhabitant.state != InhabitantData.State.GOING_HOME:
			var interruptible := _food_interruptible(inhabitant.state)
			if _needs_emergency_food(inhabitant) or (interruptible and _needs_food_run(inhabitant)):
				# Interruptible states can be resumed exactly. For aborted states
				# with a stale path (harvest/deliver/…), instead safely re-enter:
				# WORKING with a hut, otherwise site search (homeless).
				if interruptible:
					inhabitant.resume_state = inhabitant.state
				elif inhabitant.home_building_id != -1:
					inhabitant.resume_state = InhabitantData.State.WORKING
				else:
					inhabitant.resume_state = InhabitantData.State.SEEKING_SITE
				_start_food_run(inhabitant)
		# Stall guard: accumulate time in the build phase without progress. Reset to 0
		# happens on real progress (material delivered / build timer running) in the
		# handlers; if the inhabitant leaves the build phase (e.g. a food detour), it counts anew.
		if inhabitant.state == InhabitantData.State.FETCHING_MATERIALS or inhabitant.state == InhabitantData.State.BUILDING:
			inhabitant.build_stall_timer += sim_delta
		else:
			inhabitant.build_stall_timer = 0.0
		# M31: same idea as build_stall_timer, but for an input producer's raw-material trip -
		# feeds the price ceiling in _willingness_to_pay. Deliberately NOT reset when the state
		# briefly bounces to WORKING between failed purchase attempts (still waiting on the same
		# shortage) - _handle_working resets it once the hut's input buffer is replenished.
		if inhabitant.state == InhabitantData.State.FETCHING_INPUT:
			inhabitant.input_wait_timer += sim_delta
		if DEBUG_PERF:
			# Record cost per state separately (key = state name at the
			# time the handler was entered), to unambiguously find the most expensive handler.
			var _key: String = "st_" + str(InhabitantData.State.keys()[inhabitant.state])
			var _s := Time.get_ticks_usec()
			_process_inhabitant_state(inhabitant, sim_delta)
			_perf_usec[_key] = _perf_usec.get(_key, 0) + (Time.get_ticks_usec() - _s)
		else:
			_process_inhabitant_state(inhabitant, sim_delta)
		# M20: only accumulate the (cheap) time since the last sale. The
		# break-even price (break_even_unit) is NOT computed every frame,
		# only when needed: on sale, on the profitability check, and
		# when displayed in the InfoPanel (recompute_break_even).
		inhabitant.time_since_last_sale += sim_delta
		# Profession-switch check: personally paced (random × 10 days) instead of for
		# all inhabitants simultaneously once a day. Spreads the load and gives each
		# inhabitant their own "patience" before giving up an unprofitable profession.
		# M37: sleep and the daily housing decision are acted on at the free decision point in
		# _handle_working; here only their clocks run.
		inhabitant.rest_timer += sim_delta
		inhabitant.house_check_timer -= sim_delta
		inhabitant.job_check_timer -= sim_delta
		if inhabitant.job_check_timer <= 0.0:
			inhabitant.job_check_timer = _job_check_interval(inhabitant)
			_check_market_profitability(inhabitant)
	t = _perf("inhabitant_state", t)

	_crop_accum += sim_delta
	if _crop_accum >= CROP_UPDATE_INTERVAL:
		_update_crops(_crop_accum)
		_crop_accum = 0.0
	t = _perf("crops", t)

	_resource_regen_accum += sim_delta
	if _resource_regen_accum >= RESOURCE_REGEN_INTERVAL:
		_resource_regen_accum -= RESOURCE_REGEN_INTERVAL
		_regenerate_resources()
		_spread_trees()
	t = _perf("regen_trees", t)

	_food_consumption_accum += sim_delta
	if _food_consumption_accum >= FOOD_CONSUMPTION_INTERVAL:
		_food_consumption_accum -= FOOD_CONSUMPTION_INTERVAL
		_process_food_consumption()

	if initial_spawned < INITIAL_INHABITANT_COUNT:
		_initial_spawn_accum += sim_delta
		if _initial_spawn_accum >= INITIAL_SPAWN_INTERVAL:
			_initial_spawn_accum -= INITIAL_SPAWN_INTERVAL
			spawn_initial_inhabitant()

	# M20: exchange tick (pricing, seller payment, crown export) replaces the
	# old tithe/market logic.
	_market_tick_accum += sim_delta
	if _market_tick_accum >= MarketManager.MARKET_TICK_INTERVAL:
		_market_tick_accum -= MarketManager.MARKET_TICK_INTERVAL
		MarketManager.tick()

	_daily_tax_accum += sim_delta
	if _daily_tax_accum >= DAY_LENGTH_SECONDS:
		_daily_tax_accum -= DAY_LENGTH_SECONDS
		_process_daily_tax()
		_process_basic_income()
		_process_building_maintenance()

	# RunRecorder: periodic KPI snapshot (tier 1). The only hook point of the
	# time-series recording; cheap when RECORD_ENABLED is off (early return).
	_record_accum += sim_delta
	if _record_accum >= RECORD_SAMPLE_INTERVAL:
		_record_accum -= RECORD_SAMPLE_INTERVAL
		RunRecorder.sample_metrics()

	_debug_log_accum += sim_delta
	if _debug_log_accum >= DEBUG_LOG_INTERVAL:
		_debug_log_accum -= DEBUG_LOG_INTERVAL
		_print_stock_summary()
	t = _perf("periodic", t)

	if DEBUG_STARVE:
		_starve_accum += delta
		if _starve_accum >= 1.0:
			_starve_accum = 0.0
			_write_starve_log()

	if DEBUG_PERF:
		_perf_frames += 1
		_perf_real_accum += delta
		if _perf_real_accum >= 1.0:
			_print_perf()
			_perf_usec.clear()
			_perf_inhabitant_usec = 0
			_perf_frames = 0
			_perf_real_accum = 0.0


# ---------------------------------------------------------------------------
# M7: building production tick
# ---------------------------------------------------------------------------
func _process_buildings(delta: float) -> void:
	for building in BuildingManager.buildings:
		if not building.is_constructed:
			continue
		var def := building.def
		# Woodcutter and quarry huts no longer produce passively – their
		# inhabitants harvest wood/stone on-site (see _handle_gatherer_working).
		if def.type == BuildingDef.BuildingType.WOODCUTTER_HUT or def.type == BuildingDef.BuildingType.QUARRY_HUT:
			continue
		if def.output_interval <= 0.0 or def.output_good < 0:
			continue

		# M21: input producers consume their raw material from the hut's LOCAL buffer
		# (already bought at storage, see _handle_fetching_input). If it's empty, production
		# pauses until the inhabitant fetches more.
		if def.input_good >= 0:
			if building.community_stock.get(def.input_good, 0.0) < def.input_amount:
				continue

		var terrain_cell := Vector2i(-1, -1)
		if BUILDING_TYPE_TO_TERRAIN.has(def.type):
			var terrain: TileRuntimeData.TerrainType = BUILDING_TYPE_TO_TERRAIN[def.type]
			terrain_cell = _find_resource_cell_near(building.cell, terrain)
			if terrain_cell == Vector2i(-1, -1):
				continue

		building.production_timer -= delta
		if building.production_timer > 0.0:
			continue

		building.production_timer = def.output_interval

		if def.input_good >= 0:
			# Take from the local buffer (already paid for when bought at storage).
			building.community_stock[def.input_good] = building.community_stock.get(def.input_good, 0.0) - def.input_amount

		if terrain_cell != Vector2i(-1, -1):
			var tile := WorldGrid.get_tile(terrain_cell)
			tile.resource_amount = maxf(0.0, tile.resource_amount - RESOURCE_DEPLETION_PER_HARVEST)

		var prev: float = building.output_stock.get(def.output_good, 0.0)
		building.output_stock[def.output_good] = prev + def.output_amount

		print("[M7:Production] %s produces %.1f %s  (buffer: %.1f)" % [
			def.display_name, def.output_amount,
			Goods.GoodType.keys()[def.output_good], building.output_stock[def.output_good],
		])
		GlobalInventory.notify_resources_changed()


# ---------------------------------------------------------------------------
# M8: food consumption
# ---------------------------------------------------------------------------
func _process_food_consumption() -> void:
	var granary := BuildingManager.get_granary()
	if granary == null:
		return
	if GameState.inhabitants.is_empty():
		return

	# M21: every inhabitant eats and pays for THEIR meal out of their own budget
	# (closed loop: the bakers earn from consumption). Whoever can't pay
	# OR finds no food misses the meal → hunger/missed_meals rise.
	var starved: Array[int] = []
	for inh: InhabitantData in GameState.inhabitants:
		# M22: whoever is currently actively en route to the granary already resolves their hunger –
		# no missed meal is counted against them during this time (no starving on the
		# way to eat). The buy decision itself is made in the target selector (_handle_working).
		if inh.state == InhabitantData.State.MARKET_TRIP:
			continue
		var eaten := _feed_inhabitant(inh)
		# M28: normalize against the PERSONAL need (food_need_multiplier), not the
		# global base value – otherwise a hungrier/more frugal inhabitant would falsely
		# count as full after a partial bite (or never as full).
		var personal_need := FOOD_PER_INHABITANT_PER_TICK * inh.food_need_multiplier()
		var recovery := clampf(eaten / personal_need, 0.0, 1.0) if personal_need > 0.0 else 1.0
		if recovery >= 1.0:
			inh.hunger = maxf(0.0, inh.hunger - 0.1)
			inh.missed_meals = 0
		else:
			# M28: diligence drawback – hard workers get hungry faster when food is short.
			inh.hunger = minf(1.0, inh.hunger + (1.0 - recovery) * 0.15 * inh.hunger_gain_multiplier())
			inh.missed_meals += 1
			# M28: resilience benefit – tolerates up to RESILIENCE_HUNGER_TOLERANCE_MAX
			# extra missed meals before the inhabitant starves.
			if inh.missed_meals >= STARVATION_DEATH_MEALS + inh.starvation_meal_tolerance():
				starved.append(inh.id)

	for id in starved:
		print("[M18:Death] Inhabitant %d has starved." % id)
		var inh := GameState.get_inhabitant(id)
		if inh != null:
			RunRecorder.record_death(id, inh.profession, inh.gold, inh.state, inh.missed_meals)
		GameState.remove_inhabitant(id)

	GlobalInventory.notify_resources_changed()


## M22: feeds an inhabitant from THEIR OWN stock (inventory) and returns the amount
## eaten. NO money is moved – payment already happened when buying at the granary
## (see _handle_market_trip). This way nobody spends money in the field/workplace anymore.
func _feed_inhabitant(inh: InhabitantData) -> float:
	# M28: speed drawback raises, frugality benefit lowers the personal need.
	var need := FOOD_PER_INHABITANT_PER_TICK * inh.food_need_multiplier()
	# M37: asleep at home → the meal comes out of the pantry first.
	var from_pantry := 0.0
	if inh.state == InhabitantData.State.SLEEPING and _at_home(inh):
		from_pantry = minf(inh.pantry_food, need)
		inh.pantry_food -= from_pantry
		need -= from_pantry
	return from_pantry + _feed_from_inventory(inh, need)


func _feed_from_inventory(inh: InhabitantData, need: float) -> float:
	var have: float = inh.inventory.get(Goods.GoodType.FOOD, 0.0)
	var eaten := minf(have, need)
	if eaten <= 0.0:
		return 0.0
	var left := have - eaten
	if left > 0.0:
		inh.inventory[Goods.GoodType.FOOD] = left
	else:
		inh.inventory.erase(Goods.GoodType.FOOD)
	return eaten


# ---------------------------------------------------------------------------
# M37: staggered start – the Town Hall releases one colonist every INITIAL_SPAWN_INTERVAL
# ---------------------------------------------------------------------------
func spawn_initial_inhabitant() -> void:
	var town_hall := BuildingManager.get_town_hall()
	var spawn_cell: Vector2i = WorldGrid.MAP_SIZE / 2
	if town_hall != null:
		spawn_cell = town_hall.cell + Vector2i(1, town_hall.def.footprint_size.y)
	var inh := GameState.add_inhabitant(spawn_cell)
	inh.world_pos += Vector2(randf_range(-5.0, 5.0), randf_range(-5.0, 5.0))
	if inh.node_ref:
		inh.node_ref.position = inh.world_pos
	initial_spawned += 1
	GlobalInventory.notify_population_changed(GameState.population_count())
	print("[M37:Spawn] Colonist %d arrives (%d/%d)." % [inh.id, initial_spawned, INITIAL_INHABITANT_COUNT])


# ---------------------------------------------------------------------------
# M21: central gold booking with a floating +/- indicator over the inhabitant
# ---------------------------------------------------------------------------
## Changes an inhabitant's gold and shows the change as a floating number, so it's
## visible that the budget is really being used. Use for all bookings outside the exchange
## (tax, basic income, food fallback, repair).
func adjust_gold(inh: InhabitantData, delta: float) -> void:
	inh.gold += delta
	if inh.node_ref != null:
		inh.node_ref.show_gold_delta(delta)


# ---------------------------------------------------------------------------
# M17: daily head tax (treasury)
# ---------------------------------------------------------------------------
func _process_daily_tax() -> void:
	var tax := BuildingManager.get_daily_tax()
	if tax <= 0.0:
		return

	var total := 0.0
	for inh: InhabitantData in GameState.inhabitants:
		var pay := minf(inh.gold, tax)
		adjust_gold(inh, -pay)
		total += pay

	if total > 0.0:
		GlobalInventory.add_gold(total)
		print("[M17:Tax] %.1f gold collected in head tax." % total)
		RunRecorder.record("tax", {"total": total, "per_head": tax})


# ---------------------------------------------------------------------------
# M20: basic income / welfare (Town Hall policy)
# ---------------------------------------------------------------------------
func _process_basic_income() -> void:
	var income := BuildingManager.get_basic_income()
	if income == 0.0:
		return
	var total := 0.0
	if income > 0.0:
		for inh: InhabitantData in GameState.inhabitants:
			var pay := minf(income, GlobalInventory.gold)
			if pay <= 0.0:
				break
			GlobalInventory.spend_gold(pay)
			adjust_gold(inh, pay)
			total += pay
	else:
		var tax := -income
		var collected := 0.0
		for inh: InhabitantData in GameState.inhabitants:
			var pay := minf(inh.gold, tax)
			adjust_gold(inh, -pay)
			collected += pay
		if collected > 0.0:
			GlobalInventory.add_gold(collected)
		total -= collected
	if total > 0.0:
		print("[M20:BasicIncome] %.1f gold paid out." % total)
		RunRecorder.record("basic_income", {"total": total})
	elif total < 0.0:
		print("[M20:BasicIncome] %.1f gold collected in flat tax." % -total)
		RunRecorder.record("basic_income", {"total": total})


# ---------------------------------------------------------------------------
# M21: building maintenance – repair every 10 days, otherwise decay
# ---------------------------------------------------------------------------
## Checks all repairable work huts daily: due huts are automatically repaired from
## an inhabitant's budget. If nobody can pay, the hut tints
## (brown/grey) and falls derelict once the grace period expires (disappears).
func _process_building_maintenance() -> void:
	var day := get_current_day()
	var to_demolish: Array[BuildingInstance] = []
	var expired_ruins: Array[BuildingInstance] = []
	for b in BuildingManager.buildings:
		# Occupants on a ruin mean someone is restoring it – leave it standing.
		if b.is_derelict and b.occupants.is_empty() and day - b.derelict_since_day >= RUIN_LIFETIME_DAYS:
			expired_ruins.append(b)
			continue
		if not _is_repairable(b):
			continue
		var age := day - b.last_repaired_day
		if age < REPAIR_INTERVAL_DAYS:
			continue
		# M22: repair due – just flag it. An inhabitant of the hut fetches building
		# material from storage at the free decision point (_try_start_repair) and repairs it.
		_set_repair_state(b, true)
		if age >= REPAIR_INTERVAL_DAYS + REPAIR_GRACE_DAYS:
			to_demolish.append(b)
	for b in to_demolish:
		print("[M21:Decay] %s (ID=%d) falls derelict for lack of repair." % [b.def.display_name, b.id])
		RunRecorder.record("derelict", {
			"building_id": b.id,
			"type": BuildingDef.BuildingType.keys()[b.def.type],
			"cell": [b.cell.x, b.cell.y],
		})
		# M37: a neglected house is torn down rather than left as a ruin nobody would reclaim.
		if b.def.type == BuildingDef.BuildingType.HOUSE:
			_demolish_building(b)
		else:
			_derelict_building(b)
	for b in expired_ruins:
		print("[Decay] Ruin %s (ID=%d) has crumbled away." % [b.def.display_name, b.id])
		RunRecorder.record("ruin_removed", {
			"building_id": b.id,
			"type": BuildingDef.BuildingType.keys()[b.def.type],
			"cell": [b.cell.x, b.cell.y],
		})
		_demolish_building(b)


func _is_repairable(b: BuildingInstance) -> bool:
	return b.is_constructed and b.def.type in REPAIRABLE_BUILDING_TYPES


# ---------------------------------------------------------------------------
# M22: repair as an active errand (priority 2 in the target selector)
# ---------------------------------------------------------------------------
## Derives repair material cost from the hut's build cost: a fraction
## REPAIR_MATERIAL_FRACTION per good, minimum 1 unit. Empty if the hut has no build cost.
func _repair_material_cost(hut: BuildingInstance) -> Dictionary:
	var cost := {}
	for good in hut.def.build_cost:
		var amt: float = hut.def.build_cost[good]
		cost[good] = maxf(1.0, floor(amt * REPAIR_MATERIAL_FRACTION))
	return cost


## Attempts to start a repair errand for a due hut of one's own. Returns true
## if the inhabitant was sent off to do it (state changed).
func _try_start_repair(inh: InhabitantData, hut: BuildingInstance) -> bool:
	if not hut.needs_repair or not hut.is_constructed:
		return false
	# pending_build_cost occupied → a repair (or a build) is already running on this hut;
	# a second inhabitant shouldn't start the same repair.
	if not hut.pending_build_cost.is_empty():
		return false

	var cost := _repair_material_cost(hut)
	if cost.is_empty():
		# Hut without build material → free instant repair, then continue working normally.
		hut.last_repaired_day = get_current_day()
		_set_repair_state(hut, false)
		return false

	# Only start if the material is actually available at storage (otherwise the
	# fetch loop would run into nothing). The hut stays flagged and is retried later.
	for good in cost:
		var storage := BuildingManager.get_storage_for_good(good)
		if storage == null or storage.community_stock.get(good, 0.0) < cost[good]:
			return false

	hut.pending_build_cost = cost.duplicate()
	inh.fetch_target_good = -1
	inh.state = InhabitantData.State.FETCHING_MATERIALS
	return true


## Sets the repair need and updates the building node's tint (only on a
## state change, to avoid unnecessary tweens).
func _set_repair_state(b: BuildingInstance, needs: bool) -> void:
	if b.needs_repair == needs:
		return
	b.needs_repair = needs
	if b.node_ref != null and b.node_ref.has_method("set_repair_visual"):
		b.node_ref.set_repair_visual(needs)


## M22: lets an overdue hut FALL DERELICT instead of demolishing it. It remains standing
## as a ruin (footprint occupied, is_constructed == false) and can be restored by an
## inhabitant in exchange for building material. The previous inhabitants become homeless and look
## for a new workplace (preferring an empty/derelict hut, see _handle_seeking_site).
func _derelict_building(b: BuildingInstance) -> void:
	for occ_id in b.occupants:
		var inh := GameState.get_inhabitant(occ_id)
		if inh != null:
			inh.home_building_id = -1
			inh.path = PackedVector2Array()
			inh.path_index = 0
			inh.idle_retry_timer = 0.0
			inh.state = InhabitantData.State.SEEKING_SITE
	b.occupants.clear()
	# Repair tint off, ruin visuals on; mark as an unfinished ruin.
	_set_repair_state(b, false)
	b.is_constructed = false
	b.is_derelict = true
	b.derelict_since_day = get_current_day()
	b.output_stock.clear()  # discard running production
	# Restoring costs the full build cost and the build time (like a new build on this spot).
	b.pending_build_cost = b.def.build_cost.duplicate()
	b.construction_timer = b.def.build_time_seconds
	if b.node_ref != null and b.node_ref.has_method("set_derelict_visual"):
		b.node_ref.set_derelict_visual(true)
	GlobalInventory.notify_resources_changed()


## Aborts a stuck build (no progress since BUILD_STALL_TIMEOUT). The
## half-finished hut remains standing as a reclaimable ruin (_derelict_building sets the
## inhabitant to SEEKING_SITE anyway). The aborting inhabitant picks a NEW profession –
## maybe another trade has become more lucrative in the meantime (profession = NONE →
## in _handle_seeking_site, assign_profession_for_new_inhabitant / pick_best_profession takes over).
func _abort_stalled_build(inh: InhabitantData, hut: BuildingInstance) -> void:
	# M37: a stuck HOUSE is simply given up – no ruin, and the builder keeps their trade.
	if hut.def.type == BuildingDef.BuildingType.HOUSE:
		print("[M37:House] House %d stalled → given up by inhabitant %d." % [hut.id, inh.id])
		_demolish_building(hut)
		inh.build_stall_timer = 0.0
		return
	print("[Build:Abort] %s (ID=%d) stalled for %.0fs without progress → ruin, inhabitant %d picks a new profession." % [
		hut.def.display_name, hut.id, BUILD_STALL_TIMEOUT, inh.id])
	RunRecorder.record("build_aborted", {
		"building_id": hut.id,
		"type": BuildingDef.BuildingType.keys()[hut.def.type],
		"inhabitant_id": inh.id,
	})
	_derelict_building(hut)
	withdraw_market_orders(inh)  # M36: no standing bids for a trade they no longer practise
	inh.profession = InhabitantData.Profession.NONE
	inh.build_stall_timer = 0.0
	inh.idle_retry_timer = 0.0
	inh.state = InhabitantData.State.SEEKING_SITE


## Fully removes a derelict building: from management, the world grid, and
## the scene. Former inhabitants are released and look for a new workplace.
func _demolish_building(b: BuildingInstance) -> void:
	for occ_id in b.occupants:
		var inh := GameState.get_inhabitant(occ_id)
		if inh != null and b.def.type == BuildingDef.BuildingType.HOUSE:
			# M37: losing a house leaves them homeless, not jobless.
			# shortcut: the pantry is kept on the inhabitant and reappears in their next house; drop
			# or carry it if lost-house food should matter for balance.
			inh.house_id = -1
			if inh.build_target_id == b.id:
				inh.build_target_id = -1
				if inh.state == InhabitantData.State.FETCHING_MATERIALS or inh.state == InhabitantData.State.BUILDING:
					inh.state = InhabitantData.State.WORKING
		elif inh != null:
			inh.home_building_id = -1
			inh.path = PackedVector2Array()
			inh.path_index = 0
			inh.idle_retry_timer = 0.0
			inh.state = InhabitantData.State.SEEKING_SITE
	b.occupants.clear()
	WorldGrid.set_building_footprint_rect(b.cell, b.def.footprint_size, -1, false)
	if b.node_ref != null:
		b.node_ref.queue_free()
		b.node_ref = null
	BuildingManager.buildings.erase(b)
	GlobalInventory.notify_resources_changed()


# ---------------------------------------------------------------------------
# M31: willingness to pay for building/repair material and profession raw material
# ---------------------------------------------------------------------------
## How long (sim seconds) it takes this inhabitant's price ceiling to reach full wealth:
## resilience (patient) extends it, diligence (wants to get back to work) shortens it.
func _resource_patience_seconds(inh: InhabitantData) -> float:
	var factor := 1.0 + inh.trait_resilience * RESILIENCE_PATIENCE_BONUS_MAX \
		- inh.trait_diligence * DILIGENCE_IMPATIENCE_PENALTY_MAX
	return maxf(RESOURCE_PATIENCE_SECONDS * 0.2, RESOURCE_PATIENCE_SECONDS * factor)


## Personal price ceiling for a resource purchase (building material, repair, profession raw
## material): starts at the exchange's fair price (crown_ask) and rises toward the buyer's
## current wealth as `wait_timer` (build_stall_timer / input_wait_timer) grows, reaching full
## wealth at _resource_patience_seconds(). Always clamped to at most the buyer's own gold – a
## broke inhabitant's ceiling never climbs above what they actually have, no matter how long
## they wait, so scarcity of gold is a hard limit, not just impatience.
func _willingness_to_pay(inh: InhabitantData, exchange: MarketExchange, good: int, wait_timer: float) -> float:
	var fair := exchange.crown_ask(good)
	var t := clampf(wait_timer / _resource_patience_seconds(inh), 0.0, 1.0)
	return minf(lerpf(fair, maxf(fair, inh.gold), t), inh.gold)


# ---------------------------------------------------------------------------
# M20: break-even price & market-driven profession switching
# ---------------------------------------------------------------------------
## Computes the break-even price per unit from food consumption, the last
## price paid for food, and the time since the last sale (custom formula).
func recompute_break_even(inh: InhabitantData) -> void:
	var batch := 1.0
	var home := BuildingManager.get_building(inh.home_building_id)
	if home != null and home.def != null and home.def.carry_capacity > 0.0:
		batch = home.def.carry_capacity
	# M28: personal food need (speed/frugality) feeds into the cost of living.
	var food_rate := (FOOD_PER_INHABITANT_PER_TICK * inh.food_need_multiplier()) / FOOD_CONSUMPTION_INTERVAL
	var cost_of_living_per_s := food_rate * inh.last_food_unit_price
	inh.break_even_unit = (cost_of_living_per_s * inh.time_since_last_sale) / batch


## Personal check interval for the profession switch: random factor × 10 days. The
## factor is rolled once at spawn, so each inhabitant checks on their own
## rhythm (spreads the load and varies the "patience"). maxf guarantees a
## minimum interval, so a factor near 0 doesn't effectively check every day.
func _job_check_interval(inh: InhabitantData) -> float:
	return maxf(0.5, inh.job_check_factor * 10.0) * DAY_LENGTH_SECONDS


## M20: mark-to-market valuation of a single inhabitant (personally paced).
## If the current market price (incl. subsidy/tariff) doesn't cover the break-even price,
## their unprofitability counter rises; after UNPROFITABLE_SWITCH_STREAK consecutive
## checks they switch profession. The market price (get_market_price = cheapest offer)
## follows the price drift downward in the consignment model – a chronically oversupplied good
## thus falls below break-even and the profession self-regulates downward (a more stable,
## less erratic signal than the last realized individual price).
func _check_market_profitability(inh: InhabitantData) -> void:
	if not PROFESSION_TO_GOOD.has(inh.profession):
		return
	recompute_break_even(inh)  # only at the check, not every frame
	var good: int = PROFESSION_TO_GOOD[inh.profession]
	# M31: a producer of a currently-scarce good is needed regardless of the drifted market price –
	# don't let them abandon their post during a shortage. This stops the death-spiral oscillation
	# where a hunter, seeing FOOD prices drift down from their own oversupply, quit for an idle
	# baker role and food production then collapsed. Glutted goods (stock >= target) still switch.
	if EconomyManager.is_good_scarce(good):
		inh.unprofitable_streak = 0
		return
	var price: float = BuildingManager.get_market_price(good) + BuildingManager.get_subsidy(good)
	if price < inh.break_even_unit:
		inh.unprofitable_streak += 1
		if inh.unprofitable_streak >= UNPROFITABLE_SWITCH_STREAK:
			try_switch_unprofitable(inh)
	else:
		inh.unprofitable_streak = 0


## M36: pulls every order this inhabitant has resting in any exchange, and releases goods they
## already paid for but will never come to collect. Called whenever they change trade or lose
## their hut: a standing bid for the OLD profession's raw material would otherwise keep buying
## on their behalf forever, and the reservation would stay locked out of the market.
func withdraw_market_orders(inh: InhabitantData) -> void:
	for b: BuildingInstance in BuildingManager.buildings:
		if b.exchange != null:
			b.exchange.withdraw_all_for(inh.id)


## Market-driven switch to the most lucrative scarce profession when the work is permanently
## unprofitable.
func try_switch_unprofitable(inh: InhabitantData) -> void:
	inh.unprofitable_streak = 0
	var best := EconomyManager.pick_best_profession(inh.profession)
	if best != inh.profession and best != InhabitantData.Profession.NONE:
		withdraw_market_orders(inh)
		print("[M20:JobChange] Inhabitant %d switches from %s to %s (unprofitable)" % [
			inh.id, InhabitantData.Profession.keys()[inh.profession], InhabitantData.Profession.keys()[best]])
		RunRecorder.record("jobchange", {
			"id": inh.id,
			"from": InhabitantData.Profession.keys()[inh.profession],
			"to": InhabitantData.Profession.keys()[best],
		})
		GameState.change_profession(inh.id, best)


# ---------------------------------------------------------------------------
# M22: target selector conditions (priority 1: food)
# ---------------------------------------------------------------------------
## true if the inhabitant should restock food now: their carried stock barely
## covers one meal, there's a granary AND they have money for it. Without money
## the trip isn't worth it – better to keep working and earning.
func _needs_food_run(inh: InhabitantData) -> bool:
	if inh.inventory.get(Goods.GoodType.FOOD, 0.0) >= FOOD_RESTOCK_THRESHOLD:
		return false
	return _pantry_has_food(inh) or _can_obtain_food(inh)


## M22: emergency hunger – the carried stock barely covers the next meal. Then the
## inhabitant may abort ANY activity (even non-interruptible ones) to immediately walk to the
## granary, provided they'd actually get food there.
func _needs_emergency_food(inh: InhabitantData) -> bool:
	if inh.inventory.get(Goods.GoodType.FOOD, 0.0) > FOOD_PER_INHABITANT_PER_TICK * 0.5:
		return false
	return _pantry_has_food(inh) or _can_obtain_food(inh)


## M23: true if the inhabitant would actually get food at the granary: there's a
## granary AND they can pay for it (money available) OR it's currently free (price 0).
## Previously the trip failed outright on `gold <= 0` – this made broke inhabitants starve
## even when food was set free (see the MarketExchange pricing model).
func _can_obtain_food(inh: InhabitantData) -> bool:
	var granary := BuildingManager.get_granary()
	if granary == null:
		return false
	if inh.gold > 0.0:
		return true
	# M24: broke but carrying goods? Then they can first sell their carried goods (except food)
	# at the market and buy food with the proceeds (see _liquidate_for_food) – instead of starving despite having goods.
	if inh.non_food_count() > 0.0:
		return true
	var price: float = granary.exchange.get_price(Goods.GoodType.FOOD) if granary.exchange != null \
		else BuildingManager.get_sell_price(Goods.GoodType.FOOD)
	return price <= 0.0


## States that can safely be paused for a hunger-driven purchase and resumed afterward
## (no carried delivery goods, not mid-field-action). FETCHING_MATERIALS is
## included because an interrupted build would otherwise starve at the start (everyone building
## simultaneously) – the 1 carried unit of building material stays in the inventory and is delivered after the purchase.
func _food_interruptible(state: int) -> bool:
	return state in [
		InhabitantData.State.SEEKING_SITE,
		InhabitantData.State.MOVING_TO_BUILD,
		InhabitantData.State.FETCHING_MATERIALS,
		InhabitantData.State.BUILDING,
		InhabitantData.State.WORKING,
		InhabitantData.State.SLEEPING,  # M37
	]


## M37: a food run goes home to the pantry when it holds at least a meal, otherwise to market.
func _start_food_run(inh: InhabitantData) -> void:
	if _pantry_has_food(inh):
		_start_going_home(inh)
	else:
		_start_market_trip(inh)


func _pantry_has_food(inh: InhabitantData) -> bool:
	return inh.house_id != -1 and inh.pantry_food >= FOOD_PER_INHABITANT_PER_TICK * inh.food_need_multiplier()


# ---------------------------------------------------------------------------
# M8: start a market trip
# ---------------------------------------------------------------------------
func _start_market_trip(inhabitant: InhabitantData) -> void:
	var destination := MarketManager.pick_best_market(Goods.GoodType.FOOD, inhabitant.cell, MarketManager.Side.BUY)
	if destination == null:
		if DEBUG_STARVE:
			print("[STARVE] #%d no market target (pick_best_market==null) → no purchase" % inhabitant.id)
		return
	inhabitant.trade_target_id = destination.id
	# M36: standing bid for food, left before setting off – see _start_input_fetch. A hunter or
	# baker can fill it while the buyer is still on the road; if nobody does, the bid climbs to
	# the crown's ask and is served there, so this never delays a meal.
	if destination.exchange != null:
		destination.exchange.post_resting_buy(Goods.GoodType.FOOD,
			_food_purchase_amount(inhabitant), inhabitant, null)
	inhabitant.path = WorldGrid.find_path(inhabitant.cell, destination.cell)
	inhabitant.path_index = 0
	inhabitant.state = InhabitantData.State.MARKET_TRIP


# ---------------------------------------------------------------------------
# Movement
# ---------------------------------------------------------------------------
func _process_movement(inhabitant: InhabitantData, delta: float) -> void:
	if inhabitant.path.is_empty() or inhabitant.path_index >= inhabitant.path.size():
		return

	var target: Vector2 = inhabitant.path[inhabitant.path_index]
	var speed_mult := WorldGrid.get_speed_multiplier(inhabitant.cell)
	var speed := inhabitant.move_speed_base * speed_mult
	var to_target := target - inhabitant.world_pos
	var step := speed * delta

	if to_target.length() <= step:
		inhabitant.world_pos = target
		inhabitant.path_index += 1
		var new_cell := WorldGrid.world_to_cell(inhabitant.world_pos)
		if new_cell != inhabitant.cell:
			inhabitant.cell = new_cell
			var t := WorldGrid.get_tile(new_cell)
			# The owning farmer enters their own field without wear.
			var own_field := inhabitant.profession == InhabitantData.Profession.FARMER \
				and t.crop_field_owner == inhabitant.home_building_id
			# M32: woodcutters and hunters move through forest without wearing it down, so
			# they never trample away the forest they work in (other professions do wear it,
			# and a forest tile that turns into a path is destroyed – see register_step).
			var forest_worker := t.terrain == TileRuntimeData.TerrainType.FOREST \
				and (inhabitant.profession == InhabitantData.Profession.WOODCUTTER \
					or inhabitant.profession == InhabitantData.Profession.HUNTER)
			WorldGrid.register_step(new_cell, own_field or forest_worker)
	else:
		inhabitant.world_pos += to_target.normalized() * step

	if inhabitant.node_ref:
		inhabitant.node_ref.position = inhabitant.world_pos


# ---------------------------------------------------------------------------
# State dispatcher
# ---------------------------------------------------------------------------
func _process_inhabitant_state(inhabitant: InhabitantData, delta: float) -> void:
	# M38: a visitor lingers inside the building for a moment before the handler acts.
	if inhabitant.dwell_timer > 0.0:
		inhabitant.dwell_timer -= delta
		return
	if _path_done(inhabitant):
		if not inhabitant.dwell_paid and inhabitant.state in VISIT_STATES and _beside_building(inhabitant.cell):
			inhabitant.dwell_paid = true
			inhabitant.dwell_timer = VISIT_DWELL_SECONDS
			return
	else:
		inhabitant.dwell_paid = false
	match inhabitant.state:
		InhabitantData.State.SEEKING_SITE:
			_handle_seeking_site(inhabitant)
		InhabitantData.State.MOVING_TO_BUILD:
			_handle_moving_to_build(inhabitant)
		InhabitantData.State.FETCHING_MATERIALS:
			_handle_fetching_materials(inhabitant)
		InhabitantData.State.BUILDING:
			_handle_building(inhabitant, delta)
		InhabitantData.State.WORKING:
			_handle_working(inhabitant)
		InhabitantData.State.DELIVERING:
			_handle_delivering(inhabitant)
		InhabitantData.State.RETURNING:
			_handle_returning(inhabitant)
		InhabitantData.State.MARKET_TRIP:
			_handle_market_trip(inhabitant)
		InhabitantData.State.FARM_TENDING:
			_handle_farm_tending(inhabitant)
		InhabitantData.State.GATHERING:
			_handle_gathering(inhabitant, delta)
		InhabitantData.State.HAULING_HOME:
			_handle_hauling_home(inhabitant)
		InhabitantData.State.HUNTING:
			_handle_hunting(inhabitant, delta)
		InhabitantData.State.FETCHING_INPUT:
			_handle_fetching_input(inhabitant)
		InhabitantData.State.GOING_HOME:
			_handle_going_home(inhabitant)
		InhabitantData.State.SLEEPING:
			_handle_sleeping(inhabitant, delta)
		_:
			pass


func _handle_seeking_site(inhabitant: InhabitantData) -> void:
	# Site search (find_best_site) is expensive (map scan + several A* paths).
	# If an inhabitant finds no spot, we throttle the retry instead of searching
	# again every frame.
	if inhabitant.idle_retry_timer > 0.0:
		return

	# Already employed once? Then this inhabitant became homeless (hut fell derelict
	# or profession switched) – the cross-profession takeover below applies to them.
	var was_employed := inhabitant.profession != InhabitantData.Profession.NONE
	if inhabitant.profession == InhabitantData.Profession.NONE:
		inhabitant.profession = EconomyManager.assign_profession_for_new_inhabitant()

	# An already active, understaffed hut of one's own profession is always the first choice
	# (no build, shared workplace).
	var existing_hut := BuildingManager.get_understaffed_hut(inhabitant.profession)
	if existing_hut != null:
		_move_into_hut(inhabitant, existing_hut)
		return

	var selector := SiteSelection.new(WorldGrid, BuildingManager)

	# M22/M27: homeless inhabitants (already employed once) FIRST try to continue their
	# OWN profession (new build of their own hut type) – only once no build site can be found for
	# that do they instead take over ANY empty/derelict hut of a different trade (breaks
	# the decay/income spiral instead of staying idle forever).
	#
	# M27: order deliberately reversed (previously: reclaim first, then build). An inhabitant with
	# their OWN hut of the same profession would already have found one above (line ~984,
	# get_understaffed_hut) – if they land here, no hut of their (often freshly market-driven
	# chosen) profession exists. If reclamation unconditionally grabbed any other, usually just
	# freed-up hut first, the profession switch got immediately undone again (observed:
	# an inhabitant market-switched FARMER→MILLER, but ended up back at FARMER right away because of an
	# empty farm house – a windmill therefore never got built, the food chain
	# stayed permanently broken). An inhabitant WITHOUT a build site for their profession still
	# falls back to reclamation as before.
	if was_employed:
		var site := selector.find_best_site(inhabitant.profession)
		if site != Vector2i(-1, -1):
			_start_new_build(inhabitant, site)
			return
		# M34: prefer a hut whose trade is still economically competitive, but fall back to ANY
		# hut rather than leaving an already-homeless inhabitant idle and starving – better
		# employed in a mediocre trade than not at all (that is this branch's whole purpose).
		var reclaim := BuildingManager.get_reclaimable_hut(_reuse_allowed_types(inhabitant.profession))
		if reclaim == null:
			reclaim = BuildingManager.get_reclaimable_hut()
		if reclaim != null:
			_reassign_to_hut_profession(inhabitant, reclaim)
			_move_into_hut(inhabitant, reclaim)
			return
		if DEBUG_STARVE and inhabitant.missed_meals >= 1:
			print("[STARVE] #%d SEEKING_SITE (homeless): no build site/ruin → idle" % inhabitant.id)
		inhabitant.idle_retry_timer = IDLE_RETRY_INTERVAL
		return

	# M23: fresh inhabitants weigh their options: restore an existing empty/derelict hut OR
	# build new. Site scores are compared (same metric). Reuse gets
	# a bonus: a finished, merely empty hut saves the entire build cost → very high
	# bonus (practically always preferred); a derelict ruin costs the same building materials as
	# a new build → only a moderate bonus, so a clearly better new site still wins.
	var new_site := selector.find_best_site_scored(inhabitant.profession)
	var new_cell: Vector2i = new_site["cell"]
	var new_score: float = new_site["score"]

	# M34: only huts of a still-competitive trade may capture a fresh colonist (see
	# CROSS_TRADE_REUSE_RATIO). Without this filter the reuse bonus decided careers instead of
	# breaking ties, and a stock of farm houses recycled every new spawn into FARMER forever.
	var reuse := BuildingManager.get_reclaimable_hut(_reuse_allowed_types(inhabitant.profession))
	if reuse != null:
		var prof := BuildingManager.profession_for_building_type(reuse.def.type)
		var bonus: float = REUSE_BONUS_EMPTY if reuse.is_constructed else REUSE_BONUS_DERELICT
		var reuse_score := selector.score_site(prof, reuse.cell) + bonus
		if new_cell == Vector2i(-1, -1) or reuse_score >= new_score:
			_reassign_to_hut_profession(inhabitant, reuse)
			_move_into_hut(inhabitant, reuse)
			return

	if new_cell == Vector2i(-1, -1):
		if DEBUG_STARVE and inhabitant.missed_meals >= 1:
			print("[STARVE] #%d SEEKING_SITE (new): no build site → idle" % inhabitant.id)
		inhabitant.idle_retry_timer = IDLE_RETRY_INTERVAL
		return
	_start_new_build(inhabitant, new_cell)


## Moves an inhabitant into an existing hut (occupancy + path there).
func _move_into_hut(inhabitant: InhabitantData, hut: BuildingInstance) -> void:
	hut.occupants.append(inhabitant.id)
	inhabitant.home_building_id = hut.id
	inhabitant.path = WorldGrid.find_path(inhabitant.cell, hut.cell)
	inhabitant.path_index = 0
	inhabitant.state = InhabitantData.State.MOVING_TO_BUILD


## M34: which hut types a colonist may take over, given the profession they just picked. Taking
## over a hut rewrites the profession (_reassign_to_hut_profession), so an unfiltered search lets
## the reuse bonus overrule the economy entirely. A trade qualifies if its crowding-adjusted appeal
## is still within CROSS_TRADE_REUSE_RATIO of the best trade on offer; the colonist's own trade
## always qualifies. Reads the deterministic EconomyManager.profession_scores(), so this consumes
## no RNG and cannot shift a seeded run.
func _reuse_allowed_types(chosen: InhabitantData.Profession) -> Array:
	var scores := EconomyManager.profession_scores()
	var allowed: Array = []
	if BuildingManager.PROFESSION_TO_BUILDING_TYPE.has(chosen):
		allowed.append(BuildingManager.PROFESSION_TO_BUILDING_TYPE[chosen])
	var best := 0.0
	for profession: InhabitantData.Profession in scores:
		best = maxf(best, scores[profession])
	var threshold: float = best * CROSS_TRADE_REUSE_RATIO
	for profession: InhabitantData.Profession in scores:
		if scores[profession] < threshold:
			continue
		if not BuildingManager.PROFESSION_TO_BUILDING_TYPE.has(profession):
			continue
		var type: BuildingDef.BuildingType = BuildingManager.PROFESSION_TO_BUILDING_TYPE[profession]
		if not allowed.has(type):
			allowed.append(type)
	return allowed


## Adjusts the inhabitant's profession to the taken-over trade (if the hut is a workplace).
func _reassign_to_hut_profession(inhabitant: InhabitantData, hut: BuildingInstance) -> void:
	var prof := BuildingManager.profession_for_building_type(hut.def.type)
	if prof != InhabitantData.Profession.NONE:
		inhabitant.profession = prof


## Sends the inhabitant to a fresh build site (the new hut is registered/built there).
func _start_new_build(inhabitant: InhabitantData, cell: Vector2i) -> void:
	inhabitant.target_site_cell = cell
	inhabitant.path = WorldGrid.find_path(inhabitant.cell, cell)
	inhabitant.path_index = 0
	inhabitant.state = InhabitantData.State.MOVING_TO_BUILD


func _handle_moving_to_build(inhabitant: InhabitantData) -> void:
	if not inhabitant.path.is_empty() and inhabitant.path_index < inhabitant.path.size():
		return

	var home := BuildingManager.get_building(inhabitant.home_building_id)
	if home != null:
		if home.is_constructed:
			inhabitant.state = InhabitantData.State.WORKING
		elif not home.pending_build_cost.is_empty():
			# M22: moved into a ruin (or a new build with outstanding costs) → first fetch material and restore it.
			inhabitant.fetch_target_good = -1
			inhabitant.state = InhabitantData.State.FETCHING_MATERIALS
		else:
			inhabitant.state = InhabitantData.State.BUILDING
		return

	# Meanwhile another person for the same profession might already have registered a
	# hut (finished or under construction) with a free slot – this
	# inhabitant then moves in there instead of building their own hut next to it.
	var shared_hut := BuildingManager.get_understaffed_hut(inhabitant.profession)
	if shared_hut != null:
		shared_hut.occupants.append(inhabitant.id)
		inhabitant.home_building_id = shared_hut.id
		inhabitant.path = WorldGrid.find_path(inhabitant.cell, shared_hut.cell)
		inhabitant.path_index = 0
		return

	var building_type: BuildingDef.BuildingType = BuildingManager.PROFESSION_TO_BUILDING_TYPE[inhabitant.profession]
	var def := BuildingManager.get_building_def(building_type)

	# The previously chosen site might meanwhile have been built on by
	# someone else - then search for a new site instead of building over the existing hut.
	if not WorldGrid.is_footprint_buildable(inhabitant.target_site_cell, def.footprint_size):
		inhabitant.state = InhabitantData.State.SEEKING_SITE
		return

	var hut := BuildingManager.register_building(def, inhabitant.target_site_cell)
	hut.is_constructed = false
	hut.occupants.append(inhabitant.id)
	inhabitant.home_building_id = hut.id
	WorldGrid.set_building_footprint_rect(hut.cell, def.footprint_size, hut.id, true)
	hut.construction_timer = def.build_time_seconds
	hut.production_timer = def.output_interval
	# M35: the empty-build_cost branch is a live case, not dead code – the Woodcutter's Hut
	# has cost {} since M35 (see the milestone log): wood only ever enters the settlement
	# through a woodcutter working from a finished hut, so charging that hut 20 wood made
	# the settlement's only wood source unbuildable the moment the starting stock ran out.
	if def.build_cost.is_empty():
		inhabitant.state = InhabitantData.State.BUILDING
	else:
		hut.pending_build_cost = def.build_cost.duplicate()
		inhabitant.fetch_target_good = -1
		inhabitant.state = InhabitantData.State.FETCHING_MATERIALS


# ---------------------------------------------------------------------------
# FETCHING_MATERIALS – fetches building material batches from storage to the site
# ---------------------------------------------------------------------------
func _handle_fetching_materials(inhabitant: InhabitantData) -> void:
	if not inhabitant.path.is_empty() and inhabitant.path_index < inhabitant.path.size():
		return

	var hut := _build_site(inhabitant)
	if hut == null:
		inhabitant.state = _lost_build_site_state(inhabitant)
		return

	# Stall guard: if the build has hung without progress since BUILD_STALL_TIMEOUT (no material
	# deliverable/delivered), abort → ruin, new job choice. Prevents starving in the
	# build phase. The timer is counted up in the _process loop and zeroed here on progress.
	if inhabitant.build_stall_timer >= BUILD_STALL_TIMEOUT:
		_abort_stalled_build(inhabitant, hut)
		return

	var good := inhabitant.fetch_target_good
	if good >= 0:
		var carried: float = inhabitant.inventory.get(good, 0.0)
		if carried <= 0.0:
			# At storage: fetch a whole batch – as much as the remaining need AND free space
			# (goods_space keeps the food safety stock free) allow. Reduces the
			# number of trips considerably (e.g. farm 10+10 → 8 instead of 20 trips).
			var want := minf(hut.pending_build_cost.get(good, 0.0), inhabitant.goods_space())
			if want < 1.0:
				# No (non-food) space free? Wait until there's space again first – otherwise
				# material bought at storage would go to waste. Food is eaten continuously → space opens up.
				return
			var storage := BuildingManager.get_storage_for_good(good)
			if storage != null:
				# M20/M21: taking building material via the exchange pays the producers – out of
				# the fetching inhabitant's own budget, limited to what they're willing to pay
				# (M31: rises with build_stall_timer, capped at their gold – see
				# _willingness_to_pay). No crown fallback: too poor or too impatient simply means
				# no material this trip.
				var taken := 0.0
				if storage.exchange != null:
					var cap := _willingness_to_pay(inhabitant, storage.exchange, good, inhabitant.build_stall_timer)
					taken = storage.exchange.consume(good, want, inhabitant, cap)
				else:
					taken = storage.withdraw_community(good, want)
				if taken > 0.0:
					inhabitant.add_to_inventory(good, taken)
					inhabitant.path = WorldGrid.find_path(inhabitant.cell, hut.cell)
					inhabitant.path_index = 0
		else:
			# Arrived at build site – deposit the whole carried batch
			var needed: float = hut.pending_build_cost.get(good, 0.0)
			hut.pending_build_cost[good] = maxf(0.0, needed - carried)
			if hut.pending_build_cost[good] <= 0.0:
				hut.pending_build_cost.erase(good)
			inhabitant.inventory.erase(good)
			inhabitant.fetch_target_good = -1
			inhabitant.build_stall_timer = 0.0  # progress: material delivered
		return

	if hut.pending_build_cost.is_empty():
		# M22: all material delivered. For a new build the build phase follows; for an already
		# finished hut this was a repair errand → complete the repair.
		if not hut.is_constructed:
			inhabitant.state = InhabitantData.State.BUILDING
		else:
			hut.last_repaired_day = get_current_day()
			_set_repair_state(hut, false)
			inhabitant.build_target_id = -1
			inhabitant.state = InhabitantData.State.WORKING
		return

	# Choose next needed material and walk to the responsible storage
	good = hut.pending_build_cost.keys()[0]
	var storage := BuildingManager.get_storage_for_good(good)
	if storage == null:
		return
	inhabitant.fetch_target_good = good
	inhabitant.path = WorldGrid.find_path(inhabitant.cell, storage.cell)
	inhabitant.path_index = 0


func _handle_building(inhabitant: InhabitantData, delta: float) -> void:
	var hut := _build_site(inhabitant)
	if hut == null:
		# Fix: build site disappeared → don't access null (crash/deadlock),
		# re-enter as homeless instead.
		if DEBUG_STARVE and inhabitant.missed_meals >= 1:
			print("[STARVE] #%d BUILDING without a hut (home=%d) → SEEKING_SITE" % [inhabitant.id, inhabitant.home_building_id])
		inhabitant.state = _lost_build_site_state(inhabitant)
		return
	if hut.is_constructed:
		inhabitant.build_target_id = -1
		inhabitant.state = InhabitantData.State.WORKING
		return

	# Stall guard (analogous to FETCHING_MATERIALS): if the build is stuck without progress,
	# abbrechen → Ruine, neue Jobwahl.
	if inhabitant.build_stall_timer >= BUILD_STALL_TIMEOUT:
		_abort_stalled_build(inhabitant, hut)
		return

	if not hut.pending_build_cost.is_empty():
		return  # wait for fetcher to deliver all materials

	# M28: diligence speeds up, resilience slows down the personal work speed.
	hut.construction_timer -= delta * inhabitant.work_speed_multiplier()
	inhabitant.build_stall_timer = 0.0  # progress: build timer is actively running
	if hut.construction_timer <= 0.0:
		hut.is_constructed = true
		# M22: was this a restored ruin? Reset the marking/visuals and restart the
		# repair clock, so it doesn't immediately become due again.
		if hut.is_derelict:
			hut.is_derelict = false
			if hut.node_ref != null and hut.node_ref.has_method("set_derelict_visual"):
				hut.node_ref.set_derelict_visual(false)
		hut.last_repaired_day = get_current_day()
		BuildingManager.building_constructed.emit(hut.id)
		# M19: a finished farm house gets farmland all around it.
		if hut.def.type == BuildingDef.BuildingType.FARMER_HUT:
			WorldGrid.designate_farm_field(hut.cell, hut.def.footprint_size, hut.id, FARM_FIELD_RADIUS)
		print("[M7:Build] %s finished building (ID=%d)" % [hut.def.display_name, hut.id])
		inhabitant.build_target_id = -1
		inhabitant.state = InhabitantData.State.WORKING


func _handle_working(inhabitant: InhabitantData) -> void:
	var hut := BuildingManager.get_building(inhabitant.home_building_id)
	if hut == null:
		# Fix: hut disappeared (derelict/deleted) → do NOT wait in WORKING forever
		# (a purchase is never triggered there, the inhabitant starves on the spot).
		# Instead re-enter as homeless: looks for a hut and eats along the way.
		# Same pattern as _handle_fetching_materials / _handle_fetching_input.
		if DEBUG_STARVE and inhabitant.missed_meals >= 1:
			print("[STARVE] #%d WORKING without a hut (home=%d) → SEEKING_SITE" % [inhabitant.id, inhabitant.home_building_id])
		inhabitant.home_building_id = -1
		inhabitant.state = InhabitantData.State.SEEKING_SITE
		return

	# M22: priority target selector. Priority 1 (food) is already handled globally in the
	# _process loop (interrupts EVERY activity, not just WORKING). Priority 2 remains here:
	#   – maintenance: due repair of one's own hut (fetch material from storage)
	#   – M37: an interrupted house build/repair, sleep, the house's repair, the housing decision
	#   – otherwise: normal profession work (further below)
	if inhabitant.build_target_id != -1:
		inhabitant.state = InhabitantData.State.FETCHING_MATERIALS
		return
	if _try_start_repair(inhabitant, hut):
		return
	if _try_house_errands(inhabitant, hut):
		return

	# M19: farmers don't work passively in the hut, but plant and harvest
	# wheat on the surrounding fields.
	if inhabitant.profession == InhabitantData.Profession.FARMER:
		_handle_farmer_working(inhabitant, hut)
		return
	# M29: hunter – like a gatherer, but probabilistic loot + cell cooldown.
	if inhabitant.profession == InhabitantData.Profession.HUNTER:
		_handle_hunter_working(inhabitant, hut)
		return
	# Woodcutter/quarry worker: walk to the resource, harvest on-site, carry to the hut.
	if PROFESSION_TO_TERRAIN.has(inhabitant.profession):
		_handle_gatherer_working(inhabitant, hut)
		return
	var def := hut.def
	if def.output_good < 0:
		return

	var available: float = hut.output_stock.get(def.output_good, 0.0)
	# M22: goods_space() keeps the food reserve free, so food can be bought along the way.
	var carry := minf(minf(available, def.carry_capacity), inhabitant.goods_space())
	# M31: the hut's input buffer is fine again (or this hut has no input good) → the raw-
	# material wait is over, whether or not this particular pass has output to deliver.
	if def.input_good < 0 or hut.community_stock.get(def.input_good, 0.0) >= def.input_amount:
		inhabitant.input_wait_timer = 0.0
	if carry <= 0.0:
		# M21: nothing to deliver. Input producers (sawmill/mill/bakery) must
		# physically buy their raw material at storage when the local buffer no longer
		# suffices for a production step – then walk there, provided storage has goods.
		if def.input_good >= 0 and hut.community_stock.get(def.input_good, 0.0) < def.input_amount:
			# Choose the nearest storage with stock (not stubbornly the first), so a mill/
			# bakery also buys at a second granary instead of across town.
			# pick_best_market(BUY) already filters for storage with stock > 0.
			var src := MarketManager.pick_best_market(def.input_good, hut.cell, MarketManager.Side.BUY)
			if src != null:
				_start_input_fetch(inhabitant, hut, src)
		return

	var loaded := inhabitant.add_to_inventory(def.output_good, carry)
	hut.output_stock[def.output_good] = available - loaded

	var target := _pick_delivery_target(inhabitant)
	if target == null:
		return
	inhabitant.path = WorldGrid.find_path(inhabitant.cell, target.cell)
	inhabitant.path_index = 0
	inhabitant.state = InhabitantData.State.DELIVERING


# ---------------------------------------------------------------------------
# M21: raw material purchase for input producers (physically at storage)
# ---------------------------------------------------------------------------
## Sends an input producer (sawmill/mill/bakery) to the responsible storage, to
## buy supplies there for their hut.
func _start_input_fetch(inhabitant: InhabitantData, hut: BuildingInstance, storage: BuildingInstance) -> void:
	inhabitant.fetch_target_good = hut.def.input_good
	# Remember the target storage, so the inhabitant buys from exactly this one on arrival
	# (and not from another, in case there are multiple granaries/storages).
	inhabitant.trade_target_id = storage.id
	# M36: leave a standing bid before setting off, so a villager seller can meet it while the
	# buyer is still walking. Without this the book only ever has one side and practically every
	# trade routes through the crown (measured: p2p_share ~0.06 with the resting bid missing).
	if storage.exchange != null:
		storage.exchange.post_resting_buy(hut.def.input_good,
			_input_fetch_amount(inhabitant, hut), inhabitant, hut)
	inhabitant.path = WorldGrid.find_path(inhabitant.cell, storage.cell)
	inhabitant.path_index = 0
	inhabitant.state = InhabitantData.State.FETCHING_INPUT


## How much raw material this trip is for. Shared by the standing bid posted on departure and
## the purchase made on arrival – if the two drifted apart, a buyer would bid for one amount and
## then collect a different one.
func _input_fetch_amount(inhabitant: InhabitantData, hut: BuildingInstance) -> float:
	return minf(maxf(hut.def.carry_capacity, hut.def.input_amount), inhabitant.inventory_space())


## Two-stage trip analogous to fetching building material: at storage a batch of raw material is
## bought out of the inhabitant's budget (physical presence!), then carried to the hut and put
## into its local buffer (community_stock), from which production draws.
func _handle_fetching_input(inhabitant: InhabitantData) -> void:
	if not inhabitant.path.is_empty() and inhabitant.path_index < inhabitant.path.size():
		return

	var hut := BuildingManager.get_building(inhabitant.home_building_id)
	if hut == null:
		inhabitant.state = InhabitantData.State.SEEKING_SITE
		return

	var good := inhabitant.fetch_target_good
	if good < 0:
		inhabitant.state = InhabitantData.State.WORKING
		return

	var carried: float = inhabitant.inventory.get(good, 0.0)
	if carried <= 0.0:
		# Arrived at storage: buy a batch (payment happens here on the spot), limited
		# by the free space in the inventory. Buy from the target storage remembered at the
		# start (multiple granaries possible); fallback to the responsible default storage.
		var storage := BuildingManager.get_building(inhabitant.trade_target_id)
		if storage == null:
			storage = BuildingManager.get_storage_for_good(good)
		var want := _input_fetch_amount(inhabitant, hut)
		var bought := 0.0
		if storage != null and want > 0.0:
			if storage.exchange != null:
				# M36: whatever the standing bid already bought is theirs – collect it first, then
				# top up over the counter for the rest. The standing bid is withdrawn either way:
				# they are here now, so it has done its job.
				bought = storage.exchange.collect_reserved(inhabitant, good, want)["taken"]
				storage.exchange.withdraw_resting_buy(good, inhabitant.id)
				# M31: price ceiling rises with input_wait_timer, capped at their own gold –
				# no crown fallback, too poor or too impatient means no raw material this trip.
				if want - bought > 0.0:
					var cap := _willingness_to_pay(inhabitant, storage.exchange, good, inhabitant.input_wait_timer)
					bought += storage.exchange.consume(good, want - bought, inhabitant, cap)
			else:
				bought = storage.withdraw_community(good, want)
		if bought > 0.0:
			inhabitant.add_to_inventory(good, bought)
			inhabitant.path = WorldGrid.find_path(inhabitant.cell, hut.cell)
			inhabitant.path_index = 0
		else:
			# Storage meanwhile empty, or every lot priced above what they're currently willing to
			# pay – back to work, try again later (a different/cheaper storage next time, and
			# input_wait_timer keeps accumulating so their ceiling keeps rising).
			inhabitant.fetch_target_good = -1
			inhabitant.state = InhabitantData.State.WORKING
	else:
		# Back at the hut: put the raw material into the local buffer (capped at 100).
		var stored := hut.deliver(good, carried)
		var left := carried - stored
		if left > 0.0:
			inhabitant.inventory[good] = left
		else:
			inhabitant.inventory.erase(good)
		inhabitant.fetch_target_good = -1
		inhabitant.state = InhabitantData.State.WORKING


func _handle_delivering(inhabitant: InhabitantData) -> void:
	if not inhabitant.path.is_empty() and inhabitant.path_index < inhabitant.path.size():
		return

	var good: int = PROFESSION_TO_GOOD[inhabitant.profession]
	var total: float = inhabitant.inventory.get(good, 0.0)
	# M34: same reserve carve-out as _handle_hauling_home. _offer_carried_goods and
	# _liquidate_for_food both already `continue` on FOOD for exactly this reason; this path forgot
	# the guard, so a BAKER/HUNTER put their own rations on consignment (unpaid until a buyer takes
	# the lot) and _buy_food_at below then bought ~3 back for CASH at crown_ask plus the greed
	# premium – a guaranteed loss on every delivery trip.
	var reserve: float = _desired_food_stock(inhabitant) if good == Goods.GoodType.FOOD else 0.0
	var amount: float = maxf(0.0, total - reserve)
	var target := BuildingManager.get_building(inhabitant.trade_target_id)
	if target == null:
		target = MarketManager.pick_best_market(good, inhabitant.cell, MarketManager.Side.SELL)

	if amount > 0.0 and target != null:
		var sold := 0.0
		if target.exchange != null:
			# Consignment: the inhabitant lists their goods as their own price lot and is only
			# paid when a buyer takes it or the crown buys it up at the support price
			# (see MarketExchange.offer/tick). If storage is full, only the fitting part is
			# accepted (sold < amount).
			sold = target.exchange.offer(good, amount, inhabitant)
		else:
			# Fallback without an exchange (early game): store the goods, pay the fixed price immediately.
			sold = target.deliver(good, amount)
			var price: float = BuildingManager.get_sell_price(good)
			var wage := minf(sold * price, GlobalInventory.gold)
			if wage > 0.0:
				GlobalInventory.spend_gold(wage)
				adjust_gold(inhabitant, wage)
			inhabitant.last_sale_unit_price = price
			inhabitant.time_since_last_sale = 0.0
		# Unaccepted goods (storage full) stay in the inventory and get delivered again
		# later – so nothing is lost. M34: `total - sold`, not `amount - sold`: `amount` now excludes
		# the personal food reserve, so subtracting from it would silently delete that reserve.
		inhabitant.inventory[good] = total - sold

	inhabitant.trade_target_id = -1

	# M25: they're standing at storage anyway and just turned goods into money – top up
	# the food cushion here without any detour. This is exactly what takes the point out of
	# stockpiling: a small stock no longer costs an extra trip, but a large one still costs cargo space.
	_buy_food_at(inhabitant, target, _food_purchase_amount(inhabitant))

	var hut := BuildingManager.get_building(inhabitant.home_building_id)
	if hut != null:
		inhabitant.path = WorldGrid.find_path(inhabitant.cell, hut.cell)
		inhabitant.path_index = 0
	inhabitant.state = InhabitantData.State.RETURNING


func _handle_returning(inhabitant: InhabitantData) -> void:
	if not inhabitant.path.is_empty() and inhabitant.path_index < inhabitant.path.size():
		return
	# M22: resume the interrupted activity (resume_state; default WORKING). Reset
	# afterward, so a later normal return (after delivery) goes back to WORKING.
	inhabitant.state = inhabitant.resume_state
	inhabitant.resume_state = InhabitantData.State.WORKING


# ---------------------------------------------------------------------------
# M24: hunger emergency sale – a laden but broke inhabitant turns goods into cash
# ---------------------------------------------------------------------------
## Sells a hungry inhabitant's carried non-food goods until their
## gold is enough to buy enough food (FOOD_RESTOCK_THRESHOLD) and satisfy hunger.
## Each good is sold at its responsible exchange (the crown pays the market price); without an exchange
## the fixed-price fallback applies. This way nobody starves anymore while carrying something sellable.
func _liquidate_for_food(inh: InhabitantData, food_market: BuildingInstance) -> void:
	if inh.non_food_count() <= 0.0:
		return
	var food_price: float = food_market.exchange.get_price(Goods.GoodType.FOOD) if food_market.exchange != null \
		else BuildingManager.get_sell_price(Goods.GoodType.FOOD)
	for good in inh.inventory.keys():
		if good == Goods.GoodType.FOOD:
			continue
		# Enough money for the food need together? Then don't sell off any more goods.
		var have_food: float = inh.inventory.get(Goods.GoodType.FOOD, 0.0)
		var needed_gold := maxf(0.0, FOOD_RESTOCK_THRESHOLD - have_food) * food_price
		if food_price <= 0.0 or inh.gold >= needed_gold:
			return
		var amount: float = inh.inventory[good]
		if amount <= 0.0:
			continue
		var market := MarketManager.pick_best_market(good, inh.cell, MarketManager.Side.SELL)
		if market == null:
			continue
		var sold := 0.0
		if market.exchange != null:
			# Emergency: IMMEDIATE sale to the crown at the support price (cash now), so the
			# hungry, broke inhabitant can buy food – consignment would let them starve
			# (payment only later). See MarketExchange.sell_to_crown_now.
			sold = market.exchange.sell_to_crown_now(good, amount, inh)
		else:
			# Fallback without an exchange: store the goods and pay the fixed price out of the crown's gold.
			sold = market.deliver(good, amount)
			var wage := minf(sold * BuildingManager.get_sell_price(good), GlobalInventory.gold)
			if wage > 0.0:
				GlobalInventory.spend_gold(wage)
				adjust_gold(inh, wage)
		var left := amount - sold
		if left > 0.0:
			inh.inventory[good] = left
		else:
			inh.inventory.erase(good)


# ---------------------------------------------------------------------------
# A1: incidental sale at the market – offers carried production goods right where the inhabitant stands
# ---------------------------------------------------------------------------
## Offers every carried non-food good that this market carries, directly here (the
## inhabitant is physically present). This way e.g. a farmer sells their grain along with a food
## trip, instead of carrying it home unsold. Iterates over inventory.keys() (a copy), so
## erasing empty entries during the loop is safe.
func _offer_carried_goods(inh: InhabitantData, market: BuildingInstance) -> void:
	if market == null or market.exchange == null:
		return
	for good in inh.inventory.keys():
		if good == Goods.GoodType.FOOD:
			continue
		if not market.exchange.goods.has(good):
			continue
		var amount: float = inh.inventory[good]
		if amount <= 0.0:
			continue
		var sold := market.exchange.offer(good, amount, inh)
		var left := amount - sold
		if left > 0.0:
			inh.inventory[good] = left
		else:
			inh.inventory.erase(good)


# ---------------------------------------------------------------------------
# M25: food stock vs. cargo space – opportunity cost instead of a ban
#
# Previously every inhabitant bought food until the inventory was full. This was even
# rational for them: selling happened on delivery, food was only available on an EXTRA trip –
# so better to fill up once than walk twice. Result: everyone walked around with 5 food and
# 0 goods and stopped keeping up with their profession.
#
# Two changes take the point out of hoarding, without banning it:
#   1. Whoever delivers tops up their cushion at the same storage without a detour (_handle_delivering).
#      This way a small stock no longer costs an extra trip.
#   2. Der gewünschte Vorrat richtet sich nach der Reise zum Kornspeicher, nicht nach dem
#      Frachtwert (_desired_food_stock): so viel Essen wie der Hin-Rückweg + eine kleine
#      Sicherheitsmarge kostet, hart gedeckelt – der Rest des Inventars bleibt frei für Ware.
#      (Die frühere frachtwert-inverse Abwägung füllte unrentable Bewohner mit Essen zu und
#      nahm ihnen jeden Frachtplatz → sie konnten nie wieder rentabel werden.)
# ---------------------------------------------------------------------------
## Base cushion everyone wants to carry. Deliberately above FOOD_RESTOCK_THRESHOLD (2.0), otherwise
## the very first meal would immediately trigger the next buying trip (a travel treadmill).
const FOOD_BASE_STOCK := 3.0

## A: Sicherheitsmarge (zusätzliche Mahlzeiten über dem reinen Reisebedarf), skaliert mit
## Resilience: ängstliche (niedrige Resilienz) tragen mehr Polster, robuste weniger.
const SAFETY_MEALS_MAX := 2.0   # trait_resilience = 0.0
const SAFETY_MEALS_MIN := 0.5   # trait_resilience = 1.0
## Harte Obergrenze des Nahrungsvorrats, damit nie das halbe Inventar mit Essen verstopft.
## Auf dieser kleinen Karte greift meist die Distanz-Formel (~2–4), der Deckel ist Sicherheitsnetz.
const FOOD_STOCK_CAP := 6.0

## Wie viel Nahrung der Bewohner mitnehmen WILL – abgeleitet aus der Reisezeit zum nächsten
## Kornspeicher (Hin+Zurück) plus einer resilienz-abhängigen Sicherheitsmarge. Untergrenze
## FOOD_BASE_STOCK (> FOOD_RESTOCK_THRESHOLD, sonst Reise-Tretmühle), Obergrenze FOOD_STOCK_CAP
## (lässt immer Frachtplatz frei). KEINE Kopplung mehr an den Frachtwert – die verursachte die
## Arbeits-Todesschleife: unrentable Ware → Inventar mit Essen gefüllt → nie wieder Frachtplatz →
## nie wieder ein Verkauf, der die Ware wieder rentabel gemacht hätte.
func _desired_food_stock(inh: InhabitantData) -> float:
	var one_meal: float = FOOD_PER_INHABITANT_PER_TICK * inh.food_need_multiplier()
	var trip_meals: float = _round_trip_meals_to_granary(inh)
	var safety_meals: float = lerpf(SAFETY_MEALS_MAX, SAFETY_MEALS_MIN, inh.trait_resilience)
	var desired: float = one_meal * (trip_meals + safety_meals)
	return clampf(desired, FOOD_BASE_STOCK, FOOD_STOCK_CAP)


## Grob geschätzte Zahl der Mahlzeiten, die ein Hin-Rückweg zum nächstgelegenen Kornspeicher
## kostet. Luftlinie in Kacheln (billig; Umwege deckt die Sicherheitsmarge ab), umgerechnet über
## das persönliche Tempo (move_speed_base enthält bereits die Trait-Multiplikatoren).
func _round_trip_meals_to_granary(inh: InhabitantData) -> float:
	var granary := _nearest_granary(inh.cell)
	if granary == null or inh.move_speed_base <= 0.0:
		return 0.0
	var cells: float = Vector2(inh.cell - granary.cell).length()
	var round_trip_secs: float = 2.0 * cells * WorldGrid.TILE_SIZE / inh.move_speed_base
	return round_trip_secs / FOOD_CONSUMPTION_INTERVAL


## Nächstgelegener Kornspeicher nach Luftlinie (unabhängig vom Bestand – wir schätzen nur die
## Distanz). get_all_storages_for_good(FOOD) liefert alle Kornspeicher (BuildingManager).
func _nearest_granary(from_cell: Vector2i) -> BuildingInstance:
	var best: BuildingInstance = null
	var best_d := INF
	for g in BuildingManager.get_all_storages_for_good(Goods.GoodType.FOOD):
		var d: float = Vector2(from_cell - g.cell).length_squared()
		if d < best_d:
			best_d = d
			best = g
	return best


## Amount still missing to reach the desired stock (never more than
## physically fits in the inventory).
func _food_purchase_amount(inh: InhabitantData) -> float:
	var cur_food: float = inh.inventory.get(Goods.GoodType.FOOD, 0.0)
	return minf(inh.inventory_space(), maxf(0.0, _desired_food_stock(inh) - cur_food))


## Food purchase at a storage – shared between a dedicated buy trip (MARKET_TRIP)
## and the incidental purchase during a delivery (DELIVERING). Payment happens physically on the spot.
func _buy_food_at(inh: InhabitantData, granary: BuildingInstance, want: float) -> void:
	if granary == null or want <= 0.0:
		return
	if granary.exchange != null:
		if not granary.exchange.goods.has(Goods.GoodType.FOOD):
			return
		# M36: collect whatever the standing bid already secured, then buy the rest over the
		# counter. Both paths report the price actually paid, so last_food_unit_price stays
		# honest – it is the anchor the whole buy side prices from (ReservationPricing).
		var collected := granary.exchange.collect_reserved(inh, Goods.GoodType.FOOD, want)
		granary.exchange.withdraw_resting_buy(Goods.GoodType.FOOD, inh.id)
		var taken: float = collected["taken"]
		var cost: float = collected["cost"]
		if want - taken > 0.0:
			# Food purchase at the market price; booking in buy_food/_charge_buyer.
			var result := granary.exchange.buy_food(Goods.GoodType.FOOD, want - taken, inh)
			taken += result["taken"]
			cost += float(result["taken"]) * float(result["unit_price"])
		if taken > 0.0:
			inh.last_food_unit_price = cost / taken
			inh.add_to_inventory(Goods.GoodType.FOOD, taken)
			_charge_greed_premium(inh, cost)
		elif DEBUG_STARVE:
			print("[STARVE] #%d at market %d, but taken=0 (stock=%.1f, budget=%.1f) → empty/unaffordable" % [
				inh.id, granary.id, granary.community_stock.get(Goods.GoodType.FOOD, 0.0), inh.gold])
	else:
		# Fallback without an exchange (early game): withdraw directly, pay the fixed price to the crown.
		var available: float = granary.community_stock.get(Goods.GoodType.FOOD, 0.0)
		var sell_price: float = BuildingManager.get_sell_price(Goods.GoodType.FOOD)
		var max_affordable := want
		if sell_price > 0.0:
			max_affordable = minf(want, inh.gold / sell_price)
		var taken := minf(available, max_affordable)
		if taken > 0.0:
			granary.community_stock[Goods.GoodType.FOOD] = available - taken
			var cost := taken * sell_price
			if cost > 0.0:
				adjust_gold(inh, -cost)
				GlobalInventory.add_gold(cost)
				inh.last_food_unit_price = sell_price
			inh.add_to_inventory(Goods.GoodType.FOOD, taken)
			_charge_greed_premium(inh, cost)
	GlobalInventory.notify_resources_changed()


## M28: greed drawback – a greedy inhabitant (high `margin`, see M20) overpays on
## food purchases by a fraction of the purchase value (the markup flows to the crown treasury,
## thus mirroring greed's sell-side benefit with a drawback on their own purchases).
func _charge_greed_premium(inh: InhabitantData, purchase_value: float) -> void:
	if purchase_value <= 0.0 or inh.margin <= 0.0:
		return
	var premium := minf(purchase_value * inh.margin * GREED_BUY_PREMIUM_SCALE, inh.gold)
	if premium > 0.0:
		adjust_gold(inh, -premium)
		GlobalInventory.add_gold(premium)


# ---------------------------------------------------------------------------
# MARKET_TRIP – M8
# ---------------------------------------------------------------------------
func _handle_market_trip(inhabitant: InhabitantData) -> void:
	if not inhabitant.path.is_empty() and inhabitant.path_index < inhabitant.path.size():
		return

	var granary := BuildingManager.get_building(inhabitant.trade_target_id)
	if granary == null:
		granary = BuildingManager.get_granary()
	inhabitant.trade_target_id = -1
	# M24: if the money isn't enough for enough food, the hungry inhabitant first sells their
	# carried goods (except food), so they can buy food afterward.
	if granary != null:
		_liquidate_for_food(inhabitant, granary)
	# M22/M25: food is bought here for stock and then eaten along the way/at home.
	# How much is decided by _desired_food_stock (weighing cargo space against stock). Payment
	# happens PHYSICALLY at the granary – the only place where food-money flows.
	var want := _food_purchase_amount(inhabitant)
	# During a build (interrupted build phase): only buy up to the base cushion (FOOD_BASE_STOCK), instead of
	# filling the whole inventory with food. This way material space largely stays free and the
	# bulk material trips actually kick in. Deliberately FOOD_BASE_STOCK (3.0) and NOT FOOD_RESERVE (2.0):
	# the safety stock equals FOOD_RESTOCK_THRESHOLD (2.0), so the very first
	# meal would immediately trigger the next granary run → the build would crawl in a travel treadmill
	# to the granary instead of fetching material from storage. The base cushion provides the needed buffer.
	if inhabitant.resume_state == InhabitantData.State.FETCHING_MATERIALS \
			or inhabitant.resume_state == InhabitantData.State.BUILDING:
		var cur_food: float = inhabitant.inventory.get(Goods.GoodType.FOOD, 0.0)
		want = minf(want, maxf(0.0, FOOD_BASE_STOCK - cur_food))
	_buy_food_at(inhabitant, granary, want)

	# A1: since the inhabitant is at the granary anyway, they also offer their carried,
	# non-food goods here (e.g. a farmer their grain) – saves a dedicated
	# delivery trip. _liquidate_for_food above only covers the broke emergency (instant cash).
	if granary != null:
		_offer_carried_goods(inhabitant, granary)

	# M22: back to the interrupted activity. Whoever has a hut walks there and resumes their
	# remembered resume_state in _handle_returning. Whoever doesn't (yet) have a hut
	# (e.g. site search) resumes their activity directly.
	var hut := BuildingManager.get_building(inhabitant.home_building_id)
	if hut != null:
		inhabitant.path = WorldGrid.find_path(inhabitant.cell, hut.cell)
		inhabitant.path_index = 0
		inhabitant.state = InhabitantData.State.RETURNING
	else:
		inhabitant.state = inhabitant.resume_state
		inhabitant.resume_state = InhabitantData.State.WORKING


# ---------------------------------------------------------------------------
# M19: farming – farmer plants and harvests wheat on the fields around their hut
# ---------------------------------------------------------------------------
func _handle_farmer_working(inhabitant: InhabitantData, hut: BuildingInstance) -> void:
	# Scanning the fields (_find_farm_task) is expensive; as long as there's nothing to do,
	# don't rescan every frame.
	if inhabitant.idle_retry_timer > 0.0:
		return

	var carried: float = inhabitant.inventory.get(Goods.GoodType.GRAIN, 0.0)
	var deliver_threshold: float = maxf(hut.def.carry_capacity, 1.0)
	var task := _find_farm_task(hut)

	# Bring harvested food to the granary once the carry load is full
	# or there's nothing more to do on the fields for now. A2: also if the goods
	# have been carried undelivered for too long already (no sale since STALE_INVENTORY_SECONDS).
	if carried >= deliver_threshold or (carried > 0.0 and (task.is_empty() \
			or inhabitant.time_since_last_sale > STALE_INVENTORY_SECONDS)):
		var granary := _pick_delivery_target(inhabitant)
		if granary == null:
			return
		inhabitant.path = WorldGrid.find_path(inhabitant.cell, granary.cell)
		inhabitant.path_index = 0
		inhabitant.state = InhabitantData.State.DELIVERING
		return

	if task.is_empty():
		inhabitant.idle_retry_timer = IDLE_RETRY_INTERVAL
		return  # nothing to do – recheck after the throttle

	inhabitant.farm_target_cell = task["cell"]
	inhabitant.farm_action = task["action"]
	inhabitant.path = WorldGrid.find_path(inhabitant.cell, task["cell"])
	inhabitant.path_index = 0
	inhabitant.state = InhabitantData.State.FARM_TENDING


## Looks for the next task on the hut's fields: first harvest ripe wheat,
## otherwise plant a free field. Returns {} if nothing is pending.
func _find_farm_task(hut: BuildingInstance) -> Dictionary:
	var size := hut.def.footprint_size
	var center := Vector2(hut.cell) + Vector2(size) * 0.5
	var best_harvest := Vector2i(-1, -1)
	var best_harvest_dist := INF
	var best_plant := Vector2i(-1, -1)
	var best_plant_dist := INF

	var min_x := hut.cell.x - FARM_FIELD_RADIUS
	var max_x := hut.cell.x + size.x - 1 + FARM_FIELD_RADIUS
	var min_y := hut.cell.y - FARM_FIELD_RADIUS
	var max_y := hut.cell.y + size.y - 1 + FARM_FIELD_RADIUS
	for y in range(min_y, max_y + 1):
		for x in range(min_x, max_x + 1):
			var cell := Vector2i(x, y)
			if not WorldGrid.is_valid_cell(cell):
				continue
			var tile := WorldGrid.get_tile(cell)
			if tile.crop_field_owner != hut.id:
				continue
			var dist: float = (Vector2(cell) - center).length_squared()
			if tile.crop_stage == TileRuntimeData.CropStage.STAGE_3:
				if dist < best_harvest_dist:
					best_harvest_dist = dist
					best_harvest = cell
			elif tile.crop_stage == TileRuntimeData.CropStage.NONE and WorldGrid.is_plantable(cell):
				if dist < best_plant_dist:
					best_plant_dist = dist
					best_plant = cell

	if best_harvest != Vector2i(-1, -1):
		return {"action": InhabitantData.FarmAction.HARVEST, "cell": best_harvest}
	if best_plant != Vector2i(-1, -1):
		return {"action": InhabitantData.FarmAction.PLANT, "cell": best_plant}
	return {}


func _handle_farm_tending(inhabitant: InhabitantData) -> void:
	if not inhabitant.path.is_empty() and inhabitant.path_index < inhabitant.path.size():
		return  # still en route to the field

	var hut := BuildingManager.get_building(inhabitant.home_building_id)
	var cell := inhabitant.farm_target_cell
	# Only act if the farmer is actually standing on the target field.
	if hut != null and inhabitant.cell == cell and WorldGrid.is_valid_cell(cell):
		var tile := WorldGrid.get_tile(cell)
		match inhabitant.farm_action:
			InhabitantData.FarmAction.HARVEST:
				# Only harvest if the harvested wheat fits in the inventory (otherwise the
				# ripe field would remain standing and get harvested after the next delivery).
				# The deciding factor is the minimum of goods_space() (goods space, keeps the
				# food reserve free) and inventory_space() (physical space that
				# add_to_inventory actually limits to). If the farmer carries more than
				# FOOD_RESERVE food, inventory_space() is the smaller limit – without
				# this check, clear_crop() would clear the ripe field while
				# add_to_inventory accepts 0 and the harvest disappears.
				# M28: frugality drawback also lowers the harvest yield per field.
				var yield_amt := CROP_HARVEST_YIELD * inhabitant.yield_multiplier()
				if tile.crop_stage == TileRuntimeData.CropStage.STAGE_3 \
						and minf(inhabitant.goods_space(), inhabitant.inventory_space()) >= yield_amt:
					# Only clear the field once the harvest has actually landed in the inventory.
					if inhabitant.add_to_inventory(Goods.GoodType.GRAIN, yield_amt) >= yield_amt:
						WorldGrid.clear_crop(cell)
			InhabitantData.FarmAction.PLANT:
				if tile.crop_field_owner == hut.id and WorldGrid.is_plantable(cell):
					WorldGrid.plant_crop(cell, hut.id)

	inhabitant.farm_target_cell = Vector2i(-1, -1)
	inhabitant.farm_action = InhabitantData.FarmAction.NONE
	inhabitant.state = InhabitantData.State.WORKING


# ---------------------------------------------------------------------------
# M35: shared preconditions for on-site work (woodcutter/quarry worker/hunter)
# ---------------------------------------------------------------------------
## Can a worker actually stand on this cell and work it?
##
## A cell carrying a building is **solid in A\*** (`WorldGrid.set_building_footprint`), so it can
## never be reached — and huts are routinely built straight onto forest (`is_footprint_buildable`
## only rejects water and already-occupied cells, and site selection deliberately hunts for forest
## proximity). The terrain under a hut stays FOREST, so without this check a hunter's or
## woodcutter's own tent scored as the nearest prey/tree at distance 0 and won the search every
## single time: `find_path` silently redirected to a neighbouring cell, the worker "arrived" one
## tile off, the on-site handler saw `cell != target` and bounced back to WORKING — a per-frame
## busy loop that never set the hunting cooldown or felled the tree, so the same cell won again
## forever. Measured before this check: 4017 of 4041 hunt legs and 848 of 852 gather legs aborted
## that way (seed 42, 40 days).
##
## A path across a **forest** tile disqualifies it too: worn desire paths already convert forest to
## grass (M32, `WorldGrid.register_step`) and tree regrowth skips path cells, so this is a
## consistency guard rather than a live case — it also covers saves written before M32. Non-forest
## resources are deliberately unaffected: a track worn to a quarry face does not remove the stone.
func _tile_workable(tile: TileRuntimeData) -> bool:
	if tile.building_id != -1:
		return false
	if tile.terrain == TileRuntimeData.TerrainType.FOREST \
			and tile.path_type != TileRuntimeData.PathType.NONE:
		return false
	return true


## Does this path actually end on `target`? `WorldGrid.find_path` resolves an unreachable or solid
## target to a neighbour (`_resolve_walkable_target`) and returns an empty path when there is no
## route at all. In both cases the walker arrives somewhere else and the on-site handler bounces
## straight back to WORKING. `_tile_workable` removes the common cause (buildings), but any other
## unreachable target — a forest patch across water, a cell walled in by huts — would spin the
## same loop, so a leg is only started when the route provably lands on the target cell.
func _path_reaches(path: PackedVector2Array, target: Vector2i) -> bool:
	if path.is_empty():
		return false
	return WorldGrid.world_to_cell(path[path.size() - 1]) == target


# ---------------------------------------------------------------------------
# On-site resource harvesting – woodcutter/quarry worker walk to the resource, harvest
# it and carry it to their own hut (analogous to the farmer on the field).
# ---------------------------------------------------------------------------
func _handle_gatherer_working(inhabitant: InhabitantData, hut: BuildingInstance) -> void:
	# _find_resource_cell_near scans a 13x13 field; as long as there's nothing to harvest and
	# nothing to deliver, don't search again every frame.
	if inhabitant.idle_retry_timer > 0.0:
		return

	var good: int = PROFESSION_TO_GOOD[inhabitant.profession]
	var terrain: TileRuntimeData.TerrainType = PROFESSION_TO_TERRAIN[inhabitant.profession]
	var stored: float = hut.output_stock.get(good, 0.0)
	var resource_cell := _find_resource_cell_near(hut.cell, terrain)
	if resource_cell != Vector2i(-1, -1):
		inhabitant.resource_stall_retries = 0

	# Bring the stock from the hut to storage once a full carry load is ready
	# or there's no resource left in reach right now. A2: also if nothing has been
	# sold for too long already (STALE_INVENTORY_SECONDS), so partial amounts don't sit around.
	if stored > 0.0 and (stored >= hut.def.carry_capacity or resource_cell == Vector2i(-1, -1) \
			or inhabitant.time_since_last_sale > STALE_INVENTORY_SECONDS):
		# M22: keep the food reserve free (goods_space), so a full ore cargo hold doesn't
		# block a food purchase anymore.
		var carry: float = minf(minf(stored, hut.def.carry_capacity), inhabitant.goods_space())
		var loaded := inhabitant.add_to_inventory(good, carry)
		if loaded <= 0.0:
			# Inventory full (e.g. food stock) – try again later.
			inhabitant.idle_retry_timer = IDLE_RETRY_INTERVAL
			return
		hut.output_stock[good] = stored - loaded
		var target := _pick_delivery_target(inhabitant)
		if target == null:
			return
		inhabitant.path = WorldGrid.find_path(inhabitant.cell, target.cell)
		inhabitant.path_index = 0
		inhabitant.state = InhabitantData.State.DELIVERING
		return

	if resource_cell == Vector2i(-1, -1):
		inhabitant.resource_stall_retries += 1
		if inhabitant.resource_stall_retries >= RESOURCE_STALL_RETRIES:
			inhabitant.resource_stall_retries = 0
			try_switch_unprofitable(inhabitant)
		inhabitant.idle_retry_timer = IDLE_RETRY_INTERVAL
		return  # nothing to harvest – recheck after the throttle

	_start_gather_leg(inhabitant, resource_cell, terrain)


## M35: sends the gatherer to a resource cell. Returns false (and leaves the state alone, merely
## throttled) if no route actually reaches the cell – see _path_reaches.
func _start_gather_leg(inhabitant: InhabitantData, resource_cell: Vector2i, terrain: TileRuntimeData.TerrainType) -> bool:
	var path := WorldGrid.find_path(inhabitant.cell, resource_cell)
	if not _path_reaches(path, resource_cell):
		inhabitant.idle_retry_timer = IDLE_RETRY_INTERVAL
		return false
	inhabitant.gather_target_cell = resource_cell
	inhabitant.work_timer = WOOD_CUT_TIME if terrain == TileRuntimeData.TerrainType.FOREST else STONE_MINE_TIME
	inhabitant.path = path
	inhabitant.path_index = 0
	inhabitant.state = InhabitantData.State.GATHERING
	return true


## Walks to the resource and harvests it on-site. The harvest timer only runs while the
## inhabitant is actually standing on the target cell; no presence, no yield.
func _handle_gathering(inhabitant: InhabitantData, delta: float) -> void:
	if not inhabitant.path.is_empty() and inhabitant.path_index < inhabitant.path.size():
		return  # still en route to the resource

	var hut := BuildingManager.get_building(inhabitant.home_building_id)
	if hut == null:
		inhabitant.state = InhabitantData.State.SEEKING_SITE
		return

	var cell := inhabitant.gather_target_cell
	var terrain: TileRuntimeData.TerrainType = PROFESSION_TO_TERRAIN[inhabitant.profession]

	# Abort if the inhabitant hasn't reached the resource or it has meanwhile
	# gone (harvested by someone else).
	if not WorldGrid.is_valid_cell(cell) or inhabitant.cell != cell:
		_reset_gathering(inhabitant)
		return
	var tile := WorldGrid.get_tile(cell)
	if tile.terrain != terrain or tile.resource_amount <= 0.0 or not _tile_workable(tile):
		_reset_gathering(inhabitant)
		return

	# Harvest on-site: count down the work time. M28: diligence/resilience scale
	# the personal work speed (like the build timer).
	inhabitant.work_timer -= delta * inhabitant.work_speed_multiplier()
	if inhabitant.work_timer > 0.0:
		return

	# M28: frugality drawback lowers the yield amount per harvest action.
	var good: int = PROFESSION_TO_GOOD[inhabitant.profession]
	var harvested: float
	if terrain == TileRuntimeData.TerrainType.FOREST:
		WorldGrid.remove_tree(cell)  # the felled tree disappears
		harvested = WOOD_PER_TREE * inhabitant.yield_multiplier()
	else:
		tile.resource_amount = maxf(0.0, tile.resource_amount - STONE_DEPLETION_PER_MINE)
		harvested = STONE_PER_MINE * inhabitant.yield_multiplier()

	# Load as much as fits into the inventory; carry the rest straight to the hut's
	# woodpile so a big harvest (10 wood > one carry load) is never lost. The portion
	# in the inventory is the visible load hauled home in HAULING_HOME, the overflow is
	# credited to the hut when the inhabitant walks back (dragged home over intervals).
	var loaded := inhabitant.add_to_inventory(good, harvested)
	var overflow := harvested - loaded
	if overflow > 0.0:
		hut.output_stock[good] = hut.output_stock.get(good, 0.0) + overflow

	# Carry the harvested resource back to the hut.
	inhabitant.gather_target_cell = Vector2i(-1, -1)
	inhabitant.path = WorldGrid.find_path(inhabitant.cell, hut.cell)
	inhabitant.path_index = 0
	inhabitant.state = InhabitantData.State.HAULING_HOME
	GlobalInventory.notify_resources_changed()


## Carries the harvested resource into their own hut (output buffer). From there
## it's later delivered as a full load to storage (_handle_gatherer_working).
func _handle_hauling_home(inhabitant: InhabitantData) -> void:
	if not inhabitant.path.is_empty() and inhabitant.path_index < inhabitant.path.size():
		return  # still en route to the hut

	var hut := BuildingManager.get_building(inhabitant.home_building_id)
	if hut == null:
		inhabitant.state = InhabitantData.State.SEEKING_SITE
		return

	var good: int = PROFESSION_TO_GOOD[inhabitant.profession]
	var carried: float = inhabitant.inventory.get(good, 0.0)
	# M34: a HUNTER's product IS food, so `carried` includes their own eating cushion. Dumping all
	# of it into the hut pile left them at 0 and made _needs_emergency_food fire on the very next
	# frame – every single hunt trip ended in a forced granary run. Only the surplus above the
	# personal reserve (_desired_food_stock, the same figure _buy_food_at tops up to) is deposited.
	var reserve: float = _desired_food_stock(inhabitant) if good == Goods.GoodType.FOOD else 0.0
	var deposit: float = maxf(0.0, carried - reserve)
	if deposit > 0.0:
		hut.output_stock[good] = hut.output_stock.get(good, 0.0) + deposit
		inhabitant.inventory[good] = carried - deposit
	inhabitant.state = InhabitantData.State.WORKING


func _reset_gathering(inhabitant: InhabitantData) -> void:
	inhabitant.gather_target_cell = Vector2i(-1, -1)
	inhabitant.work_timer = 0.0
	inhabitant.state = InhabitantData.State.WORKING


# ---------------------------------------------------------------------------
# M29: hunting (hunter). Structured like the gatherer (WORKING → HUNTING → HAULING_HOME →
# DELIVERING), but the loot is probabilistic and the hunted forest cell has a Y-day
# cooldown. The tree stays standing (no remove_tree) – only the prey is temporarily gone.
# ---------------------------------------------------------------------------

## Is there prey to get on this cell right now? (Forest + HUNT_REPLENISH_DAYS cooldown expired.)
func _tile_huntable(tile: TileRuntimeData) -> bool:
	if tile.terrain != TileRuntimeData.TerrainType.FOREST:
		return false
	# M35: a hut's own footprint is unreachable (solid in A*) even though its terrain stays FOREST.
	if not _tile_workable(tile):
		return false
	if tile.last_hunted_day < 0:
		return true
	return get_current_day() - tile.last_hunted_day >= HUNT_REPLENISH_DAYS


## Nearest huntable forest cell around the hut (13x13 field, like _find_resource_cell_near).
func _find_huntable_cell_near(origin: Vector2i) -> Vector2i:
	var best := Vector2i(-1, -1)
	var best_dist := INF
	for dy in range(-RESOURCE_SEARCH_RADIUS, RESOURCE_SEARCH_RADIUS + 1):
		for dx in range(-RESOURCE_SEARCH_RADIUS, RESOURCE_SEARCH_RADIUS + 1):
			var cell := origin + Vector2i(dx, dy)
			if not WorldGrid.is_valid_cell(cell):
				continue
			if not _tile_huntable(WorldGrid.get_tile(cell)):
				continue
			var dist := dx * dx + dy * dy
			if dist < best_dist:
				best_dist = dist
				best = cell
	return best


## Like _handle_gatherer_working, but searches for a huntable forest cell instead of an ore/wood cell.
func _handle_hunter_working(inhabitant: InhabitantData, hut: BuildingInstance) -> void:
	if inhabitant.idle_retry_timer > 0.0:
		return

	var good: int = PROFESSION_TO_GOOD[inhabitant.profession]  # FOOD
	var stored: float = hut.output_stock.get(good, 0.0)
	var prey_cell := _find_huntable_cell_near(hut.cell)

	# Bring the loot from the hut to the granary once a full load is ready,
	# there's nothing to hunt right now, or nothing has been delivered for too long.
	if stored > 0.0 and (stored >= hut.def.carry_capacity or prey_cell == Vector2i(-1, -1) \
			or inhabitant.time_since_last_sale > STALE_INVENTORY_SECONDS):
		var carry: float = minf(minf(stored, hut.def.carry_capacity), inhabitant.goods_space())
		var loaded := inhabitant.add_to_inventory(good, carry)
		if loaded <= 0.0:
			inhabitant.idle_retry_timer = IDLE_RETRY_INTERVAL
			return
		hut.output_stock[good] = stored - loaded
		var target := _pick_delivery_target(inhabitant)
		if target == null:
			return
		inhabitant.path = WorldGrid.find_path(inhabitant.cell, target.cell)
		inhabitant.path_index = 0
		inhabitant.state = InhabitantData.State.DELIVERING
		return

	if prey_cell == Vector2i(-1, -1):
		inhabitant.idle_retry_timer = IDLE_RETRY_INTERVAL
		return  # no huntable forest in reach – recheck after the throttle

	# Start a fresh hunting trip: roam counter resets, head to the first (nearest) cell.
	inhabitant.hunt_cells_this_trip = 0
	_start_hunt_leg(inhabitant, prey_cell)


## Sends the hunter to a forest cell to hunt (one leg of a roaming trip). M35: returns false
## (and leaves the state alone, merely throttled) if no route actually reaches the cell – see
## _path_reaches. The caller decides what to do instead: stay in WORKING and retry after the
## throttle, or – mid-trip with loot in hand – head home.
func _start_hunt_leg(inhabitant: InhabitantData, prey_cell: Vector2i) -> bool:
	var path := WorldGrid.find_path(inhabitant.cell, prey_cell)
	if not _path_reaches(path, prey_cell):
		inhabitant.idle_retry_timer = IDLE_RETRY_INTERVAL
		return false
	inhabitant.gather_target_cell = prey_cell
	inhabitant.work_timer = HUNT_TIME
	inhabitant.path = path
	inhabitant.path_index = 0
	inhabitant.state = InhabitantData.State.HUNTING
	return true


## Walks to the forest cell and hunts there. The yield is only rolled at the end; only then is
## the cell marked as hunted (analogous to the woodcutter only felling the tree at the end).
## This way the faster of two hunters on the same cell blocks the other: they see the
## cell as no longer huntable on the next frame and abort without loot.
##
## M32: rather than returning to the hut after a single cell, the hunter roams from forest cell
## to forest cell (each rolls independently for prey) until the carry load is full or
## HUNT_CELLS_PER_TRIP cells have been worked – this spreads the search over the forest and
## raises the chance of a catch per outing. Each worked cell goes on cooldown, so the next
## nearest huntable cell is naturally a fresh one further out.
func _handle_hunting(inhabitant: InhabitantData, delta: float) -> void:
	if not inhabitant.path.is_empty() and inhabitant.path_index < inhabitant.path.size():
		return  # still en route to the forest cell

	var hut := BuildingManager.get_building(inhabitant.home_building_id)
	if hut == null:
		inhabitant.state = InhabitantData.State.SEEKING_SITE
		return

	var cell := inhabitant.gather_target_cell
	if not WorldGrid.is_valid_cell(cell) or inhabitant.cell != cell:
		_reset_gathering(inhabitant)
		return
	var tile := WorldGrid.get_tile(cell)
	# Prey gone (another hunter was faster) or forest felled meanwhile → roam on / return.
	if not _tile_huntable(tile):
		_roam_or_return(inhabitant, hut)
		return

	# Hunt on-site. M28: diligence/resilience scale the work speed.
	inhabitant.work_timer -= delta * inhabitant.work_speed_multiplier()
	if inhabitant.work_timer > 0.0:
		return

	# Hunt complete: mark the cell as hunted (start the cooldown → blocks other hunters for Y days).
	tile.last_hunted_day = get_current_day()
	inhabitant.gather_target_cell = Vector2i(-1, -1)
	inhabitant.hunt_cells_this_trip += 1

	if randf() < HUNT_SUCCESS_CHANCE:
		# HUNT_FOOD_BASE is always caught in full; only the bonus on top of it is scaled
		# down by the M28 frugality yield drawback, so a catch never falls below the base.
		var bonus := FOOD_PER_CATCH - HUNT_FOOD_BASE
		var catch_amount := HUNT_FOOD_BASE + bonus * inhabitant.yield_multiplier()
		inhabitant.add_to_inventory(PROFESSION_TO_GOOD[inhabitant.profession], catch_amount)
		GlobalInventory.notify_resources_changed()

	_roam_or_return(inhabitant, hut)


## Decides whether the hunter moves on to the next forest cell (continue roaming) or heads
## home. Homeward once the carry load is full or the per-trip cell budget is spent; otherwise
## it walks to the next nearest huntable cell. If nothing was caught and no cell is left, it
## drops back to WORKING (throttled) instead of an empty haul.
func _roam_or_return(inhabitant: InhabitantData, hut: BuildingInstance) -> void:
	var good: int = PROFESSION_TO_GOOD[inhabitant.profession]  # FOOD
	var carrying: float = inhabitant.inventory.get(good, 0.0)
	var load_full := carrying >= hut.def.carry_capacity or inhabitant.goods_space() <= 0.0
	var budget_spent := inhabitant.hunt_cells_this_trip >= HUNT_CELLS_PER_TRIP

	if not load_full and not budget_spent:
		var next_cell := _find_huntable_cell_near(hut.cell)
		# M35: an unreachable next cell ends the trip instead of restarting it – falling through
		# hauls the catch home rather than leaving the hunter standing.
		if next_cell != Vector2i(-1, -1) and _start_hunt_leg(inhabitant, next_cell):
			return

	# Trip over: haul the catch home, or – if empty-handed – idle briefly and retry later.
	if carrying > 0.0:
		inhabitant.path = WorldGrid.find_path(inhabitant.cell, hut.cell)
		inhabitant.path_index = 0
		inhabitant.state = InhabitantData.State.HAULING_HOME
	else:
		inhabitant.gather_target_cell = Vector2i(-1, -1)
		inhabitant.idle_retry_timer = IDLE_RETRY_INTERVAL
		inhabitant.state = InhabitantData.State.WORKING


## Grows all wheat, withers ripe wheat, and makes withered wheat disappear.
func _update_crops(step: float) -> void:
	var changed := false
	for cell in WorldGrid.crop_cells.duplicate():
		var tile := WorldGrid.get_tile(cell)
		# No wheat can grow on a path – a path laid over the field
		# tramples existing wheat.
		if tile.path_type != TileRuntimeData.PathType.NONE:
			WorldGrid.clear_crop(cell)
			changed = true
			continue
		tile.crop_timer += step
		match tile.crop_stage:
			TileRuntimeData.CropStage.STAGE_1:
				if tile.crop_timer >= CROP_GROW_INTERVAL:
					WorldGrid.set_crop_stage(cell, TileRuntimeData.CropStage.STAGE_2)
			TileRuntimeData.CropStage.STAGE_2:
				if tile.crop_timer >= CROP_GROW_INTERVAL:
					WorldGrid.set_crop_stage(cell, TileRuntimeData.CropStage.STAGE_3)
			TileRuntimeData.CropStage.STAGE_3:
				if tile.crop_timer >= CROP_RIPE_LIFETIME:
					WorldGrid.set_crop_stage(cell, TileRuntimeData.CropStage.DEAD)
			TileRuntimeData.CropStage.DEAD:
				if tile.crop_timer >= CROP_DEAD_LIFETIME:
					WorldGrid.clear_crop(cell)
					changed = true
	if changed:
		GlobalInventory.notify_resources_changed()


# ---------------------------------------------------------------------------
# Helper functions
# ---------------------------------------------------------------------------
## M20: chooses the best exchange for the produced good (best offer minus travel cost)
## and remembers it on the inhabitant, so the delivery targets the same exchange.
func _pick_delivery_target(inhabitant: InhabitantData) -> BuildingInstance:
	var good: int = PROFESSION_TO_GOOD[inhabitant.profession]
	var target := MarketManager.pick_best_market(good, inhabitant.cell, MarketManager.Side.SELL)
	inhabitant.trade_target_id = target.id if target != null else -1
	return target


func _find_resource_cell_near(origin: Vector2i, terrain: TileRuntimeData.TerrainType) -> Vector2i:
	var best := Vector2i(-1, -1)
	var best_dist := INF

	for dy in range(-RESOURCE_SEARCH_RADIUS, RESOURCE_SEARCH_RADIUS + 1):
		for dx in range(-RESOURCE_SEARCH_RADIUS, RESOURCE_SEARCH_RADIUS + 1):
			var cell := origin + Vector2i(dx, dy)
			if not WorldGrid.is_valid_cell(cell):
				continue
			var tile := WorldGrid.get_tile(cell)
			if tile.terrain != terrain or tile.resource_amount <= 0.0:
				continue
			# M35: skip cells a worker can never stand on (own/other huts) – see _tile_workable.
			if not _tile_workable(tile):
				continue
			var dist := dx * dx + dy * dy
			if dist < best_dist:
				best_dist = dist
				best = cell

	return best


func _regenerate_resources() -> void:
	for y in range(WorldGrid.MAP_SIZE.y):
		for x in range(WorldGrid.MAP_SIZE.x):
			var cell := Vector2i(x, y)
			var tile := WorldGrid.get_tile(cell)
			if tile.terrain != TileRuntimeData.TerrainType.FOREST and tile.terrain != TileRuntimeData.TerrainType.STONE:
				continue
			if tile.resource_amount >= 1.0:
				continue
			if randf() < RESOURCE_REGEN_CHANCE:
				tile.resource_amount = minf(1.0, tile.resource_amount + RESOURCE_REGEN_AMOUNT)


## Trees regrow randomly. On occupied cells (building, path, wheat,
## farmland) the chance is 0, on free grass small but not 0 – and it
## rises exponentially with the number of neighboring trees, so forests regrow from
## the edges inward. New trees are only placed after the pass,
## so neighbors don't cascade within the same tick.
func _spread_trees() -> void:
	var grown: Array[Vector2i] = []
	for y in range(WorldGrid.MAP_SIZE.y):
		for x in range(WorldGrid.MAP_SIZE.x):
			var cell := Vector2i(x, y)
			var tile := WorldGrid.get_tile(cell)
			if tile.terrain != TileRuntimeData.TerrainType.GRASS:
				continue
			if tile.building_id != -1 or tile.path_type != TileRuntimeData.PathType.NONE:
				continue
			if tile.crop_stage != TileRuntimeData.CropStage.NONE or tile.crop_field_owner != -1:
				continue
			var neighbors := WorldGrid.count_forest_neighbors(cell)
			var chance: float = minf(
				TREE_SPREAD_BASE_CHANCE * pow(TREE_SPREAD_GROWTH, neighbors),
				TREE_SPREAD_MAX_CHANCE)
			if randf() < chance:
				grown.append(cell)
	for cell in grown:
		WorldGrid.grow_tree(cell)


## M18: current day (1-based) for HUD display and highscore.
func get_current_day() -> int:
	return int(sim_time / DAY_LENGTH_SECONDS) + 1


## M18: resets the simulation time/counters for a restart.
func reset_state() -> void:
	speed_mode = SpeedMode.NORMAL
	sim_time = 0.0
	_resource_regen_accum = 0.0
	_debug_log_accum = 0.0
	_food_consumption_accum = 0.0
	initial_spawned = 0
	_initial_spawn_accum = 0.0
	_market_tick_accum = 0.0
	_daily_tax_accum = 0.0
	_crop_accum = 0.0
	_record_accum = 0.0


func _print_stock_summary() -> void:
	var storage := BuildingManager.get_storage_yard()
	var granary := BuildingManager.get_granary()
	var wood: float   = storage.community_stock.get(Goods.GoodType.WOOD,   0.0) if storage else 0.0
	var planks: float = storage.community_stock.get(Goods.GoodType.PLANKS, 0.0) if storage else 0.0
	var stone: float  = storage.community_stock.get(Goods.GoodType.STONE,  0.0) if storage else 0.0
	var food: float   = granary.community_stock.get(Goods.GoodType.FOOD,   0.0) if granary else 0.0
	print("[M8:Stock] t=%.0fs | Wood=%.1f Planks=%.1f Stone=%.1f Food=%.1f | Gold=%.1f | Pop=%d" % [
		sim_time, wood, planks, stone, food,
		GlobalInventory.gold, GameState.population_count()
	])


# ---------------------------------------------------------------------------
# M37: houses – build/repair target, sleep, pantry, housing decision, births
# ---------------------------------------------------------------------------
## What FETCHING_MATERIALS / BUILDING work on: their house while build_target_id is set,
## otherwise the workplace (as before M37).
func _build_site(inh: InhabitantData) -> BuildingInstance:
	if inh.build_target_id != -1:
		return BuildingManager.get_building(inh.build_target_id)
	return BuildingManager.get_building(inh.home_building_id)


## The build site vanished: a lost house only ends the errand, a lost workplace means job hunting.
func _lost_build_site_state(inh: InhabitantData) -> InhabitantData.State:
	if inh.build_target_id != -1:
		inh.build_target_id = -1
		return InhabitantData.State.WORKING
	inh.home_building_id = -1
	return InhabitantData.State.SEEKING_SITE


func _own_house(inh: InhabitantData) -> BuildingInstance:
	var house := BuildingManager.get_building(inh.house_id)
	return house if house != null and house.is_constructed else null


func _path_done(inh: InhabitantData) -> bool:
	return inh.path.is_empty() or inh.path_index >= inh.path.size()


func _beside_building(cell: Vector2i) -> bool:
	for dir in WorldGrid.NEIGHBOR_OFFSETS_8:
		var n: Vector2i = cell + dir
		if WorldGrid.is_valid_cell(n) and WorldGrid.get_tile(n).building_id != -1:
			return true
	return false


## M38: is this inhabitant inside a building right now? Read by the agent view to fade the node
## out. Workers standing at their workplace, visitors in their dwell, sleepers at their own house.
## Outdoor work (GATHERING/HUNTING/FARM_TENDING/BUILDING) is never indoors.
func is_indoors(inh: InhabitantData) -> bool:
	if inh.dwell_timer > 0.0:
		return true
	match inh.state:
		InhabitantData.State.WORKING:
			return _path_done(inh) and _beside_building(inh.cell)
		InhabitantData.State.SLEEPING:
			return _at_home(inh)
	return false


func _at_home(inh: InhabitantData) -> bool:
	var house := _own_house(inh)
	return house != null and absi(inh.cell.x - house.cell.x) + absi(inh.cell.y - house.cell.y) <= 1


## Free decision point (WORKING): repair the house if they are its richest occupant, go to bed
## when due, and once a day reconsider where they live. True if they were sent off.
func _try_house_errands(inh: InhabitantData, work: BuildingInstance) -> bool:
	var house := BuildingManager.get_building(inh.house_id)
	if house != null and house.needs_repair and _is_richest_occupant(inh, house):
		if _try_start_repair(inh, house):
			inh.build_target_id = house.id
			return true
	if inh.rest_timer >= REST_INTERVAL:
		if _own_house(inh) != null:
			inh.resume_state = InhabitantData.State.WORKING
			_start_going_home(inh)
		else:
			_fall_asleep(inh)
		return true
	if inh.house_check_timer <= 0.0:
		inh.house_check_timer = DAY_LENGTH_SECONDS
		return _decide_housing(inh, work)
	return false


func _is_richest_occupant(inh: InhabitantData, house: BuildingInstance) -> bool:
	for id in house.occupants:
		var other := GameState.get_inhabitant(id)
		if other != null and other.gold > inh.gold:
			return false
	return true


func _start_going_home(inh: InhabitantData) -> void:
	var house := _own_house(inh)
	if house == null:
		_start_market_trip(inh)
		return
	inh.path = WorldGrid.find_path(inh.cell, house.cell)
	inh.path_index = 0
	inh.state = InhabitantData.State.GOING_HOME


func _handle_going_home(inh: InhabitantData) -> void:
	if not inh.path.is_empty() and inh.path_index < inh.path.size():
		return
	if not _at_home(inh):
		# House gone (or unreachable) on the way: carry on with what they were doing.
		_return_to_work(inh)
		return
	_stock_lunchbox(inh)
	if inh.rest_timer >= REST_INTERVAL:
		_fall_asleep(inh)
	else:
		_return_to_work(inh)


## At home: carried food beyond the lunchbox goes into the pantry, a short lunchbox is topped up from it.
func _stock_lunchbox(inh: InhabitantData) -> void:
	var lunchbox := FOOD_RESTOCK_THRESHOLD + LUNCHBOX_MEALS * FOOD_PER_INHABITANT_PER_TICK * inh.food_need_multiplier()
	var carried: float = inh.inventory.get(Goods.GoodType.FOOD, 0.0)
	if carried > lunchbox:
		inh.pantry_food += carried - lunchbox
		inh.inventory[Goods.GoodType.FOOD] = lunchbox
	else:
		inh.pantry_food -= inh.add_to_inventory(Goods.GoodType.FOOD, minf(inh.pantry_food, lunchbox - carried))


func _fall_asleep(inh: InhabitantData) -> void:
	inh.path = PackedVector2Array()
	inh.path_index = 0
	inh.work_timer = SLEEP_SECONDS
	inh.state = InhabitantData.State.SLEEPING
	if _at_home(inh):
		_try_birth(inh)


func _handle_sleeping(inh: InhabitantData, delta: float) -> void:
	inh.work_timer -= delta
	if inh.work_timer > 0.0:
		return
	inh.rest_timer = 0.0
	inh.rested = _at_home(inh)
	if inh.rested:
		_stock_lunchbox(inh)
	inh.resume_state = InhabitantData.State.WORKING
	_return_to_work(inh)


## Same exit as a market trip: walk back to the workplace and resume there.
func _return_to_work(inh: InhabitantData) -> void:
	var hut := BuildingManager.get_building(inh.home_building_id)
	if hut != null:
		inh.path = WorldGrid.find_path(inh.cell, hut.cell)
		inh.path_index = 0
		inh.state = InhabitantData.State.RETURNING
	else:
		inh.state = inh.resume_state
		inh.resume_state = InhabitantData.State.WORKING


## Walking cost of living at `cell`: to work and back each day, plus the granary for food.
## Manhattan on purpose – this runs over many candidate cells, A* would be the old SEEKING_SITE lag.
func _commute(cell: Vector2i, work: BuildingInstance, granary: BuildingInstance) -> float:
	var d := 2.0 * (absi(cell.x - work.cell.x) + absi(cell.y - work.cell.y))
	if granary != null:
		d += absi(cell.x - granary.cell.x) + absi(cell.y - granary.cell.y)
	return d


## Long-term housing decision (once per day): take a free bed that clearly shortens the walk,
## else build a house near work if it pays off and they can afford it. True if they set off to build.
func _decide_housing(inh: InhabitantData, work: BuildingInstance) -> bool:
	if not work.is_constructed:
		return false
	var granary := BuildingManager.get_granary()
	var house := _own_house(inh)
	var current := _commute(house.cell, work, granary) if house != null else INF

	var best_bed: BuildingInstance = null
	var best_bed_commute := INF
	for b: BuildingInstance in BuildingManager.get_buildings_by_type(BuildingDef.BuildingType.HOUSE):
		if b == house or not b.is_constructed or b.occupants.size() >= b.def.max_capacity:
			continue
		var c := _commute(b.cell, work, granary)
		if c < best_bed_commute:
			best_bed = b
			best_bed_commute = c
	if best_bed != null and best_bed_commute < current * HOUSE_MOVE_RATIO:
		_move_house(inh, best_bed)
		return false

	var site := _find_house_site(work, granary)
	if site == Vector2i(-1, -1):
		return false
	if house != null and current - _commute(site, work, granary) < HOUSE_MIN_SAVING:
		return false
	if inh.gold < _house_cost_gold() * HOUSE_BUILD_GOLD_FACTOR or not _house_materials_buyable():
		return false
	_start_house_build(inh, site)
	return true


## Only start a house whose materials are all for sale now – otherwise the builder pays for half of
## it and the build stalls (e.g. no Planks before a sawmill runs, or the Crown not selling them).
func _house_materials_buyable() -> bool:
	var def := BuildingManager.get_building_def(BuildingDef.BuildingType.HOUSE)
	for good: int in def.build_cost:
		var storage := BuildingManager.get_storage_for_good(good)
		if storage == null or storage.exchange == null or storage.exchange.buyable(good) < def.build_cost[good]:
			return false
	return true


## Best free grass cell around the workplace (no forest, field or path – a house must not eat the
## resources or roads others depend on).
func _find_house_site(work: BuildingInstance, granary: BuildingInstance) -> Vector2i:
	var best := Vector2i(-1, -1)
	var best_commute := INF
	for dy in range(-HOUSE_SITE_RADIUS, HOUSE_SITE_RADIUS + 1):
		for dx in range(-HOUSE_SITE_RADIUS, HOUSE_SITE_RADIUS + 1):
			var cell := work.cell + Vector2i(dx, dy)
			if not WorldGrid.is_footprint_buildable(cell, Vector2i.ONE):
				continue
			var tile := WorldGrid.get_tile(cell)
			if tile.terrain != TileRuntimeData.TerrainType.GRASS or tile.crop_field_owner != -1 \
					or tile.path_type != TileRuntimeData.PathType.NONE:
				continue
			var c := _commute(cell, work, granary)
			if c < best_commute:
				best = cell
				best_commute = c
	return best


## Current market value of a house's materials (what the builder will have to pay at storage).
func _house_cost_gold() -> float:
	var def := BuildingManager.get_building_def(BuildingDef.BuildingType.HOUSE)
	var total := 0.0
	for good: int in def.build_cost:
		var storage := BuildingManager.get_storage_for_good(good)
		var price: float = storage.exchange.get_price(good) if storage != null and storage.exchange != null \
			else Goods.BASE_PRICES[good]
		total += def.build_cost[good] * price
	return total


func _move_house(inh: InhabitantData, house: BuildingInstance) -> void:
	var old := BuildingManager.get_building(inh.house_id)
	if old != null:
		old.occupants.erase(inh.id)
	house.occupants.append(inh.id)
	inh.house_id = house.id


func _start_house_build(inh: InhabitantData, cell: Vector2i) -> void:
	var def := BuildingManager.get_building_def(BuildingDef.BuildingType.HOUSE)
	var house := BuildingManager.register_building(def, cell)
	house.is_constructed = false
	house.construction_timer = def.build_time_seconds
	house.pending_build_cost = def.build_cost.duplicate()
	WorldGrid.set_building_footprint_rect(cell, def.footprint_size, house.id, true)
	_move_house(inh, house)
	inh.build_target_id = house.id
	inh.fetch_target_good = -1
	inh.state = InhabitantData.State.FETCHING_MATERIALS
	print("[M37:House] Inhabitant %d starts a house (ID=%d) at %s." % [inh.id, house.id, cell])


## Two housemates asleep at home, both fed and solvent, off cooldown → a new adult Freisasse.
func _try_birth(inh: InhabitantData) -> void:
	if GameState.population_count() >= POP_MAX or not _can_parent(inh):
		return
	var house := _own_house(inh)
	for id in house.occupants:
		var partner := GameState.get_inhabitant(id)
		if partner == null or partner == inh or partner.state != InhabitantData.State.SLEEPING:
			continue
		if not _at_home(partner) or not _can_parent(partner):
			continue
		_give_birth(inh, partner, house)
		return


func _can_parent(inh: InhabitantData) -> bool:
	return inh.missed_meals == 0 and inh.gold >= BIRTH_MIN_GOLD \
		and inh.pantry_food + inh.inventory.get(Goods.GoodType.FOOD, 0.0) >= BIRTH_FOOD_EACH \
		and get_current_day() - inh.last_birth_day >= BIRTH_COOLDOWN_DAYS


func _give_birth(a: InhabitantData, b: InhabitantData, house: BuildingInstance) -> void:
	var purse := 0.0
	for parent: InhabitantData in [a, b]:
		var from_pantry := minf(parent.pantry_food, BIRTH_FOOD_EACH)
		parent.pantry_food -= from_pantry
		parent.inventory[Goods.GoodType.FOOD] = parent.inventory.get(Goods.GoodType.FOOD, 0.0) - (BIRTH_FOOD_EACH - from_pantry)
		var share := parent.gold * BIRTH_PURSE_FRACTION
		adjust_gold(parent, -share)
		purse += share
		parent.last_birth_day = get_current_day()
	# The food is eaten up, not traded – book it as consumption like a meal.
	EconomyManager.note_consumption(Goods.GoodType.FOOD, 2.0 * BIRTH_FOOD_EACH)

	var child := GameState.add_inhabitant(house.cell)
	child.gold = purse
	# M28 traits are inherited: the parents' average plus a small mutation (GAME_DESIGN §12).
	child.trait_speed = _inherit(a.trait_speed, b.trait_speed)
	child.trait_strength = _inherit(a.trait_strength, b.trait_strength)
	child.trait_frugality = _inherit(a.trait_frugality, b.trait_frugality)
	child.trait_diligence = _inherit(a.trait_diligence, b.trait_diligence)
	child.trait_resilience = _inherit(a.trait_resilience, b.trait_resilience)
	child.margin = _inherit(a.margin, b.margin)  # greed
	child.recompute_derived_stats()
	child.last_birth_day = get_current_day()  # not a parent on day one
	if house.occupants.size() < house.def.max_capacity:
		_move_house(child, house)
	GlobalInventory.notify_population_changed(GameState.population_count())
	print("[M37:Birth] Inhabitant %d born to %d and %d in house %d. Total: %d" % [
		child.id, a.id, b.id, house.id, GameState.population_count()])
	RunRecorder.record("birth", {"id": child.id, "parents": [a.id, b.id], "house": house.id})


func _inherit(x: float, y: float) -> float:
	return clampf((x + y) * 0.5 + randf_range(-BIRTH_TRAIT_MUTATION, BIRTH_TRAIT_MUTATION), 0.0, 1.0)
