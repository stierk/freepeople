extends Node

## Economy infrastructure + the pluggable profession-choice strategy.
##
## M35: the choice ALGORITHM moved out to scripts/economy/ (see ProfessionStrategy). What stays here
## is the rolling production/consumption flow tracker, which is shared infrastructure every strategy
## may read, plus the four thin delegations so the ~13 existing call sites in SimulationManager and
## RunRecorder did not have to change.
##
## The strategy constants moved with the algorithm. That is a deliberate departure from the
## "tuning constants live at the top of their manager" convention in CLAUDE.md: those constants ARE
## the strategy, and leaving them behind would mean a second strategy silently inheriting the first
## one's tuning.

## Which strategy is used when --turbo-strategy= is not given, i.e. in all normal play.
const DEFAULT_STRATEGY := "urgency"

var _strategy: ProfessionStrategy = null


func _ready() -> void:
	_strategy = _make_strategy(_requested_strategy_name())


## M35: parsed here rather than read off TurboRunner. EconomyManager is autoload #5 and TurboRunner
## is #10, so TurboRunner._ready() has not run yet at this point. (Seeding is unaffected by that
## ordering: seed() only has to precede the first draw, which happens in World._ready(), after every
## autoload.) Same --turbo- prefix as the other dev-only flags, and like them it is simply absent in
## normal play.
func _requested_strategy_name() -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--turbo-strategy="):
			return a.substr(17)
	return DEFAULT_STRATEGY


## Unknown name is a hard error, never a silent fallback to the default — a benchmark that quietly
## measured the default under a candidate's name would be worse than no benchmark. Mirrors
## TurboRunner's invalid-invocation handling (push_error + quit(2)).
func _make_strategy(strategy: String) -> ProfessionStrategy:
	match strategy:
		"urgency":
			return UrgencyStrategy.new()
		_:
			push_error("[Economy] unknown --turbo-strategy=%s (known: urgency)" % strategy)
			get_tree().quit(2)
			# quit() only takes effect at the end of the frame; hand back the default meanwhile so
			# the remaining frame does not also spam null dereferences on top of the real error.
			return UrgencyStrategy.new()


## Identifier of the active strategy, for the strategy column of user://runs/bench.csv.
func strategy_name() -> String:
	return _strategy.strategy_name()


# ---------------------------------------------------------------------------
# M35: strategy delegation — see scripts/economy/profession_strategy.gd
# ---------------------------------------------------------------------------
func assign_profession_for_new_inhabitant() -> InhabitantData.Profession:
	return _strategy.assign_profession_for_new_inhabitant()


func pick_best_profession(exclude: InhabitantData.Profession = InhabitantData.Profession.NONE) -> InhabitantData.Profession:
	return _strategy.pick_best_profession(exclude)


func profession_scores(exclude: InhabitantData.Profession = InhabitantData.Profession.NONE) -> Dictionary:
	return _strategy.profession_scores(exclude)


func is_good_scarce(good: int) -> bool:
	return _strategy.is_good_scarce(good)


# ---------------------------------------------------------------------------
# M34: rolling production/consumption flow
# ---------------------------------------------------------------------------
## Nothing tracked actual throughput before this. RunRecorder._trade_qty looks similar but is
## unusable here: it is zeroed at every metrics sample and is fed from both directions, including
## the crown backstop (which only transfers lot OWNERSHIP – the goods never leave community_stock).
##
## A ring of buckets rotated on the sim clock gives a smoothed rate without storing timestamps.
## The window is deliberately a few days long: flow is twitchier than a stock level, and a single
## construction burst should not pin several goods at maximum urgency at once.
## Literals rather than SimulationManager.DAY_LENGTH_SECONDS because a const cannot reference
## another autoload; kept in sync with it by name here.
const DAY_SECONDS := 60.0          # == SimulationManager.DAY_LENGTH_SECONDS
const FLOW_BUCKETS := 6
const FLOW_BUCKET_SECONDS := DAY_SECONDS * 0.5   # 6 × half a day = 3-day window

var _in_buckets: Dictionary = {}
var _out_buckets: Dictionary = {}
var _bucket_index: int = 0
var _bucket_accum: float = 0.0


## Goods entering the community stock from a producer (exchange offer / direct crown sale).
func note_production(good: int, qty: float) -> void:
	if qty > 0.0:
		_bucket_array(_in_buckets, good)[_bucket_index] += qty


## Goods leaving the community stock to a consumer (market purchase, population growth).
func note_consumption(good: int, qty: float) -> void:
	if qty > 0.0:
		_bucket_array(_out_buckets, good)[_bucket_index] += qty


## Rotates the ring. Driven from SimulationManager._process on SIM time, so the window means the
## same number of game days at every speed setting.
func advance_flow_clock(delta: float) -> void:
	_bucket_accum += delta
	while _bucket_accum >= FLOW_BUCKET_SECONDS:
		_bucket_accum -= FLOW_BUCKET_SECONDS
		_bucket_index = (_bucket_index + 1) % FLOW_BUCKETS
		for good in _in_buckets:
			_in_buckets[good][_bucket_index] = 0.0
		for good in _out_buckets:
			_out_buckets[good][_bucket_index] = 0.0


func supply_rate(good: int) -> float:
	return _flow_rate(_in_buckets, good)


func measured_consumption_rate(good: int) -> float:
	return _flow_rate(_out_buckets, good)


## Units per GAME DAY, averaged over the whole window.
func _flow_rate(store: Dictionary, good: int) -> float:
	if not store.has(good):
		return 0.0
	var total := 0.0
	for v: float in store[good]:
		total += v
	return total / (float(FLOW_BUCKETS) * FLOW_BUCKET_SECONDS / DAY_SECONDS)


func _bucket_array(store: Dictionary, good: int) -> Array:
	if not store.has(good):
		var fresh: Array = []
		fresh.resize(FLOW_BUCKETS)
		fresh.fill(0.0)
		store[good] = fresh
	return store[good]


## Autoload state survives reload_current_scene(), so without this the Restart button would carry
## the previous run's flow history into the new one. Called from SaveLoadManager.restart_game.
func reset_state() -> void:
	_in_buckets = {}
	_out_buckets = {}
	_bucket_index = 0
	_bucket_accum = 0.0


## Persisted so a loaded game does not start with an empty window – every good would read as a
## total production deficit for the first few days and trigger a burst of job changes.
func serialize_flow() -> Dictionary:
	return {
		"in": _in_buckets.duplicate(true),
		"out": _out_buckets.duplicate(true),
		"index": _bucket_index,
		"accum": _bucket_accum,
	}


func restore_flow(data: Dictionary) -> void:
	reset_state()
	if data.is_empty():
		return
	_in_buckets = _restore_buckets(data.get("in", {}))
	_out_buckets = _restore_buckets(data.get("out", {}))
	_bucket_index = int(data.get("index", 0)) % FLOW_BUCKETS
	_bucket_accum = float(data.get("accum", 0.0))


## JSON turns the int good keys into strings and may shorten a bucket array; normalise both.
func _restore_buckets(raw: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for key in raw:
		var arr: Array = []
		arr.resize(FLOW_BUCKETS)
		arr.fill(0.0)
		var src: Array = raw[key]
		for i in mini(src.size(), FLOW_BUCKETS):
			arr[i] = float(src[i])
		out[int(key)] = arr
	return out
