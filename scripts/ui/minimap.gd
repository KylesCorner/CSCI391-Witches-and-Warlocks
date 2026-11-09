extends PanelContainer
## Second, independent SubViewport. Renders a lightweight map and allied markers.
## Instance this scene under PlayerHUD/HUDRoot, and move it using its Control anchors.

@onready var mini_viewport: SubViewport = $VBox/MapFrame/Viewport
@onready var map_art: MinimapMap = $VBox/MapFrame/Viewport/MapRoot/MapArt
@onready var markers: MinimapMarkers = $VBox/MapFrame/Viewport/MapRoot/TeamMarkers
@onready var mini_camera: Camera2D = $VBox/MapFrame/Viewport/MapRoot/MapCamera

var _configured: bool = false


func _ready() -> void:
	# CanvasLayers are created after the local player spawns. Wait for HUD binding.
	if multiplayer.is_server():
		set_process(false)
		return
	mini_viewport.world_2d = World2D.new()
	set_process(true)


func _process(_delta: float) -> void:
	if _configured:
		return
	var hud: PlayerHUD = get_parent().get_parent() as PlayerHUD
	if hud == null or hud.controlled_player == null:
		return
	if not is_instance_valid(hud.controlled_player):
		return
	_bind_player(hud.controlled_player)


func _bind_player(player: PlayerController) -> void:
	var players_node: Node2D = player.get_parent() as Node2D
	if players_node == null:
		return
	var world_root: Node2D = players_node.get_parent() as Node2D
	if world_root == null:
		return
	var tile_layer: TileMapLayer = world_root.get_node_or_null("TileMapLayer") as TileMapLayer
	if tile_layer == null:
		push_warning("Minimap: world TileMapLayer was not found")
		return

	var map_bounds: Rect2 = map_art.configure(tile_layer)
	var size_px: Vector2 = Vector2(mini_viewport.size)
	var fit: float = minf(size_px.x / maxf(map_bounds.size.x, 1.0), size_px.y / maxf(map_bounds.size.y, 1.0))
	var magnification: float = clampf(fit * 0.91, 0.008, 4.0)
	mini_camera.position = map_bounds.get_center()
	mini_camera.zoom = Vector2.ONE * magnification
	mini_camera.make_current()

	markers.configure(player, players_node, mini_camera)
	_configured = true
	set_process(false)
