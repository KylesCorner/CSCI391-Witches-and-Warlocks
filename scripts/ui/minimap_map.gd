class_name MinimapMap
extends Node2D
## Renders a real tile-by-tile map in the independent minimap viewport.
## Does not duplicate TileMapLayer nodes, lighting, physics or navigation.

const BACKGROUND := Color(0.11, 0.12, 0.19, 1.0)
const BORDER := Color(0.75, 0.61, 0.94, 1.0)

var _bounds := Rect2(-256.0, -256.0, 512.0, 512.0)
var _tiles: Array[Dictionary] = []
var _cell_size := Vector2(16, 16)


func configure(layer: TileMapLayer) -> Rect2:
    _tiles.clear()
    if layer.tile_set == null:
        push_warning("Minimap: TileMapLayer has no TileSet")
        queue_redraw()
        return _bounds

    var used := layer.get_used_rect()
    if used.size.x <= 0 or used.size.y <= 0:
        push_warning("Minimap: TileMapLayer contains no used cells")
        queue_redraw()
        return _bounds

    _cell_size = Vector2(layer.tile_set.tile_size) * layer.global_scale.abs()
    var first := layer.to_global(layer.map_to_local(used.position))
    var last := layer.to_global(layer.map_to_local(used.position + used.size - Vector2i.ONE))
    var lo := first.min(last) - _cell_size * 0.5
    var hi := first.max(last) + _cell_size * 0.5
    _bounds = Rect2(lo, hi - lo)

    for cell in layer.get_used_cells():
        var source_id := layer.get_cell_source_id(cell)
        var atlas := layer.get_cell_atlas_coords(cell)
        var source := layer.tile_set.get_source(source_id)
        var center := layer.to_global(layer.map_to_local(cell))
        var entry: Dictionary = {"pos": center, "source": source_id, "atlas": atlas}
        if source is TileSetAtlasSource:
            var atlas_source := source as TileSetAtlasSource
            var texture := atlas_source.texture
            if texture != null:
                entry["texture"] = texture
                entry["region"] = atlas_source.get_tile_texture_region(atlas)
        _tiles.append(entry)

    print("Minimap: loaded ", _tiles.size(), " terrain cells")
    queue_redraw()
    return _bounds


func _draw() -> void:
    draw_rect(_bounds.grow(24.0), BACKGROUND, true)
    var half := _cell_size * 0.5
    for tile in _tiles:
        var rect := Rect2(tile["pos"] - half, _cell_size)
        if tile.has("texture"):
            draw_texture_rect_region(tile["texture"], rect, tile["region"])
        else:
            # Visible fallback for non-atlas tiles.
            var id := int(tile["source"])
            var color := Color(0.23, 0.33, 0.29) if id % 2 == 0 else Color(0.35, 0.29, 0.40)
            draw_rect(rect, color, true)
    draw_rect(_bounds, BORDER, false, 2.0)
