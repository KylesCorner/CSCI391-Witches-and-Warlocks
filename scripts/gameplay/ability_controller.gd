class_name AbilityController
extends Node

# ============================================================
# SETTINGS
# ============================================================

# TRUE: bypass phase, unlock and charge restrictions.
# FALSE: use MatchManager phases, task unlocks and charges.
const DEV_MODE: bool = true

# Kept for compatibility with the existing HUD code.
const DEV_UNLOCK_ALL: bool = DEV_MODE
const DEV_UNLIMITED_CASTS: bool = DEV_MODE

const PROJECTILE_SCENE: PackedScene = preload(
	"res://scenes/gameplay/spell_projectile.tscn"
)

const INVISIBLE_ALLY_ALPHA: float = 0.35

const ABILITIES = [
	{
		"type": "projectile",
		"damage": 25,
		"speed": 550.0,
		"range": 350.0,
		"radius": 5.0
	},
	{
		"type": "explosion",
		"damage": 35,
		"speed": 280.0,
		"range": 230.0,
		"radius": 8.0,
		"splash_radius": 55.0
	},
	{
		"type": "summon",
		"contact_damage": 10,
		"duration": 8.0
	},
	{
		"type": "invisibility",
		"duration": 5.0
	}
]

signal ability_state_changed

@onready var player: PlayerController = get_parent() as PlayerController

var used_mask: int = 0
var next_projectile_id: int = 0
var projectiles: Dictionary = {}

var invisibility_active: bool = false
var invisibility_timer: Timer


# ============================================================
# INITIALIZATION AND INPUT
# ============================================================

func _ready() -> void:
	if player == null:
		push_error("AbilityController must be a child of PlayerController.")
		set_process(false)
		return

	if multiplayer.is_server():
		invisibility_timer = Timer.new()
		invisibility_timer.one_shot = true
		add_child(invisibility_timer)
		invisibility_timer.timeout.connect(_end_invisibility)
		MatchManager.phase_changed.connect(_on_phase_changed)


func _process(_delta: float) -> void:
	if multiplayer.is_server() or not player.is_multiplayer_authority():
		return

	for slot in range(ABILITIES.size()):
		if Input.is_action_just_pressed("Ability %d" % (slot + 1)):
			_try_cast(slot)
			break


func _try_cast(slot: int) -> void:
	if slot < 0 or slot >= ABILITIES.size():
		return

	if not DEV_MODE:
		if MatchManager.phase != MatchManager.Phase.FIGHT:
			print("[ABILITY] Cannot cast outside Fight phase.")
			return
		if is_spent(slot):
			print("[ABILITY] Ability already used this round.")
			return

	# Pass a world-space mouse position for projectile abilities.
	# The dedicated server computes and clamps the actual flight path.
	# Other abilities don't need to aim, but reuse the same RPC signature.
	var mouse_position: Vector2 = player.global_position + Vector2.RIGHT
	var ability_type: String = str(ABILITIES[slot]["type"])
	if ability_type == "projectile" or ability_type == "explosion":
		mouse_position = player.get_global_mouse_position()
		if not mouse_position.is_finite():
			return
		if mouse_position.distance_squared_to(player.global_position) < 0.001:
			return

	print("[CLIENT] Requesting ability ", slot + 1, " at ", mouse_position)
	request_cast.rpc_id(1, slot, mouse_position)


# ============================================================
# SERVER CAST VALIDATION
# ============================================================

@rpc("any_peer", "call_remote", "reliable")
func request_cast(slot: int, target_position: Vector2) -> void:
	if not multiplayer.is_server():
		return

	var sender: int = multiplayer.get_remote_sender_id()
	if sender != player.get_multiplayer_authority():
		print("[SERVER] Rejected cast: wrong player owner.")
		return
	if not NetworkManager.players.has(sender):
		return
	if slot < 0 or slot >= ABILITIES.size():
		return
	if player.current_health <= 0:
		return
	if not target_position.is_finite():
		return

	if not DEV_MODE:
		if MatchManager.phase != MatchManager.Phase.FIGHT:
			print("[SERVER] Rejected cast: not Fight phase.")
			return
		if not MatchManager.has_ability(sender, slot):
			print("[SERVER] Rejected cast: ability locked.")
			return
		if is_spent(slot):
			print("[SERVER] Rejected cast: ability spent.")
			return

	var config: Dictionary = ABILITIES[slot]
	var ability_type: String = str(config["type"])

	match ability_type:
		"projectile", "explosion":
			if target_position.distance_squared_to(player.global_position) < 0.001:
				return
			_consume_ability(slot, sender)
			print("[SERVER] Casting projectile ability ", slot + 1)
			_launch_projectile(slot, target_position)

		"invisibility":
			_consume_ability(slot, sender)
			_start_invisibility(float(config["duration"]))

		"summon":
			# Slot 3 has configuration but isn't implemented yet.
			print("[SERVER] Summon ability not implemented yet.")


func _consume_ability(slot: int, owner_id: int) -> void:
	if DEV_MODE:
		return
	used_mask |= (1 << slot)
	sync_used_mask.rpc_id(owner_id, used_mask)


