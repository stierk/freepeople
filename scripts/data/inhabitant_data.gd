class_name InhabitantData
extends RefCounted

# M29: HUNTER appended at the end (enums are stored as int – never change the order).
enum Profession { NONE, WOODCUTTER, SAWMILL_WORKER, QUARRY_WORKER, FARMER, MILLER, BAKER, HUNTER }
enum State {
	SEEKING_SITE,        # looking for a site/hut (only Profession == NONE, freshly spawned)
	MOVING_TO_BUILD,     # walking to the site (new hut OR existing hut with a free slot)
	FETCHING_MATERIALS,  # hauling build materials from storage one at a time to the site
	BUILDING,            # construction timer running (only for a new hut)
	WORKING,             # producing at the workplace (hut)
	DELIVERING,          # walking to the storage building with output in inventory
	RETURNING,           # walking back to the hut after a delivery
	MARKET_TRIP,         # walking to the market to buy/sell (food etc.)
	FARM_TENDING,        # M19: farmer walks onto a field to plant/harvest wheat
	GATHERING,           # woodcutter/quarry worker walks to the resource and harvests it on-site
	HAULING_HOME,        # carrying the harvested resource back to their own hut
	FETCHING_INPUT,      # M21: sawmill/mill/bakery buys raw input physically at storage
	HUNTING,             # M29: hunter walks to a forest cell and hunts prey there (probabilistic)
}

## M19: what a farmer does on their target field once they reach it.
enum FarmAction { NONE, PLANT, HARVEST }

## Maximum total amount (sum of all goods) an inhabitant can carry at once.
## Gold does NOT count toward this. Base value – an inhabitant's actual capacity lives in
## `inventory_capacity` and varies with the strength trait (see below).
const INVENTORY_CAPACITY := 10.0

## M22: this many inventory slots stay reserved for food when loading trade goods.
## This way an inhabitant on a long, uninterruptible trip (harvest/deliver) always has
## room to buy food if needed – otherwise they'd starve despite having money (full cargo).
const FOOD_RESERVE := 2.0

const BASE_MOVE_SPEED := 24.0

# ---------------------------------------------------------------------------
# M28: evolutionary traits – six character traits, randomized via randf() at spawn
# ([0,1]). 0.0 = trait not expressed (neutral), 1.0 = fully expressed.
# EVERY trait has exactly one benefit AND one drawback – see the multiplier
# functions below and docs/GAME_DESIGN.md §12 for the balance values. Designed as simple
# float genes: a later reproduction mechanic (child inherits the average of both parents +
# mutation) can build directly on these fields – not yet implemented, see the TODO
# in docs/GAME_DESIGN.md §12. The sixth trait (greed) reuses the existing `margin`
# field (M20): benefit = higher sell price (market_exchange.gd), drawback = pays
# a premium on food purchases (SimulationManager._buy_food_at, GREED_BUY_PREMIUM_SCALE).
## Speed: +move speed / +food need (faster metabolism).
var trait_speed: float = 0.0
## Strength: +carry capacity / -move speed (heavier to carry around).
var trait_strength: float = 0.0
## Frugality: -food need / -yield per gather/harvest action.
var trait_frugality: float = 0.0
## Diligence: +work speed (build/gather) / +hunger increase on a missed meal.
var trait_diligence: float = 0.0
## Resilience: +tolerance for missed meals before starving / -work speed.
var trait_resilience: float = 0.0

## This inhabitant's actual carry capacity (base + strength bonus). Set by
## `recompute_derived_stats`; until then the base value INVENTORY_CAPACITY applies.
var inventory_capacity: float = INVENTORY_CAPACITY

