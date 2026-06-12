## InfoPanel – M9
## Zeigt Details zu einem angetippten Gebäude: Belegung, Lagerbestände, Marktpreise.
extends Control

@onready var title_label: Label = $Panel/VBox/TitleLabel
@onready var body_label: Label = $Panel/VBox/BodyLabel
@onready var close_button: Button = $Panel/VBox/CloseButton

var _building_id: int = -1


func _ready() -> void:
	visible = false
	close_button.pressed.connect(hide_panel)
	GlobalInventory.resources_changed.connect(_refresh)


func show_building(building: BuildingInstance) -> void:
	_building_id = building.id
	visible = true
	_refresh()


func hide_panel() -> void:
	_building_id = -1
	visible = false


func _refresh() -> void:
	if _building_id == -1:
		return
	var building := BuildingManager.get_building(_building_id)
	if building == null:
		hide_panel()
		return

	var def := building.def
	title_label.text = "%s (#%d)" % [def.display_name, building.id]

	var lines: PackedStringArray = []

	if not building.is_constructed:
		lines.append("Im Bau... (%.0fs)" % maxf(building.construction_timer, 0.0))
	else:
		lines.append("Belegung: %d / %d" % [building.occupants.size(), def.max_capacity])

	if not building.community_stock.is_empty():
		lines.append("Lager:")
		for good: int in building.community_stock.keys():
			var amount: float = building.community_stock[good]
			if amount > 0.0:
				lines.append("  %s: %.1f" % [Goods.GoodType.keys()[good], amount])

	if not building.output_stock.is_empty():
		for good: int in building.output_stock.keys():
			var amount: float = building.output_stock[good]
			if amount > 0.0:
				lines.append("Wartet auf Abholung: %.1f %s" % [amount, Goods.GoodType.keys()[good]])

	if building.market_data != null:
		lines.append("Marktpreise:")
		for good: int in building.market_data.prices.keys():
			lines.append("  %s: %.2f G" % [Goods.GoodType.keys()[good], building.market_data.prices[good]])

	body_label.text = "\n".join(lines)
