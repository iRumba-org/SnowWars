extends Node

# --- Constants ---------------------------------------------------------

const LOBBY_NAME := "default"       # единственное место, где "зашит" лобби — расширение до
                                     # lobbies/<id> потом меняет только _get_*_root()
const DEFAULT_PORT := 4433
const MAX_CLIENTS := 16
const LOCAL_PEER_ID := 1
const THROW_DELAY_SEC := 0.4        # точка расширения под будущие типы оружия
const SNOWBALL_SPEED := 600.0
const BULLET_SPAWN_OFFSET := 45.0

const LEVEL_SCENE := preload("res://shared/scenes/Level.tscn")
const SERVER_CALCULATION_SCENE := preload("res://server/scenes/ServerCalculation.tscn")
const LOCAL_CALCULATION_SCENE := preload("res://server/scenes/LocalCalculation.tscn")
const CLIENT_CALCULATION_SCENE := preload("res://client/scenes/ClientCalculation.tscn")
const VIEW_SCENE := preload("res://client/scenes/View.tscn")
const SERVER_SNOWBALL_SCENE := preload("res://server/scenes/ServerSnowball.tscn")
const SNOW_BULLET_SCENE := preload("res://client/scenes/SnowBullet.tscn")

# --- State ---------------------------------------------------------------

enum Mode { NONE, SERVER, CLIENT, LOCAL }
var mode: Mode = Mode.NONE

var _server_calculations: Dictionary = {} # peer_id:int -> CalculationBase (ServerCalculation/LocalCalculation)
var _next_shot_id_counter: int = 0

var _client_calculations: Dictionary = {} # peer_id:int -> ClientCalculation
var _views: Dictionary = {}               # peer_id:int -> View
var _visual_snowballs: Dictionary = {}    # shot_id:int -> SnowBullet node

# --- Public API запуска (вызывается из Launcher) --------------------------

func start_server(port: int) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port, MAX_CLIENTS)
	if err != OK:
		return err
	_teardown_launcher()
	multiplayer.multiplayer_peer = peer
	mode = Mode.SERVER
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	_setup_server_game()
	_setup_server_info()
	return OK

func start_client(host: String, port: int) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(host, port)
	if err != OK:
		return err
	_teardown_launcher()
	multiplayer.multiplayer_peer = peer
	mode = Mode.CLIENT
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	_setup_client_visual()
	return OK

func start_local() -> void:
	_teardown_launcher()
	mode = Mode.LOCAL
	_setup_server_game()
	_setup_client_visual()
	_setup_server_info()
	_on_peer_connected(LOCAL_PEER_ID)

func shutdown() -> void:
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null
	mode = Mode.NONE

# --- Сетап дерева ----------------------------------------------------------

func _teardown_launcher() -> void:
	var launcher := get_tree().current_scene
	if launcher:
		get_tree().root.remove_child(launcher)
		launcher.queue_free()
		get_tree().current_scene = null

func _setup_server_game() -> void:
	match mode:
		Mode.SERVER:
			var game := Node.new()
			game.name = "Game"
			get_tree().root.add_child(game)

			var level: LevelBase = LEVEL_SCENE.instantiate()
			level.name = "Level"
			game.add_child(level)
			level.prepare_for_server()
		Mode.LOCAL:
			var global_server := Node.new()
			global_server.name = "globalServer"
			get_tree().root.add_child(global_server)

			var level: LevelBase = LEVEL_SCENE.instantiate()
			level.name = "game"
			global_server.add_child(level)
			level.prepare_for_server()

func _setup_client_visual() -> void:
	match mode:
		Mode.CLIENT:
			var game := Node.new()
			game.name = "Game"
			get_tree().root.add_child(game)

			var level: LevelBase = LEVEL_SCENE.instantiate()
			level.name = "Level"
			game.add_child(level)
		Mode.LOCAL:
			var visual := Node.new()
			visual.name = "visual"
			get_tree().root.add_child(visual)

			var level: LevelBase = LEVEL_SCENE.instantiate()
			level.name = "currentGame"
			visual.add_child(level)

func _setup_server_info() -> void:
	var info := ServerInfo.new()
	info.name = "serverInfo"
	get_tree().root.add_child(info)

func _get_server_game_root() -> Node:
	match mode:
		Mode.SERVER:
			return get_node("/root/Game/Level")
		Mode.LOCAL:
			return get_node("/root/globalServer/game")
	return null

func _get_visual_game_root() -> Node:
	match mode:
		Mode.CLIENT:
			return get_node("/root/Game/Level")
		Mode.LOCAL:
			return get_node("/root/visual/currentGame")
	return null

