extends Node

## LAN server discovery for Witches & Warlocks (Godot 4.7).
## UDP/7001 is discovery ONLY. Gameplay remains ENet/7000.
## The bootstrap scene instantiates this as a root child on server and client.

const DISCOVERY_PORT: int = 7001
const PROTOCOL_TAG: String = "WAW_LAN_DISCOVERY_V1"
const DISCOVERY_REQUEST: String = "WAW_DISCOVER_V1"
const BROADCAST_IP: String = "255.255.255.255"
const LOBBY_PATH: String = "res://scenes/lobby.tscn"

var _socket: PacketPeerUDP = null
var _server_mode: bool = false
var _client_mode: bool = false
var _server_name: String = "Witches & Warlocks Server"

var _lobby: Control = null
var _lobby_fields: VBoxContainer = null
var _browser_button: Button = null
var _overlay: CanvasLayer = null
var _server_rows: VBoxContainer = null
var _result_label: Label = null
var _servers: Dictionary = {} # key: source-IP:game-port
var _scan_remaining: float = 0.0


func _ready() -> void:
	set_process(false)


func _exit_tree() -> void:
	if _socket != null:
		_socket.close()


func start_server() -> void:
	if not is_inside_tree():
		push_error("LAN discovery server was started before entering the scene tree.")
		return
	_server_mode = true
	_server_name = OS.get_environment("WAW_SERVER_NAME").strip_edges()
	if _server_name.is_empty():
		var hostname: String = OS.get_environment("HOSTNAME").strip_edges()
		if hostname.is_empty():
			hostname = OS.get_environment("COMPUTERNAME").strip_edges()
		if hostname.is_empty():
			hostname = "LAN"
		_server_name = "Witches & Warlocks - " + hostname
	_server_name = _server_name.replace("\n", " ").replace("\r", " ").substr(0, 48)

	_socket = PacketPeerUDP.new()
	var err: Error = _socket.bind(DISCOVERY_PORT, "0.0.0.0")
	if err != OK:
		push_warning("LAN discovery could not bind UDP %d (error %d). ENet server is still running." % [DISCOVERY_PORT, err])
		_socket = null
		return

	set_process(true)
	print("LAN discovery listening on UDP %d as '%s'" % [DISCOVERY_PORT, _server_name])


func start_client() -> void:
	if not is_inside_tree():
		push_error("LAN discovery client was started before entering the scene tree.")
		return
	_client_mode = true
	_socket = PacketPeerUDP.new()
	var err: Error = _socket.bind(0, "0.0.0.0")
	if err != OK:
		push_warning("LAN discovery client could not open UDP socket (error %d). Manual IP joining still works." % err)
		_socket = null
	else:
		_socket.set_broadcast_enabled(true)
		set_process(true)

	# Receives notifications after each new lobby scene is initialized.
	get_tree().scene_changed.connect(_on_scene_changed)
	_on_scene_changed()


func _process(delta: float) -> void:
	if _socket == null:
		return

	# Avoid locking up a frame if the network sends excessive packets.
	var packets_read: int = 0
	while _socket.get_available_packet_count() > 0 and packets_read < 64:
		packets_read += 1
		var packet: PackedByteArray = _socket.get_packet()
		var sender_ip: String = _socket.get_packet_ip()
		var sender_port: int = _socket.get_packet_port()
		if packet.size() > 1024:
			continue
		if _server_mode:
			_process_server_request(packet, sender_ip, sender_port)
		elif _client_mode:
			_process_client_response(packet, sender_ip)

	if _client_mode and _scan_remaining > 0.0:
		_scan_remaining -= delta
		if _scan_remaining <= 0.0:
			_scan_remaining = 0.0
			_render_servers()


# ----------------------------- SERVER ------------------------------

func _process_server_request(packet: PackedByteArray, sender_ip: String, sender_port: int) -> void:
	if packet.get_string_from_utf8() != DISCOVERY_REQUEST:
		return
	if sender_ip.is_empty() or sender_port <= 0:
		return
	if not multiplayer.is_server():
		return

	var player_count: int = NetworkManager.players.size()
	var max_players: int = NetworkManager.MAX_PLAYERS
	var state: int = int(NetworkManager.session_state)
	var status: String = "Unavailable"
	match state:
		NetworkManager.SessionState.LOBBY:
			status = "Lobby"
		NetworkManager.SessionState.LOADING:
			status = "Loading"
		NetworkManager.SessionState.PLAYING:
			status = "In Game"
	var joinable: bool = state == NetworkManager.SessionState.LOBBY and player_count < max_players

	var response: Dictionary = {
		"tag": PROTOCOL_TAG,
		"name": _server_name,
		"port": NetworkManager.PORT,
		"players": player_count,
		"max_players": max_players,
		"status": status,
		"joinable": joinable
	}
	if _socket.set_dest_address(sender_ip, sender_port) == OK:
		_socket.put_packet(JSON.stringify(response).to_utf8_buffer())


# ----------------------------- CLIENT ------------------------------

