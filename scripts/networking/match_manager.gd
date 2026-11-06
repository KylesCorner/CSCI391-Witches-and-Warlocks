extends Node

signal phase_changed(new_phase: Phase, round_number: int)
signal timer_changed(seconds_left: int)
signal tasks_changed(peer_id: int, task_mask: int)

enum Phase { WAITING, PREPARE, FIGHT }

const PREPARE_SECONDS: int = 90
const FIGHT_SECONDS: int = 60
const MAX_INTERACTION_DISTANCE: float = 45.0

# One completed task = one charge of the corresponding ability.
# Each mask is the set of tasks needed to earn ONE charge.
# For multiple-task recipes, the available earned charges are the
# minimum completion count across all required tasks.
const ABILITY_REQUIREMENTS: Array[int] = [0b0001, 0b0010, 0b0100, 0b1000]
const MAX_CHARGES_PER_ABILITY: int = 5

var phase: Phase = Phase.WAITING
var round_number: int = 0
var seconds_left: int = 0

# Compatibility: bit N is set once task N has been completed at least once.
var task_masks: Dictionary = {}
# peer_id -> PackedInt32Array([task1_count, task2_count, task3_count, task4_count])
var task_counts: Dictionary = {}
# peer_id -> { "path": NodePath, "serial": int }
var _active_tasks: Dictionary = {}
var _next_task_serial: int = 0
var round_timer: Timer


func _ready() -> void:
	round_timer = Timer.new()
	round_timer.wait_time = 1.0
	round_timer.one_shot = false
	add_child(round_timer)
	round_timer.timeout.connect(_on_timer_timeout)
	NetworkManager.all_players_loaded.connect(_on_all_players_loaded)


func _on_all_players_loaded() -> void:
	if multiplayer.is_server():
		call_deferred("_start_if_players_spawned")


func _start_if_players_spawned() -> void:
	var scene: Node = get_tree().current_scene
	if scene == null:
		return
	var players: Node = scene.get_node_or_null("WorldView/WorldViewport/World/Players")
	if players == null or players.get_child_count() < NetworkManager.players.size():
		push_warning("Player spawning incomplete; match start skipped")
		return
	start_match()


func start_match() -> void:
	if not multiplayer.is_server() or phase != Phase.WAITING:
		return
	round_number = 1
	_start_phase(Phase.PREPARE)


func _start_phase(next_phase: Phase) -> void:
	if not multiplayer.is_server():
		return

	_active_tasks.clear()
	if next_phase == Phase.PREPARE:
		for peer_id in NetworkManager.players.keys():
			sync_task_counts.rpc(int(peer_id), PackedInt32Array([0, 0, 0, 0]))

	var duration: int = PREPARE_SECONDS if next_phase == Phase.PREPARE else FIGHT_SECONDS
	sync_phase.rpc(int(next_phase), round_number, duration)
	round_timer.start()


func _on_timer_timeout() -> void:
	if not multiplayer.is_server():
		return
	if seconds_left <= 1:
		if phase == Phase.PREPARE:
			_start_phase(Phase.FIGHT)
		else:
			round_number += 1
			_start_phase(Phase.PREPARE)
		return
	sync_phase.rpc(int(phase), round_number, seconds_left - 1)


@rpc("authority", "call_local", "reliable")
func sync_phase(new_phase: int, new_round: int, remaining: int) -> void:
	var changed: bool = int(phase) != new_phase or round_number != new_round
	phase = new_phase as Phase
	round_number = new_round
	seconds_left = remaining
	if changed:
		phase_changed.emit(phase, round_number)
	timer_changed.emit(seconds_left)


# Server owns counts. All clients receive progress; no client can award charges.
@rpc("authority", "call_local", "reliable")
func sync_task_counts(peer_id: int, counts: PackedInt32Array) -> void:
	if counts.size() != 4:
		return
	var clean: PackedInt32Array = counts.duplicate()
	var mask: int = 0
	for index in range(4):
		clean[index] = clampi(clean[index], 0, MAX_CHARGES_PER_ABILITY)
		if clean[index] > 0:
			mask |= 1 << index
	task_counts[peer_id] = clean
	task_masks[peer_id] = mask
	# Emit for every completion, even if the old bit mask is unchanged.
	tasks_changed.emit(peer_id, mask)


