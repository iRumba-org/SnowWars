extends CharacterBody2D

const SPEED := 300.0
const BULLET_SCENE := preload("res://scenes/SnowBullet.tscn")
const BULLET_SPAWN_OFFSET := 45.0

func _physics_process(_delta: float) -> void:
	var input_vector := Vector2.ZERO
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		input_vector.x -= 1
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		input_vector.x += 1
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		input_vector.y -= 1
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		input_vector.y += 1

	velocity = input_vector.normalized() * SPEED
	move_and_slide()

	var mouse_pos := get_global_mouse_position()
	rotation = (mouse_pos - global_position).angle() + PI / 2

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_shoot()

func _shoot() -> void:
	var direction := Vector2.UP.rotated(rotation)
	var bullet := BULLET_SCENE.instantiate()
	bullet.global_position = global_position + direction * BULLET_SPAWN_OFFSET
	bullet.direction = direction
	get_parent().add_child(bullet)
