extends Node

## Feuert wenn ein neuer Bewohner erstellt wurde (M8: Bevölkerungswachstum, World.gd reagiert darauf)
signal inhabitant_added(data: InhabitantData)
## M18: Feuert wenn die Bevölkerung auf 0 sinkt (Anzahl überlebter Tage).
signal game_over(days_survived: int)

var inhabitants: Array[InhabitantData] = []

var _next_inhabitant_id: int = 0


func population_count() -> int:
	return inhabitants.size()


## M10: Zähler für die nächste Bewohner-ID (für Save/Load).
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
	inh.gold = 10.0
	inhabitants.append(inh)
	inhabitant_added.emit(inh)
	return inh


## M18: Bewohner ist verstorben - aus der Simulation entfernen, Node bleibt als Grab.
## Bei Bevölkerung 0 wird game_over mit der Anzahl überlebter Tage gefeuert.
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


## M18: setzt den Bewohner-Zustand für einen Neustart zurück.
func reset_state() -> void:
	inhabitants.clear()
	_next_inhabitant_id = 0


func get_inhabitant(id: int) -> InhabitantData:
	for inh in inhabitants:
		if inh.id == id:
			return inh
	return null


## M16: für die Klick-Auswahl im InfoPanel (Main.gd reicht die getippte Zelle durch).
func get_inhabitant_at_cell(cell: Vector2i) -> InhabitantData:
	for inh in inhabitants:
		if inh.cell == cell:
			return inh
	return null


## M16: Bewohner wechselt den Beruf, verlässt seine bisherige Hütte und sucht
## über SEEKING_SITE eine neue Arbeitsstätte für den neuen Beruf.
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
	inh.state = InhabitantData.State.SEEKING_SITE
