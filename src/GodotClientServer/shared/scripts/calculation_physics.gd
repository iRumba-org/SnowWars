class_name CalculationPhysics

const SPEED := 300.0

static func step(body: CharacterBody2D, move_vector: Vector2, aim_angle: float) -> void:
	body.velocity = move_vector * SPEED
	body.move_and_slide()
	body.rotation = aim_angle
