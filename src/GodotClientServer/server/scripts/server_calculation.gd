class_name ServerCalculation
extends CalculationBase

var _move_vector: Vector2 = Vector2.ZERO
var _aim_angle: float = 0.0

func _physics_process(_delta: float) -> void:
	CalculationPhysics.step(self, _move_vector, _aim_angle)

func receive_input(move_vector: Vector2, aim_angle: float) -> void:
	_move_vector = move_vector
	_aim_angle = aim_angle

@rpc("any_peer", "unreliable_ordered")
func submit_move_state(move_vector: Vector2, aim_angle: float) -> void:
	if multiplayer.get_remote_sender_id() != peer_id:
		return
	receive_input(move_vector, aim_angle)
