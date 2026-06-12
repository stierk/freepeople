extends Node2D

var data: InhabitantData


func setup(inhabitant_data: InhabitantData) -> void:
	data = inhabitant_data
	position = data.world_pos
