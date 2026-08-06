extends Node

# --- Constants ---------------------------------------------------------

const DEFAULT_PORT := 4433
const MAX_CLIENTS := 16
const LOCAL_PEER_ID := 1

# --- State ---------------------------------------------------------------

enum Mode { NONE, SERVER, CLIENT, LOCAL }
var mode: Mode = Mode.NONE

# --- Сигналы: тонкая обёртка над MultiplayerAPI (и её LOCAL-эквивалент) -----
# Слушает Host — сам Net ничего не знает о Host/Lobby/игровой логике.

signal peer_connected(peer_id: int)
signal peer_disconnected(peer_id: int)
signal connected_to_server()
signal connection_failed()
signal server_disconnected()

# --- Public API запуска (вызывается из Launcher) --------------------------

func start_server(port: int) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port, MAX_CLIENTS)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	mode = Mode.SERVER
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	return OK

func start_client(host: String, port: int) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(host, port)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	mode = Mode.CLIENT
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	return OK

func start_local() -> void:
	mode = Mode.LOCAL
	peer_connected.emit(LOCAL_PEER_ID)

func shutdown() -> void:
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null
	mode = Mode.NONE

# --- Переизлучение сигналов MultiplayerAPI ----------------------------------

func _on_peer_connected(peer_id: int) -> void:
	peer_connected.emit(peer_id)

func _on_peer_disconnected(peer_id: int) -> void:
	peer_disconnected.emit(peer_id)

func _on_connected_to_server() -> void:
	connected_to_server.emit()

func _on_connection_failed() -> void:
	push_error("Net: connection to server failed")
	connection_failed.emit()

func _on_server_disconnected() -> void:
	push_error("Net: server disconnected")
	server_disconnected.emit()

func get_local_peer_id() -> int:
	if mode == Mode.LOCAL:
		return LOCAL_PEER_ID
	if multiplayer.multiplayer_peer != null:
		return multiplayer.get_unique_id()
	return LOCAL_PEER_ID
