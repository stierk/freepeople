## InfoPanel – M9/M16 (redesign)
## Right-docked, opaque dark panel (40% of the width, full height below the
## HUD bar – its 16 px sit as offset_top on the scene's `Center` node)
## with high readability: bright labels,
## numbers in amber, simple +/− steppers instead of a SpinBox. Shows details for a
## tapped building (occupancy, stock, market prices, price/policy sliders)
## or a tapped inhabitant (profession, gold, hunger, inventory).
extends Control

## M25: the player tapped a good's Now price and wants to see its trade chronicle.
signal market_chart_requested(building_id: int, good: int)

const PROFESSION_NAMES := {
	InhabitantData.Profession.WOODCUTTER: "Woodcutter",
	InhabitantData.Profession.SAWMILL_WORKER: "Sawmill Worker",
	InhabitantData.Profession.QUARRY_WORKER: "Quarry Worker",
	InhabitantData.Profession.FARMER: "Farmer",
	InhabitantData.Profession.MILLER: "Miller",
	InhabitantData.Profession.BAKER: "Baker",
	InhabitantData.Profession.HUNTER: "Hunter",  # M29
}

# Contrast colors against the dark panel background.
const COLOR_LABEL := Color(0.82, 0.76, 0.66)    # muted bright – descriptions
const COLOR_VALUE := Color(1.0, 0.80, 0.35)     # amber – numbers stand out
const COLOR_SECTION := Color(0.62, 0.82, 0.95)  # accent – section headers
const COLOR_WARN := Color(1.0, 0.45, 0.35)      # warning (repair needed)

const FONT_BODY := 10
const FONT_SECTION := 11

# Column widths of the combined trade table (Name | Buy | Now | Sell), so the
# header and data rows line up. At only 480 px viewport width the
# panel is ~192 px wide; the row therefore has to stay very narrow, otherwise the Sell stepper
# slides off the right edge (horizontal scroll is off). Stepper width = 14+1+22+1+14 = 52.
const TRADE_NAME_WIDTH := 28.0
const TRADE_STEPPER_WIDTH := 52.0
const TRADE_NOW_WIDTH := 22.0
# Tight column spacing of the trade row (header + data identical).
const TRADE_SEPARATION := 2

@onready var title_label: Label = $Center/Panel/Margin/VBox/Header/TitleLabel
@onready var close_button: Button = $Center/Panel/Margin/VBox/Header/CloseButton
@onready var scroll: ScrollContainer = $Center/Panel/Margin/VBox/Scroll
@onready var content: VBoxContainer = $Center/Panel/Margin/VBox/Scroll/Content
@onready var stats_box: VBoxContainer = $Center/Panel/Margin/VBox/Scroll/Content/StatsBox
@onready var action_box: VBoxContainer = $Center/Panel/Margin/VBox/Scroll/Content/ActionBox
@onready var backdrop: ColorRect = $Backdrop

var _building_id: int = -1
var _inhabitant_id: int = -1

# The panel content is rebuilt on every resource change. So a rebuild
# doesn't destroy the buttons/steppers mid-click (which would make `pressed` never fire),
# `resources_changed` is only marked as "dirty" and throttled in _process, and only
# applied once no mouse button is currently held.
var _dirty: bool = false
var _refresh_cooldown: float = 0.0
const REFRESH_INTERVAL := 0.3


func _ready() -> void:
	visible = false
	set_process(false)
	close_button.pressed.connect(hide_panel)
	backdrop.gui_input.connect(_on_backdrop_input)
	GlobalInventory.resources_changed.connect(_on_resources_changed)


func show_building(building: BuildingInstance) -> void:
	_building_id = building.id
	_inhabitant_id = -1
	visible = true
	set_process(true)
	_refresh()


## M16: inhabitant view with profession/gold/hunger + inventory.
func show_inhabitant(inhabitant: InhabitantData) -> void:
	_inhabitant_id = inhabitant.id
	_building_id = -1
	visible = true
	set_process(true)
	_refresh()


func hide_panel() -> void:
	_building_id = -1
	_inhabitant_id = -1
	_dirty = false
	visible = false
	set_process(false)


func _on_resources_changed() -> void:
	# Just flag it – the actual rebuild happens throttled in _process, so
	# a frequently firing signal doesn't tear apart the interaction.
	_dirty = true


func _process(delta: float) -> void:
	if not visible:
		return
	if _refresh_cooldown > 0.0:
		_refresh_cooldown -= delta
	if not _dirty:
		return
	# Never rebuild while the left mouse button is held: otherwise the button
	# under the cursor gets recreated between mouse-down and -up and `pressed` never fires.
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		return
	if _refresh_cooldown > 0.0:
		return
	_dirty = false
	_refresh_cooldown = REFRESH_INTERVAL
	_refresh()


