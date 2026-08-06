class_name AuthoritativeCalculation
extends CalculationBase

@export var max_snowballs: int = 3
@export var snowballs: int = 3
@export var start_snowballs: int = 3
@export var snowball_craft_time_sec: float = 1.5

var _regen_timer_sec: float = 0.0
var _craft_progress_sec: float = 0.0

func _ready() -> void:
	super._ready()
	snowballs = start_snowballs

func _physics_process(delta: float) -> void:
	if health <= 0.0 or health >= max_health:
		pass
	else:
		_regen_timer_sec += delta
		if _regen_timer_sec >= health_regen_delay_sec:
			health = min(max_health, health + health_regen_per_sec * delta)

	if snowballs < max_snowballs:
		_craft_progress_sec += delta
		if _craft_progress_sec >= snowball_craft_time_sec:
			snowballs += 1
			_craft_progress_sec = 0.0

func consume_snowball() -> bool:
	if snowballs <= 0:
		return false
	snowballs -= 1
	_craft_progress_sec = 0.0
	return true

func apply_damage(attacker: CalculationBase) -> void:
	if health <= 0.0:
		return
	health = max(0.0, health - snowball_damage)
	_regen_timer_sec = 0.0
	if health == 0.0:
		_eliminate()

func _eliminate() -> void:
	pass  # заглушка-хук, полная логика в отдельном issue (#8)
