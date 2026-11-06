
extends Node2D


#
# ============================================================
# PLAYER SCENES
# ============================================================
#

const PLAYER_SCENES := {
	"warlock": preload(
		"res://scenes/players/warlock.tscn"
	),

	"witch": preload(
		"res://scenes/players/witch.tscn"
	)
}


#
# ============================================================
# HUD SCENE
# ============================================================
#

const PLAYER_HUD_SCENE: PackedScene = \
	preload("res://scenes/players/player_hud.tscn")


#
# ============================================================
# NODE REFERENCES
# ============================================================
#

# Game world lives in a SubViewport so CanvasModulate / lights
# never affect HUD or future UI (CanvasLayers on Main).
@onready var world_view: SubViewportContainer = \
	$WorldView

@onready var world_viewport: SubViewport = \
	$WorldView/WorldViewport

@onready var world: Node2D = \
	$WorldView/WorldViewport/World

@onready var players_node: Node2D = \
	$WorldView/WorldViewport/World/Players


@onready var spawn_points: Array[Marker2D] = [
	$WorldView/WorldViewport/World/SpawnPoints/Spawn1,
	$WorldView/WorldViewport/World/SpawnPoints/Spawn2,
	$WorldView/WorldViewport/World/SpawnPoints/Spawn3,
	$WorldView/WorldViewport/World/SpawnPoints/Spawn4
]


#
# ============================================================
# READY
# ============================================================
#

func _ready() -> void:
	_fit_world_viewport()
	if not get_viewport().size_changed.is_connected(_fit_world_viewport):
		get_viewport().size_changed.connect(_fit_world_viewport)

	#
	# Only the dedicated server handles
	# authoritative player spawning.
	#
	if multiplayer.is_server():

		NetworkManager.all_players_loaded.connect(
			_spawn_all_players
		)

	#
	# Allow the scene tree to finish loading.
	#
	await get_tree().process_frame

	NetworkManager.report_game_loaded()


#
# ============================================================
# WORLD VIEWPORT
# ============================================================
#

func _fit_world_viewport() -> void:
	var vp_size: Vector2i = get_viewport().get_visible_rect().size
	if vp_size.x < 1 or vp_size.y < 1:
		return

	world_viewport.size = vp_size
	world_view.position = Vector2.ZERO
	world_view.size = Vector2(vp_size)


## Parent for world-space gameplay nodes (projectiles, FX, etc.).
func get_world_root() -> Node2D:
	return world


#
# ============================================================
# SPAWN ALL PLAYERS
# ============================================================
#

func _spawn_all_players() -> void:

	if not multiplayer.is_server():
		return

	var peer_ids := NetworkManager.players.keys()

	peer_ids.sort()

	var spawn_index: int = 0

	for peer_id in peer_ids:

		var player_info: Dictionary = \
			NetworkManager.players[peer_id]

		#
		# Player's lobby name.
		#
		var display_name := str(
			player_info.get(
				"name",
				"Player"
			)
		)

		#
		# Selected player class.
		#
		var selected_class := str(
			player_info.get(
				"class",
				"warlock"
			)
		)

		#
		# Spawn the player on all peers.
		#
		spawn_player.rpc(
			int(peer_id),
			display_name,
			selected_class,
			spawn_index
		)

		spawn_index += 1
		
		# Start the gameplay loop after all player
		# spawn RPCs have been issued.
		#MatchManager.start_match()


#
# ============================================================
# SPAWN PLAYER
# ============================================================
#

@rpc("authority", "call_local", "reliable")
func spawn_player(
	peer_id: int,
	display_name: String,
	selected_class: String,
	spawn_index: int
) -> void:

	#
	# Validate selected class.
	#
	if not PLAYER_SCENES.has(selected_class):

		push_error(
			"Unknown player class: %s"
			% selected_class
		)

		return

	#
	# Validate spawn location.
	#
	if spawn_index < 0 \
	or spawn_index >= spawn_points.size():

		push_error(
			"Invalid spawn point index: %s"
			% spawn_index
		)

		return

	#
	# Ensure every peer uses the same
	# player node name for RPC paths.
	#
	var network_node_name := str(peer_id)

	#
	# Prevent duplicate spawning.
	#
	if players_node.has_node(
		NodePath(network_node_name)
	):

		return

	#
	# Instantiate the selected class.
	#
	var player_scene: PackedScene = \
		PLAYER_SCENES[selected_class]

	var player: PlayerController = \
		player_scene.instantiate() as PlayerController

	if player == null:

		push_error(
			"Player scene '%s' does not inherit PlayerController."
			% selected_class
		)

		return

	#
	# Assign the network identity.
	#
	player.name = network_node_name

	#
	# Set player information BEFORE
	# adding it to the scene tree.
	#
	player.set_display_name(display_name)

	player.class_id = selected_class

	#
	# The owning client controls movement.
	# Recursive authority also applies
	# to MultiplayerSync.
	#
	player.set_multiplayer_authority(
		peer_id,
		true
	)

	#
	# Add the player to the scene.
	#
	players_node.add_child(player)

	#
	# Assign the spawn position.
	#
	player.global_position = \
		spawn_points[spawn_index].global_position

	print(
		"Spawned ",
		display_name,
		" [",
		peer_id,
		"] as ",
		selected_class
	)

	#
	# Create the HUD only on the
	# player's own client.
	#
	_create_local_player_hud(
		player,
		peer_id
	)


#
# ============================================================
# CREATE LOCAL PLAYER HUD
# ============================================================
#

func _create_local_player_hud(
	player: PlayerController,
	peer_id: int
) -> void:

	#
	# Dedicated servers do not need UI.
	#
	if multiplayer.is_server():
		return

	#
	# Only create a HUD for the
	# locally controlled player.
	#
	if peer_id != multiplayer.get_unique_id():
		return

	#
	# Prevent duplicate HUD instances.
	#
	if has_node("PlayerHUD"):
		return

	#
	# Instantiate the shared HUD.
	#
	var hud: PlayerHUD = \
		PLAYER_HUD_SCENE.instantiate() as PlayerHUD

	if hud == null:

		push_error(
			"Failed to instantiate PlayerHUD."
		)

		return

	#
	# Add HUD to Main, not BasePlayer.
	#
	hud.name = "PlayerHUD"

	add_child(hud)

	#
	# Bind the HUD to this player's state.
	# This connects health_changed
	# and initializes class-specific UI.
	#
	hud.bind_player(player)

	print(
		"Created local HUD for ",
		player.display_name,
		" (",
		player.class_id,
		")"
	)
