## HUD – M9
## Obere Leiste: Gold, Bevölkerung, Ressourcen, Zeitsteuerung, Speichern/Laden.
extends Control

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

@onready var save_button: Button = $Row/SaveButton
@onready var load_button: Button = $Row/LoadButton


func _ready() -> void:
	GlobalInventory.gold_changed.connect(_on_gold_changed)
	GlobalInventory.resources_changed.connect(_refresh_resources)
	GlobalInventory.population_changed.connect(_on_population_changed)

	pause_button.pressed.connect(_on_speed_pressed.bind(SimulationManager.SpeedMode.PAUSED))
	speed1_button.pressed.connect(_on_speed_pressed.bind(SimulationManager.SpeedMode.NORMAL))
	speed2_button.pressed.connect(_on_speed_pressed.bind(SimulationManager.SpeedMode.FAST))
	speed3_button.pressed.connect(_on_speed_pressed.bind(SimulationManager.SpeedMode.FASTEST))

	save_button.pressed.connect(_on_save_pressed)
	load_button.pressed.connect(_on_load_pressed)

	_on_gold_changed(GlobalInventory.gold)
	_refresh_resources()
	_on_population_changed(GameState.population_count())
	_update_speed_buttons()


func _on_gold_changed(new_amount: float) -> void:
	gold_label.text = "Gold: %d" % int(new_amount)


func _refresh_resources() -> void:
	wood_label.text = "Holz: %d" % int(GlobalInventory.get_community_total(Goods.GoodType.WOOD))
	planks_label.text = "Bretter: %d" % int(GlobalInventory.get_community_total(Goods.GoodType.PLANKS))
	stone_label.text = "Stein: %d" % int(GlobalInventory.get_community_total(Goods.GoodType.STONE))
	food_label.text = "Nahrung: %d" % int(GlobalInventory.get_food())


func _on_population_changed(new_count: int) -> void:
	pop_label.text = "Bev: %d" % new_count


func _on_speed_pressed(mode: SimulationManager.SpeedMode) -> void:
	SimulationManager.speed_mode = mode
	_update_speed_buttons()


func _update_speed_buttons() -> void:
	pause_button.set_pressed_no_signal(SimulationManager.speed_mode == SimulationManager.SpeedMode.PAUSED)
	speed1_button.set_pressed_no_signal(SimulationManager.speed_mode == SimulationManager.SpeedMode.NORMAL)
	speed2_button.set_pressed_no_signal(SimulationManager.speed_mode == SimulationManager.SpeedMode.FAST)
	speed3_button.set_pressed_no_signal(SimulationManager.speed_mode == SimulationManager.SpeedMode.FASTEST)


func _on_save_pressed() -> void:
	SaveLoadManager.save_game()


func _on_load_pressed() -> void:
	if SaveLoadManager.has_save():
		SaveLoadManager.load_game()
