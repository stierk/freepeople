## RunRecorder – exportable recording of a complete game run.
##
## Goal: make a run's trajectory traceable precisely enough that balancing and
## bugs ("why does the economy collapse?", "why does someone starve despite having money?")
## can be analyzed externally (Excel/Python). TWO files are written per run to user://runs/:
##
##   run_<start_time>_metrics.csv   – tier 1: periodic KPI time series ("flight recorder").
##       One row per sample interval (see SimulationManager._record_accum) with
##       population, gold, avg hunger, cumulative deaths, plus per-good (stock,
##       crown remainder, market price, traded volume), per-profession, and per-building-type counts.
##   run_<start_time>_events.jsonl  – tier 2: append-only event stream. One JSON line
##       per domain event (birth, starved, jobchange, derelict, build_aborted, tax,
##       basic_income, game_over) with sim time, day, type, and payload → the causal chain.
##
## The start timestamp in the filename separates runs from each other (externally comparable).
## RECORD_ENABLED can hard-disable everything; then there is practically no overhead
## (every entry point returns early).
##
## Not-yet-implemented, more expensive expansion tiers (deliberately left open):
##   Tier 3 – deterministic replay (record seed + inputs, replay a run exactly);
##            requires a determinism overhaul first (central seeded RNG, fixed
##            timestep instead of delta-bound sim).
##   Tier 4 – full snapshot ring per day (dump SaveLoadManager serialization → rewind).
extends Node

## Master switch. Set to false to disable all recording (no file I/O, no
## collecting), so normal play incurs no extra load.
const RECORD_ENABLED := true

const RUNS_DIR := "user://runs"
## Real-time seconds between two file flushes of the buffered lines.
const FLUSH_INTERVAL := 5.0

## M35: one row per finished turbo run, accumulated ACROSS runs (unlike the per-run metrics CSV),
## so tools/bench.ps1 can sweep seeds × strategies and compare them. Written from here rather than
## from TurboRunner because everything it needs already lives here: RUNS_DIR, the _append_lines
## primitive, _cumulative_deaths, and the avg_hunger / inhabitants_gold definitions used by
## sample_metrics — recomputing those elsewhere would let the two definitions drift apart.
const BENCH_PATH := "user://runs/bench.csv"
## M36: `p2p_share` appended at the END (Import-Csv reads by header, so older sweeps still parse).
const BENCH_HEADER := "strategy,seed,days,survived,population,deaths,avg_hunger,inhabitants_gold,crown_gold,prof_entropy,p2p_share"

## M36: who stood on the other side of a trade. The whole point of the order-book rewrite was
## that inhabitants trade with EACH OTHER instead of everything routing through the crown, and
## that claim was previously unmeasurable — record_trade only counted goods and quantity, so a
## settlement where the crown was the counterparty to every single deal looked identical to one
## with a working internal market.
enum Party { VILLAGER, CROWN }

var _metrics_path: String = ""
var _events_path: String = ""
var _metrics_buffer: PackedStringArray = []
var _events_buffer: PackedStringArray = []
var _flush_accum: float = 0.0
var _paths_printed: bool = false

## Cumulative deaths over the whole run (in every metrics row).
var _cumulative_deaths: int = 0
## good -> amount traded since the last metrics sample (reset afterward).
var _trade_qty: Dictionary = {}
## M36: volume by counterparty since the last metrics sample (reset afterward).
var _trade_qty_villager: float = 0.0
var _trade_qty_crown: float = 0.0
## M36: the same, cumulative over the whole run – feeds the bench row's p2p_share.
var _trade_total_villager: float = 0.0
var _trade_total_crown: float = 0.0


func _ready() -> void:
	if not RECORD_ENABLED:
		return
	# Hook birth and game-over via the existing GameState signals – this way
	# GameState.gd stays untouched. The connection survives reload_current_scene (autoload).
	GameState.inhabitant_added.connect(_on_inhabitant_added)
	GameState.game_over.connect(_on_game_over)
	start_new_run()


