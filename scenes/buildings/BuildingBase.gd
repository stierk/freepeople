extends Node2D

signal building_tapped(building_id: int)

## Gebäude-Sprites stammen aus verschiedenen Sheets (fliegevolge_overworld) bzw. dem
## Alt-Bestand (pixelholes). Schlüssel = BuildingDef.sprite_sheet.
const SHEETS := {
	"base": preload("res://assets/fliegevolge_overworld/BaseSet.png"),
	"farm": preload("res://assets/fliegevolge_overworld/Farmlands.png"),
	"vik": preload("res://assets/fliegevolge_overworld/Vikings.png"),
	"px": preload("res://assets/pixelholes_overworld/MasterSimple.png"),
}

@onready var sprite: Sprite2D = $Sprite2D
@onready var click_area: Area2D = $ClickArea
@onready var collision_shape: CollisionShape2D = $ClickArea/CollisionShape2D

var building_id: int = -1


func _ready() -> void:
	click_area.input_event.connect(_on_click_area_input_event)


## M11: Node-Position ist die obere linke Ecke des Footprints (siehe World.gd).
## Sprite und Klickfläche werden auf footprint_size * TILE_SIZE skaliert/positioniert,
## sodass mehrzellige Gebäude ihren gesamten Footprint ausfüllen.
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


func _on_click_area_input_event(_viewport: Node, event: InputEvent, _shape_idx: int) -> void:
	if event is InputEventScreenTouch and event.pressed:
		building_tapped.emit(building_id)
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		building_tapped.emit(building_id)
