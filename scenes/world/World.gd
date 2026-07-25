extends Node2D

# Tileset sources (see resources/tileset_world.tres):
#   0 = BaseSet (fliegevolge): ground, water, paths, flowers, stone
#   1 = Farmlands (fliegevolge): farmland/wheat stages
#   2 = MasterSimple (pixelholes, legacy assets): trees (the large fliegevolge trees are
#       multi-tile clusters and don't fit the per-cell overlay → open issue)
const SRC_BASE := 0
const SRC_FARM := 1
const SRC_TREES := 2

# Ground / paths / decoration (BaseSet)
const ATLAS_GRASS := Vector2i(1, 1)          # clean meadow (footprint fill)
# Meadow variants for some rendering variety.
const GRASS_TILES := [Vector2i(1, 1), Vector2i(0, 0), Vector2i(2, 0), Vector2i(0, 1)]
# Coastline autotiling (code-based): water tile depending on which sides border
# land. Mask: N=1, E=2, S=4, W=8 (bit set = land/grass borders there).
# The 9 tiles come from the water-to-grass blob [21,0]–[23,2].
const ATLAS_WATER := Vector2i(22, 1)         # full water (center)
const WATER_EDGE_TILES := {
	0: Vector2i(22, 1),   # water all around
	1: Vector2i(22, 0),   # land to the north
	2: Vector2i(23, 1),   # land to the east
	4: Vector2i(22, 2),   # land to the south
	8: Vector2i(21, 1),   # land to the west
	9: Vector2i(21, 0),   # north+west (top-left corner)
	3: Vector2i(23, 0),   # north+east (top-right corner)
	12: Vector2i(21, 2),  # south+west (bottom-left corner)
	6: Vector2i(23, 2),   # south+east (bottom-right corner)
}
# Path autotiling (code-based like the coastline). Mask: N=1, E=2, S=4, W=8
# (bit set = NO path borders there). Dirt blob [6,12]–[8,14] (desire path),
# gravel blob [6,3]–[8,5] (road/pavement).
const ATLAS_DESIRE_PATH := Vector2i(7, 13)  # full dirt (center / fallback)
const PATH_TILES := {
	# area/corner/edge tiles (dirt blob [6,12]–[8,14])
	0: Vector2i(7, 13), 1: Vector2i(7, 12), 2: Vector2i(8, 13), 4: Vector2i(7, 14), 8: Vector2i(6, 13),
	9: Vector2i(6, 12), 3: Vector2i(8, 12), 12: Vector2i(6, 14), 6: Vector2i(8, 14),
	# 1-wide paths with a real edge: vertical strip [9,12]–[9,14], horizontal
	# [10,14]–[12,14], single spot [13,14].
	10: Vector2i(9, 13),  # vertical (grass E+W)
	11: Vector2i(9, 12),  # vertical top end (path continues downward)
	14: Vector2i(9, 14),  # vertical bottom end (path continues upward)
	5: Vector2i(11, 14),  # horizontal (grass N+S)
	13: Vector2i(10, 14), # horizontal left end (path continues to the right)
	7: Vector2i(12, 14),  # horizontal right end (path continues to the left)
	15: Vector2i(13, 14), # single path cell (grass all around)
}
const ATLAS_ROAD := Vector2i(7, 4)          # full gravel (center / fallback)
const ROAD_TILES := {
	0: Vector2i(7, 4), 1: Vector2i(7, 3), 2: Vector2i(8, 4), 4: Vector2i(7, 5), 8: Vector2i(6, 4),
	9: Vector2i(6, 3), 3: Vector2i(8, 3), 12: Vector2i(6, 5), 6: Vector2i(8, 5),
}
const ATLAS_FLOWERS := Vector2i(4, 0)       # flowers as grass decoration

# Natural stone (BaseSet): the stones are 2 tiles tall. STONE_VARIANTS are the
# bottom halves (row 22); the top half sits one row above and is drawn in the
# TreeTopLayer in the cell above, so the whole stone is visible.
const STONE_VARIANTS := [
	Vector2i(16, 22),
	Vector2i(17, 22),
	Vector2i(18, 22),
	Vector2i(19, 22),
]

