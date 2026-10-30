extends Area2D

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

func _ready() -> void:
	add_to_group("interactable")
	_apply_config()

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
