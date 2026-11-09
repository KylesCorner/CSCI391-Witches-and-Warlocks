extends Node

## Dedicated-server match recycling.
## Instantiated under /root by bootstrap.gd; survives main-scene changes.
## Never closes the ENet peer, so the same server can accept a new lobby.

var _reset_queued: bool = false


func _ready() -> void:
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	get_tree().scene_changed.connect(_on_scene_changed)


func _on_peer_disconnected(_peer_id: int) -> void:
	# NetworkManager processes the disconnection first. Wait until that
	# handler removes the peer and its player before deciding to reset.
	if _is_dedicated_server_running():
		_queue_reset_check()


func _on_scene_changed(scene: Node) -> void:
	# A slow scene load can finish AFTER the last client disconnects.
	# In that case, clear the stale gameplay scene as well.
	if scene == null or scene.scene_file_path != NetworkManager.GAME_SCENE:
		return
	if not _is_dedicated_server_running():
		return
	if NetworkManager.session_state == NetworkManager.SessionState.LOBBY \
			and NetworkManager.players.is_empty() \
			and multiplayer.get_peers().is_empty():
		_queue_reset_check()


func _queue_reset_check() -> void:
	if _reset_queued:
		return
	_reset_queued = true
	call_deferred("_reset_if_no_peers")


func _is_dedicated_server_running() -> bool:
	# is_server() alone also returns true for Godot's offline multiplayer.
	return multiplayer.is_server() \
		and multiplayer.multiplayer_peer is ENetMultiplayerPeer


func _reset_if_no_peers() -> void:
	_reset_queued = false

	if not _is_dedicated_server_running():
		return

	# A new connection might arrive while the deferred check is pending.
	# Never erase a live connection or a registered player.
	if not multiplayer.get_peers().is_empty():
		return
	if not NetworkManager.players.is_empty():
		return

	if NetworkManager.session_state == NetworkManager.SessionState.DISCONNECTED:
		return

	print("[SERVER] All clients disconnected. Resetting for the next match.")

	# Stop round timer, discard scores, tasks, health tracking, and
	# match-completion state without sending RPCs to absent clients.
	MatchManager._reset_match()

	# Clear the lobby/load handshake while preserving the *existing*
	# ENet server socket. Do not call NetworkManager._reset_session().
	NetworkManager.players.clear()
	NetworkManager.loaded_players.clear()
	NetworkManager.lobby_leader_id = 0
	NetworkManager.server_game_loaded = false
	NetworkManager.session_state = NetworkManager.SessionState.LOBBY

	# A new Main scene will be loaded normally by load_game() when the
	# next lobby starts. The autoloads and LAN discovery remain alive.
	var scene_tree: SceneTree = get_tree()
	var scene: Node = scene_tree.current_scene
	if scene != null and scene.scene_file_path == NetworkManager.GAME_SCENE:
		scene_tree.current_scene = null
		scene.queue_free()
		print("[SERVER] Old gameplay scene released.")

	print("[SERVER] Ready for a new lobby on UDP %d." % NetworkManager.PORT)
