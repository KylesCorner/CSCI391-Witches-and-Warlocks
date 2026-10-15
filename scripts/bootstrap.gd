extends Node


const LOBBY_SCENE: String = \
	"res://scenes/lobby.tscn"


func _ready() -> void:

	var args := \
		OS.get_cmdline_user_args()


	#
	# ========================================================
	# DEDICATED SERVER
	# ========================================================
	#

	if "--dedicated" in args:

		print(
			"Starting dedicated server..."
		)


		var error := \
			NetworkManager.start_dedicated_server()


		if error != OK:

			push_error(
				"Dedicated server failed to start."
			)

			get_tree().quit(1)


		#
		# Dedicated server stays in the
		# Bootstrap scene until the server
		# starts the actual game.
		#
		return


	#
	# ========================================================
	# NORMAL CLIENT
	# ========================================================
	#

	#
	# We cannot change scenes immediately
	# inside _ready(), because Godot is
	# still building the scene tree.
	#
	call_deferred(
		"_load_lobby"
	)


#
# ============================================================
# LOAD CLIENT LOBBY
# ============================================================
#

func _load_lobby() -> void:

	var error := \
		get_tree().change_scene_to_file(
			LOBBY_SCENE
		)


	if error != OK:

		push_error(
			"Could not load lobby scene: %s"
			% error
		)
