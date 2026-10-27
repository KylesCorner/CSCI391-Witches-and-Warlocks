
class_name PlayerHUD
extends CanvasLayer


# ============================================================
# CLASS-SPECIFIC CONTENT
# ============================================================

const ABILITY_NAMES = {
	"warlock": [
		"AWP",
		"Fireball",
		"Summon Husk",
        "Invisibility"
	],
	"witch": [
		"Poison",
		"Murder Cat",
		"Trap Potion",
        "Invisibility"
	]
}

const TASK_NAMES = {
	"warlock": [
		"Contact patron",
		"Make sacrifice",
		"Pick a rune",
        "Channel a spell"
	],
	"witch": [
		"Stir cauldron",
		"Collect poison berries",
		"Pet the black cat",
        "Find a clean flask"
	]
}


# ============================================================
# PLAYER INFORMATION
# ============================================================

@onready var player_name_label: Label = \
	$HUDRoot/MarginContainer/Layout/TopRow/PlayerPanel/InfoVBox/PlayerName

@onready var class_label: Label = \
	$HUDRoot/MarginContainer/Layout/TopRow/PlayerPanel/InfoVBox/ClassName

@onready var health_bar: ProgressBar = \
	$HUDRoot/MarginContainer/Layout/TopRow/PlayerPanel/InfoVBox/HealthBar

@onready var health_text: Label = \
	$HUDRoot/MarginContainer/Layout/TopRow/PlayerPanel/InfoVBox/HealthText


# ============================================================
# TASK AND ABILITY REFERENCES
# ============================================================

@onready var task_labels: Array[Label] = [
	$HUDRoot/MarginContainer/Layout/TopRow/TaskPanel/TasksVBox/Task1,
	$HUDRoot/MarginContainer/Layout/TopRow/TaskPanel/TasksVBox/Task2,
	$HUDRoot/MarginContainer/Layout/TopRow/TaskPanel/TasksVBox/Task3,
	$HUDRoot/MarginContainer/Layout/TopRow/TaskPanel/TasksVBox/Task4
]

@onready var ability_slots: Array[Button] = [
	$HUDRoot/MarginContainer/Layout/BottomRow/AbilityPanel/AbilitySlots/Slot1,
	$HUDRoot/MarginContainer/Layout/BottomRow/AbilityPanel/AbilitySlots/Slot2,
	$HUDRoot/MarginContainer/Layout/BottomRow/AbilityPanel/AbilitySlots/Slot3,
	$HUDRoot/MarginContainer/Layout/BottomRow/AbilityPanel/AbilitySlots/Slot4
]


# ============================================================
# CONTROLLED PLAYER
# ============================================================

var controlled_player: PlayerController


func bind_player(new_player: PlayerController) -> void:
	if not is_node_ready():
		push_error("PlayerHUD must be ready before binding.")
		return

	if controlled_player != null:
		push_error("PlayerHUD is already bound to a player.")
		return

	controlled_player = new_player

	# Initial player information.
	player_name_label.text = controlled_player.display_name
	class_label.text = controlled_player.class_id.capitalize()

	# Populate the class-specific UI.
	_setup_class_ui(controlled_player.class_id)

	# Subscribe to changes instead of polling.
	controlled_player.health_changed.connect(
		_on_health_changed
	)

	# Set initial health immediately.
	_on_health_changed(
		controlled_player.current_health,
		controlled_player.max_health
	)


# ============================================================
# HEALTH
# ============================================================

func _on_health_changed(
	current: int,
	maximum: int
) -> void:
	health_bar.max_value = maximum
	health_bar.value = current

	health_text.text = "%d / %d HP" % [
		current,
		maximum
	]


# ============================================================
# CLASS UI
# ============================================================

func _setup_class_ui(selected_class: String) -> void:
	if not ABILITY_NAMES.has(selected_class):
		push_error("Unknown HUD class: " + selected_class)
		return

	var abilities: Array = ABILITY_NAMES[selected_class]
	var tasks: Array = TASK_NAMES[selected_class]

	for i in range(4):
		ability_slots[i].text = "%d - %s" % [
			i + 1,
			abilities[i]
		]

		# Abilities are placeholders until gameplay exists.
		ability_slots[i].disabled = true

		task_labels[i].text = "[ ] " + tasks[i]


# ============================================================
# TASK DISPLAY
# ============================================================

func set_task_complete(
	task_index: int,
	completed: bool
) -> void:
	if controlled_player == null:
		return

	if task_index < 0 or task_index >= 4:
		return

	var tasks: Array = TASK_NAMES[
		controlled_player.class_id
	]

	var marker := "[x] " if completed else "[ ] "

	task_labels[task_index].text = (
		marker + tasks[task_index]
	)
