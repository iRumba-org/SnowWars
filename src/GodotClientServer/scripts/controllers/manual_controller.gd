class_name ManualController
extends ControllerBase

func get_move_vector() -> Vector2:
	return Input.get_vector("move_left", "move_right", "move_up", "move_down")

func get_aim_angle() -> float:
	var mouse_pos := get_global_mouse_position()
	return (mouse_pos - global_position).angle() + PI / 2

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("shoot"):
		shoot_requested.emit()
