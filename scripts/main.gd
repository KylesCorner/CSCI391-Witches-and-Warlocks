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

# Client-only transition announcement, drawn above the PlayerHUD and scoreboard.
var _banner_layer: CanvasLayer
var _banner_panel: PanelContainer
var _banner_style: StyleBoxFlat
var _banner_text: Label
var _banner_tween: Tween


func _ready() -> void:
	# SubViewportContainer.stretch already sizes WorldViewport.
	# Do not manually resize the viewport during window drag.
	# This avoids redundant viewport work and leaves the world visible.
	_fit_world_viewport()
	if not get_viewport().size_changed.is_connected(_fit_world_viewport):
		get_viewport().size_changed.connect(_fit_world_viewport)

	if multiplayer.is_server():
		NetworkManager.all_players_loaded.connect(_spawn_all_players)
	else:
		_build_phase_banner()
		MatchManager.phase_changed.connect(_on_phase_changed)

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


# ============================================================
# PREPARE / FIGHT ANNOUNCEMENT (CLIENT ONLY)
# ============================================================

func _build_phase_banner() -> void:
	_banner_layer = CanvasLayer.new()
	_banner_layer.name = "PhaseBanner"
	_banner_layer.layer = 12  # Above PlayerHUD (5) and match scoreboard (8).
	add_child(_banner_layer)

	var center := CenterContainer.new()
	center.name = "BannerCenter"
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_banner_layer.add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_banner_panel = PanelContainer.new()
	_banner_panel.name = "BannerPanel"
	_banner_panel.custom_minimum_size = Vector2(470, 130)
	_banner_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(_banner_panel)

	_banner_style = StyleBoxFlat.new()
	_banner_style.bg_color = Color(0.10, 0.07, 0.17, 0.94)
	_banner_style.border_color = Color(0.65, 0.52, 0.95, 1.0)
	_banner_style.set_border_width_all(3)
	_banner_style.set_corner_radius_all(14)
	_banner_style.set_content_margin_all(16.0)
	_banner_panel.add_theme_stylebox_override("panel", _banner_style)

	_banner_text = Label.new()
	_banner_text.name = "BannerText"
	_banner_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner_text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_banner_text.add_theme_font_size_override("font_size", 65)
	_banner_text.add_theme_color_override("font_color", Color(0.90, 0.78, 1.0))
	_banner_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_banner_panel.add_child(_banner_text)

	_banner_layer.visible = false


func _on_phase_changed(next_phase: int, _round_number: int) -> void:
	match next_phase:
		MatchManager.Phase.PREPARE:
			_show_phase_banner(
				"PREPARE!",
				Color(0.89, 0.77, 1.0),
				Color(0.57, 0.40, 0.86, 1.0)
			)
		MatchManager.Phase.FIGHT:
			_show_phase_banner(
				"FIGHT!",
				Color(1.0, 0.73, 0.39),
				Color(0.93, 0.43, 0.19, 1.0)
			)
		_:
			_stop_phase_banner()


func _show_phase_banner(message: String, text_color: Color, border_color: Color) -> void:
	# A rapid phase transition must interrupt the previous animation cleanly.
	if _banner_tween != null and _banner_tween.is_valid():
		_banner_tween.kill()

	_banner_text.text = message
	_banner_text.add_theme_color_override("font_color", text_color)
	_banner_style.border_color = border_color
	_banner_panel.modulate.a = 0.0
	_banner_layer.visible = true

	_banner_tween = create_tween()
	_banner_tween.tween_property(_banner_panel, "modulate:a", 1.0, 0.35).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_banner_tween.tween_interval(1.1)
	_banner_tween.tween_property(_banner_panel, "modulate:a", 0.0, 0.65).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	_banner_tween.tween_callback(_hide_phase_banner)


func _hide_phase_banner() -> void:
	if _banner_layer != null:
		_banner_layer.visible = false


func _stop_phase_banner() -> void:
	if _banner_tween != null and _banner_tween.is_valid():
		_banner_tween.kill()
	_hide_phase_banner()
