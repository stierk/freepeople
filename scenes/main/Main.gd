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
		return

	## M16: Bewohner anklicken zeigt Beruf + Berufswechsel-Buttons im InfoPanel.
	var inhabitant := GameState.get_inhabitant_at_cell(cell)
	if inhabitant != null:
		ui_root.info_panel.show_inhabitant(inhabitant)
		return

	ui_root.info_panel.hide_panel()


## M9/M11/M13: Platzierung prüfen (gesamter Footprint begehbar/frei, bezahlbar) und ausführen.
func _try_place_building(def: BuildingDef, cell: Vector2i) -> bool:
	if not WorldGrid.is_footprint_buildable(cell, def.footprint_size):
		return false
	if not _can_afford_build_cost(def):
		return false

	_pay_build_cost(def)
	world.place_player_building(def, cell)
	return true


## M13: prüft sowohl Gold- als auch Güterkosten (build_cost), bevor bezahlt wird.
func _can_afford_build_cost(def: BuildingDef) -> bool:
	if GlobalInventory.gold < def.build_cost_gold:
		return false
	for good: int in def.build_cost.keys():
		var needed: float = def.build_cost[good]
		var building := BuildingManager.get_storage_for_good(good)
		if building == null or building.community_stock.get(good, 0.0) < needed:
			return false
	return true


func _pay_build_cost(def: BuildingDef) -> void:
	GlobalInventory.spend_gold(def.build_cost_gold)
	for good: int in def.build_cost.keys():
		var amount: float = def.build_cost[good]
		var building := BuildingManager.get_storage_for_good(good)
		building.withdraw_community(good, amount)
