extends Node


const LOBBY_SCENE: String = \
	"res://scenes/lobby.tscn"


func _ready() -> void:

	print("======================================")
	print("BOOTSTRAP STARTED")
	print("Dedicated feature: ",
		OS.has_feature("dedicated_server")
	)
	print("User args: ",
		OS.get_cmdline_user_args()
	)
	print("======================================")


	var args := \
		OS.get_cmdline_user_args()


	var is_dedicated := \
		OS.has_feature(
			"dedicated_server"
		) \
		or "--dedicated" in args


	if is_dedicated:

		print("DEDICATED SERVER MODE DETECTED")

		var error := \
			NetworkManager.start_dedicated_server()


		if error != OK:

			push_error(
				"Dedicated server failed: %s"
				% error
			)

			get_tree().quit(1)

			return


		print(
			"Dedicated server startup successful."
		)

		return


	print("CLIENT MODE DETECTED")

	call_deferred(
		"_load_lobby"
	)


func _load_lobby() -> void:

	var error := \
		get_tree().change_scene_to_file(
			LOBBY_SCENE
		)


	if error != OK:

		push_error(
			"Could not load lobby: %s"
			% error
		)
