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

@export var task_durations: Array[float] = [
   2, # CONTACT_PATRON
   2, # MAKE_SACRIFICE
   2, # PICK_RUNE
   2, # CHANNEL_SPELL
   2, # STIR_CAULDRON
   2, # COLLECT_POISON_BERRIES
   2, # PET_BLACK_CAT
   2, # FIND_CLEAN_FLASK
   2, # OH_GOD_OH_FUCK
]

@export var task_kind: TaskKind
# sprites should be one per task, ordered as the task kind enum shows
@export var sprites: Array[Texture2D] = []
# optional region per sprite; Rect2() (empty size) means no region
@export var sprite_regions: Array[Rect2] = [
	Rect2(0, 0, 100, 125), # CONTACT_PATRON
]

@onready var sprite = $Sprite2D

func _ready() -> void:
	add_to_group("interactable")

	match task_kind:
		TaskKind.CONTACT_PATRON:
			_set_sprite(0)
		TaskKind.MAKE_SACRIFICE:
			_set_sprite(1)
		TaskKind.PICK_RUNE:
			_set_sprite(2)
		TaskKind.CHANNEL_SPELL:
			_set_sprite(3)
		TaskKind.STIR_CAULDRON:
			_set_sprite(4)
		TaskKind.COLLECT_POISON_BERRIES:
			_set_sprite(5)
		TaskKind.PET_BLACK_CAT:
			_set_sprite(6)
		TaskKind.FIND_CLEAN_FLASK:
			_set_sprite(7)
		TaskKind.OH_GOD_OH_FUCK:
			_set_sprite(8)


func _set_sprite(index: int) -> void:
	if index < 0 or index >= sprites.size():
		push_warning("Task %s is missing sprites[%d]" % [TaskKind.keys()[task_kind], index])
		return

	sprite.texture = sprites[index]

	if index < sprite_regions.size() and sprite_regions[index].size != Vector2.ZERO:
		sprite.region_enabled = true
		sprite.region_rect = sprite_regions[index]
	else:
		sprite.region_enabled = false


func interact(player: Node) -> void:
	if player is not PlayerController:
		return

	var player_controller := player as PlayerController

	# Only the locally controlled player starts their own task state.
	if not player_controller.is_multiplayer_authority():
		return

	if player_controller.state == PlayerController.PlayerState.IN_TASK:
		return

	var index := int(task_kind)
	if index < 0 or index >= task_durations.size():
		push_warning("Task %s is missing task_durations[%d]" % [TaskKind.keys()[task_kind], index])
		return

	player_controller.start_task(task_durations[index])
