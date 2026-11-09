class_name SpellProjectile
extends CharacterBody2D

# One hitbox/movement implementation, four class-specific SpriteFrames animations.
const ANIMATIONS = {
	"warlock": ["Warlock Long", "Warlock AOE"],
	"witch": ["Witch Long", "Witch AOE"]
}

const EXPLOSION_ANIMATIONS = {
	"warlock": "Warlock Explode",
	"witch": "Witch Explode"
}

signal finished(target: Node2D, hit_position: Vector2)
signal explosion_finished

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var hitbox: CollisionShape2D = $CollisionShape2D

var direction: Vector2 = Vector2.RIGHT
var speed: float = 500.0
var max_range: float = 350.0
var travelled: float = 0.0
var server_simulated: bool = false
var stopped: bool = false
var configured: bool = false


func configure(origin: Vector2, aim: Vector2, config: Dictionary,
		shooter: PhysicsBody2D, is_server: bool) -> void:
	global_position = origin
	direction = aim.normalized()
	rotation = direction.angle()
	speed = float(config["speed"])
	max_range = float(config["range"])
	server_simulated = is_server
	var circle := CircleShape2D.new()
	circle.radius = float(config["radius"])
	hitbox.shape = circle
	# Server projectiles hit players/terrain on layer 1 AND summons on layer 2.
	# Clients only display FX and do not simulate collision/damage.
	collision_layer = 0
	collision_mask = 3 if is_server else 0
	if is_server and shooter != null:
		add_collision_exception_with(shooter)
	configured = true


func set_visual(caster_class: String, slot: int) -> void:
	if not ANIMATIONS.has(caster_class):
		push_warning("Unknown projectile class: " + caster_class)
		return
	if slot < 0 or slot >= 2:
		return
	if animated_sprite.sprite_frames == null:
		push_warning("Projectile AnimatedSprite2D has no SpriteFrames resource.")
		return
	var animation_name: StringName = StringName(ANIMATIONS[caster_class][slot])
	if not animated_sprite.sprite_frames.has_animation(animation_name):
		push_warning("Missing projectile animation: " + str(animation_name))
		return
	animated_sprite.scale = Vector2.ONE
	animated_sprite.play(animation_name)


func _physics_process(delta: float) -> void:
	if not configured or stopped:
		return
	var remaining: float = max_range - travelled
	if remaining <= 0.0:
		_finish(null, global_position)
		return
	var step: float = minf(speed * delta, remaining)
	var motion: Vector2 = direction * step
	if server_simulated:
		var collision: KinematicCollision2D = move_and_collide(motion)
		if collision != null:
			_finish(collision.get_collider() as Node2D, collision.get_position())
			return
	else:
		global_position += motion
	travelled += step
	if travelled >= max_range - 0.01:
		_finish(null, global_position)


func _finish(target: Node2D, impact_position: Vector2) -> void:
	if stopped:
		return
	stopped = true
	set_physics_process(false)
	finished.emit(target, impact_position)
	# AbilityController sends the despawn RPC and owns cleanup.


func play_explosion(caster_class: String, position: Vector2) -> bool:
	if not EXPLOSION_ANIMATIONS.has(caster_class):
		push_warning("Unknown explosion class: " + caster_class)
		return false
	if animated_sprite.sprite_frames == null:
		push_warning("Explosion SpriteFrames resource is missing.")
		return false
	var name: StringName = StringName(EXPLOSION_ANIMATIONS[caster_class])
	if not animated_sprite.sprite_frames.has_animation(name):
		push_warning("Missing SpriteFrames animation: " + str(name))
		return false
	stopped = true
	set_physics_process(false)
	global_position = position
	rotation = 0.0
	var frames: SpriteFrames = animated_sprite.sprite_frames.duplicate() as SpriteFrames
	frames.set_animation_loop(name, false)
	animated_sprite.sprite_frames = frames
	animated_sprite.animation_finished.connect(
		_on_explosion_animation_finished, CONNECT_ONE_SHOT
	)
	animated_sprite.play(name)
	return true


func _on_explosion_animation_finished() -> void:
	explosion_finished.emit()


func set_explosion_size(caster_class: String, splash_radius: float) -> void:
	if not EXPLOSION_ANIMATIONS.has(caster_class):
		return
	var frames: SpriteFrames = animated_sprite.sprite_frames
	if frames == null:
		return
	var animation_name: StringName = StringName(EXPLOSION_ANIMATIONS[caster_class])
	if not frames.has_animation(animation_name):
		return
	if frames.get_frame_count(animation_name) == 0:
		return
	var texture: Texture2D = frames.get_frame_texture(animation_name, 0)
	if texture == null:
		return
	var size: Vector2 = texture.get_size()
	if size.x <= 0.0 or size.y <= 0.0:
		return
	var diameter: float = maxf(0.0, splash_radius * 2.0)
	animated_sprite.scale = Vector2(diameter / size.x, diameter / size.y)
