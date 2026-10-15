extends Control


#
# ============================================================
# NODES
# ============================================================
#

@onready var player_name: LineEdit = \
	$Panel/VBoxContainer/PlayerName


@onready var address: LineEdit = \
	$Panel/VBoxContainer/IPAddress


@onready var join_button: Button = \
	$Panel/VBoxContainer/JoinButton


@onready var status_label: Label = \
	$Panel/VBoxContainer/StatusLabel


@onready var player_list: VBoxContainer = \
	$Panel/VBoxContainer/PlayerList


#
# NOTE:
# Your scene currently calls this node HBoxContainer2.
#
@onready var warlock_button: Button = \
	$Panel/VBoxContainer/HBoxContainer2/WarlockButton


@onready var witch_button: Button = \
	$Panel/VBoxContainer/HBoxContainer2/WitchButton


@onready var ready_button: Button = \
	$Panel/VBoxContainer/ReadyButton


@onready var start_button: Button = \
	$Panel/VBoxContainer/StartButton


#
# ============================================================
# STATE
# ============================================================
#

var local_ready: bool = false


#
# ============================================================
# READY
# ============================================================
#

func _ready() -> void:

	#
	# Network signals.
	#
	NetworkManager.lobby_updated.connect(
		_update_lobby
	)

	NetworkManager.connected_to_server.connect(
		_on_connected_to_server
	)

	NetworkManager.connection_failed.connect(
		_on_connection_failed
	)

	NetworkManager.server_disconnected.connect(
		_on_server_disconnected
	)


	#
	# Button signals.
	#
	join_button.pressed.connect(
		_on_join_button_pressed
	)

	warlock_button.pressed.connect(
		_on_warlock_button_pressed
	)

	witch_button.pressed.connect(
		_on_witch_button_pressed
	)

	ready_button.pressed.connect(
		_on_ready_button_pressed
	)

	start_button.pressed.connect(
		_on_start_button_pressed
	)


	#
	# Initial UI.
	#
	status_label.text = \
		"Not connected"

	start_button.visible = false


#
# ============================================================
# JOIN
# ============================================================
#

func _on_join_button_pressed() -> void:

	status_label.text = \
		"Connecting..."


	var error := \
		NetworkManager.join_game(
			address.text,
			player_name.text
		)


	if error != OK:

		status_label.text = \
			"Could not connect"


func _on_connected_to_server() -> void:

	status_label.text = \
		"Connected"

	local_ready = false

	ready_button.text = \
		"Ready"


func _on_connection_failed() -> void:

	status_label.text = \
		"Connection failed"


func _on_server_disconnected() -> void:

	status_label.text = \
		"Server disconnected"

	start_button.visible = false


#
# ============================================================
# CLASS SELECTION
# ============================================================
#

func _on_warlock_button_pressed() -> void:

	NetworkManager.choose_class(
		"warlock"
	)

	status_label.text = \
		"Selected Warlock"


func _on_witch_button_pressed() -> void:

	NetworkManager.choose_class(
		"witch"
	)

	status_label.text = \
		"Selected Witch"


#
# ============================================================
# READY
# ============================================================
#

func _on_ready_button_pressed() -> void:

	local_ready = \
		not local_ready


	NetworkManager.set_player_ready(
		local_ready
	)


	if local_ready:

		ready_button.text = \
			"Not Ready"

	else:

		ready_button.text = \
			"Ready"


#
# ============================================================
# START
# ============================================================
#

func _on_start_button_pressed() -> void:

	NetworkManager.request_start_game()


#
# ============================================================
# LOBBY DISPLAY
# ============================================================
#

func _update_lobby() -> void:

	#
	# Remove old player rows.
	#
	for child in player_list.get_children():

		child.queue_free()


	#
	# Sort peers so the player list doesn't
	# jump around every update.
	#
	var peer_ids := \
		NetworkManager.players.keys()

	peer_ids.sort()


	#
	# Create one row per player.
	#
	for peer_id in peer_ids:

		var info: Dictionary = \
			NetworkManager.players[peer_id]


		var display_name := str(
			info.get(
				"name",
				"Player"
			)
		)


		var selected_class := str(
			info.get(
				"class",
				"warlock"
			)
		)


		var is_ready := bool(
			info.get(
				"ready",
				false
			)
		)


		var ready_text := \
			"READY" \
			if is_ready \
			else "NOT READY"


		var leader_text := ""


		if int(peer_id) == \
				NetworkManager.lobby_leader_id:

			leader_text = \
				" [LEADER]"


		var row := \
			Label.new()


		row.text = \
			"%s%s | %s | %s" % [
				display_name,
				leader_text,
				selected_class.capitalize(),
				ready_text
			]


		player_list.add_child(
			row
		)


	#
	# Only the lobby leader gets the
	# Start Game button.
	#
	start_button.visible = \
		NetworkManager.is_local_lobby_leader()


	start_button.disabled = \
		not NetworkManager.can_start_game()
