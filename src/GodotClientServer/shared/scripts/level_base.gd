class_name LevelBase
extends Node2D

const SERVER_CALCULATION_SCENE := preload("res://server/scenes/ServerCalculation.tscn")
const LOCAL_CALCULATION_SCENE := preload("res://server/scenes/LocalCalculation.tscn")
const CLIENT_CALCULATION_SCENE := preload("res://client/scenes/ClientCalculation.tscn")
const VIEW_SCENE := preload("res://client/scenes/View.tscn")

var _server_calculations: Dictionary = {} # peer_id:int -> CalculationBase (ServerCalculation/LocalCalculation)

var _client_calculations: Dictionary = {} # peer_id:int -> ClientCalculation
var _views: Dictionary = {}               # peer_id:int -> View

func prepare_for_server() -> void:
	for node in get_tree().get_nodes_in_group("visual_only"):
		node.queue_free()
	_strip_static_objects(self)

func _strip_static_objects(node: Node) -> void:
	for child in node.get_children():
		if child is StaticObjectBase:
			child.strip_for_server()
		else:
			_strip_static_objects(child)

# --- Авторитетная половина (используется на корне из Net._setup_server_game) ---

func spawn_authoritative_calculation(peer_id: int) -> CalculationBase:
	var calculation: CalculationBase
	match Net.mode:
		Net.Mode.SERVER:
			calculation = SERVER_CALCULATION_SCENE.instantiate()
		Net.Mode.LOCAL:
			calculation = LOCAL_CALCULATION_SCENE.instantiate()
	calculation.name = "Player_%d" % peer_id
	calculation.peer_id = peer_id
	_server_calculations[peer_id] = calculation
	add_child(calculation)
	return calculation

func despawn_authoritative_calculation(peer_id: int) -> void:
	var calculation: CalculationBase = _server_calculations.get(peer_id)
	if calculation:
		calculation.queue_free()
	_server_calculations.erase(peer_id)

func build_roster() -> Array:
	var roster: Array = []
	for peer_id in _server_calculations.keys():
		var calculation: CalculationBase = _server_calculations[peer_id]
		roster.append({
			"peer_id": peer_id,
			"position": calculation.global_position,
			"rotation": calculation.rotation,
		})
	return roster

func get_server_calculations() -> Dictionary:
	return _server_calculations

# --- Визуальная половина (используется на корне из Net._setup_client_visual) ---

func ensure_client_view(peer_id: int, spawn_position: Vector2, spawn_rotation: float) -> void:
	if _client_calculations.has(peer_id):
		return
	var calculation: ClientCalculation = CLIENT_CALCULATION_SCENE.instantiate()
	calculation.name = "Player_%d" % peer_id
	calculation.peer_id = peer_id
	calculation.global_position = spawn_position
	calculation.rotation = spawn_rotation
	add_child(calculation)
	_client_calculations[peer_id] = calculation

	var view: View = VIEW_SCENE.instantiate()
	view.name = "Player_%d_View" % peer_id
	add_child(view)
	view.set_calculation(calculation)
	_views[peer_id] = view

func ensure_local_view(peer_id: int, calculation: CalculationBase) -> void:
	if _views.has(peer_id):
		return

	var view: View = VIEW_SCENE.instantiate()
	view.name = "Player_%d_View" % peer_id
	add_child(view)
	view.set_calculation(calculation)
	_views[peer_id] = view

func remove_client_view(peer_id: int) -> void:
	var calculation: ClientCalculation = _client_calculations.get(peer_id)
	if calculation:
		calculation.queue_free()
	_client_calculations.erase(peer_id)

	var view: View = _views.get(peer_id)
	if view:
		view.queue_free()
	_views.erase(peer_id)

func get_client_calculation(peer_id: int) -> ClientCalculation:
	return _client_calculations.get(peer_id)

func get_client_calculations() -> Dictionary:
	return _client_calculations