## Starts a fresh run: closes out the previous one (flush) and creates two new
## files with the current timestamp. Called on game start (_ready) and on every
## restart (SaveLoadManager.restart_game).
func start_new_run() -> void:
	if not RECORD_ENABLED:
		return
	_flush_buffers()  # save any leftovers from the previous run

	DirAccess.make_dir_recursive_absolute(RUNS_DIR)
	# Strip colons from the ISO timestamp (Windows filenames).
	var stamp := Time.get_datetime_string_from_system().replace(":", "-").replace("T", "_")
	_metrics_path = "%s/run_%s_metrics.csv" % [RUNS_DIR, stamp]
	_events_path = "%s/run_%s_events.jsonl" % [RUNS_DIR, stamp]
	_metrics_buffer = PackedStringArray()
	_events_buffer = PackedStringArray()
	_cumulative_deaths = 0
	_trade_qty = {}
	_trade_qty_villager = 0.0
	_trade_qty_crown = 0.0
	_trade_total_villager = 0.0
	_trade_total_crown = 0.0

	# Create the CSV file with a header row …
	var mf := FileAccess.open(_metrics_path, FileAccess.WRITE)
	if mf != null:
		mf.store_line(_csv_header())
		mf.close()
	# … and an empty events file, so _append_lines can append to it later.
	var ef := FileAccess.open(_events_path, FileAccess.WRITE)
	if ef != null:
		ef.close()

	if not _paths_printed:
		print("[Recorder] Metrics: %s" % ProjectSettings.globalize_path(_metrics_path))
		print("[Recorder] Events:  %s" % ProjectSettings.globalize_path(_events_path))
		_paths_printed = true

	record("run_start", {})


func _process(delta: float) -> void:
	if not RECORD_ENABLED:
		return
	_flush_accum += delta
	if _flush_accum >= FLUSH_INTERVAL:
		_flush_accum = 0.0
		_flush_buffers()


# ---------------------------------------------------------------------------
# Tier 2: event stream (JSONL)
# ---------------------------------------------------------------------------
## Appends a domain event as one JSON line. `payload` is arbitrary event data.
func record(type: String, payload: Dictionary) -> void:
	if not RECORD_ENABLED:
		return
	var entry := {
		"t": SimulationManager.sim_time,
		"day": SimulationManager.get_current_day(),
		"type": type,
		"data": payload,
	}
	_events_buffer.append(JSON.stringify(entry))


## An inhabitant starving: increments the cumulative death counter (for the metrics row)
## and writes an event. profession/gold/state/missed_meals must be captured BEFORE
## GameState.remove_inhabitant() (afterward the InhabitantData no longer exists).
func record_death(id: int, profession: int, gold: float, state: int, missed_meals: int) -> void:
	if not RECORD_ENABLED:
		return
	_cumulative_deaths += 1
	record("starved", {
		"id": id,
		"profession": InhabitantData.Profession.keys()[profession],
		"gold": gold,
		"state": InhabitantData.State.keys()[state],
		"missed_meals": missed_meals,
	})


# ---------------------------------------------------------------------------
# Tier 1: KPI time series (CSV)
# ---------------------------------------------------------------------------
## Counts traded volume per good since the last sample (cheap accumulator, called from
## the exchanges' DEAL sites). Flows into the next metrics row and is then reset to zero.
## `party` (M36) is who the OTHER side was, split out so a run shows whether the settlement
## traded internally or merely funnelled everything through the crown.
func record_trade(good: int, qty: float, party: int) -> void:
	if not RECORD_ENABLED or qty <= 0.0:
		return
	_trade_qty[good] = _trade_qty.get(good, 0.0) + qty
	if party == Party.VILLAGER:
		_trade_qty_villager += qty
		_trade_total_villager += qty
	else:
		_trade_qty_crown += qty
		_trade_total_crown += qty


## Share of all traded volume that changed hands between two inhabitants rather than with the
## crown. 0.0 = the crown was the counterparty to everything (the pre-M36 failure mode).
func p2p_share() -> float:
	var total := _trade_total_villager + _trade_total_crown
	return (_trade_total_villager / total) if total > 0.0 else 0.0