# ============================================================
# PROJECTILE SPAWNING
# ============================================================

func _launch_projectile(slot: int, mouse_position: Vector2) -> void:
	var config: Dictionary = ABILITIES[slot]
	var to_mouse: Vector2 = mouse_position - player.global_position
	var distance: float = to_mouse.length()
	if distance < 0.001:
		return

	var direction: Vector2 = to_mouse / distance
	var origin: Vector2
	var flight_range: float

	if str(config["type"]) == "explosion":
		# The AOE destination is the mouse, capped at ability range.
		# Spawn closer for very short casts, so we never overshoot.
		var capped_distance: float = minf(distance, float(config["range"]))
		var spawn_offset: float = minf(18.0, capped_distance * 0.5)
		origin = player.global_position + direction * spawn_offset
		flight_range = capped_distance - spawn_offset
		print("[SERVER] AOE target: ", player.global_position + direction * capped_distance)
	else:
		# Long-range shots still travel their configured maximum distance.
		origin = player.global_position + direction * 18.0
		flight_range = float(config["range"])

	var projectile_id: int = next_projectile_id
	next_projectile_id += 1

	_spawn_local_projectile(projectile_id, slot, origin, direction, flight_range, true)
	spawn_projectile_fx.rpc(projectile_id, slot, origin, direction, flight_range)


@rpc("any_peer", "call_remote", "reliable")
func spawn_projectile_fx(
	projectile_id: int,
	slot: int,
	origin: Vector2,
	direction: Vector2,
	flight_range: float
) -> void:
	if multiplayer.get_remote_sender_id() != 1:
		return
	if slot < 0 or slot > 1:
		return
	_spawn_local_projectile(projectile_id, slot, origin, direction, flight_range, false)


func _spawn_local_projectile(
	projectile_id: int,
	slot: int,
	origin: Vector2,
	direction: Vector2,
	flight_range: float,
	is_server: bool
) -> void:
	if projectiles.has(projectile_id):
		return

	var projectile: SpellProjectile = PROJECTILE_SCENE.instantiate() as SpellProjectile
	if projectile == null:
		push_error("SpellProjectile scene root must use spell_projectile.gd.")
		return

	get_tree().current_scene.add_child(projectile)
	var projectile_config: Dictionary = ABILITIES[slot].duplicate()
	projectile_config["range"] = flight_range
	projectile.configure(origin, direction, projectile_config, player, is_server)
	projectile.set_visual(player.class_id, slot)
	projectiles[projectile_id] = projectile

	if not is_server:
		var max_lifetime: float = flight_range / maxf(float(projectile_config["speed"]), 1.0) + 4.0
		_cleanup_stale_projectile(projectile_id, max_lifetime)

	if is_server:
		projectile.finished.connect(
			_on_projectile_finished.bind(projectile_id, slot)
		)


func _on_projectile_finished(
	target: Node2D,
	hit_position: Vector2,
	projectile_id: int,
	slot: int
) -> void:
	var config: Dictionary = ABILITIES[slot]
	match str(config["type"]):
		"projectile":
			_apply_direct_damage(target, int(config["damage"]))
			despawn_projectile_fx.rpc(projectile_id)
		"explosion":
			# Explosion occurs at the server-confirmed impact/cursor/range point.
			_apply_explosion(hit_position, config)
			# Clients switch their flying sprite to the explosion animation.
			explode_projectile_fx.rpc(projectile_id, hit_position)

	# The dedicated server does not need to animate an explosion.
	_remove_projectile(projectile_id)


func _apply_direct_damage(body: Node2D, damage: int) -> void:
	var target: PlayerController = body as PlayerController
	if target == null:
		print("[SERVER] Projectile missed or hit environment.")
		return
	if target.class_id == player.class_id:
		print("[SERVER] Friendly fire ignored.")
		return

	target.take_damage(damage)
	print("[SERVER] HIT: ", target.display_name, " | HP: ", target.current_health)


func _apply_explosion(position: Vector2, config: Dictionary) -> void:
	var shape := CircleShape2D.new()
	shape.radius = float(config["splash_radius"])

	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = shape
	query.transform = Transform2D(0.0, position)
	query.collision_mask = 1
	query.exclude = [player.get_rid()]

	var results: Array[Dictionary] = player.get_world_2d().direct_space_state.intersect_shape(query, 32)
	var damaged: Dictionary = {}

	for result in results:
		var target: PlayerController = result["collider"] as PlayerController
		if target == null or target.class_id == player.class_id:
			continue
		var target_id: int = target.get_instance_id()
		if damaged.has(target_id):
			continue
		damaged[target_id] = true
		target.take_damage(int(config["damage"]))
		print("[SERVER] EXPLOSION HIT: ", target.display_name, " | HP: ", target.current_health)

	print("[SERVER] Explosion at ", position)


# ============================================================
# AOE EXPLOSION VISUAL — CLIENTS ONLY
# ============================================================

