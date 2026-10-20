extends Node2D


#
# ============================================================
# PLAYER SCENES
# ============================================================
#

const PLAYER_SCENES := {
	"warlock":
		preload(
			"res://scenes/players/warlock.tscn"
		),

	"witch":
		preload(
			"res://scenes/players/witch.tscn"
		)
}


#
# ============================================================
# NODES
# ============================================================
#

@onready var players_node: Node2D = \
	$Players


@onready var spawn_points: Array[Marker2D] = [
	$SpawnPoints/Spawn1,
	$SpawnPoints/Spawn2,
	$SpawnPoints/Spawn3,
	$SpawnPoints/Spawn4
]


#
# ============================================================
# READY
# ============================================================
#

func _ready() -> void:

	#
	# Only the dedicated server performs
	# the authoritative player spawning.
	#
	if multiplayer.is_server():

		NetworkManager.all_players_loaded.connect(
			_spawn_all_players
		)


	#
	# Give the scene one frame to finish
	# entering the scene tree.
	#
	await get_tree().process_frame


	NetworkManager.report_game_loaded()


#
# ============================================================
# SPAWN ALL PLAYERS
# ============================================================
#

func _spawn_all_players() -> void:

	if not multiplayer.is_server():
		return


	var peer_ids := \
		NetworkManager.players.keys()


	peer_ids.sort()


	var spawn_index: int = 0


	for peer_id in peer_ids:

		var player_info: Dictionary = \
			NetworkManager.players[
				peer_id
			]


		#
		# Player name entered in lobby.
		#
		var display_name := str(
			player_info.get(
				"name",
				"Player"
			)
		)


		#
		# Selected class.
		#
		var selected_class := str(
			player_info.get(
				"class",
				"warlock"
			)
		)


		spawn_player.rpc(
			int(peer_id),
			display_name,
			selected_class,
			spawn_index
		)


		spawn_index += 1


#
# ============================================================
# SPAWN PLAYER
# ============================================================
#

@rpc(
	"authority",
	"call_local",
	"reliable"
)
func spawn_player(
	peer_id: int,
	display_name: String,
	selected_class: String,
	spawn_index: int
) -> void:

	#
	# Validate class.
	#
	if not PLAYER_SCENES.has(
		selected_class
	):

		push_error(
			"Unknown player class: %s"
			% selected_class
		)

		return


	#
	# Validate spawn point.
	#
	if spawn_index < 0 \
	or spawn_index >= \
			spawn_points.size():

		push_error(
			"Invalid spawn point index: %s"
			% spawn_index
		)

		return


	var network_node_name := \
		str(peer_id)


	#
	# Prevent accidental duplicate spawning.
	#
	if players_node.has_node(
		NodePath(
			network_node_name
		)
	):

		return


	var player_scene: PackedScene = \
		PLAYER_SCENES[
			selected_class
		]


	var player: PlayerController = \
		player_scene.instantiate() \
		as PlayerController


	if player == null:

		push_error(
			"Player scene '%s' does not inherit PlayerController."
			% selected_class
		)

		return


	#
	# Every peer must use the same node name
	# so RPC paths match.
	#
	player.name = \
		network_node_name


	#
	# Give the player its lobby name.
	#
	# This happens before add_child(), so
	# _ready() sees the correct value.
	#
	player.set_display_name(
		display_name
	)


	#
	# Give this player's client authority
	# over its player node.
	#
	# recursive = true also gives authority
	# to MultiplayerSync.
	#
	player.set_multiplayer_authority(
		peer_id,
		true
	)


	#
	# Add player to scene.
	#
	players_node.add_child(
		player
	)


	#
	# Move to assigned spawn point.
	#
	player.global_position = \
		spawn_points[
			spawn_index
		].global_position


	print(
		"Spawned ",
		display_name,
		" [",
		peer_id,
		"] as ",
		selected_class
	)