# --- Клиентские сигналы MultiplayerAPI -------------------------------------

func _on_connected_to_server() -> void:
	pass

func _on_connection_failed() -> void:
	push_error("Net: connection to server failed")

func _on_server_disconnected() -> void:
	push_error("Net: server disconnected")

# --- Подключение/отключение (сервер) ---------------------------------------

func _on_peer_connected(peer_id: int) -> void:
	var calculation := _spawn_authoritative_calculation(peer_id)
	match mode:
		Mode.SERVER:
			receive_player_roster.rpc_id(peer_id, _build_roster())
			spawn_visual_player.rpc(peer_id, calculation.global_position, calculation.rotation)
		Mode.LOCAL:
			_ensure_local_view(peer_id)

func _on_peer_disconnected(peer_id: int) -> void:
	_despawn_authoritative_calculation(peer_id)
	despawn_visual_player.rpc(peer_id)

func _spawn_authoritative_calculation(peer_id: int) -> CalculationBase:
	var calculation: CalculationBase
	match mode:
		Mode.SERVER:
			calculation = SERVER_CALCULATION_SCENE.instantiate()
		Mode.LOCAL:
			calculation = LOCAL_CALCULATION_SCENE.instantiate()
	calculation.name = "Player_%d" % peer_id
	calculation.peer_id = peer_id
	_server_calculations[peer_id] = calculation
	_get_server_game_root().add_child(calculation)
	return calculation

func _despawn_authoritative_calculation(peer_id: int) -> void:
	var calculation: CalculationBase = _server_calculations.get(peer_id)
	if calculation:
		calculation.queue_free()
	_server_calculations.erase(peer_id)

func _build_roster() -> Array:
	var roster: Array = []
	for peer_id in _server_calculations.keys():
		var calculation: CalculationBase = _server_calculations[peer_id]
		roster.append({
			"peer_id": peer_id,
			"position": calculation.global_position,
			"rotation": calculation.rotation,
		})
	return roster

# --- Выстрел ------------------------------------------------------------------

func request_shoot() -> void:
	match mode:
		Mode.LOCAL:
			_apply_shoot(LOCAL_PEER_ID)
		Mode.CLIENT:
			submit_shoot.rpc_id(1)

@rpc("any_peer", "reliable")
func submit_shoot() -> void:
	_apply_shoot(multiplayer.get_remote_sender_id())

# --- Мировое состояние: сервер → клиенты ------------------------------------

func _physics_process(_delta: float) -> void:
	if mode == Mode.SERVER:
		_broadcast_world_state()

func _broadcast_world_state() -> void:
	var states: Dictionary = {}
	for peer_id in _server_calculations.keys():
		var calculation: CalculationBase = _server_calculations[peer_id]
		states[peer_id] = {
			"position": calculation.global_position,
			"rotation": calculation.rotation,
		}
	push_world_state.rpc(states)

@rpc("authority", "unreliable_ordered")
func push_world_state(states: Dictionary) -> void:
	_apply_world_state(states)

func _apply_world_state(states: Dictionary) -> void:
	var now := Time.get_ticks_msec()
	for peer_id in states.keys():
		var state: Dictionary = states[peer_id]
		var calculation: ClientCalculation = _client_calculations.get(peer_id)
		if calculation:
			calculation.receive_snapshot(state.position, state.rotation, now)

# --- Ростер / спавн-деспавн визуальных игроков -------------------------------

@rpc("authority", "reliable")
func receive_player_roster(roster: Array) -> void:
	for entry in roster:
		_ensure_client_view(entry.peer_id, entry.position, entry.rotation)

@rpc("authority", "reliable")
func spawn_visual_player(peer_id: int, position: Vector2, rotation: float) -> void:
	_ensure_client_view(peer_id, position, rotation)

@rpc("authority", "reliable")
func despawn_visual_player(peer_id: int) -> void:
	_remove_client_view(peer_id)

func _ensure_local_view(peer_id: int) -> void:
	if _views.has(peer_id):
		return
	var calculation: LocalCalculation = _server_calculations.get(peer_id)
	if not calculation:
		return

	var view: View = VIEW_SCENE.instantiate()
	view.name = "Player_%d_View" % peer_id
	_get_visual_game_root().add_child(view)
	view.set_calculation(calculation)
	_views[peer_id] = view