@rpc("any_peer", "call_remote", "reliable")
func explode_projectile_fx(projectile_id: int, hit_position: Vector2) -> void:
	if multiplayer.get_remote_sender_id() != 1:
		return

	if not projectiles.has(projectile_id):
		push_warning("Missing AOE projectile for explosion ID %d" % projectile_id)
		return

	# Do not type this variable: dictionary entries can contain stale nodes.
	var projectile = projectiles[projectile_id]
	if not is_instance_valid(projectile):
		projectiles.erase(projectile_id)
		return

	projectile.explosion_finished.connect(
		_remove_projectile.bind(projectile_id), CONNECT_ONE_SHOT
	)
	# Movement halts; animation changes to Warlock/Witch Explode.
	if not projectile.play_explosion(player.class_id, hit_position):
		_remove_projectile(projectile_id)
		return

	# Scale only the explosion animation, not the flying projectile.
	projectile.set_explosion_size(
		player.class_id,
		float(ABILITIES[1]["splash_radius"])
	)

	# Fallback if an animation never finishes.
	_cleanup_stale_projectile(projectile_id, 3.0)


@rpc("any_peer", "call_remote", "reliable")
func despawn_projectile_fx(projectile_id: int) -> void:
	if multiplayer.get_remote_sender_id() != 1:
		return
	_remove_projectile(projectile_id)


func _cleanup_stale_projectile(projectile_id: int, lifetime: float) -> void:
	await get_tree().create_timer(lifetime).timeout
	if not is_inside_tree():
		return
	if projectiles.has(projectile_id):
		print("[PROJECTILE] Safety cleanup: ", projectile_id)
		_remove_projectile(projectile_id)


func _remove_projectile(projectile_id: int) -> void:
	if not projectiles.has(projectile_id):
		return

	# Leave the value untyped: the referenced node may already be freed.
	var projectile = projectiles.get(projectile_id)
	projectiles.erase(projectile_id)

	if is_instance_valid(projectile):
		projectile.queue_free()


# ============================================================
# INVISIBILITY — SLOT 4
# ============================================================

func _start_invisibility(duration: float) -> void:
	if not multiplayer.is_server():
		return

	invisibility_active = true
	sync_invisibility.rpc(true)
	invisibility_timer.start(duration)
	print("[SERVER] ", player.display_name, " invisible for ", duration, " seconds.")


func _end_invisibility() -> void:
	if not multiplayer.is_server():
		return

	invisibility_timer.stop()
	if not invisibility_active:
		return

	invisibility_active = false
	sync_invisibility.rpc(false)
	print("[SERVER] ", player.display_name, " is visible again.")


@rpc("any_peer", "call_remote", "reliable")
func sync_invisibility(active: bool) -> void:
	# Player nodes are client-authoritative, so we explicitly verify the server.
	if multiplayer.get_remote_sender_id() != 1:
		return

	invisibility_active = active
	_apply_invisibility_visual(active)


func _apply_invisibility_visual(active: bool) -> void:
	var sprite: AnimatedSprite2D = player.get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
	var player_tag: Node2D = player.get_node_or_null("PlayerTag") as Node2D
	if sprite == null:
		push_warning("Player has no AnimatedSprite2D.")
		return

	var is_owner: bool = player.is_multiplayer_authority()
	var local_class: String = str(NetworkManager.local_player_info.get("class", ""))
	var is_ally: bool = local_class == player.class_id

	# Always reset first so invisibility expiration restores the sprite.
	sprite.visible = true
	var color: Color = sprite.modulate
	color.a = 1.0

	if active:
		if is_owner or is_ally:
			# Invisible player and teammates get the same ghost appearance.
			color.a = INVISIBLE_ALLY_ALPHA
		else:
			# Enemies cannot see the player sprite at all.
			sprite.visible = false

	sprite.modulate = color

	if player_tag != null:
		# The owner's tag is always hidden. Enemy tags disappear while invisible.
		# Teammates still see the tag over the translucent sprite.
		player_tag.visible = not is_owner and not (active and not is_ally)

	print(
		"[INVISIBILITY] ", player.display_name,
		" | Active: ", active,
		" | Owner: ", is_owner,
		" | Ally: ", is_ally,
		" | Alpha: ", color.a
	)


# ============================================================
# CHARGES AND ROUND RESET
# ============================================================

func is_spent(slot: int) -> bool:
	if slot < 0 or slot >= ABILITIES.size():
		return true
	return (used_mask & (1 << slot)) != 0


@rpc("any_peer", "call_remote", "reliable")
func sync_used_mask(new_mask: int) -> void:
	if multiplayer.get_remote_sender_id() != 1:
		return
	used_mask = new_mask
	ability_state_changed.emit()


func _on_phase_changed(new_phase: int, _round_number: int) -> void:
	if not multiplayer.is_server():
		return
	if new_phase != MatchManager.Phase.PREPARE:
		return

	# An invisible player must become visible again when Fight ends.
	_end_invisibility()

	used_mask = 0
	var owner_id: int = player.get_multiplayer_authority()
	if owner_id != 1:
		sync_used_mask.rpc_id(owner_id, used_mask)