const STRENGTH_CAPACITY_BONUS_MAX := 4.0    # +carry capacity at full strength
const STRENGTH_SPEED_PENALTY_MAX := 0.2     # -20% move speed at full strength
const SPEED_MOVE_BONUS_MAX := 0.25          # +25% move speed at full speed
const SPEED_FOOD_PENALTY_MAX := 0.3         # +30% food need at full speed
const FRUGALITY_FOOD_BONUS_MAX := 0.25      # -25% food need at full frugality
const FRUGALITY_YIELD_PENALTY_MAX := 0.15   # -15% yield at full frugality
const DILIGENCE_WORK_BONUS_MAX := 0.25      # +25% work speed at full diligence
const DILIGENCE_HUNGER_PENALTY_MAX := 0.4   # +40% hunger increase at full diligence
const RESILIENCE_HUNGER_TOLERANCE_MAX := 2.0  # + tolerated missed meals
const RESILIENCE_WORK_PENALTY_MAX := 0.2    # -20% work speed at full resilience


## Move speed multiplier from speed (benefit) and strength (drawback).
func move_speed_multiplier() -> float:
	return (1.0 + trait_speed * SPEED_MOVE_BONUS_MAX) * (1.0 - trait_strength * STRENGTH_SPEED_PENALTY_MAX)


## Personal food-need multiplier from frugality (benefit, lowers need) and
## speed (drawback, raises need). Apply to FOOD_PER_INHABITANT_PER_TICK.
func food_need_multiplier() -> float:
	return (1.0 - trait_frugality * FRUGALITY_FOOD_BONUS_MAX) * (1.0 + trait_speed * SPEED_FOOD_PENALTY_MAX)


## Yield multiplier (frugality drawback) for gather/harvest amounts (wood, stone, grain).
func yield_multiplier() -> float:
	return 1.0 - trait_frugality * FRUGALITY_YIELD_PENALTY_MAX


## Work-speed multiplier from diligence (benefit) and resilience (drawback), apply to
## build/gather timers (bigger = finishes faster).
func work_speed_multiplier() -> float:
	return (1.0 + trait_diligence * DILIGENCE_WORK_BONUS_MAX) * (1.0 - trait_resilience * RESILIENCE_WORK_PENALTY_MAX)


## Hunger-increase multiplier (diligence drawback) on a missed meal.
func hunger_gain_multiplier() -> float:
	return 1.0 + trait_diligence * DILIGENCE_HUNGER_PENALTY_MAX


## Extra tolerated missed meals before starving (resilience benefit).
func starvation_meal_tolerance() -> int:
	return int(round(trait_resilience * RESILIENCE_HUNGER_TOLERANCE_MAX))


## Recomputes the trait-derived base stats (move speed, carry capacity).
## Call at spawn (GameState.add_inhabitant) and after loading (SaveLoadManager),
## AFTER the trait_* fields have been set.
func recompute_derived_stats() -> void:
	move_speed_base = BASE_MOVE_SPEED * move_speed_multiplier()
	inventory_capacity = INVENTORY_CAPACITY + trait_strength * STRENGTH_CAPACITY_BONUS_MAX

var id: int = -1
var profession: Profession = Profession.NONE
var state: State = State.SEEKING_SITE
## M22: state to return to after a hunger-driven buy-food trip, so an
## interrupted activity (build, fetching materials, work) resumes afterward.
var resume_state: State = State.WORKING
var home_building_id: int = -1

var cell: Vector2i = Vector2i.ZERO
var world_pos: Vector2 = Vector2.ZERO
var path: PackedVector2Array = []
var path_index: int = 0
var move_speed_base: float = BASE_MOVE_SPEED

var inventory: Dictionary = {}
var gold: float = 0.0
var production_timer: float = 0.0

var hunger: float = 0.0
## M18: number of consecutive missed meals (hunger tinting, death at STARVATION_DEATH_MEALS)
var missed_meals: int = 0
var node_ref: Node2D = null

