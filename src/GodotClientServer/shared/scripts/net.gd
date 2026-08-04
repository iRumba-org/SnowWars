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
const RENDER_DELAY_MSEC := 100
const SNAPSHOT_BUFFER_SIZE := 8

const LEVEL_SCENE := preload("res://scenes/Level.tscn")
const PLAYER_SCENE := preload("res://scenes/Player.tscn")
const VISUAL_PLAYER_SCENE := preload("res://scenes/VisualPlayer.tscn")
const SERVER_SNOWBALL_SCENE := preload("res://scenes/ServerSnowball.tscn")
const SNOW_BULLET_SCENE := preload("res://scenes/SnowBullet.tscn")

# --- State ---------------------------------------------------------------

enum Mode { NONE, SERVER, CLIENT, LOCAL }
var mode: Mode = Mode.NONE

var _server_players: Dictionary = {}     # peer_id:int -> Player
var _next_shot_id_counter: int = 0

var _visual_players: Dictionary = {}     # peer_id:int -> VisualPlayer
var _state_buffers: Dictionary = {}      # peer_id:int -> Array[{position, rotation, time}]
var _visual_snowballs: Dictionary = {}   # shot_id:int -> SnowBullet node

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
	var global_server := Node.new()
	global_server.name = "globalServer"
	get_tree().root.add_child(global_server)

	var level: LevelBase = LEVEL_SCENE.instantiate()
	level.name = "game"
	global_server.add_child(level)
	level.prepare_for_server()

func _setup_client_visual() -> void:
	var client := Node.new()
	client.name = "client"
	get_tree().root.add_child(client)

	var client_game := Node.new()
	client_game.name = "game"
	client.add_child(client_game)

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
	return get_node("/root/globalServer/game")

func _get_visual_game_root() -> Node:
	return get_node("/root/visual/currentGame")

# --- Клиентские сигналы MultiplayerAPI -------------------------------------

func _on_connected_to_server() -> void:
	pass

func _on_connection_failed() -> void:
	push_error("Net: connection to server failed")

func _on_server_disconnected() -> void:
	push_error("Net: server disconnected")

# --- Подключение/отключение (сервер) ---------------------------------------

func _on_peer_connected(peer_id: int) -> void:
	var player := _spawn_authoritative_player(peer_id)
	match mode:
		Mode.SERVER:
			receive_player_roster.rpc_id(peer_id, _build_roster())
			spawn_visual_player.rpc(peer_id, player.global_position, player.rotation)
		Mode.LOCAL:
			_ensure_visual_player(peer_id, player.global_position, player.rotation)

func _on_peer_disconnected(peer_id: int) -> void:
	_despawn_authoritative_player(peer_id)
	despawn_visual_player.rpc(peer_id)

func _spawn_authoritative_player(peer_id: int) -> Player:
	var player: Player = PLAYER_SCENE.instantiate()
	_server_players[peer_id] = player
	_get_server_game_root().add_child(player)
	return player

func _despawn_authoritative_player(peer_id: int) -> void:
	var player: Player = _server_players.get(peer_id)
	if player:
		player.queue_free()
	_server_players.erase(peer_id)

func _build_roster() -> Array:
	var roster: Array = []
	for peer_id in _server_players.keys():
		var player: Player = _server_players[peer_id]
		roster.append({
			"peer_id": peer_id,
			"position": player.global_position,
			"rotation": player.rotation,
		})
	return roster

# --- Ввод: клиент → сервер ---------------------------------------------------

func request_move_state(move_vector: Vector2, aim_angle: float) -> void:
	match mode:
		Mode.LOCAL:
			_apply_move_state(LOCAL_PEER_ID, move_vector, aim_angle)
		Mode.CLIENT:
			submit_move_state.rpc_id(1, move_vector, aim_angle)

func request_shoot() -> void:
	match mode:
		Mode.LOCAL:
			_apply_shoot(LOCAL_PEER_ID)
		Mode.CLIENT:
			submit_shoot.rpc_id(1)

@rpc("any_peer", "unreliable_ordered")
func submit_move_state(move_vector: Vector2, aim_angle: float) -> void:
	_apply_move_state(multiplayer.get_remote_sender_id(), move_vector, aim_angle)

@rpc("any_peer", "reliable")
func submit_shoot() -> void:
	_apply_shoot(multiplayer.get_remote_sender_id())

func _apply_move_state(peer_id: int, move_vector: Vector2, aim_angle: float) -> void:
	var player: Player = _server_players.get(peer_id)
	if player:
		player.controller.set_state(move_vector, aim_angle)

# --- Мировое состояние: сервер → клиенты ------------------------------------

