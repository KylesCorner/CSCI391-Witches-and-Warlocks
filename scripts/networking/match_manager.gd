
extends Node

signal phase_changed(new_phase: Phase, round_number: int)
signal timer_changed(seconds_left: int)
signal tasks_changed(peer_id: int, task_mask: int)
signal scores_changed
signal round_ended(round_index: int, winning_class: String, reason: String)
signal match_finished(winning_class: String)

enum Phase { WAITING, PREPARE, FIGHT, FINISHED }

const PREPARE_SECONDS: int = 15
const FIGHT_SECONDS: int = 10
const MAX_ROUNDS: int = 3
const WINS_TO_TAKE_MATCH: int = 2
const MAX_INTERACTION_DISTANCE: float = 45.0
const ABILITY_REQUIREMENTS: Array[int] = [0b0001, 0b0010, 0b0100, 0b1000]
const MAX_CHARGES_PER_ABILITY: int = 5
const TEAMS: Array[String] = ["warlock", "witch"]
const CREDITS_SCENE: String = "res://scenes/credits.tscn"

var phase: Phase = Phase.WAITING
var round_number: int = 0
var seconds_left: int = 0

# These dictionaries are replicated from the dedicated server.
var round_damage: Dictionary = {"warlock": 0, "witch": 0}
var total_damage: Dictionary = {"warlock": 0, "witch": 0}
var round_wins: Dictionary = {"warlock": 0, "witch": 0}
var round_results: Array[Dictionary] = []
var match_winner: String = ""

var task_masks: Dictionary = {}
var task_counts: Dictionary = {}
var _active_tasks: Dictionary = {}
var _next_task_serial: int = 0
var _fight_teams: Dictionary = {}
var round_timer: Timer
var _credits_transition_started: bool = false

# Observe real health reductions without changing PlayerController or spells.
# In the current game, attacks only hurt the opposing player class.
var _tracked_health: Dictionary = {}
var _tracked_instances: Dictionary = {}
var _saved_collision_layers: Dictionary = {}
var _respawn_positions: Dictionary = {}

# Match UI exists above the existing PlayerHUD on client machines only.
var _overlay: CanvasLayer
var _overlay_label: Label
var _overlay_status: Label
var _status_message: String = ""
var _status_seconds: float = 0.0


func _ready() -> void:
	round_timer = Timer.new()
	round_timer.wait_time = 1.0
	round_timer.one_shot = false
	add_child(round_timer)
	round_timer.timeout.connect(_on_timer_timeout)
	NetworkManager.all_players_loaded.connect(_on_all_players_loaded)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)


func _on_peer_disconnected(_peer_id: int) -> void:
	if multiplayer.is_server() and phase == Phase.FIGHT:
		call_deferred("_check_team_wipe")


func _process(delta: float) -> void:
	if _status_seconds > 0.0:
		_status_seconds = maxf(0.0, _status_seconds - delta)
		if _status_seconds == 0.0:
			_status_message = ""
			_refresh_overlay()

	# A movement state RPC can arrive just after a health/death update.
	# Enforce the defeated state until the next preparation respawn.
	if phase == Phase.FIGHT:
		for raw_id in _tracked_instances.keys():
			var player: PlayerController = _get_player(int(raw_id))
			if player != null and player.current_health <= 0 \
					and player.state != PlayerController.PlayerState.DEAD:
				_set_player_alive(player, false)


func _on_all_players_loaded() -> void:
	if not multiplayer.is_server():
		return
	sync_reset_match.rpc()
	call_deferred("_start_if_players_spawned")


@rpc("authority", "call_local", "reliable")
func sync_reset_match() -> void:
	_reset_match()


func _reset_match() -> void:
	round_timer.stop()
	phase = Phase.WAITING
	round_number = 0
	seconds_left = 0
	match_winner = ""
	round_damage = {"warlock": 0, "witch": 0}
	total_damage = {"warlock": 0, "witch": 0}
	round_wins = {"warlock": 0, "witch": 0}
	round_results.clear()
	task_masks.clear()
	task_counts.clear()
	_active_tasks.clear()
	_fight_teams.clear()
	_credits_transition_started = false
	_tracked_health.clear()
	_tracked_instances.clear()
	_saved_collision_layers.clear()
	_respawn_positions.clear()
	_status_message = ""
	_status_seconds = 0.0
	_refresh_overlay()


