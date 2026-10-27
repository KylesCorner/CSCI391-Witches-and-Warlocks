
class_name TaskStation
extends Area2D


# ============================================================
# SETTINGS
# ============================================================

@export_range(0, 3) var task_index: int = 0

@export_enum("warlock", "witch")
var owning_class: String = "warlock"

func _ready() -> void:
	add_to_group("interactable")

# ============================================================
# INTERACTION
# ============================================================

func interact(player: PlayerController) -> void:

	# Only the locally controlled player
	# can initiate an interaction.
	if not player.is_multiplayer_authority():
		return

	# Clients request task completion.
	if multiplayer.is_server():
		return

	# Tasks are only available during Prepare.
	if MatchManager.phase != MatchManager.Phase.PREPARE:
		print("Cannot complete tasks outside Prepare phase.")
		return

	# Check class locally for immediate feedback.
	if player.class_id != owning_class:
		print("This task belongs to the other class.")
		return

	print(
		"Requesting task ",
		task_index + 1,
		" at ",
		get_path()
	)

	# The server performs final validation.
	MatchManager.request_complete_task.rpc_id(
		1,
		get_path()
	)
