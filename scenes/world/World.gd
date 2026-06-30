extends Node2D

# Tileset-Quellen (siehe resources/tileset_world.tres):
#   0 = BaseSet (fliegevolge): Böden, Wasser, Wege, Blumen, Steine
#   1 = Farmlands (fliegevolge): Acker-/Weizenstufen
#   2 = MasterSimple (pixelholes, Alt-Bestand): Bäume (große fliegevolge-Bäume sind
#       Mehrkachel-Cluster und passen nicht in das Per-Zelle-Overlay → offen)
const SRC_BASE := 0
const SRC_FARM := 1
const SRC_TREES := 2

# Böden / Wege / Deko (BaseSet, Blob-Innenkacheln)
const ATLAS_GRASS := Vector2i(7, 1)
const ATLAS_WATER := Vector2i(22, 1)
const ATLAS_DESIRE_PATH := Vector2i(7, 13)  # Lehm-/Feldweg
const ATLAS_ROAD := Vector2i(7, 4)          # Geröll-/Steinpflaster
const ATLAS_FLOWERS := Vector2i(4, 0)       # Blumen als Gras-Dekoration

# Natürlicher Stein (BaseSet): die Steine sind 2 Kacheln hoch. STONE_VARIANTS sind die
# Unterteile (Zeile 22); das Oberteil liegt jeweils eine Zeile darüber und wird im
# TreeTopLayer in der Zelle oberhalb gezeichnet, sodass der ganze Stein sichtbar ist.
const STONE_VARIANTS := [
	Vector2i(16, 22),
	Vector2i(17, 22),
	Vector2i(18, 22),
	Vector2i(19, 22),
]

# Acker-/Weizen-Wachstumsstufen: gepflügter Boden → grüne Triebe → sattes gelbes Feld.
# Stufe 1/2 aus Farmlands (SRC_FARM), Stufe 3 = Trockengras-Feld aus BaseSet (SRC_BASE).
const CROP_ATLAS := {
	TileRuntimeData.CropStage.STAGE_1: Vector2i(1, 4),  # frisch gepflügter Acker (Aussaat)
	TileRuntimeData.CropStage.STAGE_2: Vector2i(1, 1),  # grüne Triebe (Wachstum)
	TileRuntimeData.CropStage.STAGE_3: Vector2i(7, 7),  # sattes gelbes Feld (erntereif)
	TileRuntimeData.CropStage.DEAD:    Vector2i(1, 4),  # zurück zu kahlem Boden
}
const CROP_SRC := {
	TileRuntimeData.CropStage.STAGE_1: SRC_FARM,
	TileRuntimeData.CropStage.STAGE_2: SRC_FARM,
	TileRuntimeData.CropStage.STAGE_3: SRC_BASE,
	TileRuntimeData.CropStage.DEAD:    SRC_FARM,
}

# Baum-Varianten (pixelholes, Quelle SRC_TREES). Ein Baum, der von vielen Bäumen
# umringt ist, wird als dichter Wald gezeichnet, ein vereinzelter als freistehender Baum.
const FOREST_TREES := [   # dichtes Wald-Innere (Cluster)
	Vector2i(6, 1),
	Vector2i(6, 2),
	Vector2i(8, 1),
	Vector2i(8, 2),
]
const SINGLE_TREES := [   # freistehende Einzelbäume
	Vector2i(7, 1),
	Vector2i(7, 2),
]
## Ab so vielen benachbarten Waldzellen (von 8) gilt ein Baum als „umringt" (Wald).
const FOREST_DENSE_NEIGHBORS := 5

const BUILDING_BASE_SCENE := preload("res://scenes/buildings/BuildingBase.tscn")
const INHABITANT_SCENE := preload("res://scenes/agents/Inhabitant.tscn")
const INITIAL_INHABITANT_COUNT := 8