func _start_if_players_spawned() -> void:
	var scene: Node = get_tree().current_scene
	if scene == null:
		return
	var players: Node = scene.get_node_or_null("WorldView/WorldViewport/World/Players")
	if players == null or players.get_child_count() < NetworkManager.players.size():
		push_warning("Player spawning incomplete; match start skipped")
		return
	_bind_players()
	start_match()


func start_match() -> void:
	if not multiplayer.is_server() or phase != Phase.WAITING:
		return
	round_number = 1
	_start_phase(Phase.PREPARE)


func _start_phase(next_phase: Phase) -> void:
	if not multiplayer.is_server() or phase == Phase.FINISHED:
		return

	_active_tasks.clear()
	if next_phase == Phase.PREPARE:
		round_damage = {"warlock": 0, "witch": 0}
		for peer_id in NetworkManager.players.keys():
			sync_task_counts.rpc(int(peer_id), PackedInt32Array([0, 0, 0, 0]))
		_broadcast_scores()

	if next_phase == Phase.FIGHT:
		_bind_players()
		_fight_teams.clear()
		for peer_id in NetworkManager.players.keys():
			var team: String = str(NetworkManager.players[peer_id].get("class", ""))
			if team in TEAMS:
				_fight_teams[team] = true

	var duration: int = PREPARE_SECONDS if next_phase == Phase.PREPARE else FIGHT_SECONDS
	sync_phase.rpc(int(next_phase), round_number, duration)

	# Tell every client to reuse its existing player nodes (and existing HUD).
	# No player scene or Main.gd modification is required.
	if next_phase == Phase.PREPARE:
		sync_respawn_all.rpc(_make_spawn_map())

	round_timer.start()


func _on_timer_timeout() -> void:
	if not multiplayer.is_server() or phase == Phase.FINISHED:
		return
	if seconds_left > 1:
		sync_phase.rpc(int(phase), round_number, seconds_left - 1)
		return
	if phase == Phase.PREPARE:
		_start_phase(Phase.FIGHT)
	elif phase == Phase.FIGHT:
		_end_round("time limit")


@rpc("authority", "call_local", "reliable")
func sync_phase(new_phase: int, new_round: int, remaining: int) -> void:
	var changed: bool = int(phase) != new_phase or round_number != new_round
	phase = new_phase as Phase
	round_number = new_round
	seconds_left = remaining
	if changed:
		phase_changed.emit(phase, round_number)
		_bind_players()
	timer_changed.emit(seconds_left)
	if changed:
		_refresh_overlay()


# Observe health_changed on both server and clients. This supplies:
# - effective enemy HP damage on the server;
# - the DEAD player state and collision disabling on every peer.
func _bind_players() -> void:
	for raw_id in NetworkManager.players.keys():
		var peer_id: int = int(raw_id)
		var player: PlayerController = _get_player(peer_id)
		if player == null:
			continue
		var instance_id: int = player.get_instance_id()
		if int(_tracked_instances.get(peer_id, -1)) == instance_id:
			continue
		_tracked_instances[peer_id] = instance_id
		_tracked_health[peer_id] = player.current_health
		_saved_collision_layers[peer_id] = player.collision_layer
		player.health_changed.connect(_on_player_health_changed.bind(peer_id))
		if player.current_health <= 0:
			_set_player_alive(player, false)


