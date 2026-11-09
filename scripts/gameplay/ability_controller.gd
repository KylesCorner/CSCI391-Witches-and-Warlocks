class_name AbilityController
extends Node

# Each completed task grants one charge (up to MatchManager.MAX_CHARGES_PER_ABILITY).
const DEV_MODE: bool = false
const DEV_UNLOCK_ALL: bool = DEV_MODE
const DEV_UNLIMITED_CASTS: bool = DEV_MODE

const PROJECTILE_SCENE: PackedScene = preload("res://scenes/gameplay/spell_projectile.tscn")
const SUMMON_SCENE: PackedScene = preload("res://scenes/gameplay/summon.tscn")
const INVISIBLE_ALLY_ALPHA: float = 0.35
const INVISIBLE_SPEED_MULTIPLIER: float = 1.5

const ABILITIES: Array[Dictionary] = [
	{"type": "projectile", "damage": 25, "speed": 550.0, "range": 350.0, "radius": 5.0},
	{"type": "explosion", "damage": 35, "speed": 280.0, "range": 230.0,
	 "radius": 8.0, "splash_radius": 55.0},
	{"type": "summon", "contact_damage": 10, "duration": 8.0},
	{"type": "invisibility", "duration": 5.0}
]

signal ability_state_changed
signal ability_error(message: String)

@onready var player: PlayerController = get_parent() as PlayerController

var used_counts: PackedInt32Array = PackedInt32Array([0, 0, 0, 0])
var next_projectile_id: int = 0
var projectiles: Dictionary = {}
var next_summon_id: int = 0
var summons: Dictionary = {}
var _summon_net_elapsed: Dictionary = {}
var invisibility_active: bool = false
var invisibility_timer: Timer
var _normal_speed: float = 0.0


func _ready() -> void:
	if player == null:
		push_error("AbilityController must be a child of PlayerController")
		set_process(false)
		return
	if multiplayer.is_server():
		invisibility_timer = Timer.new()
		invisibility_timer.one_shot = true
		add_child(invisibility_timer)
		invisibility_timer.timeout.connect(_end_invisibility)
		MatchManager.phase_changed.connect(_on_phase_changed)
		
func _exit_tree() -> void:
	if MatchManager.phase_changed.is_connected(_on_phase_changed):
		MatchManager.phase_changed.disconnect(_on_phase_changed)

func _process(_delta: float) -> void:
	if multiplayer.is_server() or not player.is_multiplayer_authority():
		return
	for slot in range(ABILITIES.size()):
		if Input.is_action_just_pressed("Ability %d" % (slot + 1)):
			try_cast(slot)
			break


# The HUD uses this function too.
func try_cast(slot: int) -> void:
	if multiplayer.is_server() or not player.is_multiplayer_authority():
		return
	if slot < 0 or slot >= ABILITIES.size():
		return
	if player.current_health <= 0:
		ability_error.emit("Cannot cast while defeated")
		return
	if slot == 3 and invisibility_active:
		ability_error.emit("Invisibility is already active")
		return
	if not DEV_MODE:
		if MatchManager.phase != MatchManager.Phase.FIGHT:
			ability_error.emit("Abilities can only be used during Fight")
			return
		if is_spent(slot):
			ability_error.emit("No charges remaining; repeat the corresponding task")
			return

	var aim: Vector2 = player.global_position + Vector2.RIGHT
	var kind: String = str(ABILITIES[slot]["type"])
	if kind == "projectile" or kind == "explosion":
		aim = player.get_global_mouse_position()
		if not aim.is_finite() or aim.distance_squared_to(player.global_position) < 0.001:
			return
	request_cast.rpc_id(1, slot, aim)


@rpc("any_peer", "call_remote", "reliable")
func request_cast(slot: int, target_position: Vector2) -> void:
	if not multiplayer.is_server():
		return
	var sender: int = multiplayer.get_remote_sender_id()
	if sender != player.get_multiplayer_authority() or not NetworkManager.players.has(sender):
		return
	if slot < 0 or slot >= ABILITIES.size():
		return
	if player.current_health <= 0 or not target_position.is_finite():
		return
	if slot == 3 and invisibility_active:
		return
	if not DEV_MODE:
		if MatchManager.phase != MatchManager.Phase.FIGHT:
			return
		if not MatchManager.has_ability(sender, slot) or is_spent(slot):
			return

	var config: Dictionary = ABILITIES[slot]
	match str(config["type"]):
		"projectile", "explosion":
			if target_position.distance_squared_to(player.global_position) < 0.001:
				return
			_consume_ability(slot, sender)
			_launch_projectile(slot, target_position)
		"summon":
			_consume_ability(slot, sender)
			_start_summon(config)
		"invisibility":
			_consume_ability(slot, sender)
			_start_invisibility(float(config["duration"]))


