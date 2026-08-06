class_name LocalCalculation
extends AuthoritativeCalculation

var _move_vector: Vector2 = Vector2.ZERO
var _aim_angle: float = 0.0

func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	CalculationPhysics.step(self, _move_vector, _aim_angle)

func receive_input(move_vector: Vector2, aim_angle: float) -> void:
	_move_vector = move_vector
	_aim_angle = aim_angle

func request_move_state(move_vector: Vector2, aim_angle: float) -> void:
	receive_input(move_vector, aim_angle)

func request_shoot() -> void:
	if not consume_snowball():
		return
	await get_tree().create_timer(CalculationSnowball.THROW_DELAY_SEC).timeout
	var muzzle := CalculationSnowball.compute_muzzle(self)
	var game_root := _get_game_root()
	var visual_root := _get_visual_root()
	var shot_id := game_root.next_shot_id()
	CalculationSnowball.spawn_server_snowball(game_root, shot_id, muzzle.origin, muzzle.direction, CalculationSnowball.SNOWBALL_SPEED, self)
	visual_root.spawn_visual_snowball(shot_id, muzzle.origin, muzzle.direction, CalculationSnowball.SNOWBALL_SPEED)

func on_snowball_hit(shot_id: int, hit_position: Vector2) -> void:
	_get_visual_root().finalize_snowball_hit(shot_id, hit_position)

# LocalCalculation спавнится как прямой потомок узла "Game" (авторитетный LevelBase). В
# LOCAL-режиме тот же Lobby ещё держит соседний узел "VisualGame" (визуальный LevelBase) —
# поднимаемся до Lobby и берём его по имени.
func _get_game_root() -> LevelBase:
	return get_parent()

func _get_visual_root() -> LevelBase:
	return get_parent().get_parent().get_node("VisualGame")