func _on_backdrop_input(event: InputEvent) -> void:
	# A click on the darkened backdrop closes the panel (like CloseButton).
	if event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT:
		hide_panel()


func _refresh() -> void:
	_clear_content()
	if _building_id != -1:
		_refresh_building()
	elif _inhabitant_id != -1:
		_refresh_inhabitant()
	# The panel has a fixed size (right side, 40% wide, full height below the HUD); the
	# scroll fills the rest below the header. After a rebuild only reset to the top.
	call_deferred("_reset_scroll")


func _reset_scroll() -> void:
	scroll.scroll_vertical = 0


func _refresh_building() -> void:
	var building := BuildingManager.get_building(_building_id)
	if building == null:
		hide_panel()
		return

	var def := building.def
	title_label.text = "%s (#%d)" % [def.display_name, building.id]

	if not building.is_constructed:
		_add_stat("Under construction", "%.0fs" % maxf(building.construction_timer, 0.0))
	else:
		_add_stat("Occupants", "%d / %d" % [building.occupants.size(), def.max_capacity])
		_append_repair_status(building)

	if not building.community_stock.is_empty():
		var shown := false
		for good: int in building.community_stock.keys():
			var amount: float = building.community_stock[good]
			if amount > 0.0:
				if not shown:
					_add_section("Storage")
					shown = true
				_add_stat(Goods.DISPLAY_NAMES[good], "%.1f" % amount)

	if not building.output_stock.is_empty():
		var shown := false
		for good: int in building.output_stock.keys():
			var amount: float = building.output_stock[good]
			if amount > 0.0:
				if not shown:
					_add_section("Awaiting pickup")
					shown = true
				_add_stat(Goods.DISPLAY_NAMES[good], "%.1f" % amount)

	_append_production_metrics(building)

	if building.exchange != null and building.trade_data != null:
		_add_trade_table(building)
	_add_trade_data_editors(building)
	_add_policy_editors(building)


## M20: shows three pricing metrics per inhabitant in the production building:
## last sale price, break-even price, desired price.
func _append_production_metrics(building: BuildingInstance) -> void:
	var good: int = building.def.output_good
	if good < 0 and not building.occupants.is_empty():
		var first := GameState.get_inhabitant(building.occupants[0])
		if first != null:
			good = SimulationManager.PROFESSION_TO_GOOD.get(first.profession, -1)
	if good < 0:
		return
	_add_section("Production")
	_add_stat("Market price %s" % Goods.DISPLAY_NAMES.get(good, "?"),
		"%.2f G" % BuildingManager.get_market_price(good))
	if building.occupants.is_empty():
		return
	_add_stat("Worker", "sale / break-even / want")
	for occ_id: int in building.occupants:
		var inh := GameState.get_inhabitant(occ_id)
		if inh == null:
			continue
		SimulationManager.recompute_break_even(inh)  # only compute when displaying
		var desired: float = inh.break_even_unit * (1.0 + inh.margin * SimulationManager.MARGIN_SCALE)
		_add_stat("#%d" % inh.id, "%.2f / %.2f / %.2f" % [
			inh.last_sale_unit_price, inh.break_even_unit, desired])


## M21: repair status of a work hut (due in X days, or urgently needed).
func _append_repair_status(building: BuildingInstance) -> void:
	if not (building.def.type in SimulationManager.REPAIRABLE_BUILDING_TYPES):
		return
	if building.needs_repair:
		_add_stat("Repair", "!! NEEDED (expires soon)", COLOR_WARN)
		return
	var due_in: int = SimulationManager.REPAIR_INTERVAL_DAYS - (SimulationManager.get_current_day() - building.last_repaired_day)
	_add_stat("Repair due in", "%d days" % maxi(0, due_in))


## M17: Treasury -> head tax. Storage yard/granary are covered by the combined
## trade table (`_add_trade_table`).
func _add_trade_data_editors(building: BuildingInstance) -> void:
	var td := building.trade_data
	if td == null:
		return

	if building.def.type == BuildingDef.BuildingType.TREASURY:
		_add_section("Taxes")
		_add_stepper("Head Tax (Gold/day)", td.daily_tax, _on_daily_tax_changed.bind(building.id))


## M23: combined trade row per good: [− Buy +]  Now  [− Sell +]. The current price
## (Now, exchange.get_price) sits centered between the two steppers and updates
## immediately when Buy or Sell changes.
func _add_trade_table(building: BuildingInstance) -> void:
	_add_section("Trade prices")
	_add_trade_header()
	for good: int in building.exchange.goods:
		_add_trade_row(building, good)


