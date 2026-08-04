class_name ControllerBase
extends Node2D

signal shoot_requested

func get_move_vector() -> Vector2:
	return Vector2.ZERO

func get_aim_angle() -> float:
	return 0.0