func get_task_count(peer_id: int, task_index: int) -> int:
	if task_index < 0 or task_index >= 4:
		return 0
	var counts: PackedInt32Array = task_counts.get(peer_id, PackedInt32Array())
	if counts.size() != 4:
		return 0
	return counts[task_index]


func get_ability_count(peer_id: int, ability_index: int) -> int:
	if ability_index < 0 or ability_index >= ABILITY_REQUIREMENTS.size():
		return 0
	var required: int = ABILITY_REQUIREMENTS[ability_index]
	if required == 0:
		return 0
	var earned: int = MAX_CHARGES_PER_ABILITY
	for task_index in range(4):
		if (required & (1 << task_index)) != 0:
			earned = mini(earned, get_task_count(peer_id, task_index))
	return earned


func get_ability_mask(peer_id: int) -> int:
	var mask: int = 0
	for index in range(ABILITY_REQUIREMENTS.size()):
		if get_ability_count(peer_id, index) > 0:
			mask |= 1 << index
	return mask


func has_ability(peer_id: int, ability_index: int) -> bool:
	return get_ability_count(peer_id, ability_index) > 0


func _get_player(peer_id: int) -> PlayerController:
	var scene: Node = get_tree().current_scene
	if scene == null:
		return null
	return scene.get_node_or_null(
		NodePath("WorldView/WorldViewport/World/Players/" + str(peer_id))
	) as PlayerController


func _get_world_task(task_path: NodePath) -> WorldTask:
	if not task_path.is_absolute():
		return null
	var scene: Node = get_tree().current_scene
	if scene == null:
		return null
	var task: WorldTask = get_node_or_null(task_path) as WorldTask
	if task == null or not scene.is_ancestor_of(task):
		return null
	return task


func _valid_task_request(peer_id: int, task: WorldTask) -> bool:
	if phase != Phase.PREPARE or task == null:
		return false
	if not NetworkManager.players.has(peer_id):
		return false
	var player: PlayerController = _get_player(peer_id)
	if player == null or player.current_health <= 0:
		return false
	var info: Dictionary = NetworkManager.players[peer_id]
	if task.get_owning_class() != str(info.get("class", "")):
		return false
	if not task.is_in_group("interactable"):
		return false
	if player.global_position.distance_to(task.global_position) > MAX_INTERACTION_DISTANCE:
		return false
	var index: int = task.get_task_index()
	return index >= 0 and index < 4 and get_task_count(peer_id, index) < MAX_CHARGES_PER_ABILITY


@rpc("any_peer", "call_remote", "reliable")
func request_begin_task(task_path: NodePath) -> void:
	if not multiplayer.is_server():
		return
	var peer_id: int = multiplayer.get_remote_sender_id()
	if _active_tasks.has(peer_id):
		return
	var task: WorldTask = _get_world_task(task_path)
	if not _valid_task_request(peer_id, task):
		return

	_next_task_serial += 1
	var serial: int = _next_task_serial
	_active_tasks[peer_id] = {"path": task_path, "serial": serial}
	var task_index: int = task.get_task_index()
	var duration: float = clampf(task.get_task_duration(), 0.1, 15.0)
	_complete_task_after_duration(peer_id, task_path, task_index, round_number, serial, duration)


func _complete_task_after_duration(
	peer_id: int, task_path: NodePath, task_index: int,
	started_round: int, serial: int, duration: float
) -> void:
	await get_tree().create_timer(duration).timeout
	var active: Dictionary = _active_tasks.get(peer_id, {})
	if int(active.get("serial", -1)) != serial:
		return
	_active_tasks.erase(peer_id)
	if phase != Phase.PREPARE or round_number != started_round:
		return
	var task: WorldTask = _get_world_task(task_path)
	if not _valid_task_request(peer_id, task):
		return
	if task.get_task_index() != task_index:
		return

	var counts: PackedInt32Array = task_counts.get(
		peer_id, PackedInt32Array([0, 0, 0, 0])
	)
	counts = counts.duplicate()
	counts[task_index] += 1
	sync_task_counts.rpc(peer_id, counts)
	print("[TASK] Peer ", peer_id, " completed task ", task_index + 1,
		" | earned charges: ", counts[task_index], "/", MAX_CHARGES_PER_ABILITY)
