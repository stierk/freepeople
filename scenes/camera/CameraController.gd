extends Camera2D

signal tile_tapped(cell: Vector2i)

const MIN_ZOOM := 0.5
const MAX_ZOOM := 4.0
const ZOOM_STEP := 0.1
const TAP_MAX_DURATION_MSEC := 250
const TAP_MAX_DISTANCE := 10.0

var _touch_points: Dictionary = {}
var _pinch_start_dist: float = 0.0
var _pinch_start_zoom: float = 1.0
var _press_start_pos: Vector2 = Vector2.ZERO
var _press_start_time: int = 0
var _is_dragging: bool = false


func _ready() -> void:
	var map_pixel_size := Vector2(WorldGrid.MAP_SIZE) * WorldGrid.TILE_SIZE
	limit_left = 0
	limit_top = 0
	limit_right = int(map_pixel_size.x)
	limit_bottom = int(map_pixel_size.y)
	position = map_pixel_size / 2.0


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		_handle_touch(event)
	elif event is InputEventScreenDrag:
		_handle_drag(event)
	elif event is InputEventMouseButton:
		_handle_mouse_button(event)


func _handle_touch(event: InputEventScreenTouch) -> void:
	if event.pressed:
		_touch_points[event.index] = event.position
		if _touch_points.size() == 1:
			_press_start_pos = event.position
			_press_start_time = Time.get_ticks_msec()
			_is_dragging = false
		else:
			_pinch_start_dist = 0.0
	else:
		var was_single_touch := _touch_points.size() == 1
		_touch_points.erase(event.index)
		if was_single_touch and not _is_dragging:
			_maybe_emit_tap(event.position)
		if _touch_points.size() < 2:
			_pinch_start_dist = 0.0


func _handle_drag(event: InputEventScreenDrag) -> void:
	_touch_points[event.index] = event.position
	if _touch_points.size() == 1:
		if event.position.distance_to(_press_start_pos) > TAP_MAX_DISTANCE:
			_is_dragging = true
		position -= event.relative / zoom
	elif _touch_points.size() == 2:
		if _pointer_over_ui():
			return  # the pinch belongs to the UI panel under the finger, not the map
		var points := _touch_points.values()
		var dist: float = points[0].distance_to(points[1])
		if _pinch_start_dist == 0.0:
			_pinch_start_dist = dist
			_pinch_start_zoom = zoom.x
		else:
			var factor: float = dist / _pinch_start_dist
			var new_zoom: float = clamp(_pinch_start_zoom * factor, MIN_ZOOM, MAX_ZOOM)
			zoom = Vector2(new_zoom, new_zoom)


func _handle_mouse_button(event: InputEventMouseButton) -> void:
	if not event.pressed:
		return
	if event.button_index != MOUSE_BUTTON_WHEEL_UP and event.button_index != MOUSE_BUTTON_WHEEL_DOWN:
		return
	if _pointer_over_ui():
		return  # scrolling belongs to the UI panel under the pointer, not the map
	if event.button_index == MOUSE_BUTTON_WHEEL_UP:
		zoom = Vector2.ONE * clamp(zoom.x + ZOOM_STEP, MIN_ZOOM, MAX_ZOOM)
	else:
		zoom = Vector2.ONE * clamp(zoom.x - ZOOM_STEP, MIN_ZOOM, MAX_ZOOM)


## true if the pointer is over a UI element that accepts mouse events
## (mouse_filter != IGNORE). This automatically applies to EVERY UI panel – InfoPanel,
## BuildMenu, GameOverPanel – without each one needing to be known individually. The HUD
## bar deliberately stays at IGNORE and still lets zoom through.
func _pointer_over_ui() -> bool:
	return get_viewport().gui_get_hovered_control() != null


func _maybe_emit_tap(screen_pos: Vector2) -> void:
	if Time.get_ticks_msec() - _press_start_time > TAP_MAX_DURATION_MSEC:
		return
	if screen_pos.distance_to(_press_start_pos) > TAP_MAX_DISTANCE:
		return
	var world_pos: Vector2 = get_viewport().get_canvas_transform().affine_inverse() * screen_pos
	var cell := WorldGrid.world_to_cell(world_pos)
	tile_tapped.emit(cell)
