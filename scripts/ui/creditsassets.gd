extends Control
## Scrolling credits scene — dark blue & purple theme (Godot 4.x)
## Controls: hold Enter/Space (ui_accept) to speed up, Esc (ui_cancel) to skip.

@export var scroll_speed: float = 60.0          # pixels per second
@export var fast_multiplier: float = 4.0        # speed while holding ui_accept
@export_file("*.tscn") var next_scene: String = ""  # leave empty to loop the credits

# ---------- Colours ----------
const COL_TITLE   := "#e0c8ff"  # pale lavender
const COL_HEADING := "#b78cff"  # purple
const COL_NAME    := "#ffffff"
const COL_AUTHOR  := "#9fc0ff"  # soft blue
const COL_DETAIL  := "#7d86b8"  # muted blue-grey

# ---------- Credits data (edit freely) ----------
const SOUNDS := [
	["01385 witch cackle 3 natural.wav", "Robinhood76", "https://freesound.org/s/84746/", "Attribution NonCommercial 4.0"],
	["DSGNVocl_Weird Whispering Spells.Dry_EM", "newlocknew", "https://freesound.org/s/763000/", "Attribution NonCommercial 4.0"],
	["knife sharpen 02.wav", "Anthousai", "https://freesound.org/s/336593/", "Creative Commons 0"],
	["Rune Forest (Sample)", "SilverIllusionist", "https://freesound.org/s/670645/", "Attribution NonCommercial 4.0"],
	["pick_up_magic_diamonds.wav", "sastoryteller", "https://freesound.org/s/352900/", "Creative Commons 0"],
	["21-FLOR.wav", "carolinaGG", "https://freesound.org/s/429381/", "Attribution NonCommercial 3.0"],
	["cat's purring2.wav", "ChExi", "https://freesound.org/s/646599/", "Attribution 4.0"],
	["wine-glasses-clinking", "BogumilaMerc", "https://freesound.org/s/835833/", "Creative Commons 0"],
	["Fireball", "qubodup", "https://freesound.org/s/442827/", "Attribution 4.0"],
	["squishes.wav", "Eneasz", "https://freesound.org/s/216882/", "Creative Commons 0"],
	["Short-Fireball-Woosh.flac", "wjl", "https://freesound.org/s/267887/", "Creative Commons 0"],
	["Match", "qubodup", "https://freesound.org/s/171693/", "Attribution 4.0"],
	["23 FIACCOLA PASS.aiff", "lollosound", "https://freesound.org/s/124372/", "Creative Commons 0"],
	["Dull Decompression Punch Impact Explodes 96kHz", "qubodup", "https://freesound.org/s/71274/", "Creative Commons 0"],
	["Hard Glass Break 2", "ElevatorFan2020", "https://freesound.org/s/861043/", "Creative Commons 0"],
	["Angry Cat", "Kinoton", "https://freesound.org/s/656619/", "Creative Commons 0"],
]

const ART := [
	["LostKing Tileset", "loxaevion", "https://loxaevion.itch.io/lostking-tileset"],
	["Dreamy Tile Set", "clovertea", "https://clovertea.itch.io/dreamy-tile-set"],
	["Grimoire", "miminoaccount", "https://miminoaccount.itch.io/grimoire"],
	["16x16 Swords and Daggers", "replixel", "https://replixel.itch.io/16x16-swords-and-daggers"],
	["Goat Characters", "chaoswitchnikol", "https://chaoswitchnikol.itch.io/goat-characters"],
	["Black Cat Sprites", "carysaurus", "https://carysaurus.itch.io/black-cat-sprites"],
]

const IMAGES := [
	["Free PNG", "PNGWing", "https://www.pngwing.com/en/free-png-iawwn"],
]

