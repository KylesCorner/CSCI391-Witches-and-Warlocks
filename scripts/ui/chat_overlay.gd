extends PanelContainer
## Global/team chat, embedded in PlayerHUD. Existing ChatManager RPCs unchanged.

@onready var title_label: Label = $Contents/Header/ChannelLabel
@onready var chat_log: RichTextLabel = $Contents/ChatLog
@onready var chat_entry: LineEdit = $Contents/ChatEntry
@onready var hint_label: Label = $Contents/HintLabel

var _active_channel: int = ChatManager.GLOBAL
var _typing: bool = false
var _rendered_count: int = 0


func _ready() -> void:
	if multiplayer.is_server():
		queue_free()
		return
	chat_entry.visible = false
	chat_entry.max_length = ChatManager.MAX_MESSAGE_LENGTH
	chat_log.scroll_following = true
	ChatManager.message_received.connect(_on_message_received)
	ChatManager.history_cleared.connect(_on_history_cleared)
	_refresh_channel_label()
	for entry in ChatManager.history:
		_append_line(int(entry["channel"]), str(entry["sender_name"]), str(entry["sender_team"]), str(entry["message"]))


func _input(event: InputEvent) -> void:
	if multiplayer.is_server():
		return
	if event is InputEventKey and event.echo:
		return
	if _typing:
		if event.is_action_pressed("chat_close"):
			_close_chat()
		elif event.is_action_pressed("chat_switch"):
			_active_channel = ChatManager.TEAM if _active_channel == ChatManager.GLOBAL else ChatManager.GLOBAL
			_refresh_channel_label()
		elif event.is_action_pressed("chat_send"):
			_submit_chat()
		else:
			return
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("chat_global"):
		_open_chat(ChatManager.GLOBAL)
	elif event.is_action_pressed("chat_team"):
		_open_chat(ChatManager.TEAM)
	else:
		return
	get_viewport().set_input_as_handled()


func _open_chat(channel: int) -> void:
	if NetworkManager.session_state != NetworkManager.SessionState.PLAYING:
		return
	_typing = true
	ChatManager.set_typing(true)
	_active_channel = channel
	chat_entry.visible = true
	chat_entry.text = ""
	_refresh_channel_label()
	chat_entry.call_deferred("grab_focus")


func _close_chat() -> void:
	_typing = false
	ChatManager.set_typing(false)
	chat_entry.text = ""
	chat_entry.release_focus()
	chat_entry.visible = false
	_refresh_channel_label()


func _submit_chat() -> void:
	var message: String = chat_entry.text.strip_edges()
	if not message.is_empty():
		ChatManager.send_message(_active_channel, message)
	_close_chat()


func _refresh_channel_label() -> void:
	var team_name: String = str(NetworkManager.local_player_info.get("class", "warlock"))
	if _active_channel == ChatManager.TEAM:
		title_label.text = "TEAM · " + team_name.to_upper()
		title_label.add_theme_color_override("font_color", Color(0.77, 0.63, 1.0))
	else:
		title_label.text = "GLOBAL"
		title_label.add_theme_color_override("font_color", Color(0.59, 0.82, 1.0))
	if _typing:
		chat_entry.placeholder_text = "Message " + ("team..." if _active_channel == ChatManager.TEAM else "everyone...")
		hint_label.text = "Enter send   ·   Tab switch   ·   Esc close"
	else:
		hint_label.text = "Enter global   ·   T team"


func _on_message_received(channel: int, sender_name: String, sender_team: String, message: String) -> void:
	if _rendered_count >= ChatManager.MAX_HISTORY:
		chat_log.clear()
		_rendered_count = 0
		for entry in ChatManager.history:
			_append_line(int(entry["channel"]), str(entry["sender_name"]), str(entry["sender_team"]), str(entry["message"]))
	else:
		_append_line(channel, sender_name, sender_team, message)


func _on_history_cleared() -> void:
	chat_log.clear()
	_rendered_count = 0
	if _typing:
		_close_chat()


func _append_line(channel: int, sender_name: String, sender_team: String, message: String) -> void:
	_rendered_count += 1
	var color: Color = Color(0.73, 0.61, 1.0) if channel == ChatManager.TEAM else Color(0.57, 0.79, 1.0)
	var label_text: String = "TEAM" if channel == ChatManager.TEAM else "ALL"
	chat_log.push_color(color)
	chat_log.add_text("[" + label_text + "] " + sender_name)
	chat_log.pop()
	chat_log.add_text(": " + message + "
")


func _exit_tree() -> void:
	if _typing:
		ChatManager.set_typing(false)