func _on_player_health_changed(current: int, maximum: int, peer_id: int) -> void:
	var player: PlayerController = _get_player(peer_id)
	var previous: int = int(_tracked_health.get(peer_id, maximum))
	_tracked_health[peer_id] = current

	if multiplayer.is_server():
		if phase == Phase.FIGHT and current < previous and player != null:
			# Friendly fire is already forbidden by AbilityController.
			# Damage to a Warlock was caused by a Witch, and vice versa.
			var attacking_team: String = "witch" if player.class_id == "warlock" else "warlock"
			record_damage(attacking_team, previous - current)
		elif phase == Phase.PREPARE and current < previous and player != null:
			# A projectile from the previous phase cannot kill someone in prep.
			player._set_health_local(maximum)
			player.sync_health.rpc(maximum)
			return

		if phase == Phase.FIGHT and current <= 0 and previous > 0:
			call_deferred("_check_team_wipe")

	if player != null:
		if not multiplayer.is_server() and phase == Phase.PREPARE and current <= 0:
			# Guard against a late, previous-round health packet.
			player._set_health_local(maximum)
			return
		_set_player_alive(player, current > 0)


func _set_player_alive(player: PlayerController, alive: bool) -> void:
	var peer_id: int = player.get_multiplayer_authority()
	var net_sync: PlayerMultiplayerSync = player.get_node_or_null("MultiplayerSync") as PlayerMultiplayerSync
	if alive:
		if player.state == PlayerController.PlayerState.DEAD:
			player.change_state(PlayerController.PlayerState.IDLE)
		player.set_deferred("collision_layer", int(_saved_collision_layers.get(peer_id, 1)))
		if net_sync != null:
			net_sync.set_physics_process(true)
	else:
		player.velocity = Vector2.ZERO
		if player.state != PlayerController.PlayerState.DEAD:
			player.change_state(PlayerController.PlayerState.DEAD)
		player.set_deferred("collision_layer", 0)
		if net_sync != null:
			net_sync.set_physics_process(false)


# ============================================================
# RESPAWN: ONLY PLAYERS WHO DIED
# ============================================================
func _make_spawn_map() -> Dictionary:
	var locations: Array[Vector2] = []
	var scene: Node = get_tree().current_scene
	if scene == null:
		return {}
	for i in range(1, 5):
		var marker: Marker2D = scene.get_node_or_null(
			"WorldView/WorldViewport/World/SpawnPoints/Spawn%d" % i
		) as Marker2D
		if marker != null:
			locations.append(marker.global_position)
	if locations.is_empty():
		push_error("No world spawn points found; cannot respawn players")
		return {}

	var result: Dictionary = {}
	var peer_ids: Array = NetworkManager.players.keys()
	peer_ids.sort()
	for i in range(peer_ids.size()):
		var peer_id: int = int(peer_ids[i])
		var player: PlayerController = _get_player(peer_id)

		# Only respawn defeated players.
		# Survivors keep their position and remaining health.
		if player == null or player.current_health > 0:
			continue

		result[peer_id] = locations[i % locations.size()]
	return result


@rpc("authority", "call_local", "reliable")
func sync_respawn_all(positions: Dictionary) -> void:
	_respawn_positions = positions.duplicate(true)
	_bind_players()
	for raw_id in positions.keys():
		_respawn_peer(int(raw_id), positions[raw_id])


func _respawn_peer(peer_id: int, point: Vector2) -> void:
	var player: PlayerController = _get_player(peer_id)
	if player == null:
		_respawn_when_available(peer_id, point)
		return
	_apply_respawn(player, point)


func _respawn_when_available(peer_id: int, point: Vector2) -> void:
	# Network scene spawns and MatchManager RPCs can arrive in either order.
	for _try in range(30):
		await get_tree().process_frame
		if phase != Phase.PREPARE:
			return
		var player: PlayerController = _get_player(peer_id)
		if player != null:
			_bind_players()
			_apply_respawn(player, point)
			return
	push_warning("Could not find peer %d for respawn" % peer_id)


func _apply_respawn(player: PlayerController, point: Vector2) -> void:
	player.global_position = point
	player.velocity = Vector2.ZERO
	player._task_timer = null
	player._set_health_local(player.max_health)
	_tracked_health[player.get_multiplayer_authority()] = player.max_health
	player.change_state(PlayerController.PlayerState.IDLE)
	_set_player_alive(player, true)

	var net_sync: PlayerMultiplayerSync = player.get_node_or_null("MultiplayerSync") as PlayerMultiplayerSync
	if net_sync != null:
		net_sync.target_position = point
		net_sync.target_velocity = Vector2.ZERO
		net_sync.time_since_update = 0.0
		net_sync.has_received_position = false
		net_sync.send_timer = 0.0
		net_sync.last_state = -1
		net_sync.last_facing_direction = -1


