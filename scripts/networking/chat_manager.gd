extends Node
## Server-authoritative text chat for the existing dedicated ENet server.
## Team identity comes from NetworkManager.players[peer_id]["class"].

signal message_received(channel: int, sender_name: String, sender_team: String, message: String)
signal history_cleared

const GLOBAL: int = 0
const TEAM: int = 1
const MAX_MESSAGE_LENGTH: int = 200
const MAX_HISTORY: int = 80
const MIN_SEND_INTERVAL_MS: int = 400

var is_typing: bool = false
var history: Array[Dictionary] = []
var _last_sent_ms: Dictionary = {}


func _ready() -> void:
	NetworkManager.connected_to_server.connect(clear_history)
	NetworkManager.server_disconnected.connect(clear_history)
	NetworkManager.connection_failed.connect(clear_history)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)


func clear_history() -> void:
	set_typing(false)
	history.clear()
	_last_sent_ms.clear()
	history_cleared.emit()


# Keep all gameplay input disabled while the local chat field is focused.
# This avoids replacing the project's existing player and ability scripts.
func set_typing(active: bool) -> void:
	is_typing = active
	if multiplayer.is_server():
		return
	var scene: Node = get_tree().current_scene
	if scene == null:
		return
	var players_node: Node = scene.get_node_or_null("WorldView/WorldViewport/World/Players")
	if players_node == null:
		return
	var player: PlayerController = players_node.get_node_or_null(NodePath(str(multiplayer.get_unique_id()))) as PlayerController
	if player == null:
		return
	if active:
		player.velocity = Vector2.ZERO
		if player.state == PlayerController.PlayerState.WALKING:
			player.change_state(PlayerController.PlayerState.IDLE)
	player.set_physics_process(not active)
	var ability_controller: Node = player.get_node_or_null("AbilityController")
	if ability_controller != null:
		ability_controller.set_process(not active)


func send_message(channel: int, message: String) -> void:
	# Clients submit to peer 1, never directly to other clients.
	if multiplayer.is_server():
		return
	if NetworkManager.session_state != NetworkManager.SessionState.PLAYING:
		return
	if channel != GLOBAL and channel != TEAM:
		return
	var cleaned: String = _sanitize(message)
	if cleaned.is_empty():
		return
	request_message.rpc_id(1, channel, cleaned)


@rpc("any_peer", "call_remote", "reliable")
func request_message(channel: int, message: String) -> void:
	if not multiplayer.is_server():
		return

	var sender_id: int = multiplayer.get_remote_sender_id()
	if sender_id == 1 or not NetworkManager.players.has(sender_id):
		return
	if NetworkManager.session_state != NetworkManager.SessionState.PLAYING:
		return
	if channel != GLOBAL and channel != TEAM:
		return

	var cleaned: String = _sanitize(message)
	if cleaned.is_empty():
		return

	# A modest server-side throttle prevents message floods.
	var now_ms: int = Time.get_ticks_msec()
	var previous_ms: int = int(_last_sent_ms.get(sender_id, -MIN_SEND_INTERVAL_MS))
	if now_ms - previous_ms < MIN_SEND_INTERVAL_MS:
		return
	_last_sent_ms[sender_id] = now_ms

	var sender: Dictionary = NetworkManager.players[sender_id]
	var sender_team: String = str(sender.get("class", ""))
	var sender_name: String = _sanitize(str(sender.get("name", "Player"))).substr(0, 28)

	# Select recipients ON THE SERVER. Enemy clients never receive team text.
	for peer_id_variant in NetworkManager.players.keys():
		var peer_id: int = int(peer_id_variant)
		if channel == TEAM:
			var recipient: Dictionary = NetworkManager.players[peer_id]
			if str(recipient.get("class", "")) != sender_team:
				continue
		receive_message.rpc_id(peer_id, channel, sender_name, sender_team, cleaned)


@rpc("authority", "call_remote", "reliable")
func receive_message(channel: int, sender_name: String, sender_team: String, message: String) -> void:
	# Only the dedicated server is permitted to deliver chat to a client.
	if multiplayer.is_server() or multiplayer.get_remote_sender_id() != 1:
		return
	if channel != GLOBAL and channel != TEAM:
		return
	var cleaned: String = _sanitize(message)
	if cleaned.is_empty():
		return

	var entry: Dictionary = {
		"channel": channel,
		"sender_name": sender_name.substr(0, 28),
		"sender_team": sender_team,
		"message": cleaned
	}
	history.append(entry)
	if history.size() > MAX_HISTORY:
		history.pop_front()
	message_received.emit(channel, entry["sender_name"], sender_team, cleaned)


func _sanitize(raw: String) -> String:
	var clean: String = raw.replace("\n", " ").replace("\r", " ").replace("\t", " ").strip_edges()
	return clean.substr(0, MAX_MESSAGE_LENGTH)


func _on_peer_disconnected(peer_id: int) -> void:
	if multiplayer.is_server():
		_last_sent_ms.erase(peer_id)
