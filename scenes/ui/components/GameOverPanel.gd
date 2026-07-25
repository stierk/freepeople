## GameOverPanel - M18
## Shown as soon as the population drops to 0 (GameState.game_over).
## Shows days survived + highscore (user://highscore.json) and allows a restart.
extends Control

const HIGHSCORE_PATH := "user://highscore.json"

@onready var days_label: Label = $Panel/VBox/DaysLabel
@onready var highscore_label: Label = $Panel/VBox/HighscoreLabel
@onready var restart_button: Button = $Panel/VBox/RestartButton


func _ready() -> void:
	visible = false
	restart_button.pressed.connect(_on_restart_pressed)
	GameState.game_over.connect(_on_game_over)


func _on_game_over(days_survived: int) -> void:
	var highscore := _load_highscore()
	var is_new_record := days_survived > highscore
	if is_new_record:
		highscore = days_survived
		_save_highscore(highscore)

	days_label.text = "Days survived: %d" % days_survived
	if is_new_record:
		highscore_label.text = "New highscore: %d days!" % highscore
	else:
		highscore_label.text = "Highscore: %d days" % highscore

	SimulationManager.speed_mode = SimulationManager.SpeedMode.PAUSED
	visible = true


func _load_highscore() -> int:
	if not FileAccess.file_exists(HIGHSCORE_PATH):
		return 0
	var file := FileAccess.open(HIGHSCORE_PATH, FileAccess.READ)
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		return 0
	return parsed.get("days_survived", 0)


func _save_highscore(days_survived: int) -> void:
	var file := FileAccess.open(HIGHSCORE_PATH, FileAccess.WRITE)
	file.store_string(JSON.stringify({"days_survived": days_survived}))
	file.close()


func _on_restart_pressed() -> void:
	SaveLoadManager.restart_game()
