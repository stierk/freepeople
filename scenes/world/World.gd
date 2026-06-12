extends Node2D

const ATLAS_GRASS := Vector2i(5, 0)
const ATLAS_WATER := Vector2i(0, 0)
const ATLAS_FOREST := Vector2i(16, 11)
const ATLAS_STONE := Vector2i(8, 13)
const ATLAS_DESIRE_PATH := Vector2i(6, 1)
const ATLAS_ROAD := Vector2i(6, 2)

const BUILDING_BASE_SCENE := preload("res://scenes/buildings/BuildingBase.tscn")
const INHABITANT_SCENE := preload("res://scenes/agents/Inhabitant.tscn")
const INITIAL_INHABITANT_COUNT := 8

@onready var terrain_layer: TileMapLayer = $TerrainLayer
@onready var overlay_layer: TileMapLayer = $OverlayLayer
@onready var buildings_container: Node2D = $BuildingsContainer
@onready var agents_container: Node2D = $AgentsContainer


func _ready() -> void:
	WorldGrid.path_type_changed.connect(_render_overlay_cell)
	BuildingManager.building_constructed.connect(_on_building_constructed)
	GameState.inhabitant_added.connect(_on_inhabitant_added)  # M8: Bevölkerungswachstum
	SaveLoadManager.game_loaded.connect(_on_game_loaded)  # M10: Save/Load

	if SaveLoadManager.has_save():
		SaveLoadManager.load_game()
	else:
		WorldGrid.generate_terrain(randi())
		WorldGrid.setup_astar()
		_render_terrain()
		_place_start_buildings()
		_spawn_initial_inhabitants()


func _render_terrain() -> void:
	for y in range(WorldGrid.MAP_SIZE.y):
		for x in range(WorldGrid.MAP_SIZE.x):
			var cell := Vector2i(x, y)
			var tile := WorldGrid.get_tile(cell)

			if tile.terrain == TileRuntimeData.TerrainType.WATER:
				terrain_layer.set_cell(cell, 0, ATLAS_WATER)
			else:
				terrain_layer.set_cell(cell, 0, ATLAS_GRASS)

			_render_overlay_cell(cell)


func _place_start_buildings() -> void:
	var center := WorldGrid.MAP_SIZE / 2
	_place_building(BuildingDef.BuildingType.STORAGE_YARD, center + Vector2i(-2, 0))
	_place_building(BuildingDef.BuildingType.GRANARY,      center + Vector2i(-1, 0))
	_place_building(BuildingDef.BuildingType.TREASURY,     center)
	_place_building(BuildingDef.BuildingType.MARKET,       center + Vector2i(1, 0))  # M8


func _place_building(type: BuildingDef.BuildingType, cell: Vector2i) -> BuildingInstance:
	var tile := WorldGrid.get_tile(cell)
	tile.terrain = TileRuntimeData.TerrainType.GRASS
	terrain_layer.set_cell(cell, 0, ATLAS_GRASS)
	overlay_layer.erase_cell(cell)

	var def := BuildingManager.get_building_def(type)
	var instance := BuildingManager.register_building(def, cell)
	WorldGrid.set_building_footprint(cell, instance.id, true)
	_instantiate_building_node(instance)

	return instance


func _instantiate_building_node(instance: BuildingInstance) -> void:
	var node := BUILDING_BASE_SCENE.instantiate()
	buildings_container.add_child(node)
	node.setup(instance.def, instance.id)
	node.position = WorldGrid.cell_to_world(instance.cell)
	instance.node_ref = node


func _on_building_constructed(building_id: int) -> void:
	var instance := BuildingManager.get_building(building_id)
	_instantiate_building_node(instance)


## M9: Vom Spieler über das Baumenü platziertes Gebäude registrieren und anzeigen.
func place_player_building(def: BuildingDef, cell: Vector2i) -> BuildingInstance:
	var instance := BuildingManager.register_building(def, cell)
	WorldGrid.set_building_footprint(cell, instance.id, true)
	overlay_layer.erase_cell(cell)
	_instantiate_building_node(instance)
	GlobalInventory.notify_resources_changed()
	return instance


func _spawn_initial_inhabitants() -> void:
	var storage := BuildingManager.get_storage_yard()
	var spawn_cell := storage.cell + Vector2i(0, 1)

	# Signal ist schon verbunden; initial direkt spawnen ohne Signal-Umweg,
	# da add_inhabitant das Signal feuert und _on_inhabitant_added den Node anlegt.
	# Aber world_pos-Jitter muss danach gesetzt werden → kurz direkt instanziieren.
	for i in range(INITIAL_INHABITANT_COUNT):
		# add_inhabitant feuert inhabitant_added → _on_inhabitant_added erstellt den Node
		var inh := GameState.add_inhabitant(spawn_cell)
		inh.world_pos += Vector2(randf_range(-5.0, 5.0), randf_range(-5.0, 5.0))
		if inh.node_ref:
			inh.node_ref.position = inh.world_pos


## M8: Bewohner-Node für per Signal gespawnten Bewohner erstellen (Bevölkerungswachstum)
func _on_inhabitant_added(inh: InhabitantData) -> void:
	_instantiate_inhabitant_node(inh)


func _instantiate_inhabitant_node(inh: InhabitantData) -> void:
	var node := INHABITANT_SCENE.instantiate()
	agents_container.add_child(node)
	node.setup(inh)
	inh.node_ref = node


## M10: Nach dem Laden eines Spielstands Terrain + Gebäude-/Bewohner-Nodes neu aufbauen.
func _on_game_loaded() -> void:
	for child in buildings_container.get_children():
		child.queue_free()
	for child in agents_container.get_children():
		child.queue_free()

	_render_terrain()

	for b: BuildingInstance in BuildingManager.buildings:
		_instantiate_building_node(b)
	for inh: InhabitantData in GameState.inhabitants:
		_instantiate_inhabitant_node(inh)


func _render_overlay_cell(cell: Vector2i) -> void:
	var tile := WorldGrid.get_tile(cell)

	match tile.path_type:
		TileRuntimeData.PathType.ROAD:
			overlay_layer.set_cell(cell, 0, ATLAS_ROAD)
			return
		TileRuntimeData.PathType.DESIRE_PATH:
			overlay_layer.set_cell(cell, 0, ATLAS_DESIRE_PATH)
			return

	match tile.terrain:
		TileRuntimeData.TerrainType.FOREST:
			overlay_layer.set_cell(cell, 0, ATLAS_FOREST)
		TileRuntimeData.TerrainType.STONE:
			overlay_layer.set_cell(cell, 0, ATLAS_STONE)
		_:
			overlay_layer.erase_cell(cell)
