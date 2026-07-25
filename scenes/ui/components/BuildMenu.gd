## BuildMenu – M9
## Lists all player-placeable buildings (BuildingDef.is_player_placeable).
## A click activates placement mode; Main.gd queries active_def on tile tap.
extends Control

signal placement_selected(def: BuildingDef)

@onready var column: VBoxContainer = $Column

var active_def: BuildingDef = null

var _buttons: Dictionary = {}


func _ready() -> void:
	for type: BuildingDef.BuildingType in BuildingManager.BUILDING_DEF_PATHS.keys():
		var def := BuildingManager.get_building_def(type)
		if not def.is_player_placeable:
			continue

		var button := Button.new()
		button.toggle_mode = true
		button.text = "%s\n%s" % [def.display_name, _format_cost(def)]
		button.pressed.connect(_on_button_pressed.bind(def))
		column.add_child(button)
		_buttons[def.type] = button


## M13: shows both goods and gold costs.
func _format_cost(def: BuildingDef) -> String:
	var parts: PackedStringArray = []
	for good: int in def.build_cost.keys():
		var amount: float = def.build_cost[good]
		if amount > 0.0:
			parts.append("%d %s" % [int(amount), Goods.DISPLAY_NAMES[good]])
	if def.build_cost_gold > 0.0:
		parts.append("%d Gold" % int(def.build_cost_gold))
	if parts.is_empty():
		return "Free"
	return ", ".join(parts)


func set_active_def(def: BuildingDef) -> void:
	active_def = def
	for type: BuildingDef.BuildingType in _buttons.keys():
		var button: Button = _buttons[type]
		button.set_pressed_no_signal(def != null and def.type == type)


func _on_button_pressed(def: BuildingDef) -> void:
	if active_def == def:
		set_active_def(null)
	else:
		set_active_def(def)
	placement_selected.emit(active_def)
