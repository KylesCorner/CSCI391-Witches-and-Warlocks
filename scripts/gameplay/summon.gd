class_name Summon
extends CharacterBody2D

## One animation per class; A* uses only Terrain 0 floor tiles.
## The dedicated server controls movement, targeting, and melee damage.
@export var move_speed: float = 115.0
@export var melee_range: float = 28.0
@export var attack_cooldown: float = 0.85
@export var repath_interval: float = 0.25
@export var floor_terrain_set: int = 0
@export var floor_terrain: int = 0
@export var log_paths: bool = false

@onready var warlock_sprite: AnimatedSprite2D = $Animations/Warlock
@onready var witch_sprite: AnimatedSprite2D = $Animations/Witch

var team: String = ""
var owner_peer_id: int = -1
var summon_id: int = -1
var melee_damage: int = 10
var remaining_life: float = 8.0
var controller

var _configured: bool = false
var _dying: bool = false
var _attack_wait: float = 0.0
var _repath_wait: float = 0.0
var _floor: TileMapLayer
var _astar: AStarGrid2D
var _target: PlayerController
var _route: Array[Vector2i] = []
var _route_index: int = 0
var _goal_cell: Vector2i = Vector2i(-99999, -99999)
var _net_position: Vector2 = Vector2.ZERO
var _net_velocity: Vector2 = Vector2.ZERO


func _ready() -> void:
	# Players' collision mask is layer 1. Summons occupy layer 2,
	# so players can walk through them while enemy spells can hit them.
	collision_layer = 2 if multiplayer.is_server() else 0
	collision_mask = 1 if multiplayer.is_server() else 0
	set_physics_process(multiplayer.is_server())


func configure(new_controller, id: int, owner_id: int,
		owner_team: String, duration: float, damage: int) -> void:
	controller = new_controller
	summon_id = id
	owner_peer_id = owner_id
	team = owner_team
	remaining_life = duration
	melee_damage = damage
	_configured = true
	add_to_group("summons")

	warlock_sprite.visible = team == "warlock"
	witch_sprite.visible = team == "witch"
	var sprite: AnimatedSprite2D = _sprite()
	sprite.play("Default")

	if multiplayer.is_server():
		_build_floor_grid()
		var owner: PlayerController = _get_owner()
		if owner != null:
			# AbilityController initially spawns a few pixels ahead;
			# use the caster's floor tile instead to avoid spawning in a wall.
			var cell: Vector2i = _cell(owner.global_position)
			if _is_floor(cell):
				global_position = _world(cell)
			else:
				push_warning("Summon: owner is not on a walkable floor cell")
	_net_position = global_position


func _physics_process(delta: float) -> void:
	if not _configured or _dying or not multiplayer.is_server():
		return

	remaining_life -= delta
	_attack_wait = maxf(0.0, _attack_wait - delta)
	if remaining_life <= 0.0 or MatchManager.phase != MatchManager.Phase.FIGHT \
	or _get_owner() == null:
		controller.despawn_summon(summon_id)
		return

	# Drop invisible, dead, or disconnected targets without waiting for a repath.
	if _target != null and not _visible_enemy(_target):
		_target = null
		_route.clear()
		_repath_wait = 0.0

	_repath_wait -= delta
	if _repath_wait <= 0.0:
		_repath_wait = repath_interval
		_find_path()

	velocity = Vector2.ZERO
	if _target != null:
		if global_position.distance_to(_target.global_position) <= melee_range \
		and _clear_melee_line(_target):
			if _attack_wait <= 0.0:
				_target.take_damage(melee_damage)
				_attack_wait = attack_cooldown
				controller.broadcast_summon_attack(summon_id)
		else:
			_follow_route(delta)

	if absf(velocity.x) > 1.0:
		_sprite().flip_h = velocity.x < 0.0
	controller.broadcast_summon_motion(summon_id, global_position, velocity, delta)


func _build_floor_grid() -> void:
	_floor = get_parent().get_node_or_null("TileMapLayer") as TileMapLayer
	if _floor == null or _floor.tile_set == null:
		push_error("Summon: World/TileMapLayer missing")
		return

	var region: Rect2i = _floor.get_used_rect()
	_astar = AStarGrid2D.new()
	_astar.region = region
	_astar.cell_size = Vector2.ONE
	_astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
	_astar.update()

	# A* defaults to all cells traversable. Start completely blocked.
	_astar.fill_solid_region(region, true)
	var count: int = 0
	for cell in _floor.get_used_cells():
		var tile: TileData = _floor.get_cell_tile_data(cell)
		if tile != null and tile.terrain_set == floor_terrain_set \
		and tile.terrain == floor_terrain:
			_astar.set_point_solid(cell, false)
			count += 1
	print("[SUMMON A*] %d floor tiles (terrain %d), walls blocked" % [count, floor_terrain])


