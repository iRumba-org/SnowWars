class_name LocalCalculation
extends CalculationBase

var _move_vector: Vector2 = Vector2.ZERO
var _aim_angle: float = 0.0

func _physics_process(_delta: float) -> void:
	CalculationPhysics.step(self, _move_vector, _aim_angle)

func receive_input(move_vector: Vector2, aim_angle: float) -> void:
	_move_vector = move_vector
	_aim_angle = aim_angle

func request_move_state(move_vector: Vector2, aim_angle: float) -> void:
	receive_input(move_vector, aim_angle)

var _next_shot_id_counter: int = 0
var _visual_snowballs: Dictionary = {}   # shot_id:int -> SnowBullet node

func request_shoot() -> void:
	await get_tree().create_timer(CalculationSnowball.THROW_DELAY_SEC).timeout
	var muzzle := CalculationSnowball.compute_muzzle(self)
	_next_shot_id_counter += 1
	var shot_id := _next_shot_id_counter
	CalculationSnowball.spawn_server_snowball(Net._get_server_game_root(), shot_id, muzzle.origin, muzzle.direction, CalculationSnowball.SNOWBALL_SPEED, self)
	_visual_snowballs[shot_id] = CalculationSnowball.spawn_visual_snowball(Net._get_visual_game_root(), muzzle.origin, muzzle.direction, CalculationSnowball.SNOWBALL_SPEED)

func on_snowball_hit(shot_id: int, hit_position: Vector2) -> void:
	CalculationSnowball.finalize_visual_hit(_visual_snowballs, shot_id, hit_position)
