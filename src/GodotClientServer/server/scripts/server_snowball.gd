class_name ServerSnowball
extends Area2D

var shot_id: int = -1
var shooter_calculation: CalculationBase = null
var direction: Vector2 = Vector2.ZERO
var speed: float = 600.0
var _already_hit := false

func _ready() -> void:
	body_entered.connect(_on_body_entered)

func _physics_process(delta: float) -> void:
	position += direction * speed * delta

func _on_body_entered(body: Node2D) -> void:
	if _already_hit:
		return
	_already_hit = true
	if body is CalculationBase and body != shooter_calculation:
		body.apply_damage(shooter_calculation)
	if is_instance_valid(shooter_calculation):
		shooter_calculation.on_snowball_hit(shot_id, global_position)
	queue_free()
