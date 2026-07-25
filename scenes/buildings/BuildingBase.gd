extends Node2D

signal building_tapped(building_id: int)

## Building sprites come from various sheets (fliegevolge_overworld) or the
## legacy assets (pixelholes). Key = BuildingDef.sprite_sheet.
const SHEETS := {
	"base": preload("res://assets/fliegevolge_overworld/BaseSet.png"),
	"farm": preload("res://assets/fliegevolge_overworld/Farmlands.png"),
	"vik": preload("res://assets/fliegevolge_overworld/Vikings.png"),
	"px": preload("res://assets/pixelholes_overworld/MasterSimple.png"),
}

## Frames per second for animated buildings (e.g. quarry hut forge).
const ANIM_FPS := 5.0
## Chimney smoke: 4 frames in Vikings.png starting at [20,16], ~3 fps.
const SMOKE_REGION := Rect2(320, 256, 16, 16)
const SMOKE_FRAMES := 4
const SMOKE_FPS := 3.0

## M21: brown/grey color tint for buildings awaiting an overdue repair –
## analogous to the tint on starving inhabitants.
const COLOR_NEEDS_REPAIR := Color(0.4, 0.28, 0.2, 1.0)
## M22: dark, desaturated ruin tint for derelict huts until they are restored.
const COLOR_DERELICT := Color(0.3, 0.3, 0.32, 1.0)

@onready var sprite: Sprite2D = $Sprite2D
@onready var click_area: Area2D = $ClickArea
@onready var collision_shape: CollisionShape2D = $ClickArea/CollisionShape2D

var building_id: int = -1

var _anim_atlas: AtlasTexture = null
var _anim_base: Rect2 = Rect2()
var _anim_frames: int = 1
var _anim_index: int = 0
var _anim_accum: float = 0.0

var _smoke_atlas: AtlasTexture = null
var _smoke_index: int = 0
var _smoke_accum: float = 0.0


func _ready() -> void:
	click_area.input_event.connect(_on_click_area_input_event)
	set_process(false)


## M11: node position is the top-left corner of the footprint (see World.gd).
## Sprite and click area are scaled/positioned to footprint_size * TILE_SIZE,
## so multi-cell buildings fill their entire footprint.
func setup(def: BuildingDef, instance_id: int) -> void:
	building_id = instance_id
	var atlas := AtlasTexture.new()
	atlas.atlas = SHEETS.get(def.sprite_sheet, SHEETS["px"])
	atlas.region = Rect2(def.sprite_atlas_region)
	sprite.texture = atlas

	var footprint_px := Vector2(def.footprint_size * WorldGrid.TILE_SIZE)
	var region_size := Vector2(def.sprite_atlas_region.size)
	if region_size.x > 0.0 and region_size.y > 0.0:
		sprite.scale = footprint_px / region_size
	sprite.position = footprint_px / 2.0

	var shape := RectangleShape2D.new()
	shape.size = footprint_px
	collision_shape.shape = shape
	collision_shape.position = footprint_px / 2.0

	# Cycle animated buildings (anim_frames > 1) through their horizontal frames.
	_anim_frames = maxi(1, def.anim_frames)
	if _anim_frames > 1:
		_anim_atlas = atlas
		_anim_base = Rect2(def.sprite_atlas_region)

	# Chimney smoke as its own sprite, top-center above the building.
	if def.has_smoke:
		_smoke_atlas = AtlasTexture.new()
		_smoke_atlas.atlas = SHEETS["vik"]
		_smoke_atlas.region = SMOKE_REGION
		var smoke := Sprite2D.new()
		smoke.texture = _smoke_atlas
		smoke.position = Vector2(footprint_px.x / 2.0, 1.0)  # top-center (roof/chimney)
		add_child(smoke)

	set_process(_anim_frames > 1 or _smoke_atlas != null)


func _process(delta: float) -> void:
	if _anim_frames > 1:
		_anim_accum += delta
		if _anim_accum >= 1.0 / ANIM_FPS:
			_anim_accum = 0.0
			_anim_index = (_anim_index + 1) % _anim_frames
			_anim_atlas.region = Rect2(
				_anim_base.position + Vector2(_anim_index * _anim_base.size.x, 0.0),
				_anim_base.size)
	if _smoke_atlas != null:
		_smoke_accum += delta
		if _smoke_accum >= 1.0 / SMOKE_FPS:
			_smoke_accum = 0.0
			_smoke_index = (_smoke_index + 1) % SMOKE_FRAMES
			_smoke_atlas.region = Rect2(
				SMOKE_REGION.position + Vector2(_smoke_index * SMOKE_REGION.size.x, 0.0),
				SMOKE_REGION.size)


## M21: fades the repair color tint in (active) or back to normal. Called by
## SimulationManager on state change (repair due / done).
func set_repair_visual(active: bool) -> void:
	var target := COLOR_NEEDS_REPAIR if active else Color.WHITE
	var tween := create_tween()
	tween.tween_property(self, "modulate", target, 0.5)


## M22: tints a derelict hut as a ruin (active) or resets it to normal after restoration.
## Called by SimulationManager on decay/rebuild.
func set_derelict_visual(active: bool) -> void:
	var target := COLOR_DERELICT if active else Color.WHITE
	var tween := create_tween()
	tween.tween_property(self, "modulate", target, 0.5)


func _on_click_area_input_event(_viewport: Node, event: InputEvent, _shape_idx: int) -> void:
	if event is InputEventScreenTouch and event.pressed:
		building_tapped.emit(building_id)
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		building_tapped.emit(building_id)
