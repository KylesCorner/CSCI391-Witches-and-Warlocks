extends Node


#
# ============================================================
# SIGNALS
# ============================================================
#

signal lobby_updated
signal connected_to_server
signal connection_failed
signal server_disconnected
signal all_players_loaded


#
# ============================================================
# SESSION STATE
# ============================================================
#

enum SessionState {
	DISCONNECTED,
	LOBBY,
	LOADING,
	PLAYING
}


var session_state: SessionState = SessionState.DISCONNECTED


#
# ============================================================
# NETWORK SETTINGS
# ============================================================
#

const PORT: int = 7000
const MAX_PLAYERS: int = 4

const GAME_SCENE: String = \
	"res://scenes/main.tscn"


const VALID_CLASSES: Array[String] = [
	"warlock",
	"witch"
]


#
# ============================================================
# PLAYER DATA
# ============================================================
#

#
# Example:
#
# {
#     1: {
#         "name": "Kyle",
#         "class": "warlock",
#         "ready": true
#     }
# }
#
var players: Dictionary = {}


var local_player_info: Dictionary = {
	"name": "Player",
	"class": "warlock",
	"ready": false
}


#
# Tracks which peers finished loading main.tscn.
#
var loaded_players: Dictionary = {}


#
# ============================================================
# READY
# ============================================================
#

func _ready() -> void:

	multiplayer.peer_disconnected.connect(
		_on_peer_disconnected
	)

	multiplayer.connected_to_server.connect(
		_on_connected_to_server
	)

	multiplayer.connection_failed.connect(
		_on_connection_failed
	)

	multiplayer.server_disconnected.connect(
		_on_server_disconnected
	)


#
# ============================================================
# HOST
# ============================================================
#

func host_game(
	player_name_text: String
) -> Error:

	_reset_session()

	var clean_name := \
		player_name_text.strip_edges()

	if clean_name.is_empty():
		clean_name = "Host"

	local_player_info = {
		"name": clean_name,
		"class": "warlock",
		"ready": false
	}

	var peer := ENetMultiplayerPeer.new()

	var error := peer.create_server(
		PORT,
		MAX_PLAYERS
	)

	if error != OK:
		return error

	multiplayer.multiplayer_peer = peer

	#
	# Server is always peer ID 1.
	#
	players[1] = \
		local_player_info.duplicate(true)

	session_state = SessionState.LOBBY

	lobby_updated.emit()

	return OK


#
# ============================================================
# JOIN
# ============================================================
#

func join_game(
	address_text: String,
	player_name_text: String
) -> Error:

	_reset_session()

	var clean_name := \
		player_name_text.strip_edges()

	if clean_name.is_empty():
		clean_name = "Player"

	local_player_info = {
		"name": clean_name,
		"class": "warlock",
		"ready": false
	}

	var address := \
		address_text.strip_edges()

	if address.is_empty():
		address = "127.0.0.1"

	var peer := ENetMultiplayerPeer.new()

	var error := peer.create_client(
		address,
		PORT
	)

	if error != OK:
		return error

	multiplayer.multiplayer_peer = peer

	return OK


#
# ============================================================
# CONNECTION EVENTS
# ============================================================
#

func _on_connected_to_server() -> void:

	session_state = SessionState.LOBBY

	register_player.rpc_id(
		1,
		local_player_info
	)

	connected_to_server.emit()


func _on_connection_failed() -> void:

	_reset_session()

	connection_failed.emit()


func _on_server_disconnected() -> void:

	_reset_session()

	server_disconnected.emit()


func _on_peer_disconnected(
	peer_id: int
) -> void:

	if not multiplayer.is_server():
		return

	players.erase(peer_id)
	loaded_players.erase(peer_id)

	_sync_lobby()


#
# ============================================================
# REGISTER PLAYER
# ============================================================
#

@rpc(
	"any_peer",
	"call_remote",
	"reliable"
)
func register_player(
	info: Dictionary
) -> void:

	if not multiplayer.is_server():
		return

	var peer_id := \
		multiplayer.get_remote_sender_id()

	var new_player_name := str(
		info.get(
			"name",
			"Player"
		)
	)

	var selected_class := str(
		info.get(
			"class",
			"warlock"
		)
	)

	if selected_class not in VALID_CLASSES:
		selected_class = "warlock"

	players[peer_id] = {
		"name": new_player_name,
		"class": selected_class,
		"ready": false
	}

	_sync_lobby()