func _consume_ability(slot: int, owner_id: int) -> void:
	if DEV_MODE:
		return
	used_counts[slot] += 1
	if owner_id != 1:
		sync_used_counts.rpc_id(owner_id, used_counts)
	ability_state_changed.emit()


# Server-owned projectile collision and damage; clients render effects.
func _launch_projectile(slot: int, mouse_position: Vector2) -> void:
	var config: Dictionary = ABILITIES[slot]
	var delta: Vector2 = mouse_position - player.global_position
	var distance: float = delta.length()
	if distance < 0.001:
		return
	var direction: Vector2 = delta / distance
	var origin: Vector2
	var flight_range: float
	if str(config["type"]) == "explosion":
		var capped: float = minf(distance, float(config["range"]))
		var offset: float = minf(18.0, capped * 0.5)
		origin = player.global_position + direction * offset
		flight_range = capped - offset
	else:
		origin = player.global_position + direction * 18.0
		flight_range = float(config["range"])

	var id: int = next_projectile_id
	next_projectile_id += 1
	_spawn_local_projectile(id, slot, origin, direction, flight_range, true)
	spawn_projectile_fx.rpc(id, slot, origin, direction, flight_range)


@rpc("any_peer", "call_remote", "reliable")
func spawn_projectile_fx(id: int, slot: int, origin: Vector2,
		direction: Vector2, flight_range: float) -> void:
	if multiplayer.get_remote_sender_id() != 1 or slot < 0 or slot > 1:
		return
	_spawn_local_projectile(id, slot, origin, direction, flight_range, false)


func _get_world_root() -> Node:
	var scene: Node = get_tree().current_scene
	if scene != null and scene.has_method("get_world_root"):
		var root: Node = scene.call("get_world_root")
		if root != null:
			return root
	return scene if scene != null else get_tree().root


func _spawn_local_projectile(id: int, slot: int, origin: Vector2,
		direction: Vector2, flight_range: float, is_server: bool) -> void:
	if projectiles.has(id):
		return
	var projectile: SpellProjectile = PROJECTILE_SCENE.instantiate() as SpellProjectile
	if projectile == null:
		push_error("Projectile scene is not a SpellProjectile")
		return
	_get_world_root().add_child(projectile)
	var config: Dictionary = ABILITIES[slot].duplicate()
	config["range"] = flight_range
	projectile.configure(origin, direction, config, player, is_server)
	projectile.set_visual(player.class_id, slot)
	projectiles[id] = projectile
	if is_server:
		# Our own team's minions must not absorb friendly projectiles.
		for node in get_tree().get_nodes_in_group("summons"):
			var summon: Summon = node as Summon
			if summon != null and summon.team == player.class_id:
				projectile.add_collision_exception_with(summon)
		projectile.finished.connect(_on_projectile_finished.bind(id, slot))
	else:
		var duration: float = flight_range / maxf(float(config["speed"]), 1.0) + 4.0
		_cleanup_stale_projectile(id, duration)


func _on_projectile_finished(target: Node2D, hit_position: Vector2,
		id: int, slot: int) -> void:
	var config: Dictionary = ABILITIES[slot]
	if str(config["type"]) == "projectile":
		_apply_direct_damage(target, int(config["damage"]))
		despawn_projectile_fx.rpc(id)
	else:
		_apply_explosion(hit_position, config)
		explode_projectile_fx.rpc(id, hit_position)
	_remove_projectile(id)


func _apply_direct_damage(body: Node2D, damage: int) -> void:
	var summon: Summon = body as Summon
	if summon != null:
		if summon.team != player.class_id:
			summon.take_hit()
		return
	var target: PlayerController = body as PlayerController
	if target != null and target.class_id != player.class_id:
		target.take_damage(damage)