# --- Market economy (M20): individual pricing ---------------------------
## Personal margin [0,1], set once at spawn via randf(). Determines how
## much of a markup on the break-even price the inhabitant demands.
var margin: float = 0.0
## Price per unit the inhabitant achieved on their last sale of their goods.
var last_sale_unit_price: float = 0.0
## Price per unit the inhabitant last paid for food.
var last_food_unit_price: float = Goods.BASE_PRICES[Goods.GoodType.FOOD]
## Sim seconds since the last sale of their own goods (drives the break-even).
var time_since_last_sale: float = 0.0
## Counter of consecutive unprofitable sales (break-even > price achieved).
## At UNPROFITABLE_SWITCH_STREAK the inhabitant switches profession.
var unprofitable_streak: int = 0
## Last computed break-even price per unit (for display only).
var break_even_unit: float = 0.0
## Personal random factor [0,1] for the profession-switch check interval (× 10 days).
## Set at spawn via randf(); spreads out the (rare) profitability check.
var job_check_factor: float = 0.5
## Sim seconds until the next profession-switch check (personally paced).
var job_check_timer: float = 0.0
## Sim seconds until the next expensive idle search (site/resource/field).
## Prevents an idle inhabitant from running the expensive scans every frame.
var idle_retry_timer: float = 0.0
## Sim seconds without build progress (no material delivered, or the build timer stalls),
## while the inhabitant is in the build phase (FETCHING_MATERIALS/BUILDING). Once it reaches
## BUILD_STALL_TIMEOUT, the build is aborted (hut → ruin, new job choice).
var build_stall_timer: float = 0.0
## M31: sim seconds without progress on an input producer's raw-material purchase (FETCHING_INPUT
## only) – feeds the personal price ceiling in SimulationManager._willingness_to_pay. Resets on
## a successful purchase, or when the inhabitant leaves the state.
var input_wait_timer: float = 0.0

var target_site_cell: Vector2i = Vector2i(-1, -1)
var fetch_target_good: int = -1
## M20: exchange (building ID) the inhabitant is traveling to for a sale/food purchase.
var trade_target_id: int = -1

## M19: target cell and planned action of a farmer (plant/harvest).
var farm_target_cell: Vector2i = Vector2i(-1, -1)
var farm_action: FarmAction = FarmAction.NONE

## Target cell of the resource (tree/stone) a woodcutter/quarry worker is harvesting.
var gather_target_cell: Vector2i = Vector2i(-1, -1)
## Remaining work time (sim seconds) until the resource is harvested.
var work_timer: float = 0.0
## M32: forest cells a hunter has already worked on the current hunting trip. A hunter
## roams from forest cell to forest cell (each rolls for prey) until loaded or this
## reaches HUNT_CELLS_PER_TRIP, then hauls the catch home. Reset when a new trip starts.
var hunt_cells_this_trip: int = 0


# ---------------------------------------------------------------------------
# Inventory – gold does not count toward it
# ---------------------------------------------------------------------------
## Sum of all carried goods amounts.
func inventory_count() -> float:
	var total := 0.0
	for amt in inventory.values():
		total += amt
	return total


## Remaining free inventory space (never negative).
func inventory_space() -> float:
	return maxf(0.0, inventory_capacity - inventory_count())


## Sum of all carried goods EXCEPT food.
func non_food_count() -> float:
	var total := 0.0
	for good in inventory:
		if good != Goods.GoodType.FOOD:
			total += inventory[good]
	return total


## M22: free space for trade goods, accounting for the food reserve. This way
## up to FOOD_RESERVE slots always stay free for food, no matter how much cargo is carried.
func goods_space() -> float:
	return maxf(0.0, (inventory_capacity - FOOD_RESERVE) - non_food_count())


## Stores as much as possible (limited by inventory_space) into the inventory and returns the
## amount actually added.
func add_to_inventory(good: int, amount: float) -> float:
	var can := minf(amount, inventory_space())
	if can > 0.0:
		inventory[good] = inventory.get(good, 0.0) + can
	return can
