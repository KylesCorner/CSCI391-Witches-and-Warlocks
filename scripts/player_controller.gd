class_name PlayerController
extends CharacterBody2D


#
# ============================================================
# SIGNALS
# ============================================================
#

signal interact_requested
signal state_changed(new_state: PlayerState)


#
# ============================================================
# SETTINGS
# ============================================================
#

@export var speed: float = 100.0


#
# ============================================================
# NODE REFERENCES
# ============================================================
#

@onready var animated_sprite: AnimatedSprite2D = \
	$AnimatedSprite2D

@onready var interaction_area: Area2D = \
	$InteractionArea

@onready var camera: Camera2D = \
	$Camera2D

#
# ============================================================
# DIRECTION
# ============================================================
#

enum Direction {
	FRONT,
	BACK,
	LEFT,
	RIGHT
}


var facing_direction: Direction = \
	Direction.FRONT


#
# ============================================================
# PLAYER STATE
# ============================================================
#

enum PlayerState {
	IDLE,
	WALKING,
	ATTACKING,
	HURT,
	DEAD
}


var state: PlayerState = \
	PlayerState.IDLE


#
# ============================================================
# READY
# ============================================================
#


func _ready() -> void:

	if animated_sprite.sprite_frames == null:

		push_error(
			"AnimatedSprite2D has no SpriteFrames resource!"
		)

		return


	#
	# ========================================================
	# LOCAL CAMERA
	# ========================================================
	#

	if is_multiplayer_authority():

		camera.enabled = true
		camera.make_current()

	else:

		camera.enabled = false


	_update_current_animation()

#
# ============================================================
# PHYSICS
# ============================================================
#

func _physics_process(
	_delta: float
) -> void:

	#
	# Only the computer that owns this
	# player processes keyboard input.
	#
	if not is_multiplayer_authority():
		return


	match state:

		PlayerState.IDLE, \
		PlayerState.WALKING:

			_process_movement()


		PlayerState.ATTACKING:

			_process_attacking()


		PlayerState.HURT:

			_process_hurt()


		PlayerState.DEAD:

			_process_dead()


	#
	# E = interact
	#
	if Input.is_action_just_pressed(
		"interact"
	):

		interact()


#
# ============================================================
# MOVEMENT
# ============================================================
#

func _process_movement() -> void:

	var input_direction := Input.get_vector(
		"move_left",
		"move_right",
		"move_up",
		"move_down"
	)


	velocity = \
		input_direction * speed


	move_and_slide()


	if input_direction == Vector2.ZERO:

		change_state(
			PlayerState.IDLE
		)

		return


	update_facing_direction(
		input_direction
	)


	change_state(
		PlayerState.WALKING
	)


#
# ============================================================
# ATTACKING
# ============================================================
#

func _process_attacking() -> void:

	velocity = Vector2.ZERO


#
# ============================================================
# HURT
# ============================================================
#

func _process_hurt() -> void:

	velocity = Vector2.ZERO


#
# ============================================================
# DEAD
# ============================================================
#

func _process_dead() -> void:

	velocity = Vector2.ZERO


#
# ============================================================
# STATE MACHINE
# ============================================================
#

func change_state(
	new_state: PlayerState
) -> void:

	if state == new_state:
		return


	state = new_state


	_update_current_animation()


	state_changed.emit(
		state
	)


#
# ============================================================
# NETWORK STATE APPLICATION
# ============================================================
#

#
# Called by PlayerMultiplayerSync on
# remote copies of this player.
#
func apply_network_state(
	new_state: int,
	new_facing_direction: int
) -> void:

	state = new_state

	facing_direction = \
		new_facing_direction


	_update_current_animation()


#
# ============================================================
# FACING DIRECTION
# ============================================================
#

func update_facing_direction(
	direction: Vector2
) -> void:

	var old_direction := \
		facing_direction


	if abs(direction.x) > \
			abs(direction.y):

		if direction.x > 0.0:

			facing_direction = \
				Direction.RIGHT

		else:

			facing_direction = \
				Direction.LEFT

	else:

		if direction.y > 0.0:

			facing_direction = \
				Direction.FRONT

		else:

			facing_direction = \
				Direction.BACK


	#
	# Direction changed while still in
	# the same state, so update animation.
	#
	if old_direction != facing_direction:

		_update_current_animation()


