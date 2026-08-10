extends Node3D

@export var model_scale: float = 1.0
@export var model_yaw: float = 0.0

func _ready() -> void:
	if model_scale != 1.0:
		scale *= model_scale
	if model_yaw != 0.0:
		rotation.y += model_yaw
