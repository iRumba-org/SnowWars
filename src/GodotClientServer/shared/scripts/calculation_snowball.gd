class_name CalculationSnowball

const THROW_DELAY_SEC := 0.4
const SNOWBALL_SPEED := 600.0
const BULLET_SPAWN_OFFSET := 45.0

const SERVER_SNOWBALL_SCENE := preload("res://server/scenes/ServerSnowball.tscn")
const SNOW_BULLET_SCENE := preload("res://client/scenes/SnowBullet.tscn")

static func compute_muzzle(shooter: CalculationBase) -> Dictionary:
	var direction := Vector2.UP.rotated(shooter.rotation)
	var origin := shooter.global_position + direction * BULLET_SPAWN_OFFSET
	return {"direction": direction, "origin": origin}

static func spawn_server_snowball(parent: Node, shot_id: int, origin: Vector2, direction: Vector2, speed: float, shooter: CalculationBase) -> void:
	var snowball: ServerSnowball = SERVER_SNOWBALL_SCENE.instantiate()
	snowball.shot_id = shot_id
	snowball.shooter_calculation = shooter
	snowball.direction = direction
	snowball.speed = speed
	snowball.global_position = origin
	parent.add_child(snowball)

static func spawn_visual_snowball(parent: Node, origin: Vector2, direction: Vector2, speed: float) -> Node:
	var bullet := SNOW_BULLET_SCENE.instantiate()
	bullet.direction = direction
	bullet.speed = speed
	bullet.global_position = origin
	parent.add_child(bullet)
	return bullet

static func finalize_visual_hit(visual_snowballs: Dictionary, shot_id: int, hit_position: Vector2) -> void:
	var bullet = visual_snowballs.get(shot_id)
	if bullet and is_instance_valid(bullet):
		bullet.global_position = hit_position
		bullet.queue_free()
	visual_snowballs.erase(shot_id)
