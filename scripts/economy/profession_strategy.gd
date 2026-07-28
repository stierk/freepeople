class_name ProfessionStrategy
extends RefCounted

## M35: pluggable profession-choice algorithm.
##
## Profession choice is the most decisive mechanic in the simulation — it decides whether the food
## chain staffs itself or the roster freezes (see the M31/M34 blocks in EconomyManager). Judging a
## change to it by eyeballing a single turbo run has already misled once: during M34 the seed that
## was inspected happened to be the WORST of five for the change under test, and the single-seed read
## suggested a regression that the 5-seed mean contradicted. This interface exists so candidate
## algorithms can be run against a fixed set of seeds and compared on numbers (tools/bench.ps1).
##
## A strategy owns the DECISION only. The rolling production/consumption flow tracker stays in
## EconomyManager as shared infrastructure — every strategy may read it back through
## `EconomyManager.supply_rate()` / `EconomyManager.measured_consumption_rate()`.
##
## `profession_scores` (the pull side: who gets recruited) and `is_good_scarce` (the hold side: who
## is protected from being judged unprofitable) read the same underlying signal and MUST be
## implemented together by one strategy. Splitting them across strategies would reintroduce exactly
## the pull/hold disagreement M34 fixed, where FARMER/MILLER were effectively unfireable while
## BAKER/HUNTER had no protection at all.
##
## Base implementations push_error rather than returning a plausible value, so a half-implemented
## strategy fails loudly instead of quietly biasing a benchmark.


## Short identifier used by --turbo-strategy=<name> and recorded in the strategy column of
## user://runs/bench.csv.
func strategy_name() -> String:
	_not_implemented("strategy_name")
	return "?"


## Called for a freshly spawned colonist (SimulationManager._handle_seeking_site).
func assign_profession_for_new_inhabitant() -> InhabitantData.Profession:
	_not_implemented("assign_profession_for_new_inhabitant")
	return InhabitantData.Profession.NONE


## Called for a market-driven job switch. `exclude` skips a profession — normally the inhabitant's
## current one, so a switcher is never re-assigned the job they are leaving.
func pick_best_profession(_exclude: InhabitantData.Profession = InhabitantData.Profession.NONE) -> InhabitantData.Profession:
	_not_implemented("pick_best_profession")
	return InhabitantData.Profession.NONE


## Appeal per eligible profession, WITHOUT any random tie-break. Must be deterministic and must not
## consume the global RNG: it is sampled once per game day into RunRecorder's appeal_<PROF> columns
## and read by the cross-trade hut-reuse gate, and drawing here would shift a seeded run.
func profession_scores(_exclude: InhabitantData.Profession = InhabitantData.Profession.NONE) -> Dictionary:
	_not_implemented("profession_scores")
	return {}


## Hold side of the same signal: is this good in genuine deficit? Used by
## SimulationManager._check_market_profitability to keep a producer of a scarce good from
## abandoning their post on a drifted price.
func is_good_scarce(_good: int) -> bool:
	_not_implemented("is_good_scarce")
	return false


func _not_implemented(method: String) -> void:
	push_error("ProfessionStrategy.%s() not implemented by %s" % [method, get_script().resource_path])
