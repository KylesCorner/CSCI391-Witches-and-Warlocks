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


var session_state: SessionState = \
	SessionState.DISCONNECTED


#
# ============================================================
# SETTINGS
# ============================================================
#

const PORT: int = 7000

const MAX_PLAYERS: int = 4

#
# Keep at 1 while developing.
#
# Change to 4 if you eventually want to
# require a full lobby.
#
const MIN_PLAYERS_TO_START: int = 1


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
# Peer 1 is the dedicated server and is
# NEVER stored here.
#
#
# Example:
#
# {
#     12345: {
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
# First player into the lobby gets the
# Start button.
#
var lobby_leader_id: int = 0


#
# ============================================================
# GAME LOADING
# ============================================================
#

var loaded_players: Dictionary = {}

var server_game_loaded: bool = false


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
# DEDICATED SERVER
# ============================================================
#

func start_dedicated_server() -> Error:

	_reset_session()


	var peer := \
		ENetMultiplayerPeer.new()


	#
	# Dedicated server is not one of the
	# players, so all four connection slots
	# belong to clients.
	#
	var error := peer.create_server(
		PORT,
		MAX_PLAYERS
	)


	if error != OK:

		return error


	multiplayer.multiplayer_peer = peer


	session_state = \
		SessionState.LOBBY


	print(
		"======================================"
	)

	print(
		"Witches and Warlocks Dedicated Server"
	)

	print(
		"Port: ",
		PORT
	)

	print(
		"Player slots: ",
		MAX_PLAYERS
	)

	print(
		"======================================"
	)


	return OK


#
# ============================================================
# CLIENT JOIN
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


	var peer := \
		ENetMultiplayerPeer.new()


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

	session_state = \
		SessionState.LOBBY


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


	print(
		"Player disconnected: ",
		peer_id
	)


	players.erase(
		peer_id
	)


	loaded_players.erase(
		peer_id
	)


	if peer_id == lobby_leader_id:

		_assign_new_lobby_leader()


	_sync_lobby()


	if session_state == \
			SessionState.LOADING:

		_check_all_game_loaded()


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


	if peer_id == 1:
		return


	#
	# Reject registration beyond our
	# configured capacity.
	#
	if players.size() >= MAX_PLAYERS:
		return


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


	#
	# First player becomes lobby leader.
	#
	if lobby_leader_id == 0:

		lobby_leader_id = \
			peer_id


	print(
		"Player joined: ",
		new_player_name,
		" [",
		peer_id,
		"]"
	)


	_sync_lobby()


#
# ============================================================
# LOBBY LEADER
# ============================================================
#

func _assign_new_lobby_leader() -> void:

	lobby_leader_id = 0


	if players.is_empty():
		return


	var peer_ids := \
		players.keys()


	peer_ids.sort()


	lobby_leader_id = \
		int(peer_ids[0])


	print(
		"New lobby leader: ",
		lobby_leader_id
	)


func is_local_lobby_leader() -> bool:

	if multiplayer.is_server():
		return false


	if lobby_leader_id == 0:
		return false


	return \
		multiplayer.get_unique_id() \
		== lobby_leader_id


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


	if multiplayer.is_server():
		return


	local_player_info["class"] = \
		selected_class


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


	if not players.has(
		peer_id
	):
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

	if multiplayer.is_server():
		return


	local_player_info["ready"] = \
		is_ready


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


	if not players.has(
		peer_id
	):
		return


	players[peer_id]["ready"] = \
		is_ready


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
		players.duplicate(true),
		lobby_leader_id
	)


@rpc(
	"authority",
	"call_local",
	"reliable"
)
func receive_lobby_state(
	new_players: Dictionary,
	new_lobby_leader_id: int
) -> void:

	players = \
		new_players.duplicate(true)


	lobby_leader_id = \
		new_lobby_leader_id


	lobby_updated.emit()


#
# ============================================================
# CAN START?
# ============================================================
#

func can_start_game() -> bool:

	if players.size() < \
			MIN_PLAYERS_TO_START:

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


#
# ============================================================
# START REQUEST
# ============================================================
#

func request_start_game() -> void:

	if multiplayer.is_server():
		return


	if not is_local_lobby_leader():
		return


	request_start_game_server.rpc_id(
		1
	)


@rpc(
	"any_peer",
	"call_remote",
	"reliable"
)
func request_start_game_server() -> void:

	if not multiplayer.is_server():
		return


	var sender_id := \
		multiplayer.get_remote_sender_id()


	if sender_id != lobby_leader_id:

		print(
			"Rejected start request from ",
			sender_id
		)

		return


	if not can_start_game():

		print(
			"Cannot start game yet."
		)

		return


	_start_game()


#
# ============================================================
# START GAME
# ============================================================
#

func _start_game() -> void:

	if not multiplayer.is_server():
		return


	session_state = \
		SessionState.LOADING


	loaded_players.clear()

	server_game_loaded = false


	print(
		"Starting game with ",
		players.size(),
		" player(s)."
	)


	load_game.rpc(
		GAME_SCENE
	)


#
# ============================================================
# LOAD GAME SCENE
# ============================================================
#

@rpc(
	"authority",
	"call_local",
	"reliable"
)
func load_game(
	scene_path: String
) -> void:

	session_state = \
		SessionState.LOADING


	get_tree().change_scene_to_file(
		scene_path
	)


#
# ============================================================
# LOADING HANDSHAKE
# ============================================================
#

func report_game_loaded() -> void:

	#
	# Dedicated server.
	#
	if multiplayer.is_server():

		server_game_loaded = true


		print(
			"Server loaded main scene."
		)


		_check_all_game_loaded()

		return


	#
	# Client.
	#
	player_loaded.rpc_id(
		1
	)


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


	if not players.has(
		peer_id
	):
		return


	loaded_players[peer_id] = true


	print(
		"Player loaded: ",
		peer_id,
		" (",
		loaded_players.size(),
		"/",
		players.size(),
		")"
	)


	_check_all_game_loaded()


func _check_all_game_loaded() -> void:

	if not multiplayer.is_server():
		return


	if not server_game_loaded:
		return


	if loaded_players.size() != \
			players.size():

		return


	print(
		"Everyone loaded."
	)


	set_playing.rpc()


	all_players_loaded.emit()


#
# ============================================================
# PLAYING
# ============================================================
#

@rpc(
	"authority",
	"call_local",
	"reliable"
)
func set_playing() -> void:

	session_state = \
		SessionState.PLAYING


#
# ============================================================
# RESET
# ============================================================
#

func _reset_session() -> void:

	players.clear()

	loaded_players.clear()


	lobby_leader_id = 0

	server_game_loaded = false


	session_state = \
		SessionState.DISCONNECTED


	multiplayer.multiplayer_peer = \
		OfflineMultiplayerPeer.new()
