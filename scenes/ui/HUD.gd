## HUD – M9/M18/M26
## Top bar: day counter, gold, population, resources, economy shortcuts (Policies/Treasury/Market),
## speed controls, restart.
extends Control

@onready var day_label: Label = $Row/DayLabel
@onready var gold_label: Label = $Row/GoldLabel
@onready var pop_label: Label = $Row/PopLabel
@onready var wood_label: Label = $Row/WoodLabel
@onready var planks_label: Label = $Row/PlanksLabel
@onready var stone_label: Label = $Row/StoneLabel
@onready var food_label: Label = $Row/FoodLabel

@onready var pause_button: Button = $Row/Pause
@onready var speed1_button: Button = $Row/Speed1
@onready var speed2_button: Button = $Row/Speed2
@onready var speed3_button: Button = $Row/Speed3

@onready var restart_button: Button = $Row/RestartButton
@onready var restart_confirm_dialog: ConfirmationDialog = $RestartConfirmDialog

## M26: HUD quick-access buttons to the economy systems (Town Hall policy, Treasury, Market).
@onready var policy_button: Button = $Row/PolicyButton
@onready var treasury_button: Button = $Row/TreasuryButton
@onready var market_button: Button = $Row/MarketButton

## M26: the HUD doesn't know the InfoPanel (siblings). It reports the open request with the
## resolved building; UIRoot opens the panel (same pattern as market_chart_requested).
signal building_info_requested(building: BuildingInstance)


func _ready() -> void:
	GlobalInventory.gold_changed.connect(_on_gold_changed)
	GlobalInventory.resources_changed.connect(_refresh_resources)
	GlobalInventory.population_changed.connect(_on_population_changed)

	pause_button.pressed.connect(_on_speed_pressed.bind(SimulationManager.SpeedMode.PAUSED))
	speed1_button.pressed.connect(_on_speed_pressed.bind(SimulationManager.SpeedMode.NORMAL))
	speed2_button.pressed.connect(_on_speed_pressed.bind(SimulationManager.SpeedMode.FAST))
	speed3_button.pressed.connect(_on_speed_pressed.bind(SimulationManager.SpeedMode.FASTEST))

	restart_button.pressed.connect(_on_restart_pressed)
	restart_confirm_dialog.confirmed.connect(_on_restart_confirmed)

	# M26: economy quick-access buttons. Policy lives at the Town Hall, tax/prices at the Treasury,
	# the trade table + price chart at the Storage Yard (starter exchange, always exists).
	policy_button.pressed.connect(func() -> void: building_info_requested.emit(BuildingManager.get_town_hall()))
	treasury_button.pressed.connect(func() -> void: building_info_requested.emit(BuildingManager.get_treasury()))
	market_button.pressed.connect(func() -> void: building_info_requested.emit(BuildingManager.get_storage_yard()))

	_on_gold_changed(GlobalInventory.gold)
	_refresh_resources()
	_on_population_changed(GameState.population_count())
	_update_speed_buttons()
	_refresh_day()


func _process(_delta: float) -> void:
	_refresh_day()


func _refresh_day() -> void:
	day_label.text = "Day %d" % SimulationManager.get_current_day()


func _on_gold_changed(new_amount: float) -> void:
	gold_label.text = "Gold: %d" % int(new_amount)


func _refresh_resources() -> void:
	wood_label.text = "%s: %d" % [Goods.DISPLAY_NAMES[Goods.GoodType.WOOD], int(GlobalInventory.get_community_total(Goods.GoodType.WOOD))]
	planks_label.text = "%s: %d" % [Goods.DISPLAY_NAMES[Goods.GoodType.PLANKS], int(GlobalInventory.get_community_total(Goods.GoodType.PLANKS))]
	stone_label.text = "%s: %d" % [Goods.DISPLAY_NAMES[Goods.GoodType.STONE], int(GlobalInventory.get_community_total(Goods.GoodType.STONE))]
	food_label.text = "%s: %d" % [Goods.DISPLAY_NAMES[Goods.GoodType.FOOD], int(GlobalInventory.get_community_total(Goods.GoodType.FOOD))]


func _on_population_changed(new_count: int) -> void:
	pop_label.text = "Pop: %d" % new_count


func _on_speed_pressed(mode: SimulationManager.SpeedMode) -> void:
	SimulationManager.speed_mode = mode
	_update_speed_buttons()


func _update_speed_buttons() -> void:
	pause_button.set_pressed_no_signal(SimulationManager.speed_mode == SimulationManager.SpeedMode.PAUSED)
	speed1_button.set_pressed_no_signal(SimulationManager.speed_mode == SimulationManager.SpeedMode.NORMAL)
	speed2_button.set_pressed_no_signal(SimulationManager.speed_mode == SimulationManager.SpeedMode.FAST)
	speed3_button.set_pressed_no_signal(SimulationManager.speed_mode == SimulationManager.SpeedMode.FASTEST)


func _on_restart_pressed() -> void:
	restart_confirm_dialog.popup_centered()


func _on_restart_confirmed() -> void:
	SaveLoadManager.restart_game()
