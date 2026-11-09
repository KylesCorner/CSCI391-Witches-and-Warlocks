extends Node


const LOBBY_SCENE: String = \
	"res://scenes/lobby.tscn"

# One LAN discovery node survives scene changes. It never touches ENet gameplay.
const LAN_DISCOVERY_SCRIPT: Script = preload(
	"res://scripts/networking/lan_discovery.gd"
)

# Server-only watcher persists after bootstrap.tscn is replaced by the game.
const SERVER_AUTO_RESET_SCRIPT: Script = preload(
	"res://scripts/networking/server_auto_reset.gd"
)


func _ready() -> void:

	print("======================================")
	print("BOOTSTRAP STARTED")
	print("Dedicated feature: ",
		OS.has_feature("dedicated_server")
	)
	print("User args: ",
		OS.get_cmdline_user_args()
	)
	print("======================================")

	var args := \
		OS.get_cmdline_user_args()

	var is_dedicated := \
		OS.has_feature(
			"dedicated_server"
		) \
		or "--dedicated" in args

	if is_dedicated:

		print("DEDICATED SERVER MODE DETECTED")

		var error := \
			NetworkManager.start_dedicated_server()

		if error != OK:

			push_error(
				"Dedicated server failed: %s"
				% error
			)

			get_tree().quit(1)
			return

		# The root is still initializing in _ready(). Defer attachment;
		# otherwise add_child() can fail and leave discovery orphaned.
		call_deferred("_install_lan_discovery", true)
		call_deferred("_install_server_auto_reset")

		print(
			"Dedicated server startup successful."
		)
		return

	print("CLIENT MODE DETECTED")

	# Install discovery first, then load lobby: deferred calls are FIFO.
	# The /root/LanDiscovery node survives scene changes and will
	# re-inject the browser when the player returns to the lobby.
	call_deferred("_install_lan_discovery", false)

	call_deferred(
		"_load_lobby"
	)


func _load_lobby() -> void:

	var error := \
		get_tree().change_scene_to_file(
			LOBBY_SCENE
		)

	if error != OK:

		push_error(
			"Could not load lobby: %s"
			% error
		)


func _install_lan_discovery(server_mode: bool) -> void:
	# This is deliberately called deferred from _ready(). A synchronous
	# root.add_child() can fail while the root is busy initializing a scene.
	var scene_tree: SceneTree = get_tree()
	if scene_tree == null:
		push_error("LAN discovery bootstrap is no longer in the scene tree.")
		return

	var root: Window = scene_tree.root
	if root.has_node("LanDiscovery"):
		return

	var discovery: Node = LAN_DISCOVERY_SCRIPT.new()
	discovery.name = "LanDiscovery"
	root.add_child(discovery)

	if not discovery.is_inside_tree():
		push_error("LAN discovery could not attach to the scene tree.")
		discovery.free()
		return

	if server_mode:
		discovery.call("start_server")
	else:
		discovery.call("start_client")


func _install_server_auto_reset() -> void:
	# /root survives scene changes; bootstrap.tscn itself does not.
	var scene_tree: SceneTree = get_tree()
	if scene_tree == null:
		push_error("Server reset watcher could not access SceneTree.")
		return
	var root: Window = scene_tree.root
	if root.has_node("ServerAutoReset"):
		return
	var watcher: Node = SERVER_AUTO_RESET_SCRIPT.new()
	watcher.name = "ServerAutoReset"
	root.add_child(watcher)
	if not watcher.is_inside_tree():
		push_error("Server auto-reset watcher failed to attach.")
		watcher.free()
		return
	print("[SERVER] Automatic reset watcher installed.")
