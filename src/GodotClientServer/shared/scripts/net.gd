extends Node

# --- Constants ---------------------------------------------------------

const LOBBY_NAME := "default"       # единственное место, где "зашит" лобби — расширение до
                                     # lobbies/<id> потом меняет только _get_*_root()
const DEFAULT_PORT := 4433
const MAX_CLIENTS := 16
const LOCAL_PEER_ID := 1

const LEVEL_SCENE := preload("res://shared/scenes/Level.tscn")

# --- State ---------------------------------------------------------------

enum Mode { NONE, SERVER, CLIENT, LOCAL }
var mode: Mode = Mode.NONE

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

func _get_server_game_root() -> LevelBase:
	match mode:
		Mode.SERVER:
			return get_node("/root/Game/Level")
		Mode.LOCAL:
			return get_node("/root/globalServer/game")
	return null

func _get_visual_game_root() -> LevelBase:
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
	var calculation := _get_server_game_root().spawn_authoritative_calculation(peer_id)
	match mode:
		Mode.SERVER:
			receive_player_roster.rpc_id(peer_id, _get_server_game_root().build_roster())
			spawn_visual_player.rpc(peer_id, calculation.global_position, calculation.rotation)
		Mode.LOCAL:
			_get_visual_game_root().ensure_local_view(peer_id, calculation)

func _on_peer_disconnected(peer_id: int) -> void:
	_get_server_game_root().despawn_authoritative_calculation(peer_id)
	despawn_visual_player.rpc(peer_id)

# --- Мировое состояние: сервер → клиенты ------------------------------------

func _physics_process(_delta: float) -> void:
	if mode == Mode.SERVER:
		_broadcast_world_state()

func _broadcast_world_state() -> void:
	var states: Dictionary = {}
	var calculations := _get_server_game_root().get_server_calculations()
	for peer_id in calculations.keys():
		var calculation: CalculationBase = calculations[peer_id]
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
	var visual_root := _get_visual_game_root()
	for peer_id in states.keys():
		var state: Dictionary = states[peer_id]
		var calculation: ClientCalculation = visual_root.get_client_calculation(peer_id)
		if calculation:
			calculation.receive_snapshot(state.position, state.rotation, now)

# --- Ростер / спавн-деспавн визуальных игроков -------------------------------

@rpc("authority", "reliable")
func receive_player_roster(roster: Array) -> void:
	for entry in roster:
		_get_visual_game_root().ensure_client_view(entry.peer_id, entry.position, entry.rotation)

@rpc("authority", "reliable")
func spawn_visual_player(peer_id: int, position: Vector2, rotation: float) -> void:
	_get_visual_game_root().ensure_client_view(peer_id, position, rotation)

@rpc("authority", "reliable")
func despawn_visual_player(peer_id: int) -> void:
	_get_visual_game_root().remove_client_view(peer_id)

func get_local_peer_id() -> int:
	if mode == Mode.LOCAL:
		return LOCAL_PEER_ID
	if multiplayer.multiplayer_peer != null:
		return multiplayer.get_unique_id()
	return LOCAL_PEER_ID

# --- Геттер для ServerInfo -----------------------------------------------------

func get_known_player_ids() -> Array:
	if mode == Mode.SERVER or mode == Mode.LOCAL:
		return _get_server_game_root().get_server_calculations().keys()
	return _get_visual_game_root().get_client_calculations().keys()