func _physics_process(_delta: float) -> void:
	if mode == Mode.SERVER or mode == Mode.LOCAL:
		_broadcast_world_state()

func _broadcast_world_state() -> void:
	var states: Dictionary = {}
	for peer_id in _server_players.keys():
		var player: Player = _server_players[peer_id]
		states[peer_id] = {
			"position": player.global_position,
			"rotation": player.rotation,
		}
	match mode:
		Mode.SERVER:
			push_world_state.rpc(states)
		Mode.LOCAL:
			_apply_world_state(states)

@rpc("authority", "unreliable_ordered")
func push_world_state(states: Dictionary) -> void:
	_apply_world_state(states)

func _apply_world_state(states: Dictionary) -> void:
	var now := Time.get_ticks_msec()
	for peer_id in states.keys():
		var state: Dictionary = states[peer_id]
		_push_snapshot(peer_id, state.position, state.rotation, now)

func _push_snapshot(peer_id: int, position: Vector2, rotation: float, time_msec: int) -> void:
	if not _state_buffers.has(peer_id):
		_state_buffers[peer_id] = []
	var buffer: Array = _state_buffers[peer_id]
	buffer.append({"position": position, "rotation": rotation, "time": time_msec})
	while buffer.size() > SNAPSHOT_BUFFER_SIZE:
		buffer.pop_front()

# --- Интерполяция (читает VisualPlayer._process) ----------------------------

func sample_player_state(peer_id: int, render_time_msec: int) -> Dictionary:
	if not _state_buffers.has(peer_id):
		return {}
	var buffer: Array = _state_buffers[peer_id]
	if buffer.is_empty():
		return {}

	var oldest: Dictionary = buffer[0]
	if render_time_msec <= oldest.time:
		return {"position": oldest.position, "rotation": oldest.rotation}

	var newest: Dictionary = buffer[buffer.size() - 1]
	if render_time_msec >= newest.time:
		return {"position": newest.position, "rotation": newest.rotation}

	for i in range(buffer.size() - 1):
		var a: Dictionary = buffer[i]
		var b: Dictionary = buffer[i + 1]
		if a.time <= render_time_msec and render_time_msec <= b.time:
			var span := float(b.time - a.time)
			var t := 0.0
			if span > 0.0:
				t = float(render_time_msec - a.time) / span
			return {
				"position": a.position.lerp(b.position, t),
				"rotation": lerp_angle(a.rotation, b.rotation, t),
			}

	return {"position": newest.position, "rotation": newest.rotation}

# --- Ростер / спавн-деспавн визуальных игроков -------------------------------

@rpc("authority", "reliable")
func receive_player_roster(roster: Array) -> void:
	for entry in roster:
		_ensure_visual_player(entry.peer_id, entry.position, entry.rotation)

@rpc("authority", "reliable")
func spawn_visual_player(peer_id: int, position: Vector2, rotation: float) -> void:
	_ensure_visual_player(peer_id, position, rotation)

@rpc("authority", "reliable")
func despawn_visual_player(peer_id: int) -> void:
	_remove_visual_player(peer_id)

func _ensure_visual_player(peer_id: int, position: Vector2, rotation: float) -> void:
	if _visual_players.has(peer_id):
		return
	var visual: VisualPlayer = VISUAL_PLAYER_SCENE.instantiate()
	visual.peer_id = peer_id
	visual.global_position = position
	visual.rotation = rotation
	_get_visual_game_root().add_child(visual)
	_visual_players[peer_id] = visual
	_state_buffers[peer_id] = []

func _remove_visual_player(peer_id: int) -> void:
	var visual: VisualPlayer = _visual_players.get(peer_id)
	if visual:
		visual.queue_free()
	_visual_players.erase(peer_id)
	_state_buffers.erase(peer_id)

func get_local_peer_id() -> int:
	if mode == Mode.LOCAL:
		return LOCAL_PEER_ID
	if multiplayer.multiplayer_peer != null:
		return multiplayer.get_unique_id()
	return LOCAL_PEER_ID

# --- Выстрел / снежки ---------------------------------------------------------

func _apply_shoot(peer_id: int) -> void:
	await get_tree().create_timer(THROW_DELAY_SEC).timeout

	var player: Player = _server_players.get(peer_id)
	if not player:
		return

	var shot_id := _next_shot_id()
	var direction := Vector2.UP.rotated(player.rotation)
	var origin := player.global_position + direction * BULLET_SPAWN_OFFSET
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
	var shooter: VisualPlayer = _visual_players.get(shooter_peer_id)
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
		return _server_players.keys()
	return _visual_players.keys()
