extends Node2D

const PLAYER_SCENES := {
	"warlock": preload("res://scenes/players/warlock.tscn"),
	"witch": preload("res://scenes/players/witch.tscn")
}
const PLAYER_HUD_SCENE: PackedScene = preload("res://scenes/players/player_hud.tscn")

@onready var world_view: SubViewportContainer = $WorldView
@onready var world_viewport: SubViewport = $WorldView/WorldViewport
@onready var world: Node2D = $WorldView/WorldViewport/World
@onready var players_node: Node2D = $WorldView/WorldViewport/World/Players
@onready var spawn_points: Array[Marker2D] = [
	$WorldView/WorldViewport/World/SpawnPoints/Spawn1,
	$WorldView/WorldViewport/World/SpawnPoints/Spawn2,
	$WorldView/WorldViewport/World/SpawnPoints/Spawn3,
	$WorldView/WorldViewport/World/SpawnPoints/Spawn4
]

func _ready() -> void:
	_fit_world_viewport()
	if not get_viewport().size_changed.is_connected(_fit_world_viewport):
		get_viewport().size_changed.connect(_fit_world_viewport)
	if multiplayer.is_server():
		NetworkManager.all_players_loaded.connect(_spawn_all_players)
	await get_tree().process_frame
	NetworkManager.report_game_loaded()
	
func _fit_world_viewport() -> void:
	if multiplayer.is_server():
		return

	var vp_size: Vector2i = get_viewport().get_visible_rect().size

	if vp_size.x < 1 or vp_size.y < 1:
		return

	world_view.position = Vector2.ZERO
	world_view.size = Vector2(vp_size)

func get_world_root() -> Node2D:
	return world

func _spawn_all_players() -> void:
	if not multiplayer.is_server():
		return
	var peer_ids := NetworkManager.players.keys()
	peer_ids.sort()
	var spawn_index: int = 0
	for peer_id in peer_ids:
		var player_info: Dictionary = NetworkManager.players[peer_id]
		var display_name := str(player_info.get("name", "Player"))
		var selected_class := str(player_info.get("class", "warlock"))
		spawn_player.rpc(int(peer_id), display_name, selected_class, spawn_index)
		spawn_index += 1

@rpc("authority", "call_local", "reliable")
func spawn_player(peer_id: int, display_name: String, selected_class: String, spawn_index: int) -> void:
	if not PLAYER_SCENES.has(selected_class):
		push_error("Unknown player class: %s" % selected_class)
		return
	if spawn_index < 0 or spawn_index >= spawn_points.size():
		push_error("Invalid spawn point index: %s" % spawn_index)
		return
	var network_node_name := str(peer_id)
	if players_node.has_node(NodePath(network_node_name)):
		return
	var player_scene: PackedScene = PLAYER_SCENES[selected_class]
	var player: PlayerController = player_scene.instantiate() as PlayerController
	if player == null:
		push_error("Player scene '%s' does not inherit PlayerController." % selected_class)
		return
	player.name = network_node_name
	player.set_display_name(display_name)
	player.class_id = selected_class
	player.set_multiplayer_authority(peer_id, true)
	players_node.add_child(player)
	player.global_position = spawn_points[spawn_index].global_position
	print("Spawned ", display_name, " [", peer_id, "] as ", selected_class)
	_create_local_player_hud(player, peer_id)

func _create_local_player_hud(player: PlayerController, peer_id: int) -> void:
	if multiplayer.is_server():
		return
	if peer_id != multiplayer.get_unique_id():
		return
	if has_node("PlayerHUD"):
		return
	var hud: PlayerHUD = PLAYER_HUD_SCENE.instantiate() as PlayerHUD
	if hud == null:
		push_error("Failed to instantiate PlayerHUD.")
		return
	hud.name = "PlayerHUD"
	add_child(hud)
	hud.bind_player(player)
	print("Created local HUD for ", player.display_name, " (", player.class_id, ")")
