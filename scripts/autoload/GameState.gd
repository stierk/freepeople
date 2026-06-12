extends Node

var inhabitants: Array[InhabitantData] = []
var gold: float = 100.0

var _next_inhabitant_id: int = 0


func population_count() -> int:
	return inhabitants.size()


func add_inhabitant(spawn_cell: Vector2i) -> InhabitantData:
	var inh := InhabitantData.new()
	inh.id = _next_inhabitant_id
	_next_inhabitant_id += 1
	inh.cell = spawn_cell
	inh.world_pos = WorldGrid.cell_to_world(spawn_cell)
	inhabitants.append(inh)
	return inh