# Farmland/wheat growth stages (Farmlands raised beds, column 15): empty bed
# (sown) → seedlings → ripe stalks. After harvest/empty farmland the bed shows
# stage 1 again (empty bed).
const ATLAS_FALLOW := Vector2i(15, 0)  # empty farmland bed (harvested or not yet sown)
const CROP_ATLAS := {
	TileRuntimeData.CropStage.STAGE_1: Vector2i(15, 0),  # empty bed (sown)
	TileRuntimeData.CropStage.STAGE_2: Vector2i(15, 1),  # seedlings
	TileRuntimeData.CropStage.STAGE_3: Vector2i(15, 3),  # ripe stalks (ready to harvest)
	TileRuntimeData.CropStage.DEAD:    Vector2i(15, 0),  # back to the empty bed
}
const CROP_SRC := {
	TileRuntimeData.CropStage.STAGE_1: SRC_FARM,
	TileRuntimeData.CropStage.STAGE_2: SRC_FARM,
	TileRuntimeData.CropStage.STAGE_3: SRC_FARM,
	TileRuntimeData.CropStage.DEAD:    SRC_FARM,
}

# Tree variants (pixelholes, source SRC_TREES). A tree surrounded by many other
# trees is drawn as dense forest, an isolated one as a standalone tree.
const FOREST_TREES := [   # dense forest interior (cluster)
	Vector2i(6, 1),
	Vector2i(6, 2),
	Vector2i(8, 1),
	Vector2i(8, 2),
]
const SINGLE_TREES := [   # standalone individual trees
	Vector2i(7, 1),
	Vector2i(7, 2),
]
## From this many neighboring forest cells (out of 8) onward, a tree counts as "surrounded" (forest).
const FOREST_DENSE_NEIGHBORS := 5

const BUILDING_BASE_SCENE := preload("res://scenes/buildings/BuildingBase.tscn")
const INHABITANT_SCENE := preload("res://scenes/agents/Inhabitant.tscn")
const INITIAL_INHABITANT_COUNT := 10

@onready var terrain_layer: TileMapLayer = $TerrainLayer
@onready var overlay_layer: TileMapLayer = $OverlayLayer
@onready var tree_top_layer: TileMapLayer = $TreeTopLayer
@onready var buildings_container: Node2D = $BuildingsContainer
@onready var agents_container: Node2D = $AgentsContainer


func _ready() -> void:
	WorldGrid.path_type_changed.connect(_on_path_changed)  # path + neighbors (autotiling)
	WorldGrid.crop_changed.connect(_render_overlay_cell)  # M19: redraw wheat
	WorldGrid.terrain_changed.connect(_render_overlay_cell)  # felled/regrown trees
	BuildingManager.building_constructed.connect(_on_building_constructed)
	GameState.inhabitant_added.connect(_on_inhabitant_added)  # M8: population growth
	SaveLoadManager.game_loaded.connect(_on_game_loaded)  # M10: save/load

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
				terrain_layer.set_cell(cell, SRC_BASE, _water_tile(cell))
			else:
				terrain_layer.set_cell(cell, SRC_BASE, _grass_tile(cell))

			_render_overlay_cell(cell)


## Chooses the matching water tile based on the adjacent land/grass sides (coastline
## autotiling). Edges outside the map count as water, so no artificial coastline
## appears at the map border.
func _water_tile(cell: Vector2i) -> Vector2i:
	var mask := 0
	if not _is_water(cell + Vector2i(0, -1)): mask |= 1   # north = land
	if not _is_water(cell + Vector2i(1, 0)):  mask |= 2   # east
	if not _is_water(cell + Vector2i(0, 1)):  mask |= 4   # south
	if not _is_water(cell + Vector2i(-1, 0)): mask |= 8   # west
	return WATER_EDGE_TILES.get(mask, ATLAS_WATER)


func _is_water(cell: Vector2i) -> bool:
	if not WorldGrid.is_valid_cell(cell):
		return true  # treat the map edge as water (no coastline at the border)
	return WorldGrid.get_tile(cell).terrain == TileRuntimeData.TerrainType.WATER


## Ground tile per cell: green grass (variant from GRASS_TILES).
func _grass_tile(cell: Vector2i) -> Vector2i:
	return GRASS_TILES[(cell.x * 13 + cell.y * 7) % GRASS_TILES.size()]


## Path autotiling: tile depending on which sides have NO path bordering.
func _path_tile(cell: Vector2i, tiles: Dictionary, fallback: Vector2i) -> Vector2i:
	var mask := 0
	if not _is_path(cell + Vector2i(0, -1)): mask |= 1
	if not _is_path(cell + Vector2i(1, 0)):  mask |= 2
	if not _is_path(cell + Vector2i(0, 1)):  mask |= 4
	if not _is_path(cell + Vector2i(-1, 0)): mask |= 8
	return tiles.get(mask, fallback)


