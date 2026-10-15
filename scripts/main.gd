extends Node2D


#
# ============================================================
# PLAYER CLASS SCENES
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
	# Server waits until every peer has
	# finished loading this scene.
	#
	if multiplayer.is_server():

		NetworkManager.all_players_loaded.connect(
			_spawn_all_players
		)


	#
	# Allow one frame for Main and all
	# children to finish entering tree.
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
			NetworkManager.players[peer_id]


		var selected_class := str(
			player_info.get(
				"class",
				"warlock"
			)
		)


		spawn_player.rpc(
			int(peer_id),
			selected_class,
			spawn_index
		)


		spawn_index += 1


#
# ============================================================
# SPAWN ONE PLAYER
# ============================================================
#

@rpc(
	"authority",
	"call_local",
	"reliable"
)
func spawn_player(
	peer_id: int,
	selected_class: String,
	spawn_index: int
) -> void:

	if not PLAYER_SCENES.has(
		selected_class
	):
		push_error(
			"Unknown class: %s"
			% selected_class
		)

		return


	if spawn_index >= \
			spawn_points.size():

		push_error(
			"Not enough spawn points"
		)

		return


	#
	# Prevent accidental duplicate spawning.
	#
	var player_name := str(peer_id)

	if players_node.has_node(
		NodePath(player_name)
	):
		return


	var player_scene: PackedScene = \
		PLAYER_SCENES[selected_class]


	var player := \
		player_scene.instantiate()


	#
	# Every peer must use the exact same
	# node name.
	#
	player.name = player_name


	#
	# This determines which computer gets
	# to control this player.
	#
	player.set_multiplayer_authority(
		peer_id,
		true
	)


	players_node.add_child(
		player
	)


	player.global_position = \
		spawn_points[
			spawn_index
		].global_position


	player.set_meta(
		"player_class",
		selected_class
	)


	print(
		"Spawned peer ",
		peer_id,
		" as ",
		selected_class
	)
