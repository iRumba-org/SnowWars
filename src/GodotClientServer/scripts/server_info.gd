class_name ServerInfo
extends Node

func get_lobby_name() -> String:
	return Net.LOBBY_NAME

func get_player_ids() -> Array:
	return Net.get_known_player_ids()
