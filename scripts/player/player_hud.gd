class_name PlayerHUD
extends CanvasLayer

const ABILITY_NAMES: Dictionary = {
	"warlock": ["Long Range", "AOE", "Summon Husk", "Invisibility"],
	"witch": ["Long Range", "AOE", "Murder Cat", "Invisibility"]
}
const TASK_NAMES: Dictionary = {
	"warlock": ["Contact patron", "Make sacrifice", "Pick a rune", "Channel a spell"],
	"witch": ["Stir cauldron", "Collect poison berries", "Pet the black cat", "Find a clean flask"]
}
const ABILITY_REQUIREMENT_TEXT: Array[String] = [
	"Repeat Task 1", "Repeat Task 2", "Repeat Task 3", "Repeat Task 4"
]
const COLOR_WARLOCK: Color = Color(0.65, 0.81, 1.0)
const COLOR_WITCH: Color = Color(0.90, 0.66, 1.0)
const COLOR_COMPLETE: Color = Color(0.57, 0.95, 0.65)
const COLOR_LOCKED: Color = Color(0.65, 0.66, 0.71)

@onready var player_name_label: Label = $HUDRoot/MarginContainer/Layout/TopRow/PlayerPanel/InfoVBox/PlayerName
@onready var class_label: Label = $HUDRoot/MarginContainer/Layout/TopRow/PlayerPanel/InfoVBox/ClassName
@onready var health_bar: ProgressBar = $HUDRoot/MarginContainer/Layout/TopRow/PlayerPanel/InfoVBox/HealthBar
@onready var health_text: Label = $HUDRoot/MarginContainer/Layout/TopRow/PlayerPanel/InfoVBox/HealthText
@onready var task_title: Label = $HUDRoot/MarginContainer/Layout/TopRow/TaskPanel/TasksVBox/TaskTitle
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

var controlled_player: PlayerController
var ability_controller: AbilityController
var _peer_id: int = -1
var _last_task_counts: PackedInt32Array = PackedInt32Array([0, 0, 0, 0])
var _prompt_elapsed: float = 0.0
var _phase_label: Label
var _prompt_label: Label
var _toast_label: Label
var _toast_timer: Timer


func _ready() -> void:
	_create_overlay_labels()


func _create_overlay_labels() -> void:
	var root: Control = $HUDRoot
	_phase_label = Label.new()
	_phase_label.name = "PhaseStatus"
	_phase_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_phase_label.offset_left = -210.0
	_phase_label.offset_right = 210.0
	_phase_label.offset_top = 12.0
	_phase_label.offset_bottom = 44.0
	_phase_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_phase_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_phase_label.add_theme_font_size_override("font_size", 20)
	root.add_child(_phase_label)

	_prompt_label = Label.new()
	_prompt_label.name = "InteractionPrompt"
	_prompt_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_prompt_label.offset_left = -250.0
	_prompt_label.offset_right = 250.0
	_prompt_label.offset_top = -112.0
	_prompt_label.offset_bottom = -82.0
	_prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_prompt_label.add_theme_font_size_override("font_size", 17)
	root.add_child(_prompt_label)

	_toast_label = Label.new()
	_toast_label.name = "TaskToast"
	_toast_label.set_anchors_preset(Control.PRESET_CENTER)
	_toast_label.offset_left = -250.0
	_toast_label.offset_right = 250.0
	_toast_label.offset_top = -70.0
	_toast_label.offset_bottom = -30.0
	_toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast_label.add_theme_font_size_override("font_size", 20)
	root.add_child(_toast_label)

	_toast_timer = Timer.new()
	_toast_timer.one_shot = true
	_toast_timer.timeout.connect(func() -> void: _toast_label.text = "")
	add_child(_toast_timer)


func bind_player(new_player: PlayerController) -> void:
	if not is_node_ready() or controlled_player != null:
		push_error("PlayerHUD must be ready and unbound before bind_player().")
		return
	controlled_player = new_player
	_peer_id = multiplayer.get_unique_id()
	ability_controller = new_player.get_node_or_null("AbilityController") as AbilityController
	if ability_controller == null:
		push_error("PlayerHUD cannot find its player's AbilityController.")
		return

	player_name_label.text = new_player.display_name
	class_label.text = new_player.class_id.capitalize()
	var accent: Color = COLOR_WITCH if new_player.class_id == "witch" else COLOR_WARLOCK
	class_label.add_theme_color_override("font_color", accent)
	task_title.add_theme_color_override("font_color", accent)

	for slot in range(ability_slots.size()):
		ability_slots[slot].focus_mode = Control.FOCUS_NONE
		ability_slots[slot].pressed.connect(_on_ability_pressed.bind(slot))

	new_player.health_changed.connect(_on_health_changed)
	MatchManager.tasks_changed.connect(_on_tasks_changed)
	MatchManager.phase_changed.connect(_on_phase_changed)
	MatchManager.timer_changed.connect(_on_timer_changed)
	ability_controller.ability_state_changed.connect(_refresh_abilities)
	ability_controller.ability_error.connect(_show_toast)

	_on_health_changed(new_player.current_health, new_player.max_health)
	_on_phase_changed(MatchManager.phase, MatchManager.round_number)
	_on_timer_changed(MatchManager.seconds_left)
	_refresh_tasks(int(MatchManager.task_masks.get(_peer_id, 0)))
	for index in range(4):
		_last_task_counts[index] = MatchManager.get_task_count(_peer_id, index)
	_refresh_abilities()