@onready var terrain_layer: TileMapLayer = $TerrainLayer
@onready var overlay_layer: TileMapLayer = $OverlayLayer
@onready var tree_top_layer: TileMapLayer = $TreeTopLayer
@onready var buildings_container: Node2D = $BuildingsContainer
@onready var agents_container: Node2D = $AgentsContainer


func _ready() -> void:
	WorldGrid.path_type_changed.connect(_render_overlay_cell)
	WorldGrid.crop_changed.connect(_render_overlay_cell)  # M19: Weizen neu zeichnen
	WorldGrid.terrain_changed.connect(_render_overlay_cell)  # gefällte/nachgewachsene Bäume
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
				terrain_layer.set_cell(cell, SRC_BASE, ATLAS_WATER)
			else:
				terrain_layer.set_cell(cell, SRC_BASE, ATLAS_GRASS)

			_render_overlay_cell(cell)


## M12: Einziges Start-Gebäude ist das kostenlose Rathaus, das die Startressourcen
## des Spielers (100 Holz/Stein/Nahrung) sowie spätere Lieferungen aufnimmt,
## solange noch kein Lagerplatz/Kornspeicher existiert (siehe BuildingManager Fallback).
func _place_start_buildings() -> void:
	var center := WorldGrid.MAP_SIZE / 2
	var town_hall := _place_building(BuildingDef.BuildingType.TOWN_HALL, center - Vector2i(1, 1))
	town_hall.community_stock[Goods.GoodType.WOOD] = 100000.0
	town_hall.community_stock[Goods.GoodType.STONE] = 100000.0
	town_hall.community_stock[Goods.GoodType.FOOD] = 100000.0


## M11: unterstützt mehrzellige Footprints (origin = obere linke Ecke).
func _place_building(type: BuildingDef.BuildingType, cell: Vector2i) -> BuildingInstance:
	var def := BuildingManager.get_building_def(type)

	for c in WorldGrid.get_footprint_cells(cell, def.footprint_size):
		var tile := WorldGrid.get_tile(c)
		tile.terrain = TileRuntimeData.TerrainType.GRASS
		terrain_layer.set_cell(c, SRC_BASE, ATLAS_GRASS)
		overlay_layer.erase_cell(c)
		tree_top_layer.erase_cell(Vector2i(c.x, c.y - 1))

	var instance := BuildingManager.register_building(def, cell)
	WorldGrid.set_building_footprint_rect(cell, def.footprint_size, instance.id, true)
	_instantiate_building_node(instance)

	return instance


func _instantiate_building_node(instance: BuildingInstance) -> void:
	var node := BUILDING_BASE_SCENE.instantiate()
	buildings_container.add_child(node)
	node.setup(instance.def, instance.id)
	# M11: Node-Position ist die obere linke Ecke des (mehrzelligen) Footprints.
	node.position = Vector2(instance.cell * WorldGrid.TILE_SIZE)
	instance.node_ref = node


func _on_building_constructed(building_id: int) -> void:
	var instance := BuildingManager.get_building(building_id)
	_instantiate_building_node(instance)


## M9/M11: Vom Spieler über das Baumenü platziertes Gebäude registrieren und anzeigen
## (unterstützt mehrzellige Footprints).
func place_player_building(def: BuildingDef, cell: Vector2i) -> BuildingInstance:
	var instance := BuildingManager.register_building(def, cell)
	WorldGrid.set_building_footprint_rect(cell, def.footprint_size, instance.id, true)
	for c in WorldGrid.get_footprint_cells(cell, def.footprint_size):
		overlay_layer.erase_cell(c)
		tree_top_layer.erase_cell(Vector2i(c.x, c.y - 1))
	_instantiate_building_node(instance)
	_transfer_town_hall_stock(instance)
	GlobalInventory.notify_resources_changed()
	return instance


