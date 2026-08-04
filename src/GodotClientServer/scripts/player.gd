extends CharacterBody2D
class_name Player

const SPEED := 300.0

var controller: NetController

func _ready() -> void:
	controller = NetController.new()
	add_child(controller)

func _physics_process(_delta: float) -> void:
	velocity = controller.get_move_vector() * SPEED
	move_and_slide()
	rotation = controller.get_aim_angle()
