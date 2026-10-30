extends Area2D

const OUTLINE_MATERIAL := preload("res://shaders/task_outline_material.tres")

enum TaskKind {
	CONTACT_PATRON,
	MAKE_SACRIFICE,
	PICK_RUNE,
	CHANNEL_SPELL,
	STIR_CAULDRON,
	COLLECT_POISON_BERRIES,
	PET_BLACK_CAT,
	FIND_CLEAN_FLASK,
	OH_GOD_OH_FUCK
}

@export var task_kind: TaskKind
@export var config: TaskConfig

@onready var sprite: Sprite2D = $Sprite2D

var _outline_material: ShaderMaterial
var _local_overlap_count: int = 0

func _ready() -> void:
	add_to_group("interactable")
	_apply_config()
	_setup_outline_detection()

func _apply_config() -> void:
	if config == null or config.sprite == null:
		push_warning("Task %s is missing a config or sprite" % TaskKind.keys()[task_kind])
		return

	sprite.texture = config.sprite
	sprite.scale = Vector2(config.scale, config.scale)

	if config.sprite_region.size != Vector2.ZERO:
		sprite.region_enabled = true
		sprite.region_rect = config.sprite_region
	else:
		sprite.region_enabled = false

func _setup_outline_detection() -> void:
	# Outline is purely visual/local — never share the material instance.
	sprite.material = null
	monitoring = true
	if collision_mask == 0:
		collision_mask = 1

	area_entered.connect(_on_area_entered)
	area_exited.connect(_on_area_exited)

func _on_area_entered(area: Area2D) -> void:
	if not _is_local_player_interaction_area(area):
		return
	_local_overlap_count += 1
	_update_outline()

func _on_area_exited(area: Area2D) -> void:
	if not _is_local_player_interaction_area(area):
		return
	_local_overlap_count = maxi(_local_overlap_count - 1, 0)
	_update_outline()

func _is_local_player_interaction_area(area: Area2D) -> bool:
	var parent := area.get_parent()
	if parent is not PlayerController:
		return false
	return (parent as PlayerController).is_multiplayer_authority()

func _update_outline() -> void:
	if _local_overlap_count > 0:
		if _outline_material == null:
			_outline_material = OUTLINE_MATERIAL.duplicate() as ShaderMaterial
		sprite.material = _outline_material
	else:
		sprite.material = null

func interact(player: Node) -> void:
	if player is not PlayerController:
		return

	var player_controller := player as PlayerController
	if not player_controller.is_multiplayer_authority():
		return
	if player_controller.state == PlayerController.PlayerState.IN_TASK:
		return
	if config == null:
		return

	player_controller.start_task(config.duration)
