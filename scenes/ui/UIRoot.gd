## UIRoot – M9
## CanvasLayer with HUD, BuildMenu and InfoPanel. Bundles references for Main.gd.
extends CanvasLayer

@onready var hud: Control = $HUD
@onready var build_menu: Control = $BuildMenu
@onready var info_panel: Control = $InfoPanel
@onready var game_over_panel: Control = $GameOverPanel
@onready var market_chart_panel: Control = $MarketChartPanel


## M25: Clicking a Now price in the InfoPanel opens the trade chronicle. This wiring lives
## here because both panels are siblings and would otherwise not need to know about each other.
func _ready() -> void:
	info_panel.market_chart_requested.connect(_on_market_chart_requested)
	# M26: HUD quick-access buttons to the economy systems open the matching building InfoPanel.
	hud.building_info_requested.connect(_on_building_info_requested)


func _on_market_chart_requested(building_id: int, good: int) -> void:
	market_chart_panel.show_chart(BuildingManager.get_building(building_id), good)


## M26: Opens the InfoPanel for the building reported by the HUD. If it doesn't exist (e.g. no
## Treasury built yet), deliberately do nothing — show_building would otherwise access null.
func _on_building_info_requested(building: BuildingInstance) -> void:
	if building != null:
		info_panel.show_building(building)
