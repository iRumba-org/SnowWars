class_name NetController
extends ControllerBase

var _move_vector: Vector2 = Vector2.ZERO
var _aim_angle: float = 0.0

func get_move_vector() -> Vector2:
	return _move_vector

func get_aim_angle() -> float:
	return _aim_angle

func set_state(move_vector: Vector2, aim_angle: float) -> void:
	_move_vector = move_vector
	_aim_angle = aim_angle
