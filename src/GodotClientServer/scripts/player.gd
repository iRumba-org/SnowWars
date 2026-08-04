extends CharacterBody2D
class_name Player

const SPEED := 300.0
const BULLET_SCENE := preload("res://scenes/SnowBullet.tscn")
const BULLET_SPAWN_OFFSET := 45.0

var controller: ControllerBase

func _ready() -> void:
	controller = ManualController.new() if is_multiplayer_authority() else NetController.new()
	add_child(controller)
	controller.shoot_requested.connect(_shoot)

func _physics_process(_delta: float) -> void:
	velocity = controller.get_move_vector() * SPEED
	move_and_slide()
	rotation = controller.get_aim_angle()

func _shoot() -> void:
	var direction := Vector2.UP.rotated(rotation)
	var bullet := BULLET_SCENE.instantiate()
	bullet.global_position = global_position + direction * BULLET_SPAWN_OFFSET
	bullet.direction = direction
	get_parent().add_child(bullet)
