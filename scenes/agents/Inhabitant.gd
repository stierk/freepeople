extends Node2D

## M18: Einfärbung je nach verpassten Mahlzeiten (hungrig/verhungert) sowie Grab-Darstellung.
const COLOR_NORMAL := Color(1.0, 1.0, 1.0, 1.0)
const COLOR_HUNGRY := Color(0.82, 0.51, 0.27, 1.0)
const COLOR_STARVED := Color(0.35, 0.2, 0.12, 1.0)
const COLOR_GRAVE := Color(0.45, 0.45, 0.45, 0.85)
const COLOR_LERP_SPEED := 2.0

var data: InhabitantData
var is_grave: bool = false


func setup(inhabitant_data: InhabitantData) -> void:
	data = inhabitant_data
	position = data.world_pos


func _process(delta: float) -> void:
	if is_grave or data == null:
		return

	var target := COLOR_NORMAL
	if data.missed_meals >= 3:
		target = COLOR_STARVED
	elif data.missed_meals >= 1:
		target = COLOR_HUNGRY
	modulate = modulate.lerp(target, minf(1.0, delta * COLOR_LERP_SPEED))


## M18: Bewohner ist verstorben - Node bleibt als Grab stehen, keine weiteren Updates.
func mark_as_grave() -> void:
	is_grave = true
	data = null
	modulate = COLOR_GRAVE
