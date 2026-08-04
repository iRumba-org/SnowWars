class_name VisualPlayer
extends Node2D

var peer_id: int = -1
var _is_local: bool = false
var _local_controller: ManualController

func _ready() -> void:
	_is_local = peer_id == Net.get_local_peer_id()
	if _is_local:
		$Camera2D.enabled = true
		_local_controller = ManualController.new()
		add_child(_local_controller)
		_local_controller.shoot_requested.connect(Net.request_shoot)

func _process(_delta: float) -> void:
	var render_time := Time.get_ticks_msec() - Net.RENDER_DELAY_MSEC
	var state := Net.sample_player_state(peer_id, render_time)
	if not state.is_empty():
		global_position = state.position
		rotation = state.rotation

func _physics_process(_delta: float) -> void:
	if _is_local:
		Net.request_move_state(_local_controller.get_move_vector(), _local_controller.get_aim_angle())
