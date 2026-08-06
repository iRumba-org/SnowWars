class_name Host
extends Node

# Единственная точка, которая знает и о Net (режим/сигналы подключения), и об игровой
# иерархии (LobbyList/Lobby). Net о Host ничего не знает — зависимость только в одну сторону.

const LOBBY_NAME := "Лобби_1"  # имя единственного (пока) лобби; часть NodePath для RPC —
                                # должно совпадать один-в-один на SERVER и CLIENT.

var _lobby_list: LobbyList

func _ready() -> void:
	Net.peer_connected.connect(_on_peer_connected)
	Net.peer_disconnected.connect(_on_peer_disconnected)
	Net.connected_to_server.connect(_on_connected_to_server)
	Net.connection_failed.connect(_on_connection_failed)
	Net.server_disconnected.connect(_on_server_disconnected)

	_lobby_list = LobbyList.new()
	_lobby_list.name = "LobbyList"
	add_child(_lobby_list)

	match Net.mode:
		Net.Mode.SERVER:
			_ensure_lobby()
		Net.Mode.LOCAL:
			# start_local() эмитит peer_connected(LOCAL_PEER_ID) до того, как Launcher успевает
			# создать Host и подписаться на сигнал — обрабатываем локальное подключение здесь
			# напрямую, а не полагаясь на уже прошедший сигнал.
			_on_peer_connected(Net.LOCAL_PEER_ID)

func _on_peer_connected(peer_id: int) -> void:
	_ensure_lobby().on_peer_connected(peer_id)

func _on_peer_disconnected(peer_id: int) -> void:
	var lobby: Lobby = _lobby_list.get_node_or_null(LOBBY_NAME)
	if lobby:
		lobby.on_peer_disconnected(peer_id)

func _on_connected_to_server() -> void:
	_ensure_lobby()

func _on_connection_failed() -> void:
	pass

func _on_server_disconnected() -> void:
	pass

func _ensure_lobby() -> Lobby:
	var lobby: Lobby = _lobby_list.get_node_or_null(LOBBY_NAME)
	if lobby == null:
		lobby = Lobby.new()
		lobby.name = LOBBY_NAME
		_lobby_list.add_child(lobby)
	return lobby