func _is_path(cell: Vector2i) -> bool:
	if not WorldGrid.is_valid_cell(cell):
		return false
	return WorldGrid.get_tile(cell).path_type != TileRuntimeData.PathType.NONE


## A new/removed path also changes the neighbors' connecting tiles → redraw them too.
func _on_path_changed(cell: Vector2i) -> void:
	_render_overlay_cell(cell)
	for dir in [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]:
		if WorldGrid.is_valid_cell(cell + dir):
			_render_overlay_cell(cell + dir)


## M12: the only starting building is the free Town Hall, which holds the player's
## starting resources as well as later deliveries as long as no storage yard/granary
## exists yet (see BuildingManager fallback).
##
## M27: without player action, storage yard/granary/treasury stay unbuilt forever
## (only placeable via a BuildMenu click) – the Town Hall is therefore not just a transitional
## fallback but, for an unattended run, the ONLY storage/policy building that will
## ever exist. Its Town Hall policy (see below) therefore already gets sensible
## default values here instead of staying at 0, as previously only the player could change via UI.
## M27: starting stock sized tight instead of generous (factor ~3-10 below the original
## 1000/1000/1000/10000), but NOT narrowed down to a pure initial-build lottery: turbo test runs
## showed that the first ~50-90 days are very volatile (all 3 colonists can simultaneously
## become FARMER → several separate farm houses; unoccupied huts fall derelict after
## REPAIR_INTERVAL_DAYS+REPAIR_GRACE_DAYS unused and must be restored at the FULL
## build price) and the food chain (farmer→mill→bakery) takes DIFFERENT AMOUNTS OF TIME
## depending on the starting colonists' profession lottery to run stably enough and produce net
## food.
##
## M31: the food buffer was deliberately CUT from 3000 to a much smaller cushion. The old huge
## buffer masked food scarcity for ~200 days (stock ≫ EconomyManager.TARGET_FOOD=120), which (a)
## suppressed BAKER/HUNTER recruitment (both keyed to food urgency) and (b) — because eating means
## buying crown-remainder food at the Sell Price while the only product, grain, sells for less —
## drained every inhabitant's gold into the crown treasury within ~22 days (the documented
## death-spiral: bankrupt and starving in front of a full granary). A smaller cushion lets food
## scarcity surface early, so the settlement's own food producers (hunter needs only forest, no
## chain) come online and — together with the M31 market tie-break (see MarketExchange._purchase)
## — actually earn, keeping money circulating. Wood/stone still cover the volatile build phase.
## Planks are never needed (the sawmill is unreachable for inhabitants without a storage yard, see
## BuildingManager.has_storage_yard) and therefore stay at 0.
func _place_start_buildings() -> void:
	var center := WorldGrid.MAP_SIZE / 2
	var town_hall := _place_building(BuildingDef.BuildingType.TOWN_HALL, center - Vector2i(1, 1))
	town_hall.community_stock[Goods.GoodType.WOOD] = 300.0
	town_hall.community_stock[Goods.GoodType.STONE] = 200.0
	town_hall.community_stock[Goods.GoodType.FOOD] = 115.0

	# M27: the crown's baseline policy (uniform, applies equally to all inhabitants; as before,
	# always changeable by the player in the Town Hall UI). Without this, the design-documented
	# "safety net against the death spiral" stays completely inert in an unattended game
	# (see docs/GAME_DESIGN.md §6) – a baseline test run with the old 0 default showed exactly
	# this death-spiral case: inhabitants go bankrupt and starve despite a full granary,
	# because nobody without income can buy new food.
	town_hall.policy.basic_income = 0.0
	town_hall.policy.subsidy[Goods.GoodType.FOOD] = 0.0
	town_hall.policy.subsidy[Goods.GoodType.STONE] = 0.0


## M11: supports multi-cell footprints (origin = top-left corner).
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
	# M11: node position is the top-left corner of the (multi-cell) footprint.
	node.position = Vector2(instance.cell * WorldGrid.TILE_SIZE)
	instance.node_ref = node
	# M21: tint huts that already need repair (e.g. after loading) immediately.
	if instance.needs_repair and node.has_method("set_repair_visual"):
		node.set_repair_visual(true)
	# M22: tint derelict ruins (e.g. after loading) as a ruin immediately.
	if instance.is_derelict and node.has_method("set_derelict_visual"):
		node.set_derelict_visual(true)


