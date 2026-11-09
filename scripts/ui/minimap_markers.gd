class_name MinimapMarkers
extends Node2D
## Draws only the local player and teammates; never reveals enemy invisibility.

const SELF_COLOR: Color = Color(0.99, 0.96, 0.58)
const ALLY_COLOR: Color = Color(0.45, 0.91, 1.0)

var _local_player: PlayerController
var _players_node: Node2D
var _camera: Camera2D
var _elapsed: float = 0.0


func _ready() -> void:
	set_process(false)


func configure(local_player: PlayerController, players_node: Node2D, minimap_camera: Camera2D) -> void:
	_local_player = local_player
	_players_node = players_node
	_camera = minimap_camera
	set_process(true)
	queue_redraw()


func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed < 0.10:
		return
	_elapsed = 0.0
	queue_redraw()


func _draw() -> void:
	if not is_instance_valid(_local_player) or not is_instance_valid(_players_node) or not is_instance_valid(_camera):
		return
	var zoom: float = maxf(_camera.zoom.x, 0.008)
	var dot_radius: float = 4.0 / zoom
	for child in _players_node.get_children():
		var candidate: PlayerController = child as PlayerController
		if candidate == null or candidate.current_health <= 0:
			continue
		if candidate.class_id != _local_player.class_id:
			continue
		var is_self: bool = candidate == _local_player
		var radius: float = dot_radius * (1.3 if is_self else 1.0)
		var fill_color: Color = SELF_COLOR if is_self else ALLY_COLOR
		draw_circle(candidate.global_position, radius * 1.4, Color(0.02, 0.02, 0.05, 0.95))
		draw_circle(candidate.global_position, radius, fill_color)
