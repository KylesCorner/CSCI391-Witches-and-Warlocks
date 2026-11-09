class_name PlayerMultiplayerSync
extends Node

# Keep movement synchronization client-owned. The dedicated server only
# receives and relays movement reports.
@export var send_rate: float = 20.0
@export var interpolation_speed: float = 12.0
@export var max_prediction_time: float = 0.12
@export var snap_distance: float = 300.0

@onready var player: PlayerController = get_parent() as PlayerController

var send_timer: float = 0.0
var target_position: Vector2 = Vector2.ZERO
var target_velocity: Vector2 = Vector2.ZERO
var time_since_update: float = 0.0
var has_received_position: bool = false
var last_state: int = -1
var last_facing_direction: int = -1


func _ready() -> void:
	if player == null:
		push_error("MultiplayerSync requires PlayerController.")
		set_physics_process(false)
		return
	target_position = player.global_position
	last_state = int(player.state)
	last_facing_direction = int(player.facing_direction)


# A remote RPC can be delivered while a character is being despawned or
# while the current scene is changing. On an orphaned Node, `multiplayer`
# may be null. Check node lifetime BEFORE touching that API.
func _network_ready() -> bool:
	if not is_inside_tree():
		return false
	if not is_instance_valid(player) or not player.is_inside_tree():
		return false
	return multiplayer != null


func _exit_tree() -> void:
	set_physics_process(false)


func _physics_process(delta: float) -> void:
	if not _network_ready():
		return
	if multiplayer.is_server():
		return
	if player.is_multiplayer_authority():
		_send_local_movement(delta)
	else:
		_interpolate_remote_player(delta)


func _send_local_movement(delta: float) -> void:
	if not _network_ready():
		return
	send_timer += delta
	var interval: float = 1.0 / maxf(send_rate, 1.0)
	if send_timer >= interval:
		send_timer = fmod(send_timer, interval)
		submit_movement.rpc_id(1, player.global_position, player.velocity)

	var current_state: int = int(player.state)
	var current_direction: int = int(player.facing_direction)
	if current_state != last_state or current_direction != last_facing_direction:
		last_state = current_state
		last_facing_direction = current_direction
		submit_state.rpc_id(1, current_state, current_direction)


@rpc("any_peer", "call_remote", "unreliable_ordered", 0)
func submit_movement(position: Vector2, velocity: Vector2) -> void:
	if not _network_ready() or not multiplayer.is_server():
		return
	if multiplayer.get_remote_sender_id() != player.get_multiplayer_authority():
		return
	if not position.is_finite() or not velocity.is_finite():
		return
	player.global_position = position
	player.velocity = velocity
	receive_movement.rpc(position, velocity)


@rpc("any_peer", "call_remote", "unreliable_ordered", 0)
func receive_movement(position: Vector2, velocity: Vector2) -> void:
	if not _network_ready():
		return
	if multiplayer.get_remote_sender_id() != 1:
		return
	if player.is_multiplayer_authority():
		return
	if not position.is_finite() or not velocity.is_finite():
		return
	target_position = position
	target_velocity = velocity
	time_since_update = 0.0
	has_received_position = true


func _interpolate_remote_player(delta: float) -> void:
	if not _network_ready() or not has_received_position:
		return
	time_since_update += delta
	var prediction_time: float = minf(time_since_update + 0.03, max_prediction_time)
	var predicted_position: Vector2 = target_position + target_velocity * prediction_time
	var distance: float = player.global_position.distance_to(predicted_position)
	if distance > snap_distance:
		player.global_position = predicted_position
		return
	var weight: float = 1.0 - exp(-interpolation_speed * delta)
	player.global_position = player.global_position.lerp(predicted_position, weight)


@rpc("any_peer", "call_remote", "reliable", 1)
func submit_state(new_state: int, new_direction: int) -> void:
	if not _network_ready() or not multiplayer.is_server():
		return
	if multiplayer.get_remote_sender_id() != player.get_multiplayer_authority():
		return
	player.apply_network_state(new_state, new_direction)
	receive_state.rpc(new_state, new_direction)


@rpc("any_peer", "call_remote", "reliable", 1)
func receive_state(new_state: int, new_direction: int) -> void:
	if not _network_ready():
		return
	if multiplayer.get_remote_sender_id() != 1:
		return
	if player.is_multiplayer_authority():
		return
	player.apply_network_state(new_state, new_direction)
