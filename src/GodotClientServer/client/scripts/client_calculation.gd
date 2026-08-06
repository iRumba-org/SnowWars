class_name ClientCalculation
extends CalculationBase

const RENDER_DELAY_MSEC := 100
const SNAPSHOT_BUFFER_SIZE := 8

var _buffer: Array = []   # Array[{position, rotation, time}]

func receive_snapshot(snapshot_position: Vector2, snapshot_rotation: float, snapshot_health: float, snapshot_snowballs: int, snapshot_craft_progress: float, time_msec: int) -> void:
	health = snapshot_health
	snowballs = snapshot_snowballs
	craft_progress = snapshot_craft_progress
	_buffer.append({"position": snapshot_position, "rotation": snapshot_rotation, "time": time_msec})
	while _buffer.size() > SNAPSHOT_BUFFER_SIZE:
		_buffer.pop_front()

func _process(_delta: float) -> void:
	var state := _sample(Time.get_ticks_msec() - RENDER_DELAY_MSEC)
	if not state.is_empty():
		global_position = state.position
		rotation = state.rotation

func _sample(render_time_msec: int) -> Dictionary:
	if _buffer.is_empty():
		return {}

	var oldest: Dictionary = _buffer[0]
	if render_time_msec <= oldest.time:
		return {"position": oldest.position, "rotation": oldest.rotation}

	var newest: Dictionary = _buffer[_buffer.size() - 1]
	if render_time_msec >= newest.time:
		return {"position": newest.position, "rotation": newest.rotation}

	for i in range(_buffer.size() - 1):
		var a: Dictionary = _buffer[i]
		var b: Dictionary = _buffer[i + 1]
		if a.time <= render_time_msec and render_time_msec <= b.time:
			var span := float(b.time - a.time)
			var t := 0.0
			if span > 0.0:
				t = float(render_time_msec - a.time) / span
			return {
				"position": a.position.lerp(b.position, t),
				"rotation": lerp_angle(a.rotation, b.rotation, t),
			}

	return {"position": newest.position, "rotation": newest.rotation}

func request_move_state(move_vector: Vector2, aim_angle: float) -> void:
	submit_move_state.rpc_id(1, move_vector, aim_angle)

@rpc("any_peer", "unreliable_ordered")
func submit_move_state(_move_vector: Vector2, _aim_angle: float) -> void:
	pass  # тело не используется — исходящий вызов резолвится в одноимённый
	      # метод ServerCalculation на том же пути на сервере

func request_shoot() -> void:
	submit_shoot.rpc_id(1)

@rpc("any_peer", "reliable")
func submit_shoot() -> void:
	pass  # тело не используется — исходящий вызов резолвится в одноимённый
	      # метод ServerCalculation на том же пути на сервере

@rpc("authority", "reliable")
func spawn_snowball(shot_id: int, direction: Vector2, speed: float) -> void:
	var origin := global_position + direction * CalculationSnowball.BULLET_SPAWN_OFFSET
	_get_visual_root().spawn_visual_snowball(shot_id, origin, direction, speed)

@rpc("authority", "reliable")
func snowball_hit(shot_id: int, hit_position: Vector2) -> void:
	_get_visual_root().finalize_snowball_hit(shot_id, hit_position)

# ClientCalculation спавнится как прямой потомок визуального LevelBase (узел "Game" на CLIENT,
# "VisualGame" в LOCAL-режиме — см. Lobby._create_visual_game/LevelBase.ensure_client_view),
# поэтому родитель и есть искомый LevelBase.
func _get_visual_root() -> LevelBase:
	return get_parent()