func _players() -> Node:
	return get_parent().get_node_or_null("Players")


func _get_owner() -> PlayerController:
	var players: Node = _players()
	if players == null:
		return null
	var owner: PlayerController = players.get_node_or_null(str(owner_peer_id)) as PlayerController
	return owner if owner != null and owner.current_health > 0 else null


func _cell(point: Vector2) -> Vector2i:
	return _floor.local_to_map(_floor.to_local(point))


func _world(cell: Vector2i) -> Vector2:
	return _floor.to_global(_floor.map_to_local(cell))


func _is_floor(cell: Vector2i) -> bool:
	return _astar != null and _astar.is_in_boundsv(cell) \
		and not _astar.is_point_solid(cell)


func _visible_enemy(candidate: PlayerController) -> bool:
	if not is_instance_valid(candidate) or candidate.class_id == team \
	or candidate.current_health <= 0:
		return false
	var ability: AbilityController = candidate.get_node_or_null("AbilityController") as AbilityController
	return ability == null or not ability.invisibility_active


func _find_path() -> void:
	var players: Node = _players()
	if players == null or _astar == null:
		_target = null
		_route.clear()
		return

	var start: Vector2i = _cell(global_position)
	if not _is_floor(start):
		_target = null
		_route.clear()
		return

	var closest: PlayerController = null
	var best_path: Array[Vector2i] = []
	var best_goal: Vector2i = Vector2i(-99999, -99999)

	for node in players.get_children():
		var enemy: PlayerController = node as PlayerController
		if not _visible_enemy(enemy):
			continue
		var goal: Vector2i = _cell(enemy.global_position)
		if not _is_floor(goal):
			continue
		var candidate_path: Array[Vector2i] = _astar.get_id_path(start, goal)
		if candidate_path.is_empty():
			continue
		if closest == null or candidate_path.size() < best_path.size():
			closest = enemy
			best_path = candidate_path
			best_goal = goal

	if closest == null:
		_target = null
		_route.clear()
		_route_index = 0
		return

	# Preserve progress if the target hasn't changed grid cells.
	if closest == _target and best_goal == _goal_cell \
	and _route_index < _route.size():
		return

	_target = closest
	_goal_cell = best_goal
	_route = best_path
	_route_index = 0
	if log_paths:
		print("[SUMMON A*] target=", closest.name, " path tiles=", _route.size())


func _follow_route(delta: float) -> void:
	while _route_index < _route.size():
		var waypoint: Vector2 = _world(_route[_route_index])
		var offset: Vector2 = waypoint - global_position
		var distance: float = offset.length()
		if distance <= 1.5:
			_route_index += 1
			continue

		var motion: Vector2 = offset / distance * minf(move_speed * delta, distance)
		# The destination MUST be a floor tile: never chase a target
		# directly or cross blocked cells to reach it.
		if not _is_floor(_cell(global_position + motion)):
			_route.clear()
			_repath_wait = 0.0
			return
		var before: Vector2 = global_position
		var hit: KinematicCollision2D = move_and_collide(motion)
		velocity = (global_position - before) / maxf(delta, 0.001)
		if hit != null:
			_route.clear()
			_repath_wait = 0.0
		return


func _clear_melee_line(enemy: PlayerController) -> bool:
	var query: PhysicsRayQueryParameters2D = PhysicsRayQueryParameters2D.create(
		global_position, enemy.global_position)
	query.collision_mask = 1
	query.exclude = [get_rid(), enemy.get_rid()]
	return get_world_2d().direct_space_state.intersect_ray(query).is_empty()


func take_hit() -> void:
	if multiplayer.is_server() and not _dying:
		_dying = true
		controller.despawn_summon(summon_id)


# Keep the existing AbilityController RPC interface unchanged.
func set_remote_motion(position: Vector2, new_velocity: Vector2) -> void:
	if multiplayer.is_server() or _dying:
		return
	_net_position = position
	_net_velocity = new_velocity


func show_attack() -> void:
	pass  # This summon has one looping animation, even while attacking.


func _process(delta: float) -> void:
	if multiplayer.is_server() or not _configured or _dying:
		return
	var predicted: Vector2 = _net_position + _net_velocity * 0.06
	if global_position.distance_squared_to(predicted) > 250.0 * 250.0:
		global_position = predicted
	else:
		global_position = global_position.lerp(predicted, 1.0 - exp(-16.0 * delta))
	if absf(_net_velocity.x) > 1.0:
		_sprite().flip_h = _net_velocity.x < 0.0


func disappear() -> void:
	_dying = true
	queue_free()  # No separate death animation anymore.


func _sprite() -> AnimatedSprite2D:
	return witch_sprite if team == "witch" else warlock_sprite
