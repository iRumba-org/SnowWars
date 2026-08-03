extends Area2D

const SPEED := 600.0

var direction: Vector2 = Vector2.ZERO

func _ready() -> void:
	body_entered.connect(_on_body_entered)

func _physics_process(delta: float) -> void:
	position += direction * SPEED * delta

func _on_body_entered(_body: Node2D) -> void:
	queue_free()