## Samples a KPI snapshot and appends it as a CSV row. Called periodically from
## SimulationManager._process. Column order = _csv_header().
func sample_metrics() -> void:
	if not RECORD_ENABLED:
		return
	var row: PackedStringArray = []
	row.append("%.1f" % SimulationManager.sim_time)
	row.append(str(SimulationManager.get_current_day()))
	row.append(str(GameState.population_count()))
	row.append("%.1f" % GlobalInventory.gold)

	var gold_sum := 0.0
	var hunger_sum := 0.0
	var gold_min := INF
	var gold_max := -INF
	for inh: InhabitantData in GameState.inhabitants:
		gold_sum += inh.gold
		hunger_sum += inh.hunger
		gold_min = minf(gold_min, inh.gold)
		gold_max = maxf(gold_max, inh.gold)
	var pop := GameState.inhabitants.size()
	row.append("%.1f" % gold_sum)
	row.append("%.3f" % (hunger_sum / pop if pop > 0 else 0.0))
	row.append(str(_cumulative_deaths))

	for g in Goods.GoodType.values():
		row.append("%.1f" % GlobalInventory.get_community_total(g))
		row.append("%.1f" % GlobalInventory.get_crown_total(g))
		row.append("%.2f" % BuildingManager.get_market_price(g))
		row.append("%.1f" % _trade_qty.get(g, 0.0))

	var prof_counts: Dictionary = {}
	for inh: InhabitantData in GameState.inhabitants:
		prof_counts[inh.profession] = prof_counts.get(inh.profession, 0) + 1
	for p in InhabitantData.Profession.values():
		row.append(str(prof_counts.get(p, 0)))

	var bld_counts: Dictionary = {}
	var bld_constructed := 0
	var bld_derelict := 0
	var bld_needs_repair := 0
	for b: BuildingInstance in BuildingManager.buildings:
		bld_counts[b.def.type] = bld_counts.get(b.def.type, 0) + 1
		if b.is_constructed:
			bld_constructed += 1
		if b.is_derelict:
			bld_derelict += 1
		if b.needs_repair:
			bld_needs_repair += 1
	for t in BuildingDef.BuildingType.values():
		row.append(str(bld_counts.get(t, 0)))

	# Extra columns appended at the end of the row (additive, existing column order
	# stays stable): gold spread + building health, independent of the raw type counter above.
	row.append("%.1f" % (gold_min if pop > 0 else 0.0))
	row.append("%.1f" % (gold_max if pop > 0 else 0.0))
	row.append(str(bld_constructed))
	row.append(str(bld_derelict))
	row.append(str(bld_needs_repair))

	# M34: the profession-choice signal itself, so a balance run shows WHY a trade was picked
	# instead of only how many ended up in it. profession_scores() is deterministic (no
	# RANDOM_TIEBREAK), so sampling it here cannot shift a seeded run. A profession that is not
	# a candidate at all (gated on an upstream building/good) records 0.
	var appeal := EconomyManager.profession_scores()
	for p in InhabitantData.Profession.values():
		row.append("%.3f" % float(appeal.get(p, 0.0)))
	for g in Goods.GoodType.values():
		row.append("1" if EconomyManager.is_good_scarce(g) else "0")

	# M36: who traded with whom in this interval.
	row.append("%.1f" % _trade_qty_villager)
	row.append("%.1f" % _trade_qty_crown)

	_metrics_buffer.append(",".join(row))
	_trade_qty = {}  # trade volume per interval
	_trade_qty_villager = 0.0
	_trade_qty_crown = 0.0


func _csv_header() -> String:
	var cols: PackedStringArray = [
		"sim_time", "day", "population", "crown_gold",
		"inhabitants_gold", "avg_hunger", "cumulative_deaths",
	]
	for g in Goods.GoodType.values():
		var gname: String = Goods.GoodType.keys()[g]
		cols.append("community_" + gname)
		cols.append("crown_" + gname)
		cols.append("price_" + gname)
		cols.append("tradevol_" + gname)
	for p in InhabitantData.Profession.values():
		cols.append("prof_" + InhabitantData.Profession.keys()[p])
	for t in BuildingDef.BuildingType.values():
		cols.append("bld_" + BuildingDef.BuildingType.keys()[t])
	cols.append("gold_min")
	cols.append("gold_max")
	cols.append("bld_constructed_total")
	cols.append("bld_derelict_total")
	cols.append("bld_needs_repair_total")
	for p in InhabitantData.Profession.values():
		cols.append("appeal_" + InhabitantData.Profession.keys()[p])
	for g in Goods.GoodType.values():
		cols.append("scarce_" + Goods.GoodType.keys()[g])
	cols.append("tradevol_villager")
	cols.append("tradevol_crown")
	return ",".join(cols)


# ---------------------------------------------------------------------------
# Signal handlers
# ---------------------------------------------------------------------------
func _on_inhabitant_added(data: InhabitantData) -> void:
	record("birth", {"id": data.id, "cell": [data.cell.x, data.cell.y]})


