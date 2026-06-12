extends Node2D

@onready var camera_controller: Camera2D = $CameraController


func _ready() -> void:
	camera_controller.tile_tapped.connect(_on_tile_tapped)


func _on_tile_tapped(cell: Vector2i) -> void:
	print("Tile tapped: ", cell)