# ---------- Background shader ----------
const BG_SHADER := """
shader_type canvas_item;

uniform vec4 top_color : source_color = vec4(0.02, 0.03, 0.13, 1.0);    // deep navy
uniform vec4 bottom_color : source_color = vec4(0.20, 0.05, 0.30, 1.0); // dark purple
uniform vec4 glow_color : source_color = vec4(0.35, 0.15, 0.65, 1.0);

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

void fragment() {
	vec2 uv = UV;
	vec3 col = mix(top_color.rgb, bottom_color.rgb, smoothstep(0.0, 1.0, uv.y));

	// Slow drifting purple glow
	float wave = 0.5 + 0.5 * sin(TIME * 0.25 + uv.x * 3.0 + uv.y * 2.0);
	col += glow_color.rgb * 0.12 * wave * uv.y;

	// Twinkling stars
	vec2 cells = vec2(160.0, 90.0);
	vec2 id = floor(uv * cells);
	vec2 f = fract(uv * cells) - 0.5;
	float h = hash(id);
	if (h > 0.985) {
		float twinkle = 0.4 + 0.6 * sin(TIME * (1.0 + h * 3.0) + h * 100.0);
		float star = smoothstep(0.18, 0.0, length(f));
		col += vec3(0.75, 0.75, 1.0) * star * twinkle;
	}

	// Vignette
	float v = smoothstep(0.9, 0.3, length(uv - 0.5));
	col *= mix(0.6, 1.0, v);

	COLOR = vec4(col, 1.0);
}
"""

var _label: RichTextLabel
var _ready_to_scroll := false


func _ready() -> void:
	_build_background()
	_build_label()
	await get_tree().process_frame  # let fit_content measure the text
	_reset_position()
	_ready_to_scroll = true
	get_viewport().size_changed.connect(_on_resize)


func _build_background() -> void:
	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = BG_SHADER
	mat.shader = sh
	bg.material = mat
	add_child(bg)


func _build_label() -> void:
	_label = RichTextLabel.new()
	_label.bbcode_enabled = true
	_label.fit_content = true
	_label.scroll_active = false
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.add_theme_constant_override("outline_size", 6)
	_label.add_theme_color_override("font_outline_color", Color("#0a0418"))
	_label.add_theme_font_size_override("normal_font_size", 22)
	_label.text = _build_text()
	add_child(_label)
	_size_label()


func _size_label() -> void:
	var vw := get_viewport_rect().size.x
	_label.size.x = vw * 0.8
	_label.position.x = (vw - _label.size.x) / 2.0


func _reset_position() -> void:
	_label.position.y = get_viewport_rect().size.y


func _on_resize() -> void:
	_size_label()


func _build_text() -> String:
	var t := "[center]"
	t += "[font_size=64][color=%s]Credits[/color][/font_size]\n\n" % COL_TITLE
	t += "[font_size=36][color=%s]Multiplayer Assets[/color][/font_size]\n\n\n" % COL_HEADING

	# Art
	t += _heading("Art & Sprites")
	for a in ART:
		t += _entry(a[0], a[1], a[2], "")
	t += _heading("Images")
	for i in IMAGES:
		t += _entry(i[0], i[1], i[2], "")

	# Sound
	t += _heading("Sound Effects & Music")
	t += "[color=%s]Sounds from Freesound.org[/color]\n\n" % COL_DETAIL
	for s in SOUNDS:
		t += _entry(s[0], s[1], s[2], s[3])

	t += "\n\n[font_size=40][color=%s]Thank you for playing![/color][/font_size]\n" % COL_TITLE
	t += "[/center]"
	return t


func _heading(title: String) -> String:
	return "\n[font_size=40][color=%s]%s[/color][/font_size]\n" % [COL_HEADING, title] \
		+ "[color=%s]— ✦ —[/color]\n\n" % COL_HEADING


func _entry(work: String, author: String, link: String, license: String) -> String:
	var s := "[font_size=28][color=%s]%s[/color][/font_size]\n" % [COL_NAME, work]
	s += "[color=%s]by %s[/color]\n" % [COL_AUTHOR, author]
	s += "[font_size=18][color=%s]%s" % [COL_DETAIL, link]
	if license != "":
		s += "\nLicense: %s" % license
	s += "[/color][/font_size]\n\n"
	return s


func _process(delta: float) -> void:
	if not _ready_to_scroll:
		return
	var speed := scroll_speed
	if Input.is_action_pressed("ui_accept"):
		speed *= fast_multiplier
	_label.position.y -= speed * delta

	if _label.position.y + _label.size.y < 0.0:
		_finish()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_finish()


func _finish() -> void:
	if next_scene != "":
		get_tree().change_scene_to_file("res://scenes/lobby.tscn")
	else:
		_reset_position()  # loop
