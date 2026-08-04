class_name ManualController
extends ControllerBase

var _last_aim_angle: float = 0.0

func get_move_vector() -> Vector2:
	if not get_window().has_focus():
		return Vector2.ZERO
	return Input.get_vector("move_left", "move_right", "move_up", "move_down")

func get_aim_angle() -> float:
	if not get_window().has_focus():
		return _last_aim_angle
	var mouse_pos := get_global_mouse_position()
	_last_aim_angle = (mouse_pos - global_position).angle() + PI / 2
	return _last_aim_angle

func _unhandled_input(event: InputEvent) -> void:
	if not get_window().has_focus():
		return
	if event.is_action_pressed("shoot"):
		shoot_requested.emit()
