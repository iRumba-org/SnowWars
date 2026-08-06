class_name CalculationBase
extends CharacterBody2D

var peer_id: int = -1

@export var max_health: float = 100.0
@export var health: float = 100.0
@export var start_health: float = 100.0
@export var snowball_damage: float = 34.0
@export var health_regen_delay_sec: float = 3.0
@export var health_regen_per_sec: float = 1.0
@export var snowballs: int = 3
var craft_progress: float = 0.0

func _ready() -> void:
	health = start_health

func request_move_state(_move_vector: Vector2, _aim_angle: float) -> void:
	push_warning("request_move_state not implemented on %s" % get_class())

func receive_input(_move_vector: Vector2, _aim_angle: float) -> void:
	pass

func request_shoot() -> void:
	push_warning("request_shoot not implemented on %s" % get_class())

func on_snowball_hit(_shot_id: int, _hit_position: Vector2) -> void:
	pass

func apply_damage(_attacker: CalculationBase) -> void:
	push_warning("apply_damage not implemented on %s" % get_class())
