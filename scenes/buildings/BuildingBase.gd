extends Node2D

signal building_tapped(building_id: int)

const TILESET_TEXTURE := preload("res://assets/kenney_roguelike_rpg/Spritesheet/roguelikeSheet_transparent.png")

@onready var sprite: Sprite2D = $Sprite2D
@onready var click_area: Area2D = $ClickArea

var building_id: int = -1


func _ready() -> void:
	click_area.input_event.connect(_on_click_area_input_event)


func setup(def: BuildingDef, instance_id: int) -> void:
	building_id = instance_id
	var atlas := AtlasTexture.new()
	atlas.atlas = TILESET_TEXTURE
	atlas.region = Rect2(def.sprite_atlas_region)
	sprite.texture = atlas


func _on_click_area_input_event(_viewport: Node, event: InputEvent, _shape_idx: int) -> void:
	if event is InputEventScreenTouch and event.pressed:
		building_tapped.emit(building_id)
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		building_tapped.emit(building_id)