func _process_client_response(packet: PackedByteArray, sender_ip: String) -> void:
	# Source IP comes from UDP, not from potentially untrusted JSON.
	var parsed: Variant = JSON.parse_string(packet.get_string_from_utf8())
	if not parsed is Dictionary:
		return
	var response: Dictionary = parsed
	if str(response.get("tag", "")) != PROTOCOL_TAG:
		return
	if sender_ip.is_empty():
		return

	var port: int = int(response.get("port", -1))
	if port != NetworkManager.PORT:
		return
	var name: String = str(response.get("name", "Game Server")).substr(0, 48)
	var count: int = clampi(int(response.get("players", 0)), 0, 99)
	var maximum: int = clampi(int(response.get("max_players", 4)), 1, 99)
	var status: String = str(response.get("status", "Unknown")).substr(0, 24)
	var joinable: bool = response.get("joinable", false) == true and count < maximum
	var key: String = "%s:%d" % [sender_ip, port]
	_servers[key] = {
		"ip": sender_ip,
		"port": port,
		"name": name,
		"players": count,
		"max_players": maximum,
		"status": status,
		"joinable": joinable
	}
	_render_servers()


func _refresh() -> void:
	_servers.clear()
	_scan_remaining = 1.5
	_render_servers()
	if _socket == null:
		return

	# Broadcast reaches other machines on the same network.
	# Loopback additionally finds a server running on this computer.
	for target in [BROADCAST_IP, "127.0.0.1"]:
		if _socket.set_dest_address(target, DISCOVERY_PORT) == OK:
			var err: Error = _socket.put_packet(DISCOVERY_REQUEST.to_utf8_buffer())
			if err != OK:
				print("LAN discovery send error to %s: %d" % [target, err])


# ------------------------- LOBBY INTEGRATION -----------------------

func _on_scene_changed() -> void:
	_lobby = null
	_lobby_fields = null
	_browser_button = null
	_overlay = null
	_server_rows = null
	_result_label = null

	var scene: Node = get_tree().current_scene
	if scene == null or scene.scene_file_path != LOBBY_PATH:
		return
	if not scene is Control:
		return

	_lobby = scene as Control
	var fields: VBoxContainer = _lobby.get_node_or_null("Center/Panel/VBoxContainer") as VBoxContainer
	if fields == null:
		push_warning("LAN browser could not locate lobby's VBoxContainer")
		return
	_lobby_fields = fields

	_browser_button = Button.new()
	_browser_button.name = "FindLanServersButton"
	_browser_button.text = "FIND LAN SERVERS"
	_browser_button.custom_minimum_size = Vector2(0, 42)
	_browser_button.tooltip_text = "Discover Witches & Warlocks dedicated servers on your LAN"
	fields.add_child(_browser_button)
	var ip_field: Control = fields.get_node_or_null("IPAddress") as Control
	if ip_field != null:
		fields.move_child(_browser_button, ip_field.get_index() + 1)
	_browser_button.pressed.connect(_show_browser)

	# The extra button makes the original centered lobby taller than the
	# game window. Put its existing CenterContainer inside a ScrollContainer
	# so every control remains reachable at 720p and in smaller windows.
	# SceneTree.scene_changed fires after lobby._ready(), so all lobby.gd
	# @onready references have already been resolved before reparenting.
	_make_lobby_scrollable()
	_build_overlay()


func _make_lobby_scrollable() -> void:
	if _lobby == null or not is_instance_valid(_lobby):
		return
	if _lobby.has_node("LobbyScroll"):
		return

	var center: CenterContainer = _lobby.get_node_or_null("Center") as CenterContainer
	if center == null:
		push_warning("LAN browser: expected lobby CenterContainer not found")
		return

	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.name = "LobbyScroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.follow_focus = true
	scroll.mouse_filter = Control.MOUSE_FILTER_PASS
	_lobby.add_child(scroll)
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	# Keep the original CenterContainer and Panel, including all their
	# theme resources and node references, instead of rebuilding the lobby.
	center.reparent(scroll)
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL


