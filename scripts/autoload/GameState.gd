extends Node

## Fires when a new inhabitant was created (M8: population growth, World.gd reacts to this)
signal inhabitant_added(data: InhabitantData)
## M18: fires when the population drops to 0 (number of days survived).
signal game_over(days_survived: int)

var inhabitants: Array[InhabitantData] = []

var _next_inhabitant_id: int = 0


func population_count() -> int:
	return inhabitants.size()


## M31: tally of how many inhabitants currently hold each profession (Profession -> int).
## NONE is included as a key but the profession scoring only reads the working professions.
## Used by EconomyManager.pick_best_profession as an anti-clustering (crowding) signal.
func count_by_profession() -> Dictionary:
	var counts := {}
	for inh in inhabitants:
		counts[inh.profession] = counts.get(inh.profession, 0) + 1
	return counts


## M10: counter for the next inhabitant ID (for save/load).
func get_next_inhabitant_id() -> int:
	return _next_inhabitant_id


func set_next_inhabitant_id(value: int) -> void:
	_next_inhabitant_id = value


func add_inhabitant(spawn_cell: Vector2i) -> InhabitantData:
	var inh := InhabitantData.new()
	inh.id = _next_inhabitant_id
	_next_inhabitant_id += 1
	inh.cell = spawn_cell
	inh.world_pos = WorldGrid.cell_to_world(spawn_cell)
	inh.gold = 100.0
	# M22: small starting food stock, so a freshly spawned inhabitant doesn't starve
	# before they manage their first buy-food trip to the granary.
	inh.inventory[Goods.GoodType.FOOD] = 30.0
	inh.margin = randf()  # M20: personal price margin [0,1] (= greed trait, see M28)
	inh.job_check_factor = randf()  # personal profession-switch check interval (× 10 days)
	# M28: evolutionary traits – random at spawn. Each has a benefit and a drawback, see
	# inhabitant_data.gd and docs/GAME_DESIGN.md §12. Reproduction (child inherits a mix of both
	# parents) is planned as a later expansion; until then everyone spawns freshly randomized.
	inh.trait_speed = randf()
	inh.trait_strength = randf()
	inh.trait_frugality = randf()
	inh.trait_diligence = randf()
	inh.trait_resilience = randf()
	inh.recompute_derived_stats()
	inhabitants.append(inh)
	inhabitant_added.emit(inh)
	return inh


## M18: inhabitant has died - remove from the simulation, node remains as a grave.
## At population 0, game_over fires with the number of days survived.
func remove_inhabitant(id: int) -> void:
	for i in range(inhabitants.size()):
		if inhabitants[i].id == id:
			var inh := inhabitants[i]
			inhabitants.remove_at(i)
			if inh.node_ref != null:
				inh.node_ref.mark_as_grave()
			break

	GlobalInventory.notify_population_changed(population_count())
	if inhabitants.is_empty():
		game_over.emit(SimulationManager.get_current_day())


## M18: resets inhabitant state for a restart.
func reset_state() -> void:
	inhabitants.clear()
	_next_inhabitant_id = 0


func get_inhabitant(id: int) -> InhabitantData:
	for inh in inhabitants:
		if inh.id == id:
			return inh
	return null


## M16: for click selection in the InfoPanel (Main.gd passes the tapped cell through).
func get_inhabitant_at_cell(cell: Vector2i) -> InhabitantData:
	for inh in inhabitants:
		if inh.cell == cell:
			return inh
	return null


## M16: inhabitant changes profession, leaves their previous hut and looks for
## a new workplace for the new profession via SEEKING_SITE.
func change_profession(inhabitant_id: int, new_profession: InhabitantData.Profession) -> void:
	var inh := get_inhabitant(inhabitant_id)
	if inh == null or inh.profession == new_profession:
		return

	var old_hut := BuildingManager.get_building(inh.home_building_id)
	if old_hut != null:
		old_hut.occupants.erase(inhabitant_id)

	inh.profession = new_profession
	inh.home_building_id = -1
	inh.target_site_cell = Vector2i(-1, -1)
	inh.path = PackedVector2Array()
	inh.path_index = 0
	# M27: without this reset, time_since_last_sale keeps running since the last sale in the OLD
	# profession – recompute_break_even() would then keep raising the break-even price during the
	# hut build/first harvest in the NEW profession, which can trigger another profession switch
	# before the new profession ever got a chance at its first sale
	# (observed: FARMER→MILLER→FARMER→MILLER oscillation without a windmill ever getting finished).
	inh.time_since_last_sale = 0.0
	# M21: search again immediately (don't wait for the idle throttle), so the hut freed
	# up by the old trade is quickly reoccupied by an unemployed inhabitant.
	inh.idle_retry_timer = 0.0
	inh.state = InhabitantData.State.SEEKING_SITE
