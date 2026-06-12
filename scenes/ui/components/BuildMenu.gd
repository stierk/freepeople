## BuildMenu (Baumenü) – M9
## Listet alle spielerplatzierbaren Gebäude (BuildingDef.is_player_placeable) auf.
## Ein Klick aktiviert den Platzierungsmodus; Main.gd fragt active_def beim Tile-Tap ab.
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
		button.text = "%s\n%d Gold" % [def.display_name, int(def.build_cost_gold)]
		button.pressed.connect(_on_button_pressed.bind(def))
		column.add_child(button)
		_buttons[def.type] = button


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