func _apply_explosion(position: Vector2, config: Dictionary) -> void:
	var shape := CircleShape2D.new()
	shape.radius = float(config["splash_radius"])
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = shape
	query.transform = Transform2D(0.0, position)
	query.collision_mask = 3  # Players/terrain: 1; minions: 2.
	query.exclude = [player.get_rid()]
	var hits: Array[Dictionary] = player.get_world_2d().direct_space_state.intersect_shape(query, 32)
	var seen: Dictionary = {}
	for hit in hits:
		var candidate: Object = hit["collider"]
		if candidate is Summon:
			var summon: Summon = candidate as Summon
			if summon.team != player.class_id:
				summon.take_hit()
			continue
		var target: PlayerController = candidate as PlayerController
		if target == null or target.class_id == player.class_id:
			continue
		var instance: int = target.get_instance_id()
		if seen.has(instance):
			continue
		seen[instance] = true
		target.take_damage(int(config["damage"]))


@rpc("any_peer", "call_remote", "reliable")
func explode_projectile_fx(id: int, position: Vector2) -> void:
	if multiplayer.get_remote_sender_id() != 1 or not projectiles.has(id):
		return
	var projectile: SpellProjectile = projectiles[id] as SpellProjectile
	if not is_instance_valid(projectile):
		projectiles.erase(id)
		return
	projectile.explosion_finished.connect(_remove_projectile.bind(id), CONNECT_ONE_SHOT)
	if not projectile.play_explosion(player.class_id, position):
		_remove_projectile(id)
		return
	projectile.set_explosion_size(player.class_id, float(ABILITIES[1]["splash_radius"]))
	_cleanup_stale_projectile(id, 3.0)


@rpc("any_peer", "call_remote", "reliable")
func despawn_projectile_fx(id: int) -> void:
	if multiplayer.get_remote_sender_id() == 1:
		_remove_projectile(id)


func _cleanup_stale_projectile(id: int, timeout_seconds: float) -> void:
	await get_tree().create_timer(timeout_seconds).timeout
	if is_inside_tree() and projectiles.has(id):
		_remove_projectile(id)


func _remove_projectile(id: int) -> void:
	if not projectiles.has(id):
		return
	var projectile: Node = projectiles[id] as Node
	projectiles.erase(id)
	if is_instance_valid(projectile):
		projectile.queue_free()


# ============================================================
# SUMMON / MURDER CAT (SERVER-AUTHORITATIVE)
# ============================================================

func _start_summon(config: Dictionary) -> void:
	if not multiplayer.is_server():
		return
	var id: int = next_summon_id
	next_summon_id += 1
	var forward: Vector2 = player.velocity.normalized()
	if forward == Vector2.ZERO:
		forward = Vector2.RIGHT
	var origin: Vector2 = player.global_position + forward * 32.0
	_spawn_local_summon(id, origin, player.class_id,
		float(config["duration"]), int(config["contact_damage"]))
	spawn_summon_fx.rpc(id, origin, player.class_id,
		float(config["duration"]), int(config["contact_damage"]))


func _spawn_local_summon(id: int, origin: Vector2, team: String,
		duration: float, damage: int) -> void:
	if summons.has(id):
		return
	var summon: Summon = SUMMON_SCENE.instantiate() as Summon
	if summon == null:
		push_error("summon.tscn must use Summon as its root script")
		return
	summon.name = "Summon_%d_%d" % [player.get_multiplayer_authority(), id]
	_get_world_root().add_child(summon)
	summon.global_position = origin
	summon.configure(self, id, player.get_multiplayer_authority(), team, duration, damage)
	summons[id] = summon
	_summon_net_elapsed[id] = 0.0


@rpc("any_peer", "call_remote", "reliable")
func spawn_summon_fx(id: int, origin: Vector2, team: String,
		duration: float, damage: int) -> void:
	if multiplayer.get_remote_sender_id() != 1 or multiplayer.is_server():
		return
	if team != player.class_id or not origin.is_finite():
		return
	_spawn_local_summon(id, origin, team, duration, damage)


func broadcast_summon_motion(id: int, position: Vector2,
		motion_velocity: Vector2, delta: float) -> void:
	if not multiplayer.is_server() or not summons.has(id):
		return
	var elapsed: float = float(_summon_net_elapsed.get(id, 0.0)) + delta
	if elapsed < 0.10:
		_summon_net_elapsed[id] = elapsed
		return
	_summon_net_elapsed[id] = fmod(elapsed, 0.10)
	sync_summon_motion.rpc(id, position, motion_velocity)


@rpc("any_peer", "call_remote", "unreliable_ordered")
func sync_summon_motion(id: int, position: Vector2, motion_velocity: Vector2) -> void:
	if multiplayer.get_remote_sender_id() != 1 or multiplayer.is_server():
		return
	if not position.is_finite() or not motion_velocity.is_finite():
		return
	var summon: Summon = summons.get(id) as Summon
	if summon != null:
		summon.set_remote_motion(position, motion_velocity)


