class_name Lobby
extends Node

# Владеет конкретным полем боя: авторитетным game и/или визуальным visual_game (LevelBase),
# подключением/отключением игроков и рассылкой мирового состояния — всё, что раньше было
# частью Net, но касается только этого лобби (на сервере лобби может быть несколько).
#
# Единственный LevelBase процесса всегда называется "Game" — и на SERVER, и на CLIENT: путь
# LevelBase в дереве сцены должен быть идентичен на обеих сторонах, иначе RPC, адресуемые по
# абсолютному NodePath, не находят адресата. Имя "VisualGame" используется только для второго,
# дополнительного узла в LOCAL-режиме, где реального RPC нет и совпадение имён не требуется.

const LEVEL_SCENE := preload("res://shared/scenes/Level.tscn")

var game: LevelBase
var visual_game: LevelBase

func _ready() -> void:
	match Net.mode:
		Net.Mode.SERVER:
			_create_game()
			_create_server_info()
		Net.Mode.CLIENT:
			_create_visual_game("Game")
		Net.Mode.LOCAL:
			_create_game()
			_create_visual_game("VisualGame")
			_create_server_info()

func _create_game() -> void:
	game = LEVEL_SCENE.instantiate()
	game.name = "Game"
	add_child(game)
	game.prepare_for_server()

func _create_visual_game(node_name: String) -> void:
	visual_game = LEVEL_SCENE.instantiate()
	visual_game.name = node_name
	add_child(visual_game)

func _create_server_info() -> void:
	var info := ServerInfo.new()
	info.name = "ServerInfo"
	add_child(info)

# --- Подключение/отключение игроков -----------------------------------------

func on_peer_connected(peer_id: int) -> void:
	var calculation := game.spawn_authoritative_calculation(peer_id)
	match Net.mode:
		Net.Mode.SERVER:
			receive_player_roster.rpc_id(peer_id, game.build_roster())
			spawn_visual_player.rpc(peer_id, calculation.global_position, calculation.rotation)
		Net.Mode.LOCAL:
			visual_game.ensure_local_view(peer_id, calculation)

func on_peer_disconnected(peer_id: int) -> void:
	game.despawn_authoritative_calculation(peer_id)
	despawn_visual_player.rpc(peer_id)

# --- Мировое состояние: сервер → клиенты (только игроки этого лобби) -------

func _physics_process(_delta: float) -> void:
	if Net.mode == Net.Mode.SERVER:
		_broadcast_world_state()

func _broadcast_world_state() -> void:
	var states: Dictionary = {}
	var calculations := game.get_server_calculations()
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
	for peer_id in states.keys():
		var state: Dictionary = states[peer_id]
		var calculation: ClientCalculation = visual_game.get_client_calculation(peer_id)
		if calculation:
			calculation.receive_snapshot(state.position, state.rotation, now)

# --- Ростер / спавн-деспавн визуальных игроков -------------------------------

@rpc("authority", "reliable")
func receive_player_roster(roster: Array) -> void:
	for entry in roster:
		visual_game.ensure_client_view(entry.peer_id, entry.position, entry.rotation)

@rpc("authority", "reliable")
func spawn_visual_player(peer_id: int, position: Vector2, rotation: float) -> void:
	visual_game.ensure_client_view(peer_id, position, rotation)

@rpc("authority", "reliable")
func despawn_visual_player(peer_id: int) -> void:
	visual_game.remove_client_view(peer_id)

# --- Геттер для ServerInfo -----------------------------------------------------

func get_known_player_ids() -> Array:
	if Net.mode == Net.Mode.SERVER or Net.mode == Net.Mode.LOCAL:
		return game.get_server_calculations().keys()
	return visual_game.get_client_calculations().keys()