#
# ============================================================
# CLASS SELECTION
# ============================================================
#

func choose_class(
	selected_class: String
) -> void:

	if selected_class not in VALID_CLASSES:
		return

	local_player_info["class"] = selected_class

	if multiplayer.is_server():

		if not players.has(1):
			return

		players[1]["class"] = selected_class

		_sync_lobby()

	else:

		request_class_change.rpc_id(
			1,
			selected_class
		)


@rpc(
	"any_peer",
	"call_remote",
	"reliable"
)
func request_class_change(
	selected_class: String
) -> void:

	if not multiplayer.is_server():
		return

	if selected_class not in VALID_CLASSES:
		return

	var peer_id := \
		multiplayer.get_remote_sender_id()

	if not players.has(peer_id):
		return

	players[peer_id]["class"] = \
		selected_class

	_sync_lobby()


#
# ============================================================
# READY STATE
# ============================================================
#

func set_player_ready(
	is_ready: bool
) -> void:

	local_player_info["ready"] = is_ready

	if multiplayer.is_server():

		if not players.has(1):
			return

		players[1]["ready"] = is_ready

		_sync_lobby()

	else:

		request_ready_change.rpc_id(
			1,
			is_ready
		)


@rpc(
	"any_peer",
	"call_remote",
	"reliable"
)
func request_ready_change(
	is_ready: bool
) -> void:

	if not multiplayer.is_server():
		return

	var peer_id := \
		multiplayer.get_remote_sender_id()

	if not players.has(peer_id):
		return

	players[peer_id]["ready"] = is_ready

	_sync_lobby()


#
# ============================================================
# LOBBY SYNC
# ============================================================
#

func _sync_lobby() -> void:

	if not multiplayer.is_server():
		return

	receive_lobby_state.rpc(
		players.duplicate(true)
	)


@rpc(
	"authority",
	"call_local",
	"reliable"
)
func receive_lobby_state(
	new_players: Dictionary
) -> void:

	players = new_players.duplicate(true)

	lobby_updated.emit()


#
# ============================================================
# START GAME
# ============================================================
#

func can_start_game() -> bool:

	if not multiplayer.is_server():
		return false

	#
	# Require at least two players.
	#
	if players.size() < 2:
		return false

	for player_info in players.values():

		if not bool(
			player_info.get(
				"ready",
				false
			)
		):
			return false

	return true


func start_game() -> void:

	if not multiplayer.is_server():
		return

	if not can_start_game():
		return

	session_state = \
		SessionState.LOADING

	loaded_players.clear()

	load_game.rpc(
		GAME_SCENE
	)


@rpc(
	"authority",
	"call_local",
	"reliable"
)
func load_game(
	scene_path: String
) -> void:

	get_tree().change_scene_to_file(
		scene_path
	)


#
# ============================================================
# LOADING HANDSHAKE
# ============================================================
#

func report_game_loaded() -> void:

	var peer_id := \
		multiplayer.get_unique_id()

	if multiplayer.is_server():

		_mark_player_loaded(
			peer_id
		)

	else:

		player_loaded.rpc_id(1)


@rpc(
	"any_peer",
	"call_remote",
	"reliable"
)
func player_loaded() -> void:

	if not multiplayer.is_server():
		return

	var peer_id := \
		multiplayer.get_remote_sender_id()

	_mark_player_loaded(
		peer_id
	)


func _mark_player_loaded(
	peer_id: int
) -> void:

	loaded_players[peer_id] = true

	print(
		"Loaded peer ",
		peer_id,
		" (",
		loaded_players.size(),
		"/",
		players.size(),
		")"
	)

	if loaded_players.size() != \
			players.size():
		return

	session_state = \
		SessionState.PLAYING

	all_players_loaded.emit()


#
# ============================================================
# RESET
# ============================================================
#

func _reset_session() -> void:

	players.clear()
	loaded_players.clear()

	session_state = \
		SessionState.DISCONNECTED

	multiplayer.multiplayer_peer = \
		OfflineMultiplayerPeer.new()
