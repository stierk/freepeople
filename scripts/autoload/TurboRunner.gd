## TurboRunner – dev-only headless fast-forward test harness for long unattended runs.
##
## Inert unless launched with `--turbo=<days>` after `--` on the command line; never touches
## the player-facing SPEED_MULTIPLIERS or UI. Once active, it stops SimulationManager's
## engine-driven _process and steps it directly with a synthetic delta instead, decoupling
## simulated days from real wall-clock time (normally: simulated seconds = real seconds ×
## speed multiplier, capped at 5×). This lets a 1000-day balance test finish in minutes
## instead of hours.
##
## Usage:
##   <godot> --headless --path "<project>" -- --turbo=1000 [--turbo-step=1.0] [--turbo-seed=42]
##
## Exit codes: 0 = reached target day with population > 0, 1 = population died out first,
## 2 = bad invocation (missing/invalid --turbo=).
extends Node

const DEFAULT_STEP_SECONDS := 1.0
## Sim-seconds stepped per real engine frame before yielding once (keeps Godot responsive
## under --headless: OS event loop, RunRecorder's real-time flush timer, etc.).
const STEPS_PER_BATCH := 200
## Max real frames to wait for World.gd's bootstrap (Town Hall + starting population) before
## giving up. Should never trigger in practice (autoloads run before the main scene), but
## it's the safeguard against silently hanging if that ever changes.
const BOOTSTRAP_TIMEOUT_FRAMES := 600

var _target_day := 0
var _step_seconds := DEFAULT_STEP_SECONDS
var _turbo_requested := false
## When true (--turbo-storage), a Storage Yard + Granary are placed as close to the
## Town Hall as possible right after bootstrap – simulates a foresightful player's
## opening move for a balance test (see the storage-near-townhall scenario).
var _place_storage := false
## When >= 0 (--turbo-food-price=<x>), the crown's FOOD Sell price is set to <x> right after
## bootstrap – the headless equivalent of a player moving that stepper in the Town Hall UI.
## Exists to verify that the price lever actually reaches profession scoring (M34): the appeal of
## the FOOD professions must rise by PROFIT_WEIGHT * (x / BASE_PRICES[FOOD] - 1).
var _food_price := -1.0
## M35: the seed actually used, kept for the bench.csv row. -1 = no --turbo-seed given, i.e. the run
## is not reproducible and should not be compared against anything.
var _seed_value := -1


func _ready() -> void:
	var turbo_arg := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--turbo="):
			turbo_arg = a.substr(8)
			_turbo_requested = true
		elif a.begins_with("--turbo-step="):
			_step_seconds = float(a.substr(13))
		elif a == "--turbo-storage":
			_place_storage = true
		elif a.begins_with("--turbo-food-price="):
			_food_price = float(a.substr(19))
		elif a.begins_with("--turbo-seed="):
			# M34: seed the global RNG so a turbo run is reproducible. Without this, World.gd
			# calls WorldGrid.generate_terrain(randi()) on an engine-autoseeded RNG, so every
			# run gets a different map AND a different trait lottery – two runs of identical
			# code are then not comparable, which is what made earlier balance passes rely on
			# eyeballing variance across runs (see the M27 note in EconomyManager.gd).
			# This must happen in an autoload's _ready(), i.e. before World._ready() draws.
			_seed_value = int(a.substr(13))
			seed(_seed_value)
	if not _turbo_requested:
		return

	_target_day = int(turbo_arg)
	if _target_day <= 0 or _step_seconds <= 0.0:
		push_error("[Turbo] invalid --turbo=%s / --turbo-step=%.3f" % [turbo_arg, _step_seconds])
		get_tree().quit(2)
		return

	# M35: stop SimulationManager's engine-driven _process SYNCHRONOUSLY, here, rather than only in
	# the deferred _wait_for_bootstrap below. SimulationManager has no _ready(), so set_process
	# defaults to true and the engine dispatches _process(real_delta) to it; MessageQueue flushes
	# call_deferred AFTER the _process dispatch in SceneTree::process(). So a single leaked frame
	# would push a wall-clock delta into sim_time and advance_flow_clock and break reproducibility.
	# It happens to work today only because the main scene is instantiated before the first frame,
	# so _wait_for_bootstrap finds the Town Hall immediately and never awaits — an ordering accident
	# the whole benchmark would otherwise rest on.
	SimulationManager.set_process(false)

	# Always bootstrap fresh: an existing save game would send World._ready() down the
	# load branch instead of the new-game branch (see World.gd _ready).
	if FileAccess.file_exists(SaveLoadManager.SAVE_PATH):
		DirAccess.remove_absolute(SaveLoadManager.SAVE_PATH)

	print("[Turbo] target_day=%d step=%.2fs — waiting for world bootstrap" % [_target_day, _step_seconds])
	call_deferred("_wait_for_bootstrap")


