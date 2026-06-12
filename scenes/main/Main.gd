extends Node2D

@onready var camera_controller: Camera2D = $CameraController
@onready var world: Node2D = $World
@onready var ui_root: CanvasLayer = $UIRoot


func _ready() -> void:
	camera_controller.tile_tapped.connect(_on_tile_tapped)
	ui_root.build_menu.placement_selected.connect(_on_placement_selected)


## M9: Beim Aktivieren des Platzierungsmodus das InfoPanel ausblenden.
func _on_placement_selected(def: BuildingDef) -> void:
	if def != null:
		ui_root.info_panel.hide_panel()


func _on_tile_tapped(cell: Vector2i) -> void:
	var pending: BuildingDef = ui_root.build_menu.active_def
	if pending != null:
		if _try_place_building(pending, cell):
			ui_root.build_menu.set_active_def(null)
		return

	var building := BuildingManager.get_building_at_cell(cell)
	if building != null:
		ui_root.info_panel.show_building(building)
	else:
		ui_root.info_panel.hide_panel()


## M9: Platzierung prüfen (gültige Zelle, Gras, frei, bezahlbar) und ausführen.
func _try_place_building(def: BuildingDef, cell: Vector2i) -> bool:
	if not WorldGrid.is_valid_cell(cell):
		return false
	var tile := WorldGrid.get_tile(cell)
	if tile.terrain != TileRuntimeData.TerrainType.GRASS:
		return false
	if tile.building_id != -1:
		return false
	if not GlobalInventory.spend_gold(def.build_cost_gold):
		return false

	world.place_player_building(def, cell)
	return true
