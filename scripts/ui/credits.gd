extends Control

# This scene is opened by MatchManager on CLIENTS only.
# All match results remain available because MatchManager is an autoload.
@onready var winner_label: Label = $Center/Panel/Content/Winner
@onready var round_score_label: Label = $Center/Panel/Content/RoundScore
@onready var damage_label: Label = $Center/Panel/Content/DamageScore
@onready var history_label: Label = $Center/Panel/Content/RoundHistory
@onready var menu_button: Button = $Center/Panel/Content/ReturnButton
@onready var assets_credits: Button = $Center/Panel/Content/AssetsCredits


func _ready() -> void:
	match MatchManager.match_winner:
		"warlock":
			winner_label.text = "WARLOCKS WIN THE MATCH!"
		"witch":
			winner_label.text = "WITCHES WIN THE MATCH!"
		_:
			winner_label.text = "MATCH ENDS IN A DRAW"

	round_score_label.text = "ROUND WINS   Warlocks %d  -  %d Witches" % [
		int(MatchManager.round_wins.get("warlock", 0)),
		int(MatchManager.round_wins.get("witch", 0))
	]
	damage_label.text = "TOTAL DAMAGE   Warlocks %d  -  %d Witches" % [
		int(MatchManager.total_damage.get("warlock", 0)),
		int(MatchManager.total_damage.get("witch", 0))
	]

	var lines: PackedStringArray = []
	for item in MatchManager.round_results:
		var winner: String = str(item.get("winner", ""))
		var display: String = "DRAW"
		if winner == "warlock":
			display = "Warlocks"
		elif winner == "witch":
			display = "Witches"
		lines.append("Round %d — %s (%s) | Damage %d : %d" % [
			int(item.get("round", 0)),
			display,
			str(item.get("reason", "")),
			int(item.get("warlock_damage", 0)),
			int(item.get("witch_damage", 0))
		])
	history_label.text = "\n".join(lines)
	assets_credits.pressed.connect(_play_credits)
	menu_button.pressed.connect(_return_to_lobby)


func _return_to_lobby() -> void:
	# Disconnect this client. The dedicated server remains alive and is
	# not sent to a GUI credits scene. Restart the server for a new lobby.
	NetworkManager._reset_session()
	get_tree().change_scene_to_file("res://scenes/lobby.tscn")
	
func _play_credits() -> void:
	NetworkManager._reset_session()
	get_tree().change_scene_to_file("res://scenes/creditsassets.tscn")
