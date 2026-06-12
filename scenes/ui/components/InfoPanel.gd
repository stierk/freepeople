## InfoPanel – M9/M16
## Zeigt Details zu einem angetippten Gebäude (Belegung, Lagerbestände, Marktpreise)
## oder einem angetippten Bewohner (Beruf, Gold, Hunger + Berufswechsel-Buttons).
extends Control

const PROFESSION_NAMES := {
	InhabitantData.Profession.WOODCUTTER: "Woodcutter",
	InhabitantData.Profession.SAWMILL_WORKER: "Sawmill Worker",
	InhabitantData.Profession.QUARRY_WORKER: "Quarry Worker",
	InhabitantData.Profession.FARMER: "Farmer",
}

@onready var title_label: Label = $Panel/VBox/TitleLabel
@onready var body_label: Label = $Panel/VBox/BodyLabel
@onready var action_box: VBoxContainer = $Panel/VBox/ActionBox
@onready var close_button: Button = $Panel/VBox/CloseButton

var _building_id: int = -1
var _inhabitant_id: int = -1


func _ready() -> void:
	visible = false
	close_button.pressed.connect(hide_panel)
	GlobalInventory.resources_changed.connect(_refresh)


func show_building(building: BuildingInstance) -> void:
	_building_id = building.id
	_inhabitant_id = -1
	visible = true
	_refresh()


## M16: Bewohner-Ansicht mit Beruf/Gold/Hunger + Berufswechsel-Buttons.
func show_inhabitant(inhabitant: InhabitantData) -> void:
	_inhabitant_id = inhabitant.id
	_building_id = -1
	visible = true
	_refresh()


func hide_panel() -> void:
	_building_id = -1
	_inhabitant_id = -1
	visible = false


func _refresh() -> void:
	_clear_action_box()
	if _building_id != -1:
		_refresh_building()
	elif _inhabitant_id != -1:
		_refresh_inhabitant()


func _refresh_building() -> void:
	var building := BuildingManager.get_building(_building_id)
	if building == null:
		hide_panel()
		return

	var def := building.def
	title_label.text = "%s (#%d)" % [def.display_name, building.id]

	var lines: PackedStringArray = []

	if not building.is_constructed:
		lines.append("Under construction... (%.0fs)" % maxf(building.construction_timer, 0.0))
	else:
		lines.append("Occupants: %d / %d" % [building.occupants.size(), def.max_capacity])

	if not building.community_stock.is_empty():
		lines.append("Storage:")
		for good: int in building.community_stock.keys():
			var amount: float = building.community_stock[good]
			if amount > 0.0:
				lines.append("  %s: %.1f" % [Goods.DISPLAY_NAMES[good], amount])

	if not building.output_stock.is_empty():
		for good: int in building.output_stock.keys():
			var amount: float = building.output_stock[good]
			if amount > 0.0:
				lines.append("Awaiting pickup: %.1f %s" % [amount, Goods.DISPLAY_NAMES[good]])

	if building.market_data != null:
		lines.append("Market prices:")
		for good: int in building.market_data.prices.keys():
			lines.append("  %s: %.2f G" % [Goods.DISPLAY_NAMES[good], building.market_data.prices[good]])

	body_label.text = "\n".join(lines)

	_add_trade_data_editors(building)


## M17: Storage Yard/Kornspeicher -> An-/Verkaufspreise; Schatzkammer -> Kopfsteuer.
func _add_trade_data_editors(building: BuildingInstance) -> void:
	var td := building.trade_data
	if td == null:
		return

	if building.def.type == BuildingDef.BuildingType.TREASURY:
		_add_price_row("Head Tax (Gold/day)", td.daily_tax, _on_daily_tax_changed.bind(building.id))
		return

	var goods: Array[int] = [Goods.GoodType.FOOD] if building.def.type == BuildingDef.BuildingType.GRANARY \
		else [Goods.GoodType.WOOD, Goods.GoodType.PLANKS, Goods.GoodType.STONE]

	for good in goods:
		var label_text: String = Goods.DISPLAY_NAMES[good]
		_add_price_row("%s Buy Price" % label_text, td.buy_price.get(good, 0.0), _on_buy_price_changed.bind(building.id, good))
		_add_price_row("%s Sell Price" % label_text, td.sell_price.get(good, 0.0), _on_sell_price_changed.bind(building.id, good))


func _add_price_row(label_text: String, value: float, on_changed: Callable) -> void:
	var row := HBoxContainer.new()

	var label := Label.new()
	label.text = label_text
	label.size_flags_horizontal = SIZE_EXPAND_FILL
	row.add_child(label)

	var spin := SpinBox.new()
	spin.min_value = 0.0
	spin.max_value = 999.0
	spin.step = 0.5
	spin.value = value
	spin.value_changed.connect(on_changed)
	row.add_child(spin)

	action_box.add_child(row)


func _on_buy_price_changed(value: float, building_id: int, good: int) -> void:
	var building := BuildingManager.get_building(building_id)
	if building != null and building.trade_data != null:
		building.trade_data.buy_price[good] = value


func _on_sell_price_changed(value: float, building_id: int, good: int) -> void:
	var building := BuildingManager.get_building(building_id)
	if building != null and building.trade_data != null:
		building.trade_data.sell_price[good] = value


func _on_daily_tax_changed(value: float, building_id: int) -> void:
	var building := BuildingManager.get_building(building_id)
	if building != null and building.trade_data != null:
		building.trade_data.daily_tax = value


func _refresh_inhabitant() -> void:
	var inh := GameState.get_inhabitant(_inhabitant_id)
	if inh == null:
		hide_panel()
		return

	title_label.text = "Inhabitant #%d" % inh.id

	var lines: PackedStringArray = []
	lines.append("Profession: %s" % _profession_name(inh.profession))
	lines.append("Gold: %.1f" % inh.gold)
	lines.append("Hunger: %.0f%%" % (inh.hunger * 100.0))
	body_label.text = "\n".join(lines)

	for profession in PROFESSION_NAMES.keys():
		if profession == inh.profession:
			continue
		var button := Button.new()
		button.text = "Become %s" % PROFESSION_NAMES[profession]
		button.pressed.connect(_on_profession_pressed.bind(profession))
		action_box.add_child(button)


func _on_profession_pressed(new_profession: InhabitantData.Profession) -> void:
	GameState.change_profession(_inhabitant_id, new_profession)
	_refresh()


func _clear_action_box() -> void:
	for child in action_box.get_children():
		action_box.remove_child(child)
		child.queue_free()


func _profession_name(profession: InhabitantData.Profession) -> String:
	if profession == InhabitantData.Profession.NONE:
		return "No profession"
	return PROFESSION_NAMES.get(profession, "?")
