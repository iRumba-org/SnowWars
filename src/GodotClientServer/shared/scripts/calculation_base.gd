class_name CalculationBase
extends CharacterBody2D

var peer_id: int = -1

func request_move_state(_move_vector: Vector2, _aim_angle: float) -> void:
	push_warning("request_move_state not implemented on %s" % get_class())

func receive_input(_move_vector: Vector2, _aim_angle: float) -> void:
	pass

func request_shoot() -> void:
	push_warning("request_shoot not implemented on %s" % get_class())

func on_snowball_hit(_shot_id: int, _hit_position: Vector2) -> void:
	pass
