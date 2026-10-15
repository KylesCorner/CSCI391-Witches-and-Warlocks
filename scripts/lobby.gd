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

var connected_to_server: bool = false


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
	# Initial lobby state.
	#
	status_label.text = \
		"Not connected"

	connected_to_server = false

	_set_lobby_options_visible(
		false
	)


#
# ============================================================
# CONNECTION UI
# ============================================================
#

func _set_lobby_options_visible(
	visible_state: bool
) -> void:

	#
	# These elements only appear after
	# successfully connecting to the server.
	#
	player_list.visible = \
		visible_state

	class_label.visible = \
		visible_state

	classes_container.visible = \
		visible_state

	ready_button.visible = \
		visible_state


	#
	# Start is handled separately because
	# only the lobby leader may see it.
	#
	if not visible_state:

		start_button.visible = false


#
# ============================================================
# JOIN SERVER
# ============================================================
#

func _on_join_button_pressed() -> void:

	if connected_to_server:
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
# CONNECTION EVENTS
# ============================================================
#

func _on_connected_to_server() -> void:

	connected_to_server = true

	status_label.text = \
		"Connected"


	local_ready = false


	ready_button.text = \
		"Ready"


	#
	# Prevent trying to join again while
	# already connected.
	#
	join_button.disabled = true


	_set_lobby_options_visible(
		true
	)


func _on_connection_failed() -> void:

	connected_to_server = false

	status_label.text = \
		"Connection failed"


	join_button.disabled = false


	_set_lobby_options_visible(
		false
	)


func _on_server_disconnected() -> void:

	connected_to_server = false

	local_ready = false


	status_label.text = \
		"Server disconnected"


	join_button.disabled = false

	ready_button.text = \
		"Ready"


	_set_lobby_options_visible(
		false
	)


#
# ============================================================
# CLASS SELECTION
# ============================================================
#

func _on_warlock_button_pressed() -> void:

	if not connected_to_server:
		return


	NetworkManager.choose_class(
		"warlock"
	)


	status_label.text = \
		"Selected Warlock"


func _on_witch_button_pressed() -> void:

	if not connected_to_server:
		return


	NetworkManager.choose_class(
		"witch"
	)


	status_label.text = \
		"Selected Witch"


#
# ============================================================
# READY STATE
# ============================================================
#

func _on_ready_button_pressed() -> void:

	if not connected_to_server:
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

	if not connected_to_server:
		return


	if not NetworkManager.is_local_lobby_leader():
		return


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
	# Sort IDs for consistent display.
	#
	var peer_ids := \
		NetworkManager.players.keys()


	peer_ids.sort()


	#
	# Build player list.
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
	# Only show Start when:
	#
	# 1. connected
	# 2. this client is lobby leader
	#
	start_button.visible = \
		connected_to_server \
		and NetworkManager.is_local_lobby_leader()


	#
	# The leader can only start once
	# everyone is ready.
	#
	start_button.disabled = \
		not NetworkManager.can_start_game()