## Transfer goods from the town hall fallback to the first dedicated storage building.
func _transfer_town_hall_stock(instance: BuildingInstance) -> void:
	if BuildingManager.get_buildings_by_type(instance.def.type).size() != 1:
		return
	var town_hall := BuildingManager.get_town_hall()
	if town_hall == null or town_hall == instance:
		return
	var goods_to_move: Array[int] = []
	match instance.def.type:
		BuildingDef.BuildingType.GRANARY:
			goods_to_move = [Goods.GoodType.FOOD, Goods.GoodType.GRAIN, Goods.GoodType.FLOUR]
		BuildingDef.BuildingType.STORAGE_YARD:
			goods_to_move = [Goods.GoodType.WOOD, Goods.GoodType.STONE, Goods.GoodType.PLANKS]
	for good in goods_to_move:
		var amount: float = town_hall.community_stock.get(good, 0.0)
		if amount > 0.0:
			town_hall.community_stock[good] = 0.0
			instance.community_stock[good] = instance.community_stock.get(good, 0.0) + amount


func _spawn_initial_inhabitants() -> void:
	var town_hall := BuildingManager.get_town_hall()
	var spawn_cell := town_hall.cell + Vector2i(1, town_hall.def.footprint_size.y)

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
	var top_cell := Vector2i(cell.x, cell.y - 1)

	match tile.path_type:
		TileRuntimeData.PathType.ROAD:
			overlay_layer.set_cell(cell, SRC_BASE, ATLAS_ROAD)
			tree_top_layer.erase_cell(top_cell)
			return
		TileRuntimeData.PathType.DESIRE_PATH:
			overlay_layer.set_cell(cell, SRC_BASE, ATLAS_DESIRE_PATH)
			tree_top_layer.erase_cell(top_cell)
			return

	# M19: Weizen wird über dem Grasboden gezeichnet.
	if tile.crop_stage != TileRuntimeData.CropStage.NONE:
		overlay_layer.set_cell(cell, CROP_SRC[tile.crop_stage], CROP_ATLAS[tile.crop_stage])
		tree_top_layer.erase_cell(top_cell)
		return

	match tile.terrain:
		TileRuntimeData.TerrainType.FOREST:
			# Dichter Wald, wenn von genug Bäumen umringt; sonst freistehender Baum.
			var variants := FOREST_TREES if WorldGrid.count_forest_neighbors(cell) >= FOREST_DENSE_NEIGHBORS else SINGLE_TREES
			var t := (cell.x * 7 + cell.y * 13) % variants.size()
			overlay_layer.set_cell(cell, SRC_TREES, variants[t])
			tree_top_layer.erase_cell(top_cell)
		TileRuntimeData.TerrainType.STONE:
			# Unterteil in der Zelle, Oberteil eine Zelle höher (2-Kachel-Stein).
			var bottom: Vector2i = STONE_VARIANTS[(cell.x * 11 + cell.y * 5) % STONE_VARIANTS.size()]
			overlay_layer.set_cell(cell, SRC_BASE, bottom)
			tree_top_layer.set_cell(top_cell, SRC_BASE, bottom + Vector2i(0, -1))
		TileRuntimeData.TerrainType.GRASS:
			# Vereinzelte Blumen als Dekoration auf leerem Gras streuen. Ein
			# Hash-Rauschen pro Zelle ergibt ein unregelmäßiges, zufällig wirkendes
			# Muster (deterministisch, damit Neuzeichnen stabil bleibt).
			if _is_flower_cell(cell):
				overlay_layer.set_cell(cell, SRC_BASE, ATLAS_FLOWERS)
			else:
				overlay_layer.erase_cell(cell)
			tree_top_layer.erase_cell(top_cell)
		_:
			overlay_layer.erase_cell(cell)
			tree_top_layer.erase_cell(top_cell)


## Pseudo-zufälliges, aber deterministisches Streumuster für Blumen (~6 % der
## Graszellen). Klassisches fract(sin)-Hash-Rauschen statt eines regelmäßigen Modulos.
func _is_flower_cell(cell: Vector2i) -> bool:
	var h := sin(cell.x * 127.1 + cell.y * 311.7) * 43758.5453
	return (h - floorf(h)) < 0.06
