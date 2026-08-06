class_name ServerInfo
extends Node

# Добавляется как потомок Lobby (см. Lobby._create_server_info) — родитель и есть то лобби,
# о котором нужно отдавать информацию.

func get_lobby_name() -> String:
	return String(get_parent().name)

func get_player_ids() -> Array:
	var lobby := get_parent() as Lobby
	return lobby.get_known_player_ids()
