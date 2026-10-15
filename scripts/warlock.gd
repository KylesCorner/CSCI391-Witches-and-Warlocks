extends CharacterBody2D


@export var speed: float = 100.0


@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D


enum Direction {
	FRONT,
	BACK,
	LEFT,
	RIGHT
}


var facing_direction: Direction = Direction.FRONT


func _ready() -> void:
	if animated_sprite.sprite_frames == null:
		push_error(
			"AnimatedSprite2D has no SpriteFrames resource!"
		)
		return

	animated_sprite.play("Idle Front")


func _physics_process(_delta: float) -> void:
	var input_direction := Input.get_vector(
		"Warlock Left",
		"Warlock Right",
		"Warlock Forward",
		"Warlock Backward"
	)

	velocity = input_direction * speed

	move_and_slide()

	if input_direction == Vector2.ZERO:
		play_idle_animation()
	else:
		update_facing_direction(input_direction)
		play_walk_animation()


func update_facing_direction(direction: Vector2) -> void:
	if abs(direction.x) > abs(direction.y):
		if direction.x > 0.0:
			facing_direction = Direction.RIGHT
		else:
			facing_direction = Direction.LEFT
	else:
		if direction.y > 0.0:
			facing_direction = Direction.FRONT
		else:
			facing_direction = Direction.BACK


func play_walk_animation() -> void:
	match facing_direction:
		Direction.FRONT:
			change_animation("Walk Front")

		Direction.BACK:
			change_animation("Walk Back")

		Direction.LEFT:
			change_animation("Walk Left")

		Direction.RIGHT:
			change_animation("Walk Right")


func play_idle_animation() -> void:
	match facing_direction:
		Direction.FRONT:
			change_animation("Idle Front")

		Direction.BACK:
			change_animation("Idle Back")

		Direction.LEFT:
			change_animation("Idle Left")

		Direction.RIGHT:
			change_animation("Idle Right")


func change_animation(animation_name: StringName) -> void:
	if animated_sprite.sprite_frames == null:
		return

	if not animated_sprite.sprite_frames.has_animation(animation_name):
		push_error(
			"Missing animation: %s" % animation_name
		)
		return

	if animated_sprite.animation != animation_name:
		animated_sprite.play(animation_name)