#
# ============================================================
# ANIMATION STATE
# ============================================================
#

func _update_current_animation() -> void:

	match state:

		PlayerState.IDLE:

			play_idle_animation()


		PlayerState.WALKING:

			play_walk_animation()


		PlayerState.ATTACKING:

			play_state_animation(
				"Attack"
			)


		PlayerState.HURT:

			play_state_animation(
				"Hurt"
			)


		PlayerState.DEAD:

			play_state_animation(
				"Dead"
			)


#
# ============================================================
# WALK ANIMATION
# ============================================================
#

func play_walk_animation() -> void:

	match facing_direction:

		Direction.FRONT:
			change_animation(
				"Walk Front"
			)

		Direction.BACK:
			change_animation(
				"Walk Back"
			)

		Direction.LEFT:
			change_animation(
				"Walk Left"
			)

		Direction.RIGHT:
			change_animation(
				"Walk Right"
			)


#
# ============================================================
# IDLE ANIMATION
# ============================================================
#

func play_idle_animation() -> void:

	match facing_direction:

		Direction.FRONT:
			change_animation(
				"Idle Front"
			)

		Direction.BACK:
			change_animation(
				"Idle Back"
			)

		Direction.LEFT:
			change_animation(
				"Idle Left"
			)

		Direction.RIGHT:
			change_animation(
				"Idle Right"
			)


#
# ============================================================
# GENERIC STATE ANIMATION
# ============================================================
#

func play_state_animation(
	animation_prefix: String
) -> void:

	var animation_name := \
		"%s %s" % [
			animation_prefix,
			get_direction_name()
		]


	if animated_sprite.sprite_frames.has_animation(
		animation_name
	):

		change_animation(
			animation_name
		)

	else:

		#
		# Attack / Hurt / Dead animations
		# don't have to exist yet.
		#
		play_idle_animation()


#
# ============================================================
# DIRECTION STRING
# ============================================================
#

func get_direction_name() -> String:

	match facing_direction:

		Direction.FRONT:
			return "Front"

		Direction.BACK:
			return "Back"

		Direction.LEFT:
			return "Left"

		Direction.RIGHT:
			return "Right"


	return "Front"


#
# ============================================================
# CHANGE ANIMATION
# ============================================================
#

func change_animation(
	animation_name: StringName
) -> void:

	if animated_sprite.sprite_frames == null:
		return


	if not animated_sprite.sprite_frames.has_animation(
		animation_name
	):

		push_warning(
			"Missing animation: %s"
			% animation_name
		)

		return


	if animated_sprite.animation != \
			animation_name:

		animated_sprite.play(
			animation_name
		)


#
# ============================================================
# INTERACTION
# ============================================================
#

func interact() -> void:

	var target := \
		_get_closest_interactable()


	if target == null:
		return


	interact_requested.emit()


	if target.has_method(
		"interact"
	):

		target.interact(
			self
		)


#
# ============================================================
# FIND INTERACTABLE
# ============================================================
#

func _get_closest_interactable() -> Node:

	var closest_target: Node = null

	var closest_distance: float = INF


	#
	# Check Area2D objects.
	#
	for area in \
			interaction_area.get_overlapping_areas():

		var target: Node = area


		if not target.is_in_group(
			"interactable"
		):

			var parent := \
				target.get_parent()


			if parent != null \
			and parent.is_in_group(
				"interactable"
			):

				target = parent


		if not target.is_in_group(
			"interactable"
		):
			continue


		if not target.has_method(
			"interact"
		):
			continue


		var distance := \
			global_position.distance_to(
				_get_target_position(
					target
				)
			)


		if distance < closest_distance:

			closest_distance = distance

			closest_target = target


	#
	# Check physics bodies such as doors.
	#
	for body in \
			interaction_area.get_overlapping_bodies():

		var target: Node = body


		if not target.is_in_group(
			"interactable"
		):
			continue


		if not target.has_method(
			"interact"
		):
			continue


		var distance := \
			global_position.distance_to(
				_get_target_position(
					target
				)
			)


		if distance < closest_distance:

			closest_distance = distance

			closest_target = target


	return closest_target


func _get_target_position(
	target: Node
) -> Vector2:

	if target is Node2D:

		return target.global_position


	return global_position
