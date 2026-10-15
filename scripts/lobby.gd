extends Control


#
# ============================================================
# NODE REFERENCES
# ============================================================
#

@onready var player_name: LineEdit = \
	$Panel/VBoxContainer/PlayerName


@onready var address: LineEdit = \
	$Panel/VBoxContainer/IPAddress


@onready var host_button: Button = \
	$Panel/VBoxContainer/HBoxContainer/HostButton


@onready var join_button: Button = \
	$Panel/VBoxContainer/HBoxContainer/JoinButton


@onready var status_label: Label = \
	$Panel/VBoxContainer/HBoxContainer/StatusLabel


@onready var player_list: VBoxContainer = \
	$Panel/VBoxContainer/PlayerList


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
	host_button.pressed.connect(
		_on_host_button_pressed
	)

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


	status_label.text = \
		"Not connected"

	start_button.visible = false


#
# ============================================================
# HOST
# ============================================================
#

func _on_host_button_pressed() -> void:

	var error := NetworkManager.host_game(
		player_name.text
	)

	if error != OK:

		status_label.text = \
			"Could not host"

		return

	local_ready = false

	ready_button.text = "Ready"

	status_label.text = \
		"Hosting"

	_update_lobby()


#
# ============================================================
# JOIN
# ============================================================
#

func _on_join_button_pressed() -> void:

	status_label.text = \
		"Connecting..."

	var error := NetworkManager.join_game(
		address.text,
		player_name.text
	)

	if error != OK:

		status_label.text = \
			"Could not connect"


func _on_connected_to_server() -> void:

	local_ready = false

	ready_button.text = "Ready"

	status_label.text = \
		"Connected"


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

	local_ready = not local_ready

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

	NetworkManager.start_game()


#
# ============================================================
# UPDATE LOBBY UI
# ============================================================
#

func _update_lobby() -> void:

	#
	# Remove previous rows.
	#
	for child in player_list.get_children():

		child.queue_free()


	#
	# Create player rows.
	#
	var peer_ids := \
		NetworkManager.players.keys()

	peer_ids.sort()


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


		var row := Label.new()

		row.text = "%s | %s | %s" % [
			display_name,
			selected_class.capitalize(),
			ready_text
		]

		player_list.add_child(
			row
		)


	#
	# Start button belongs to host only.
	#
	start_button.visible = \
		multiplayer.is_server() \
		and NetworkManager.players.has(1)


	start_button.disabled = \
		not NetworkManager.can_start_game()