func _build_overlay() -> void:
	_overlay = CanvasLayer.new()
	_overlay.name = "LanServerBrowser"
	_overlay.layer = 20
	_lobby.add_child(_overlay)

	var dim: ColorRect = ColorRect.new()
	dim.color = Color(0.015, 0.01, 0.035, 0.82)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_overlay.add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var center: CenterContainer = CenterContainer.new()
	_overlay.add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var panel: PanelContainer = PanelContainer.new()
	panel.custom_minimum_size = Vector2(610, 400)
	var panel_style: StyleBoxFlat = StyleBoxFlat.new()
	panel_style.bg_color = Color(0.09, 0.075, 0.15, 1.0)
	panel_style.border_color = Color(0.54, 0.37, 0.76, 1.0)
	panel_style.set_border_width_all(2)
	panel_style.set_corner_radius_all(12)
	panel.add_theme_stylebox_override("panel", panel_style)
	center.add_child(panel)

	var margin: MarginContainer = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 22)
	margin.add_theme_constant_override("margin_right", 22)
	margin.add_theme_constant_override("margin_top", 18)
	margin.add_theme_constant_override("margin_bottom", 18)
	panel.add_child(margin)

	var content: VBoxContainer = VBoxContainer.new()
	content.add_theme_constant_override("separation", 12)
	margin.add_child(content)

	var title: Label = Label.new()
	title.text = "LOCAL SERVER BROWSER"
	title.add_theme_font_size_override("font_size", 23)
	title.add_theme_color_override("font_color", Color(0.87, 0.76, 1.0))
	content.add_child(title)

	var hint: Label = Label.new()
	hint.text = "Servers on the same LAN  |  UDP 7001 discovery  |  ENet 7000 game"
	hint.add_theme_font_size_override("font_size", 12)
	hint.add_theme_color_override("font_color", Color(0.7, 0.65, 0.81))
	content.add_child(hint)

	_result_label = Label.new()
	_result_label.text = "Searching LAN..."
	content.add_child(_result_label)

	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(560, 240)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(scroll)

	_server_rows = VBoxContainer.new()
	_server_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_server_rows.add_theme_constant_override("separation", 8)
	scroll.add_child(_server_rows)

	var buttons: HBoxContainer = HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 10)
	content.add_child(buttons)

	var refresh_button: Button = Button.new()
	refresh_button.text = "REFRESH"
	refresh_button.custom_minimum_size = Vector2(140, 40)
	refresh_button.pressed.connect(_refresh)
	buttons.add_child(refresh_button)

	var spacer: Control = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	buttons.add_child(spacer)

	var close_button: Button = Button.new()
	close_button.text = "CLOSE"
	close_button.custom_minimum_size = Vector2(140, 40)
	close_button.pressed.connect(_hide_browser)
	buttons.add_child(close_button)

	_overlay.visible = false


func _show_browser() -> void:
	if _overlay == null or not is_instance_valid(_overlay):
		return
	_overlay.visible = true
	_refresh()


func _hide_browser() -> void:
	if _overlay != null and is_instance_valid(_overlay):
		_overlay.visible = false


func _render_servers() -> void:
	if _server_rows == null or not is_instance_valid(_server_rows):
		return

	for child in _server_rows.get_children():
		_server_rows.remove_child(child)
		child.queue_free()

	if _socket == null:
		_result_label.text = "Discovery unavailable; use the manual IP field."
		return

	if _servers.is_empty():
		_result_label.text = "Searching LAN..." if _scan_remaining > 0.0 else "No servers found. Check UDP 7001 and refresh."
		return

	_result_label.text = "Found %d LAN server(s)" % _servers.size()
	var keys: Array = _servers.keys()
	keys.sort()
	for key in keys:
		var info: Dictionary = _servers[key]
		var row: HBoxContainer = HBoxContainer.new()
		_server_rows.add_child(row)

		var details: VBoxContainer = VBoxContainer.new()
		details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(details)

		var name_label: Label = Label.new()
		name_label.text = str(info["name"])
		name_label.add_theme_color_override("font_color", Color(0.9, 0.81, 1.0))
		details.add_child(name_label)

		var address_label: Label = Label.new()
		address_label.text = "%s:%d  |  %d/%d players  |  %s" % [
			str(info["ip"]), int(info["port"]),
			int(info["players"]), int(info["max_players"]), str(info["status"])
		]
		address_label.add_theme_font_size_override("font_size", 12)
		address_label.add_theme_color_override("font_color", Color(0.68, 0.65, 0.78))
		details.add_child(address_label)

		var join_button: Button = Button.new()
		join_button.text = "JOIN" if bool(info["joinable"]) else "UNAVAILABLE"
		join_button.disabled = not bool(info["joinable"])
		join_button.custom_minimum_size = Vector2(108, 40)
		join_button.pressed.connect(_join_selected.bind(str(info["ip"])))
		row.add_child(join_button)

		var separator: HSeparator = HSeparator.new()
		_server_rows.add_child(separator)


func _join_selected(ip: String) -> void:
	if _lobby == null or not is_instance_valid(_lobby):
		return

	# The CenterContainer now lives under LobbyScroll. Reuse the original
	# VBoxContainer reference rather than looking up its former node path.
	if _lobby_fields == null or not is_instance_valid(_lobby_fields):
		return
	var ip_field: LineEdit = _lobby_fields.get_node_or_null("IPAddress") as LineEdit
	var name_field: LineEdit = _lobby_fields.get_node_or_null("PlayerName") as LineEdit
	var join_button: Button = _lobby_fields.get_node_or_null("JoinButton") as Button
	var status_label: Label = _lobby_fields.get_node_or_null("StatusLabel") as Label
	if ip_field == null or name_field == null or join_button == null:
		return

	# Use the lobby's existing ENet join function. Never duplicate it.
	ip_field.text = ip
	_hide_browser()
	if name_field.text.strip_edges().is_empty():
		name_field.grab_focus()
		if status_label != null:
			status_label.text = "Enter a player name, then click JOIN SERVER."
		return
	join_button.emit_signal("pressed")