# Only count damage actually subtracted from enemy HP. Never count overkill.
func record_damage(attacking_team: String, effective_damage: int) -> void:
	if not multiplayer.is_server() or phase != Phase.FIGHT:
		return
	if attacking_team not in TEAMS or effective_damage <= 0:
		return
	round_damage[attacking_team] = int(round_damage[attacking_team]) + effective_damage
	total_damage[attacking_team] = int(total_damage[attacking_team]) + effective_damage
	_broadcast_scores()


func _broadcast_scores() -> void:
	sync_scores.rpc(round_damage.duplicate(true), total_damage.duplicate(true), round_wins.duplicate(true))


@rpc("authority", "call_local", "reliable")
func sync_scores(new_round_damage: Dictionary, new_total_damage: Dictionary,
		new_round_wins: Dictionary) -> void:
	round_damage = new_round_damage.duplicate(true)
	total_damage = new_total_damage.duplicate(true)
	round_wins = new_round_wins.duplicate(true)
	scores_changed.emit()
	_refresh_overlay()


# Called after a server-authoritative health change kills a player.
func player_defeated(_peer_id: int) -> void:
	if multiplayer.is_server() and phase == Phase.FIGHT:
		# Deferred: let all hits from the current physics tick settle first.
		call_deferred("_check_team_wipe")


func _check_team_wipe() -> void:
	if not multiplayer.is_server() or phase != Phase.FIGHT:
		return
	# One-team development sessions must not instantly end each fight.
	if not (_fight_teams.has("warlock") and _fight_teams.has("witch")):
		return

	var alive: Dictionary = {"warlock": 0, "witch": 0}
	for peer_id in NetworkManager.players.keys():
		var player: PlayerController = _get_player(int(peer_id))
		if player != null and player.current_health > 0 and player.class_id in TEAMS:
			alive[player.class_id] = int(alive[player.class_id]) + 1

	if int(alive["warlock"]) == 0 and int(alive["witch"]) == 0:
		_end_round("double knockout")
	elif int(alive["warlock"]) == 0:
		_end_round("team elimination", "witch")
	elif int(alive["witch"]) == 0:
		_end_round("team elimination", "warlock")


func _end_round(reason: String, forced_winner: String = "") -> void:
	if not multiplayer.is_server() or phase != Phase.FIGHT:
		return
	round_timer.stop()
	# Temporarily leave FIGHT before any result handlers run.
	phase = Phase.WAITING

	var winner: String = forced_winner
	if winner.is_empty():
		var warlock_damage: int = int(round_damage["warlock"])
		var witch_damage: int = int(round_damage["witch"])
		if warlock_damage > witch_damage:
			winner = "warlock"
		elif witch_damage > warlock_damage:
			winner = "witch"

	if winner in TEAMS:
		round_wins[winner] = int(round_wins[winner]) + 1

	var result: Dictionary = {
		"round": round_number, "winner": winner, "reason": reason,
		"warlock_damage": int(round_damage["warlock"]),
		"witch_damage": int(round_damage["witch"])
	}
	round_results.append(result)
	_broadcast_scores()
	sync_round_result.rpc(round_results.duplicate(true), round_number, winner, reason)

	if int(round_wins["warlock"]) >= WINS_TO_TAKE_MATCH \
			or int(round_wins["witch"]) >= WINS_TO_TAKE_MATCH \
			or round_number >= MAX_ROUNDS:
		_end_match()
	else:
		round_number += 1
		_start_phase(Phase.PREPARE)


@rpc("authority", "call_local", "reliable")
func sync_round_result(results: Array[Dictionary], index: int, winner: String, reason: String) -> void:
	round_results = results.duplicate(true)
	round_ended.emit(index, winner, reason)
	var description: String = "DRAW"
	if winner == "warlock":
		description = "WARLOCKS WIN"
	elif winner == "witch":
		description = "WITCHES WIN"
	_show_status("ROUND %d: %s  (%s)" % [index, description, reason])


