class_name View
extends Node2D

const HEALTH_BAR_OFFSET := Vector2(-30.0, -60.0)
const SNOWBALL_INDICATOR_OFFSET := Vector2(-32.0, -32.0)

var calculation: CalculationBase
var _is_local := false
var _local_controller: ManualController

func set_calculation(calc: CalculationBase) -> void:
	calculation = calc
	_is_local = calc.peer_id == Net.get_local_peer_id()
	if _is_local:
		$Camera2D.enabled = true
		_local_controller = ManualController.new()
		add_child(_local_controller)
		_local_controller.shoot_requested.connect(calculation.request_shoot)

func _process(_delta: float) -> void:
	if calculation == null:
		return
	global_position = calculation.global_position
	rotation = calculation.rotation

	$HealthBar.global_position = calculation.global_position + HEALTH_BAR_OFFSET
	$HealthBar.max_value = calculation.max_health
	$HealthBar.value = calculation.health

	$CraftProgressBar.global_position = calculation.global_position + HEALTH_BAR_OFFSET
	$CraftProgressBar.value = calculation.craft_progress

	$SnowballIndicator.global_position = calculation.global_position + SNOWBALL_INDICATOR_OFFSET
	var snowball_icons := $SnowballIndicator.get_children()
	for i in snowball_icons.size():
		snowball_icons[i].visible = i < calculation.snowballs

func _physics_process(_delta: float) -> void:
	if not _is_local or calculation == null:
		return
	calculation.request_move_state(_local_controller.get_move_vector(), _local_controller.get_aim_angle())
