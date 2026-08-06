class_name AuthoritativeCalculation
extends CalculationBase

var _regen_timer_sec: float = 0.0

func _physics_process(delta: float) -> void:
	if health <= 0.0 or health >= max_health:
		return
	_regen_timer_sec += delta
	if _regen_timer_sec < health_regen_delay_sec:
		return
	health = min(max_health, health + health_regen_per_sec * delta)

func apply_damage(attacker: CalculationBase) -> void:
	if health <= 0.0:
		return
	health = max(0.0, health - snowball_damage)
	_regen_timer_sec = 0.0
	if health == 0.0:
		_eliminate()

func _eliminate() -> void:
	pass  # заглушка-хук, полная логика в отдельном issue (#8)
