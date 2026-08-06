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

@rpc("any_peer", "reliable")
func submit_shoot() -> void:
	if multiplayer.get_remote_sender_id() != peer_id:
		return
	await get_tree().create_timer(CalculationSnowball.THROW_DELAY_SEC).timeout
	var muzzle := CalculationSnowball.compute_muzzle(self)
	var level := _get_game_root()
	var shot_id := level.next_shot_id()
	CalculationSnowball.spawn_server_snowball(level, shot_id, muzzle.origin, muzzle.direction, CalculationSnowball.SNOWBALL_SPEED, self)
	spawn_snowball.rpc(shot_id, muzzle.direction, CalculationSnowball.SNOWBALL_SPEED)

@rpc("authority", "reliable")
func spawn_snowball(_shot_id: int, _direction: Vector2, _speed: float) -> void:
	pass  # тело не используется — исходящий вызов резолвится в одноимённый
	      # метод ClientCalculation на том же пути на клиентах

func on_snowball_hit(shot_id: int, hit_position: Vector2) -> void:
	snowball_hit.rpc(shot_id, hit_position)

@rpc("authority", "reliable")
func snowball_hit(_shot_id: int, _hit_position: Vector2) -> void:
	pass  # тело не используется — исходящий вызов резолвится в одноимённый
	      # метод ClientCalculation на том же пути на клиентах

# ServerCalculation спавнится как прямой потомок узла "Game" (см. Lobby._create_game/
# LevelBase.spawn_authoritative_calculation), поэтому родитель и есть искомый LevelBase.
func _get_game_root() -> LevelBase:
	return get_parent()
