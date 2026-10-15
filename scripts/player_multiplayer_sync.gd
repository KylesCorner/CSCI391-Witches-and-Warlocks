class_name PlayerMultiplayerSync
extends Node


#
# ============================================================
# SETTINGS
# ============================================================
#

@export var send_rate: float = 20.0

@export var interpolation_speed: float = 15.0

@export var snap_distance: float = 150.0


#
# ============================================================
# PLAYER
# ============================================================
#

@onready var player: PlayerController = \
	get_parent() as PlayerController


#
# ============================================================
# REMOTE STATE
# ============================================================
#

var target_position: Vector2 = \
	Vector2.ZERO


var target_velocity: Vector2 = \
	Vector2.ZERO


var has_received_position: bool = false


#
# ============================================================
# SEND STATE
# ============================================================
#

var send_timer: float = 0.0


var last_state: int = -1


var last_facing_direction: int = -1


#
# ============================================================
# READY
# ============================================================
#

func _ready() -> void:

	if player == null:

		push_error(
			"PlayerMultiplayerSync must be a child of PlayerController."
		)

		set_physics_process(
			false
		)

		return


	target_position = \
		player.global_position


	last_state = \
		int(player.state)


	last_facing_direction = \
		int(player.facing_direction)


#
# ============================================================
# PHYSICS
# ============================================================
#

func _physics_process(
	delta: float
) -> void:

	if player.is_multiplayer_authority():

		_process_authority(
			delta
		)

	else:

		_process_remote_player(
			delta
		)


#
# ============================================================
# LOCAL PLAYER
# ============================================================
#

func _process_authority(
	delta: float
) -> void:

	send_timer += delta


	if send_timer >= \
			1.0 / send_rate:

		send_timer = 0.0


		sync_movement.rpc(
			player.global_position,
			player.velocity
		)


	var current_state := \
		int(player.state)


	var current_direction := \
		int(player.facing_direction)


	if current_state == last_state \
	and current_direction == \
			last_facing_direction:

		return


	last_state = \
		current_state


	last_facing_direction = \
		current_direction


	sync_state.rpc(
		current_state,
		current_direction
	)


#
# ============================================================
# REMOTE PLAYER
# ============================================================
#

func _process_remote_player(
	delta: float
) -> void:

	if not has_received_position:
		return


	var distance := \
		player.global_position.distance_to(
			target_position
		)


	#
	# If synchronization is way off,
	# snap instead of interpolating.
	#
	if distance > snap_distance:

		player.global_position = \
			target_position

		return


	player.global_position = \
		player.global_position.lerp(
			target_position,
			clamp(
				interpolation_speed * delta,
				0.0,
				1.0
			)
		)


#
# ============================================================
# MOVEMENT RPC
# ============================================================
#

@rpc(
	"authority",
	"call_remote",
	"unreliable_ordered",
	0
)
func sync_movement(
	new_position: Vector2,
	new_velocity: Vector2
) -> void:

	target_position = \
		new_position


	target_velocity = \
		new_velocity


	player.velocity = \
		new_velocity


	has_received_position = true


#
# ============================================================
# STATE RPC
# ============================================================
#

@rpc(
	"authority",
	"call_remote",
	"reliable",
	1
)
func sync_state(
	new_state: int,
	new_facing_direction: int
) -> void:

	player.apply_network_state(
		new_state,
		new_facing_direction
	)
