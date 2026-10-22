## Tuning – runtime overrides for balance constants, used by the hyperparameter tuner (tools/tune).
##
## Inert unless launched with `--turbo-params=<file.json>` after `--`; without it every lookup returns
## the in-source default, so normal play and fixed-seed reproducibility checks are unaffected.
## Must be the FIRST autoload: other autoloads read their tunables while being instantiated.
##
## Usage in a script:   var HUNT_SUCCESS_CHANCE: float = Tuning.f("HUNT_SUCCESS_CHANCE", 0.1)
## JSON file format:    {"HUNT_SUCCESS_CHANCE": 0.2, "windmill.output_interval": 6.0}
extends Node

var _overrides: Dictionary = {}


func _init() -> void:
	for a in OS.get_cmdline_user_args():
		if not a.begins_with("--turbo-params="):
			continue
		var path := a.substr(15)
		var file := FileAccess.open(path, FileAccess.READ)
		if file == null:
			push_error("[Tuning] cannot read %s" % path)
			continue
		var parsed: Variant = JSON.parse_string(file.get_as_text())
		if parsed is Dictionary:
			_overrides = parsed
			print("[Tuning] %d overrides from %s" % [_overrides.size(), path])
		else:
			push_error("[Tuning] %s is not a JSON object" % path)


func f(key: String, default: float) -> float:
	return float(_overrides.get(key, default))


func i(key: String, default: int) -> int:
	return roundi(float(_overrides.get(key, default)))


func has_override(key: String) -> bool:
	return _overrides.has(key)