## World.gd (part of the main scene) only runs AFTER all autoloads – waits until Town Hall +
## starting population exist before the simulation is ticked manually.
func _wait_for_bootstrap() -> void:
	var frames := 0
	while BuildingManager.get_town_hall() == null or GameState.inhabitants.is_empty():
		await get_tree().process_frame
		frames += 1
		if frames >= BOOTSTRAP_TIMEOUT_FRAMES:
			push_error("[Turbo] world bootstrap did not complete after %d frames — aborting" % frames)
			get_tree().quit(2)
			return
	# Turn off SimulationManager's engine-driven _process – from here on we tick it
	# ourselves with a synthetic delta, independent of the real frame time/FPS.
	SimulationManager.set_process(false)
	SimulationManager.speed_mode = SimulationManager.SpeedMode.NORMAL
	if _place_storage:
		_place_storage_near_townhall()
	if _food_price >= 0.0:
		var th := BuildingManager.get_town_hall()
		if th != null and th.trade_data != null:
			th.trade_data.sell_price[Goods.GoodType.FOOD] = _food_price
			print("[Turbo] crown FOOD Sell price set to %.2f" % _food_price)
		else:
			push_error("[Turbo] --turbo-food-price: Town Hall has no TradeData")
	print("[Turbo] bootstrap ready (pop=%d), stepping..." % GameState.population_count())
	_run_loop()


## Places a Storage Yard and a Granary on the nearest fully-grass, buildable footprints
## to the Town Hall (foresightful-player opening). Goes through World.place_player_building
## so the Town Hall's starting stock is transferred into the new storage/granary exactly like
## a real player click would (see World._transfer_town_hall_stock).
func _place_storage_near_townhall() -> void:
	var world := _find_world()
	if world == null:
		push_error("[Turbo] --turbo-storage: could not find World node")
		return
	var th := BuildingManager.get_town_hall()
	var yard_def := BuildingManager.get_building_def(BuildingDef.BuildingType.STORAGE_YARD)
	var gran_def := BuildingManager.get_building_def(BuildingDef.BuildingType.GRANARY)
	var yard_cell := _nearest_buildable_grass(th, yard_def.footprint_size)
	if yard_cell.x >= 0:
		world.place_player_building(yard_def, yard_cell)
		print("[Turbo] placed Storage Yard at %s" % yard_cell)
	var gran_cell := _nearest_buildable_grass(th, gran_def.footprint_size)
	if gran_cell.x >= 0:
		world.place_player_building(gran_def, gran_cell)
		print("[Turbo] placed Granary at %s" % gran_cell)


## Spirals outward from the Town Hall footprint and returns the closest (Manhattan, to the
## Town Hall's top-left cell) origin whose whole footprint is buildable grass. (-1,-1) if none.
func _nearest_buildable_grass(town_hall: BuildingInstance, size: Vector2i) -> Vector2i:
	var center := town_hall.cell
	var best := Vector2i(-1, -1)
	var best_dist := 1 << 30
	for radius in range(1, 20):
		for dy in range(-radius, radius + 1):
			for dx in range(-radius, radius + 1):
				if maxi(absi(dx), absi(dy)) != radius:
					continue  # only the current ring's outline
				var origin := center + Vector2i(dx, dy)
				if not _is_all_grass_buildable(origin, size):
					continue
				var dist := absi(origin.x - center.x) + absi(origin.y - center.y)
				if dist < best_dist:
					best_dist = dist
					best = origin
		if best.x >= 0:
			return best  # closest ring with any fit wins
	return best


func _is_all_grass_buildable(origin: Vector2i, size: Vector2i) -> bool:
	if not WorldGrid.is_footprint_buildable(origin, size):
		return false
	for cell in WorldGrid.get_footprint_cells(origin, size):
		if WorldGrid.get_tile(cell).terrain != TileRuntimeData.TerrainType.GRASS:
			return false
	return true


## Finds the World node (holds place_player_building) anywhere under the current scene.
func _find_world() -> Node:
	var root := get_tree().current_scene
	if root == null:
		return null
	return _find_node_with_method(root, "place_player_building")


func _find_node_with_method(node: Node, method: String) -> Node:
	if node.has_method(method):
		return node
	for child in node.get_children():
		var found := _find_node_with_method(child, method)
		if found != null:
			return found
	return null


func _run_loop() -> void:
	while true:
		for i in range(STEPS_PER_BATCH):
			if GameState.inhabitants.is_empty():
				_finish(false)
				return
			if SimulationManager.get_current_day() >= _target_day:
				_finish(true)
				return
			SimulationManager._process(_step_seconds)
		await get_tree().process_frame


func _finish(survived: bool) -> void:
	RunRecorder.flush_now()
	var day := SimulationManager.get_current_day()
	var pop := GameState.population_count()
	# M35: machine-readable summary for tools/bench.ps1, appended across runs. The human-readable
	# RESULT= line below and the exit codes stay exactly as they were — both are relied on.
	RunRecorder.append_bench_row(EconomyManager.strategy_name(), _seed_value, day, survived)
	if survived:
		print("[Turbo] RESULT=SURVIVED day=%d population=%d crown_gold=%.1f" % [day, pop, GlobalInventory.gold])
	else:
		print("[Turbo] RESULT=DIED day=%d" % day)
	get_tree().quit(0 if survived else 1)