func _on_game_over(days_survived: int) -> void:
	record("game_over", {"days_survived": days_survived})
	_flush_buffers()


# ---------------------------------------------------------------------------
# File output
# ---------------------------------------------------------------------------
## Public flush outside the normal FLUSH_INTERVAL beat or the game_over handler –
## e.g. for TurboRunner, which cleanly finishes after reaching the target day instead of dying.
func flush_now() -> void:
	if not RECORD_ENABLED:
		return
	_flush_buffers()


## M35: appends one summary row for a finished turbo run, creating bench.csv with its header the
## first time. Deliberately NOT guarded by RECORD_ENABLED: TurboRunner calls this explicitly and
## writing the row is the entire point of the call. (Benchmarking with RECORD_ENABLED = false would
## be invalid anyway — sample_metrics reaches MarketExchange.get_price()/crown_remainder(), both of
## which call _sync() and trim lots, so disabling recording changes simulation outcomes.)
func append_bench_row(strategy: String, seed_value: int, days: int, survived: bool) -> void:
	DirAccess.make_dir_recursive_absolute(RUNS_DIR)
	if not FileAccess.file_exists(BENCH_PATH):
		var header_file := FileAccess.open(BENCH_PATH, FileAccess.WRITE)
		if header_file == null:
			push_error("[Recorder] could not create %s" % BENCH_PATH)
			return
		header_file.store_line(BENCH_HEADER)
		header_file.close()
		print("[Recorder] Bench:   %s" % ProjectSettings.globalize_path(BENCH_PATH))

	# Same definitions as sample_metrics, on purpose.
	var gold_sum := 0.0
	var hunger_sum := 0.0
	for inh: InhabitantData in GameState.inhabitants:
		gold_sum += inh.gold
		hunger_sum += inh.hunger
	var pop := GameState.inhabitants.size()

	var row: PackedStringArray = [
		strategy,
		str(seed_value),
		str(days),
		"1" if survived else "0",
		str(GameState.population_count()),
		str(_cumulative_deaths),
		"%.3f" % (hunger_sum / pop if pop > 0 else 0.0),
		"%.1f" % gold_sum,
		"%.1f" % GlobalInventory.gold,
		"%.3f" % _profession_entropy(),
		"%.3f" % p2p_share(),
	]
	_append_lines(BENCH_PATH, PackedStringArray([",".join(row)]))


## M35: Shannon entropy of the final profession distribution, in BITS (log2), with NONE excluded.
## This is the direct measurement of the roster-freeze failure mode: a village of 8 farmers scores
## 0.000, one of each of the 7 professions scores log2(7) = 2.807.
## NONE is excluded deliberately — counting unemployment as its own category would make a decaying
## settlement (half the roster jobless) read as "diverse".
## It is a DIAGNOSTIC, not a goal: a settlement can be perfectly diverse and still starve, so rank
## on population with deaths as the penalty and read this alongside.
func _profession_entropy() -> float:
	var counts: Dictionary = {}
	var total := 0
	for inh: InhabitantData in GameState.inhabitants:
		if inh.profession == InhabitantData.Profession.NONE:
			continue
		counts[inh.profession] = counts.get(inh.profession, 0) + 1
		total += 1
	if total <= 0 or counts.size() < 2:
		return 0.0  # nobody employed, or everyone in one trade
	var entropy := 0.0
	for profession in counts:
		var p: float = float(counts[profession]) / float(total)
		entropy -= p * (log(p) / log(2.0))
	return entropy


func _flush_buffers() -> void:
	if not _metrics_buffer.is_empty():
		_append_lines(_metrics_path, _metrics_buffer)
		_metrics_buffer = PackedStringArray()
	if not _events_buffer.is_empty():
		_append_lines(_events_path, _events_buffer)
		_events_buffer = PackedStringArray()


## Appends lines to the end of an existing file (READ_WRITE + seek_end – WRITE would
## truncate the file). The files are created in start_new_run, so they exist here.
func _append_lines(path: String, lines: PackedStringArray) -> void:
	if path.is_empty():
		return
	var f := FileAccess.open(path, FileAccess.READ_WRITE)
	if f == null:
		return
	f.seek_end()
	for line in lines:
		f.store_line(line)
	f.close()