func broadcast_summon_attack(id: int) -> void:
	if multiplayer.is_server() and summons.has(id):
		sync_summon_attack.rpc(id)


@rpc("any_peer", "call_remote", "reliable")
func sync_summon_attack(id: int) -> void:
	if multiplayer.get_remote_sender_id() != 1 or multiplayer.is_server():
		return
	var summon: Summon = summons.get(id) as Summon
	if summon != null:
		summon.show_attack()


func despawn_summon(id: int) -> void:
	if not multiplayer.is_server() or not summons.has(id):
		return
	var summon: Summon = summons[id] as Summon
	summons.erase(id)
	_summon_net_elapsed.erase(id)
	despawn_summon_fx.rpc(id)
	if is_instance_valid(summon):
		summon.queue_free()


@rpc("any_peer", "call_remote", "reliable")
func despawn_summon_fx(id: int) -> void:
	if multiplayer.get_remote_sender_id() != 1 or multiplayer.is_server():
		return
	if not summons.has(id):
		return
	var summon: Summon = summons[id] as Summon
	summons.erase(id)
	_summon_net_elapsed.erase(id)
	if is_instance_valid(summon):
		summon.disappear()


# ============================================================
# INVISIBILITY (INCLUDES OWNER-ONLY 1.5x MOVEMENT SPEED)
# ============================================================

func _start_invisibility(duration: float) -> void:
	if not multiplayer.is_server():
		return
	invisibility_active = true
	sync_invisibility.rpc(true)
	invisibility_timer.start(duration)


func _end_invisibility() -> void:
	if not multiplayer.is_server():
		return
	if invisibility_timer != null:
		invisibility_timer.stop()
	if not invisibility_active:
		return
	invisibility_active = false
	sync_invisibility.rpc(false)


@rpc("any_peer", "call_remote", "reliable")
func sync_invisibility(active: bool) -> void:
	if multiplayer.get_remote_sender_id() != 1:
		return
	if active and not invisibility_active:
		_normal_speed = player.speed
		if player.is_multiplayer_authority():
			player.speed *= INVISIBLE_SPEED_MULTIPLIER
	elif not active and invisibility_active:
		if player.is_multiplayer_authority():
			player.speed = _normal_speed
	invisibility_active = active
	_apply_invisibility_visual(active)


func _apply_invisibility_visual(active: bool) -> void:
	var sprite: AnimatedSprite2D = player.get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
	var tag: Node2D = player.get_node_or_null("PlayerTag") as Node2D
	if sprite == null:
		return
	var owner: bool = player.is_multiplayer_authority()
	var local_class: String = str(NetworkManager.local_player_info.get("class", ""))
	var ally: bool = local_class == player.class_id
	sprite.visible = true
	var color: Color = sprite.modulate
	color.a = 1.0
	if active:
		if owner or ally:
			color.a = INVISIBLE_ALLY_ALPHA
		else:
			sprite.visible = false
	sprite.modulate = color
	if tag != null:
		tag.visible = not owner and not (active and not ally)


func get_remaining_charges(slot: int) -> int:
	if slot < 0 or slot >= ABILITIES.size():
		return 0
	if DEV_MODE:
		return MatchManager.MAX_CHARGES_PER_ABILITY
	var earned: int = MatchManager.get_ability_count(player.get_multiplayer_authority(), slot)
	return maxi(0, earned - used_counts[slot])


func is_spent(slot: int) -> bool:
	return get_remaining_charges(slot) <= 0


@rpc("any_peer", "call_remote", "reliable")
func sync_used_counts(counts: PackedInt32Array) -> void:
	if multiplayer.get_remote_sender_id() != 1 or counts.size() != ABILITIES.size():
		return
	used_counts = counts.duplicate()
	ability_state_changed.emit()

func _on_phase_changed(next_phase: int, _round: int) -> void:
	if not is_inside_tree():
		return

	if not multiplayer.is_server() or next_phase != MatchManager.Phase.PREPARE:
		return
		
	_end_invisibility()
	for id in summons.keys():
		despawn_summon(int(id))
	used_counts = PackedInt32Array([0, 0, 0, 0])
	var owner_id: int = player.get_multiplayer_authority()
	if owner_id != 1 and owner_id in multiplayer.get_peers():
		sync_used_counts.rpc_id(owner_id, used_counts)
	ability_state_changed.emit()
