extends Control


#
# ============================================================
# CONNECTION CONTROLS
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


#
# ============================================================
# CONNECTED-ONLY CONTROLS
# ============================================================
#

@onready var player_list: VBoxContainer = \
	$Panel/VBoxContainer/PlayerList


@onready var class_label: Label = \
	$Panel/VBoxContainer/ClassLabel


@onready var classes_container: HBoxContainer = \
	$Panel/VBoxContainer/HBoxContainer2


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
# LOCAL STATE
# ============================================================
#

var local_ready: bool = false

var is_connected: bool = false


#
# ============================================================
# READY
# ============================================================
#

func _ready() -> void:

	#
	# Force the initial disconnected UI.
	#
	_set_connected_ui(
		false
	)


	status_label.text = \
		"Not connected"


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
# ============================================================
# CONNECTED UI
# ============================================================
#

func _set_connected_ui(
	connected: bool
) -> void:

	is_connected = connected


	#
	# Everything below the connection
	# section is hidden until connected.
	#
	player_list.visible = connected

	class_label.visible = connected

	classes_container.visible = connected

	ready_button.visible = connected


	#
	# Start has an additional rule:
	# only the lobby leader sees it.
	#
	if not connected:

		start_button.visible = false


#
# ============================================================
# JOIN
# ============================================================
#

func _on_join_button_pressed() -> void:

	if is_connected:
		return


	status_label.text = \
		"Connecting..."


	join_button.disabled = true


	var error := \
		NetworkManager.join_game(
			address.text,
			player_name.text
		)


	if error != OK:

		status_label.text = \
			"Could not connect"

		join_button.disabled = false


#
# ============================================================
# CONNECTED
# ============================================================
#

func _on_connected_to_server() -> void:

	print(
		"Lobby: connected to server"
	)


	status_label.text = \
		"Connected"


	local_ready = false


	ready_button.text = \
		"Ready"


	join_button.disabled = true


	_set_connected_ui(
		true
	)


#
# ============================================================
# CONNECTION FAILED
# ============================================================
#

func _on_connection_failed() -> void:

	print(
		"Lobby: connection failed"
	)


	status_label.text = \
		"Connection failed"


	join_button.disabled = false


	_set_connected_ui(
		false
	)


#
# ============================================================
# SERVER DISCONNECTED
# ============================================================
#

func _on_server_disconnected() -> void:

	print(
		"Lobby: server disconnected"
	)


	status_label.text = \
		"Server disconnected"


	local_ready = false


	ready_button.text = \
		"Ready"


	join_button.disabled = false


	_set_connected_ui(
		false
	)


#
# ============================================================
# CLASS SELECTION
# ============================================================
#

func _on_warlock_button_pressed() -> void:

	if not is_connected:
		return


	NetworkManager.choose_class(
		"warlock"
	)


	status_label.text = \
		"Selected Warlock"


func _on_witch_button_pressed() -> void:

	if not is_connected:
		return


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

	if not is_connected:
		return


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
# START GAME
# ============================================================
#

func _on_start_button_pressed() -> void:

	if not is_connected:
		return


	if not NetworkManager.is_local_lobby_leader():
		return


	NetworkManager.request_start_game()


#
# ============================================================
# UPDATE LOBBY
# ============================================================
#

func _update_lobby() -> void:

	#
	# Do not accidentally reveal anything
	# if we're not actually connected.
	#
	if not is_connected:

		_set_connected_ui(
			false
		)

		return


	#
	# Clear existing player rows.
	#
	for child in player_list.get_children():

		child.queue_free()


	#
	# Sort player IDs.
	#
	var peer_ids := \
		NetworkManager.players.keys()


	peer_ids.sort()


	#
	# Rebuild player list.
	#
	for peer_id in peer_ids:

		var info: Dictionary = \
			NetworkManager.players[
				peer_id
			]


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


		var player_ready := bool(
			info.get(
				"ready",
				false
			)
		)


		var ready_text := \
			"READY" \
			if player_ready \
			else "NOT READY"


		var leader_text := ""


		if int(peer_id) == \
				NetworkManager.lobby_leader_id:

			leader_text = \
				" [LEADER]"


		var row := Label.new()


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
	# Only connected lobby leader gets Start.
	#
	start_button.visible = \
		is_connected \
		and NetworkManager.is_local_lobby_leader()


	start_button.disabled = \
		not NetworkManager.can_start_game()
