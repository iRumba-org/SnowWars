class_name CalculationBase
extends CharacterBody2D

var peer_id: int = -1

func request_move_state(_move_vector: Vector2, _aim_angle: float) -> void:
	push_warning("request_move_state not implemented on %s" % get_class())

func receive_input(_move_vector: Vector2, _aim_angle: float) -> void:
	pass
