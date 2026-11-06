class_name WorldTask
extends Area2D

const OUTLINE_MATERIAL: ShaderMaterial = preload("res://shaders/task_outline_material.tres")

enum TaskKind {
	CONTACT_PATRON,
	MAKE_SACRIFICE,
	PICK_RUNE,
	CHANNEL_SPELL,
	STIR_CAULDRON,
	COLLECT_POISON_BERRIES,
	PET_BLACK_CAT,
	FIND_CLEAN_FLASK
}

@export var task_kind: TaskKind
@export var config: TaskConfig

@onready var sprite: Sprite2D = $Sprite2D
@onready var audio_player: AudioStreamPlayer2D = $AudioStreamPlayer2D

var _outline_material: ShaderMaterial
var _local_overlap_count: int = 0


func _ready() -> void:
	add_to_group("interactable")
	_apply_config()
	_setup_outline_detection()
	MatchManager.tasks_changed.connect(_on_tasks_changed)
	MatchManager.phase_changed.connect(_on_phase_changed)


func get_owning_class() -> String:
	return "warlock" if int(task_kind) < 4 else "witch"


func get_task_index() -> int:
	return int(task_kind) if int(task_kind) < 4 else int(task_kind) - 4


func get_task_duration() -> float:
	return config.duration if config != null else 2.0


func can_interact(player: PlayerController) -> bool:
	if player == null or player.class_id != get_owning_class():
		return false
	if MatchManager.phase != MatchManager.Phase.PREPARE:
		return false
	if player.state == PlayerController.PlayerState.DEAD or player.state == PlayerController.PlayerState.IN_TASK:
		return false
	# Repeat this task to earn more charges; no need to leave its interaction area.
	return MatchManager.get_task_count(
		player.get_multiplayer_authority(), get_task_index()
	) < MatchManager.MAX_CHARGES_PER_ABILITY


func _apply_config() -> void:
	if config == null or config.sprite == null:
		push_warning("Task %s has no config or sprite" % name)
		return

	sprite.texture = config.sprite
	sprite.scale = Vector2.ONE * config.scale
	sprite.region_enabled = config.sprite_region.size != Vector2.ZERO
	if sprite.region_enabled:
		sprite.region_rect = config.sprite_region
	audio_player.stream = config.interact_sfx


func _setup_outline_detection() -> void:
	sprite.material = null
	monitoring = true
	if collision_mask == 0:
		collision_mask = 1
	area_entered.connect(_on_area_entered)
	area_exited.connect(_on_area_exited)


func _on_area_entered(area: Area2D) -> void:
	if _is_local_player_interaction_area(area):
		_local_overlap_count += 1
		_update_outline()


func _on_area_exited(area: Area2D) -> void:
	if _is_local_player_interaction_area(area):
		_local_overlap_count = maxi(0, _local_overlap_count - 1)
		_update_outline()


func _is_local_player_interaction_area(area: Area2D) -> bool:
	var player: PlayerController = area.get_parent() as PlayerController
	return player != null and player.is_multiplayer_authority()


func _update_outline() -> void:
	var local_player: PlayerController = _get_local_player()
	if _local_overlap_count > 0 and local_player != null and can_interact(local_player):
		if _outline_material == null:
			_outline_material = OUTLINE_MATERIAL.duplicate() as ShaderMaterial
		sprite.material = _outline_material
	else:
		sprite.material = null


func _get_local_player() -> PlayerController:
	for area in get_overlapping_areas():
		var player: PlayerController = area.get_parent() as PlayerController
		if player != null and player.is_multiplayer_authority():
			return player
	return null


func _on_tasks_changed(_peer_id: int, _mask: int) -> void:
	_update_outline()


func _on_phase_changed(_new_phase: int, _round: int) -> void:
	_update_outline()


func interact(player: Node) -> void:
	var controller: PlayerController = player as PlayerController
	if controller == null or not controller.is_multiplayer_authority():
		return
	if not can_interact(controller):
		return

	# Local animation/input lock only. Server grants the task after its own timer.
	MatchManager.request_begin_task.rpc_id(1, get_path())
	controller.start_task(get_task_duration())
	if audio_player.stream != null:
		audio_player.play()
	_update_outline()