func _add_trade_header() -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", TRADE_SEPARATION)
	row.add_child(_make_col_label("", TRADE_NAME_WIDTH, HORIZONTAL_ALIGNMENT_LEFT))
	row.add_child(_make_col_label("Buy", TRADE_STEPPER_WIDTH, HORIZONTAL_ALIGNMENT_CENTER))
	row.add_child(_make_col_label("Now", TRADE_NOW_WIDTH, HORIZONTAL_ALIGNMENT_CENTER))
	row.add_child(_make_col_label("Sell", TRADE_STEPPER_WIDTH, HORIZONTAL_ALIGNMENT_CENTER))
	stats_box.add_child(row)


func _add_trade_row(building: BuildingInstance, good: int) -> void:
	var td := building.trade_data
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", TRADE_SEPARATION)

	var name_label := Label.new()
	name_label.text = Goods.DISPLAY_NAMES[good]
	name_label.custom_minimum_size = Vector2(TRADE_NAME_WIDTH, 0)
	name_label.add_theme_color_override("font_color", COLOR_LABEL)
	name_label.add_theme_font_size_override("font_size", FONT_BODY)
	row.add_child(name_label)

	var now_label := Label.new()
	now_label.custom_minimum_size = Vector2(TRADE_NOW_WIDTH, 0)
	now_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	now_label.add_theme_color_override("font_color", COLOR_VALUE)
	now_label.add_theme_font_size_override("font_size", FONT_BODY)
	# M25: tapping the Now price opens this good's trade chronicle. Labels ignore
	# mouse events by default – only STOP makes the cell clickable.
	now_label.mouse_filter = Control.MOUSE_FILTER_STOP
	now_label.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	now_label.tooltip_text = "Show trade history"
	now_label.gui_input.connect(_on_now_price_input.bind(building.id, good))

	# Buy and Sell write into trade_data as before and then refresh the Now price.
	var buy_cb := func(v: float) -> void:
		_on_buy_price_changed(v, building.id, good)
		_update_now(now_label, building, good)
	var sell_cb := func(v: float) -> void:
		_on_sell_price_changed(v, building.id, good)
		_update_now(now_label, building, good)

	row.add_child(_make_stepper(td.buy_price.get(good, 0.0), buy_cb))
	row.add_child(now_label)
	row.add_child(_make_stepper(td.sell_price.get(good, 0.0), sell_cb))

	stats_box.add_child(row)
	_update_now(now_label, building, good)


func _update_now(now_label: Label, building: BuildingInstance, good: int) -> void:
	now_label.text = "%.1f" % building.exchange.get_price(good)


## M25: click on the Now price. The InfoPanel doesn't know the chart overlay itself – it just
## reports the request; wiring happens in UIRoot (both are siblings there).
func _on_now_price_input(event: InputEvent, building_id: int, good: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		market_chart_requested.emit(building_id, good)


func _make_col_label(text: String, width: float, align: int) -> Label:
	var label := Label.new()
	label.text = text
	label.custom_minimum_size = Vector2(width, 0)
	label.horizontal_alignment = align
	label.add_theme_color_override("font_color", COLOR_SECTION)
	label.add_theme_font_size_override("font_size", FONT_BODY)
	return label


## M20: Town Hall policy – subsidy/tariff per good + basic income (global levers).
func _add_policy_editors(building: BuildingInstance) -> void:
	var policy := building.policy
	if policy == null:
		return
	_add_section("Subsidies / Tariffs")
	for good in Goods.GoodType.values():
		_add_stepper("%s Subsidy" % Goods.DISPLAY_NAMES[good], policy.subsidy.get(good, 0.0),
			_on_subsidy_changed.bind(building.id, good), -99.0)
	_add_section("Welfare")
	_add_stepper("Basic Income (Gold/day, negative = flat tax)", policy.basic_income,
		_on_basic_income_changed.bind(building.id), -99.0)


func _on_subsidy_changed(value: float, building_id: int, good: int) -> void:
	var building := BuildingManager.get_building(building_id)
	if building != null and building.policy != null:
		building.policy.subsidy[good] = value


func _on_basic_income_changed(value: float, building_id: int) -> void:
	var building := BuildingManager.get_building(building_id)
	if building != null and building.policy != null:
		building.policy.basic_income = value


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

	_add_stat("Profession", _profession_name(inh.profession))
	_add_stat("Gold", "%.1f" % inh.gold)
	_add_stat("Hunger", "%.0f%%" % (inh.hunger * 100.0))

	# Diagnostic for "waiting at the Town Hall": current state, resume state, home (does it
	# still exist?) and missed meals – shows immediately what a waiting inhabitant is stuck on.
	var home_exists := BuildingManager.get_building(inh.home_building_id) != null
	_add_stat("State", InhabitantData.State.keys()[inh.state])
	_add_stat("Resume", InhabitantData.State.keys()[inh.resume_state])
	_add_stat("Home", "%d (exists: %s)" % [inh.home_building_id, "yes" if home_exists else "no"])
	_add_stat("Missed meals", "%d" % inh.missed_meals)

	# M28: evolutionary traits – raw values [0,1], so spawns/balance stay traceable.
	_add_section("Traits")
	_add_stat("Speed", "%.0f%%" % (inh.trait_speed * 100.0))
	_add_stat("Strength", "%.0f%%" % (inh.trait_strength * 100.0))
	_add_stat("Frugality", "%.0f%%" % (inh.trait_frugality * 100.0))
	_add_stat("Diligence", "%.0f%%" % (inh.trait_diligence * 100.0))
	_add_stat("Resilience", "%.0f%%" % (inh.trait_resilience * 100.0))
	_add_stat("Greed", "%.0f%%" % (inh.margin * 100.0))

	# Inventory the inhabitant is carrying.
	_add_section("Inventory (%.1f / %.0f)" % [inh.inventory_count(), inh.inventory_capacity])
	var has_items := false
	for good: int in inh.inventory.keys():
		var amount: float = inh.inventory[good]
		if amount > 0.0:
			_add_stat(Goods.DISPLAY_NAMES[good], "%.1f" % amount)
			has_items = true
	if not has_items:
		_add_stat("(empty)", "")


# --- UI building blocks -----------------------------------------------------------

## Section header (accent color) – organizes Storage/Market/Trade/… .
func _add_section(text: String) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", COLOR_SECTION)
	label.add_theme_font_size_override("font_size", FONT_SECTION)
	stats_box.add_child(label)


## Info row: description on the left (muted bright), value right-aligned (amber).
func _add_stat(name_text: String, value_text: String, value_color: Color = COLOR_VALUE) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)

	var name_label := Label.new()
	name_label.text = name_text
	name_label.size_flags_horizontal = SIZE_EXPAND_FILL
	name_label.add_theme_color_override("font_color", COLOR_LABEL)
	name_label.add_theme_font_size_override("font_size", FONT_BODY)
	row.add_child(name_label)

	var value_label := Label.new()
	value_label.text = value_text
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value_label.add_theme_color_override("font_color", value_color)
	value_label.add_theme_font_size_override("font_size", FONT_BODY)
	row.add_child(value_label)

	stats_box.add_child(row)