func _end_match() -> void:
	if not multiplayer.is_server():
		return
	var warlock_wins: int = int(round_wins["warlock"])
	var witch_wins: int = int(round_wins["witch"])
	var winner: String = ""
	if warlock_wins > witch_wins:
		winner = "warlock"
	elif witch_wins > warlock_wins:
		winner = "witch"
	elif int(total_damage["warlock"]) > int(total_damage["witch"]):
		winner = "warlock"
	elif int(total_damage["witch"]) > int(total_damage["warlock"]):
		winner = "witch"

	sync_phase.rpc(int(Phase.FINISHED), round_number, 0)
	sync_match_complete.rpc(winner)


@rpc("authority", "call_local", "reliable")
func sync_match_complete(winner: String) -> void:
	match_winner = winner
	match_finished.emit(winner)
	var description: String = "DRAW"
	if winner == "warlock":
		description = "WARLOCKS WIN"
	elif winner == "witch":
		description = "WITCHES WIN"
	_show_status("MATCH COMPLETE: %s" % description)
	if multiplayer.is_server() or _credits_transition_started:
		return
	_credits_transition_started = true
	_open_credits_after_delay()


func _open_credits_after_delay() -> void:
	# Briefly show the match result on the existing HUD before the credits.
	await get_tree().create_timer(3.0).timeout
	if is_inside_tree() and phase == Phase.FINISHED:
		if _overlay != null:
			_overlay.visible = false
		get_tree().change_scene_to_file(CREDITS_SCENE)


# An independent scoreboard so the existing PlayerHUD scene and script stay intact.
func _ensure_overlay() -> void:
	if multiplayer.is_server() or _overlay != null:
		return
	_overlay = CanvasLayer.new()
	_overlay.layer = 8
	add_child(_overlay)

	var root: Control = Control.new()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.add_child(root)

	var panel: PanelContainer = PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	panel.offset_left = -350.0
	panel.offset_right = 350.0
	panel.offset_top = 52.0
	panel.offset_bottom = 151.0
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color(0.065, 0.055, 0.11, 0.88)
	style.border_color = Color(0.53, 0.40, 0.76, 0.9)
	style.set_border_width_all(1)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(8.0)
	panel.add_theme_stylebox_override("panel", style)
	root.add_child(panel)

	var stack: VBoxContainer = VBoxContainer.new()
	stack.alignment = BoxContainer.ALIGNMENT_CENTER
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(stack)
	_overlay_label = Label.new()
	_overlay_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_overlay_label.add_theme_font_size_override("font_size", 15)
	_overlay_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_child(_overlay_label)
	_overlay_status = Label.new()
	_overlay_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_overlay_status.add_theme_font_size_override("font_size", 17)
	_overlay_status.add_theme_color_override("font_color", Color(1.0, 0.83, 0.45))
	_overlay_status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_child(_overlay_status)


func _show_status(message: String) -> void:
	_status_message = message
	_status_seconds = 3.0
	_refresh_overlay()


func _refresh_overlay() -> void:
	if multiplayer.is_server():
		return
	_ensure_overlay()
	if _overlay == null:
		return
	var show: bool = phase == Phase.FIGHT or phase == Phase.FINISHED or _status_seconds > 0.0
	_overlay.visible = show
	if not show:
		return
	_overlay_label.text = "ROUND %d/%d    |    WINS  Warlocks %d : %d Witches\nROUND DAMAGE  Warlocks %d : %d Witches\nTOTAL DAMAGE    Warlocks %d : %d Witches" % [
		round_number, MAX_ROUNDS,
		int(round_wins.get("warlock", 0)), int(round_wins.get("witch", 0)),
		int(round_damage.get("warlock", 0)), int(round_damage.get("witch", 0)),
		int(total_damage.get("warlock", 0)), int(total_damage.get("witch", 0))
	]
	_overlay_status.text = _status_message


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
		started_round: int, serial: int, duration: float) -> void:
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