func _ensure_client_view(peer_id: int, position: Vector2, rotation: float) -> void:
	if _client_calculations.has(peer_id):
		return
	var calculation: ClientCalculation = CLIENT_CALCULATION_SCENE.instantiate()
	calculation.name = "Player_%d" % peer_id
	calculation.peer_id = peer_id
	calculation.global_position = position
	calculation.rotation = rotation
	_get_visual_game_root().add_child(calculation)
	_client_calculations[peer_id] = calculation

	var view: View = VIEW_SCENE.instantiate()
	view.name = "Player_%d_View" % peer_id
	_get_visual_game_root().add_child(view)
	view.set_calculation(calculation)
	_views[peer_id] = view

func _remove_client_view(peer_id: int) -> void:
	var calculation: ClientCalculation = _client_calculations.get(peer_id)
	if calculation:
		calculation.queue_free()
	_client_calculations.erase(peer_id)

	var view: View = _views.get(peer_id)
	if view:
		view.queue_free()
	_views.erase(peer_id)

func get_local_peer_id() -> int:
	if mode == Mode.LOCAL:
		return LOCAL_PEER_ID
	if multiplayer.multiplayer_peer != null:
		return multiplayer.get_unique_id()
	return LOCAL_PEER_ID

# --- Выстрел / снежки ---------------------------------------------------------

func _apply_shoot(peer_id: int) -> void:
	await get_tree().create_timer(THROW_DELAY_SEC).timeout

	var calculation: CalculationBase = _server_calculations.get(peer_id)
	if not calculation:
		return

	var shot_id := _next_shot_id()
	var direction := Vector2.UP.rotated(calculation.rotation)
	var origin := calculation.global_position + direction * BULLET_SPAWN_OFFSET
	_spawn_server_snowball(shot_id, origin, direction, SNOWBALL_SPEED, peer_id)

	match mode:
		Mode.SERVER:
			spawn_snowball.rpc(shot_id, peer_id, origin, direction, SNOWBALL_SPEED)
		Mode.LOCAL:
			_apply_spawn_snowball(shot_id, peer_id, origin, direction, SNOWBALL_SPEED)

func _next_shot_id() -> int:
	_next_shot_id_counter += 1
	return _next_shot_id_counter

func _spawn_server_snowball(shot_id: int, origin: Vector2, direction: Vector2, speed: float, shooter_peer_id: int) -> void:
	var snowball: ServerSnowball = SERVER_SNOWBALL_SCENE.instantiate()
	snowball.shot_id = shot_id
	snowball.shooter_peer_id = shooter_peer_id
	snowball.direction = direction
	snowball.speed = speed
	snowball.global_position = origin
	_get_server_game_root().add_child(snowball)

func on_server_snowball_hit(snowball: ServerSnowball) -> void:
	if not is_instance_valid(snowball):
		return
	match mode:
		Mode.SERVER:
			snowball_hit.rpc(snowball.shot_id, snowball.global_position)
		Mode.LOCAL:
			_apply_snowball_hit(snowball.shot_id, snowball.global_position)
	snowball.queue_free()

@rpc("authority", "reliable")
func spawn_snowball(shot_id: int, shooter_peer_id: int, origin: Vector2, direction: Vector2, speed: float) -> void:
	_apply_spawn_snowball(shot_id, shooter_peer_id, origin, direction, speed)

func _apply_spawn_snowball(shot_id: int, shooter_peer_id: int, origin: Vector2, direction: Vector2, speed: float) -> void:
	var spawn_origin := origin
	var shooter: CalculationBase = _client_calculations.get(shooter_peer_id)
	if shooter:
		spawn_origin = shooter.global_position + direction * BULLET_SPAWN_OFFSET
	var bullet := SNOW_BULLET_SCENE.instantiate()
	bullet.direction = direction
	bullet.speed = speed
	bullet.global_position = spawn_origin
	_get_visual_game_root().add_child(bullet)
	_visual_snowballs[shot_id] = bullet

@rpc("authority", "reliable")
func snowball_hit(shot_id: int, position: Vector2) -> void:
	_apply_snowball_hit(shot_id, position)

func _apply_snowball_hit(shot_id: int, position: Vector2) -> void:
	var bullet = _visual_snowballs.get(shot_id)
	if bullet and is_instance_valid(bullet):
		bullet.global_position = position
		bullet.queue_free()
	_visual_snowballs.erase(shot_id)

# --- Геттер для ServerInfo -----------------------------------------------------

func get_known_player_ids() -> Array:
	if mode == Mode.SERVER or mode == Mode.LOCAL:
		return _server_calculations.keys()
	return _client_calculations.keys()