func _on_building_constructed(building_id: int) -> void:
	var instance := BuildingManager.get_building(building_id)
	_instantiate_building_node(instance)


## M9/M11: register and display a building placed by the player via the build menu
## (supports multi-cell footprints).
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

	# The signal is already connected; spawn directly at first without going through the
	# signal, since add_inhabitant fires the signal and _on_inhabitant_added creates the node.
	# But the world_pos jitter must be set afterward → briefly instantiate directly.
	for i in range(INITIAL_INHABITANT_COUNT):
		# add_inhabitant fires inhabitant_added → _on_inhabitant_added creates the node
		var inh := GameState.add_inhabitant(spawn_cell)
		inh.world_pos += Vector2(randf_range(-5.0, 5.0), randf_range(-5.0, 5.0))
		if inh.node_ref:
			inh.node_ref.position = inh.world_pos


## M8: create the inhabitant node for an inhabitant spawned via signal (population growth)
func _on_inhabitant_added(inh: InhabitantData) -> void:
	_instantiate_inhabitant_node(inh)


func _instantiate_inhabitant_node(inh: InhabitantData) -> void:
	var node := INHABITANT_SCENE.instantiate()
	agents_container.add_child(node)
	node.setup(inh)
	inh.node_ref = node


## M10: rebuild terrain + building/inhabitant nodes after loading a save game.
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
			overlay_layer.set_cell(cell, SRC_BASE, _path_tile(cell, ROAD_TILES, ATLAS_ROAD))
			tree_top_layer.erase_cell(top_cell)
			return
		TileRuntimeData.PathType.DESIRE_PATH:
			overlay_layer.set_cell(cell, SRC_BASE, _path_tile(cell, PATH_TILES, ATLAS_DESIRE_PATH))
			tree_top_layer.erase_cell(top_cell)
			return

	# M19: wheat is drawn on top of the grass ground.
	if tile.crop_stage != TileRuntimeData.CropStage.NONE:
		overlay_layer.set_cell(cell, CROP_SRC[tile.crop_stage], CROP_ATLAS[tile.crop_stage])
		tree_top_layer.erase_cell(top_cell)
		return

	# Empty farmland of a farm house (harvested or not yet sown) as an empty bed.
	if tile.crop_field_owner != -1 and tile.terrain == TileRuntimeData.TerrainType.GRASS:
		overlay_layer.set_cell(cell, SRC_FARM, ATLAS_FALLOW)
		tree_top_layer.erase_cell(top_cell)
		return

	match tile.terrain:
		TileRuntimeData.TerrainType.FOREST:
			# Dense forest when surrounded by enough trees; otherwise a standalone tree.
			var variants := FOREST_TREES if WorldGrid.count_forest_neighbors(cell) >= FOREST_DENSE_NEIGHBORS else SINGLE_TREES
			var t := (cell.x * 7 + cell.y * 13) % variants.size()
			overlay_layer.set_cell(cell, SRC_TREES, variants[t])
			tree_top_layer.erase_cell(top_cell)
		TileRuntimeData.TerrainType.STONE:
			# Bottom half in this cell, top half one cell higher (2-tile stone).
			var bottom: Vector2i = STONE_VARIANTS[(cell.x * 11 + cell.y * 5) % STONE_VARIANTS.size()]
			overlay_layer.set_cell(cell, SRC_BASE, bottom)
			tree_top_layer.set_cell(top_cell, SRC_BASE, bottom + Vector2i(0, -1))
		TileRuntimeData.TerrainType.GRASS:
			# Scatter occasional flowers as decoration on empty grass. A
			# hash noise per cell produces an irregular, randomized-looking
			# pattern (deterministic, so redraws stay stable).
			if _is_flower_cell(cell):
				overlay_layer.set_cell(cell, SRC_BASE, ATLAS_FLOWERS)
			else:
				overlay_layer.erase_cell(cell)
			tree_top_layer.erase_cell(top_cell)
		_:
			overlay_layer.erase_cell(cell)
			tree_top_layer.erase_cell(top_cell)


## Pseudo-random but deterministic scatter pattern for flowers (~6% of
## grass cells). Classic fract(sin) hash noise instead of a regular modulo.
func _is_flower_cell(cell: Vector2i) -> bool:
	var h := sin(cell.x * 127.1 + cell.y * 311.7) * 43758.5453
	return (h - floorf(h)) < 0.06
