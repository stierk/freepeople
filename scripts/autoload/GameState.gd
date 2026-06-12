extends Node

## Feuert wenn ein neuer Bewohner erstellt wurde (M8: Bevölkerungswachstum, World.gd reagiert darauf)
signal inhabitant_added(data: InhabitantData)

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
	inhabitants.append(inh)
	inhabitant_added.emit(inh)
	return inh