func _on_health_changed(current: int, maximum: int) -> void:
	health_bar.max_value = maximum
	health_bar.value = current
	health_text.text = "%d / %d HP" % [current, maximum]


func _on_tasks_changed(peer_id: int, mask: int) -> void:
	if peer_id != _peer_id:
		return
	_refresh_tasks(mask)
	_refresh_abilities()
	if controlled_player == null:
		return
	for index in range(4):
		var count: int = MatchManager.get_task_count(_peer_id, index)
		if count > _last_task_counts[index]:
			var names: Array = ABILITY_NAMES[controlled_player.class_id]
			_show_toast("%s: %d/%d charges" % [
				str(names[index]), count, MatchManager.MAX_CHARGES_PER_ABILITY
			])
		_last_task_counts[index] = count


func _refresh_tasks(_mask: int) -> void:
	if controlled_player == null:
		return
	var names: Array = TASK_NAMES[controlled_player.class_id]
	for index in range(4):
		var count: int = MatchManager.get_task_count(_peer_id, index)
		var capped: bool = count >= MatchManager.MAX_CHARGES_PER_ABILITY
		task_labels[index].text = "[%d/%d] %s" % [
			count, MatchManager.MAX_CHARGES_PER_ABILITY, str(names[index])
		]
		task_labels[index].add_theme_color_override(
			"font_color", COLOR_COMPLETE if capped else Color.WHITE
		)


func _refresh_abilities() -> void:
	if controlled_player == null or ability_controller == null:
		return
	var accent: Color = COLOR_WITCH if controlled_player.class_id == "witch" else COLOR_WARLOCK
	var in_fight: bool = MatchManager.phase == MatchManager.Phase.FIGHT
	var names: Array = ABILITY_NAMES[controlled_player.class_id]

	for index in range(4):
		var earned: int = MatchManager.get_ability_count(_peer_id, index)
		var remaining: int = ability_controller.get_remaining_charges(index)
		var implemented: bool = true  # Including Summon Husk / Murder Cat (slot 3).
		var can_cast: bool = remaining > 0 and in_fight and implemented
		if AbilityController.DEV_MODE:
			can_cast = implemented
		ability_slots[index].disabled = not can_cast

		var state: String
		if AbilityController.DEV_MODE:
			state = "DEV MODE"
		elif earned == 0:
			state = "LOCKED"
		elif remaining == 0:
			state = "EMPTY"
		elif not in_fight:
			state = "%d STORED" % remaining
		else:
			state = "%d CHARGES" % remaining

		ability_slots[index].text = "%d: %s\n%s" % [index + 1, str(names[index]), state]
		ability_slots[index].tooltip_text = "%s (%s)" % [
			str(names[index]), ABILITY_REQUIREMENT_TEXT[index]
		]
		ability_slots[index].add_theme_color_override(
			"font_color", accent if can_cast else COLOR_LOCKED
		)


func _on_ability_pressed(index: int) -> void:
	if ability_controller != null:
		ability_controller.try_cast(index)


func _on_phase_changed(new_phase: int, round_num: int) -> void:
	var phase_name: String = "WAITING"
	match new_phase:
		MatchManager.Phase.PREPARE:
			phase_name = "PREPARE — COMPLETE TASKS"
		MatchManager.Phase.FIGHT:
			phase_name = "FIGHT — CAST ABILITIES"
	_phase_label.text = "ROUND %d | %s" % [round_num, phase_name]
	_refresh_abilities()


func _on_timer_changed(remaining: int) -> void:
	var mins: int = maxi(remaining, 0) / 60
	var secs: int = maxi(remaining, 0) % 60
	var prefix: String = _phase_label.text.split(" | ")[0] if _phase_label != null else ""
	var phase_text: String = "WAITING"
	if MatchManager.phase == MatchManager.Phase.PREPARE:
		phase_text = "PREPARE"
	elif MatchManager.phase == MatchManager.Phase.FIGHT:
		phase_text = "FIGHT"
	_phase_label.text = "%s | %s  %02d:%02d" % [prefix, phase_text, mins, secs]


func _show_toast(message: String) -> void:
	_toast_label.text = message
	_toast_timer.start(2.5)


func _process(delta: float) -> void:
	if controlled_player == null or not is_instance_valid(controlled_player):
		return
	_prompt_elapsed += delta
	if _prompt_elapsed < 0.15:
		return
	_prompt_elapsed = 0.0
	var target: Node = controlled_player._get_closest_interactable()
	if target == null or not target.has_method("can_interact"):
		_prompt_label.text = ""
		return
	if not target.can_interact(controlled_player):
		_prompt_label.text = ""
		return
	var display: String = str(target.name)
	if target is WorldTask:
		var task: WorldTask = target as WorldTask
		if task.config != null and not task.config.name.is_empty():
			display = task.config.name
	_prompt_label.text = "[E] " + display
