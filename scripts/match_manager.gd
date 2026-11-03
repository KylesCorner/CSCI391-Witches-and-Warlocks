
extends Node

signal phase_changed(new_phase: Phase, round_number: int)
signal timer_changed(seconds_left: int)
signal tasks_changed(peer_id: int, task_mask: int)

enum Phase {
	WAITING,
	PREPARE,
	FIGHT
}

const PREPARE_SECONDS := 90
const FIGHT_SECONDS := 60

var phase: Phase = Phase.WAITING
var round_number: int = 0
var seconds_left: int = 0

# Four tasks are represented by four bits.
# Example: 0101 means tasks 1 and 3 are complete.
var task_masks: Dictionary = {}

var round_timer: Timer


func _ready() -> void:
	round_timer = Timer.new()
	round_timer.wait_time = 1.0
	round_timer.one_shot = false

	add_child(round_timer)

	round_timer.timeout.connect(_on_timer_timeout)


# Called once by the dedicated server.
func start_match() -> void:
	if not multiplayer.is_server():
		return

	if phase != Phase.WAITING:
		return

	round_number = 1
	_start_phase(Phase.PREPARE)


func _start_phase(next_phase: Phase) -> void:
	if not multiplayer.is_server():
		return

	if next_phase == Phase.PREPARE:
		# Reset each player's task progress.
		for peer_id in NetworkManager.players.keys():
			sync_tasks.rpc(int(peer_id), 0)

	var duration := (
		PREPARE_SECONDS
		if next_phase == Phase.PREPARE
		else FIGHT_SECONDS
	)

	sync_phase.rpc(
		int(next_phase),
		round_number,
		duration
	)

	round_timer.start()


func _on_timer_timeout() -> void:
	if not multiplayer.is_server():
		return

	seconds_left -= 1

	if seconds_left <= 0:
		if phase == Phase.PREPARE:
			_start_phase(Phase.FIGHT)
		else:
			round_number += 1
			_start_phase(Phase.PREPARE)
		return

	sync_phase.rpc(
		int(phase),
		round_number,
		seconds_left
	)


# Server broadcasts phase and timer.
@rpc("authority", "call_local", "reliable")
func sync_phase(
	new_phase: int,
	new_round: int,
	remaining: int
) -> void:

	var changed := (
		int(phase) != new_phase
		or round_number != new_round
	)

	phase = new_phase as Phase
	round_number = new_round
	seconds_left = remaining

	if changed:
		phase_changed.emit(phase, round_number)

	timer_changed.emit(seconds_left)


# Server broadcasts completed tasks.
@rpc("authority", "call_local", "reliable")
func sync_tasks(peer_id: int, mask: int) -> void:
	task_masks[peer_id] = mask
	tasks_changed.emit(peer_id, mask)


func has_ability(
	peer_id: int,
	ability_index: int
) -> bool:

	if ability_index < 0 or ability_index >= 4:
		return false

	var mask := int(task_masks.get(peer_id, 0))

	return (mask & (1 << ability_index)) != 0



# ============================================================
# COMPLETE TASK REQUEST
# ============================================================

@rpc("any_peer", "call_remote", "reliable")
func request_complete_task(
	station_path: NodePath
) -> void:
	print("Requesting complete task")

	# Only the dedicated server processes tasks.
	if not multiplayer.is_server():
		return

	# Tasks are only available during preparation.
	if phase != Phase.PREPARE:
		return

	var peer_id: int = multiplayer.get_remote_sender_id()

	if not NetworkManager.players.has(peer_id):
		return

	var scene: Node = get_tree().current_scene

	if scene == null:
		return

	# Locate the requesting player's character.
	var player: PlayerController = \
		scene.get_node_or_null(
			NodePath("Players/" + str(peer_id))
		) as PlayerController

	# Resolve the station's absolute scene-tree path.
	var station: TaskStation = \
		get_node_or_null(station_path) as TaskStation

	if player == null or station == null:
		return

	# Station must belong to the active game scene.
	if not scene.is_ancestor_of(station):
		return

	if not station.is_in_group("interactable"):
		return

	# Verify class ownership.
	var selected_class: String = str(
		NetworkManager.players[peer_id].get(
			"class",
            ""
		)
	)

	if station.owning_class != selected_class:
		return

	# Validate interaction distance.
	if player.global_position.distance_to(
		station.global_position
	) > 45.0:
		return

	var index: int = station.task_index

	if index < 0 or index >= 4:
		return

	var mask: int = int(
		task_masks.get(peer_id, 0)
	)

	# Ignore tasks already completed.
	if (mask & (1 << index)) != 0:
		return

	# Complete the task and unlock its ability.
	mask |= (1 << index)

	sync_tasks.rpc(peer_id, mask)
	
	print(
	"Task completed! Player: ",
	peer_id,
	" Task: ",
	index + 1,
	" Mask: ",
	mask
	)