## Slider row: description (expand) + [−] value [+]. Lands in the ActionBox.
func _add_stepper(name_text: String, value: float, on_changed: Callable,
		min_val: float = 0.0, max_val: float = 999.0, step: float = 0.5) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)

	var name_label := Label.new()
	name_label.text = name_text
	name_label.size_flags_horizontal = SIZE_EXPAND_FILL
	name_label.add_theme_color_override("font_color", COLOR_LABEL)
	name_label.add_theme_font_size_override("font_size", FONT_BODY)
	row.add_child(name_label)

	row.add_child(_make_stepper(value, on_changed, min_val, max_val, step))
	action_box.add_child(row)


## Building block: [−] value [+]. Buttons change the value by `step`, clamp to [min_val, max_val]
## and report it via `on_changed`. Returns the HBox (reusable for combined rows).
func _make_stepper(value: float, on_changed: Callable,
		min_val: float = 0.0, max_val: float = 999.0, step: float = 0.5) -> HBoxContainer:
	var group := HBoxContainer.new()
	group.add_theme_constant_override("separation", 1)

	var minus := Button.new()
	minus.text = "−"
	minus.custom_minimum_size = Vector2(14, 16)
	group.add_child(minus)

	var value_label := Label.new()
	value_label.text = "%.1f" % value
	value_label.custom_minimum_size = Vector2(22, 0)
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	value_label.add_theme_color_override("font_color", COLOR_VALUE)
	value_label.add_theme_font_size_override("font_size", FONT_BODY)
	group.add_child(value_label)

	var plus := Button.new()
	plus.text = "+"
	plus.custom_minimum_size = Vector2(14, 16)
	group.add_child(plus)

	minus.pressed.connect(_on_stepper.bind(value_label, on_changed, -step, min_val, max_val))
	plus.pressed.connect(_on_stepper.bind(value_label, on_changed, step, min_val, max_val))
	return group


func _on_stepper(value_label: Label, on_changed: Callable, delta: float,
		min_val: float, max_val: float) -> void:
	var new_val: float = clampf(value_label.text.to_float() + delta, min_val, max_val)
	value_label.text = "%.1f" % new_val
	on_changed.call(new_val)


func _clear_content() -> void:
	for box in [stats_box, action_box]:
		for child in box.get_children():
			box.remove_child(child)
			child.queue_free()


func _profession_name(profession: InhabitantData.Profession) -> String:
	if profession == InhabitantData.Profession.NONE:
		return "No profession"
	return PROFESSION_NAMES.get(profession, "?")
