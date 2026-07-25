## M25: Fullscreen overlay with the trade chronicle of a single good at an exchange.
## Opened by tapping the "Now" price of a resource in the InfoPanel.
##
## Deliberately an overlay, not an inset in the InfoPanel: the viewport is 480x270, the InfoPanel
## only occupies ~192 px of that width – a scatter plot wouldn't be readable in there.
extends Control

@onready var title_label: Label = $Frame/Margin/VBox/Header/TitleLabel
@onready var close_button: Button = $Frame/Margin/VBox/Header/CloseButton
@onready var plot: Control = $Frame/Margin/VBox/Plot
@onready var backdrop: ColorRect = $Backdrop

var _building_id: int = -1
var _good: int = -1

## The chart refreshes more slowly than the simulation – it's a chronicle, not a ticker.
const REFRESH_INTERVAL := 0.5
var _refresh_cooldown: float = 0.0


func _ready() -> void:
	visible = false
	set_process(false)
	close_button.pressed.connect(hide_panel)
	backdrop.gui_input.connect(_on_backdrop_input)


func show_chart(building: BuildingInstance, good: int) -> void:
	if building == null or building.exchange == null:
		return
	_building_id = building.id
	_good = good
	visible = true
	set_process(true)
	_refresh()


func hide_panel() -> void:
	_building_id = -1
	_good = -1
	visible = false
	set_process(false)


func _process(delta: float) -> void:
	_refresh_cooldown -= delta
	if _refresh_cooldown <= 0.0:
		_refresh_cooldown = REFRESH_INTERVAL
		_refresh()


func _refresh() -> void:
	var building := BuildingManager.get_building(_building_id)
	# The building may have been demolished while the overlay was open.
	if building == null or building.exchange == null:
		hide_panel()
		return
	title_label.text = "Trade History: %s" % Goods.DISPLAY_NAMES.get(_good, "?")
	plot.set_source(building.exchange, _good)


func _on_backdrop_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		hide_panel()
