class_name ServerSnowball
extends Area2D

var shot_id: int = -1
var shooter_peer_id: int = -1
var direction: Vector2 = Vector2.ZERO
var speed: float = 600.0

func _ready() -> void:
	body_entered.connect(_on_body_entered)

func _physics_process(delta: float) -> void:
	position += direction * speed * delta

func _on_body_entered(_body: Node2D) -> void:
	Net.on_server_snowball_hit(self)
