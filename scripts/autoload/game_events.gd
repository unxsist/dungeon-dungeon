extends Node
## Global event bus for decoupled communication between systems.
## Autoloaded as "GameEvents".

# Tile interaction signals
signal tile_hovered(position: Vector2i)
signal tile_unhovered()
signal tile_clicked(position: Vector2i, button: int)

# Cursor position (fires for ANY tile, not just selectable ones)
signal cursor_tile_changed(position: Vector2i)  # Vector2i(-1, -1) when not over map
signal cursor_world_position_changed(world_pos: Vector3, is_valid: bool)  # Actual 3D position for cursor light
signal tiles_selected(positions: Array[Vector2i])
signal selection_cleared()

# Tile state change signals
signal tile_changed(position: Vector2i, old_type: int, new_type: int)
signal tile_ownership_changed(position: Vector2i, old_faction: int, new_faction: int)

# Map signals
signal map_loaded(map_data: Resource)
signal map_save_requested()
signal map_load_requested(path: String)

# Gameplay action requests
signal dig_requested(position: Vector2i)
signal claim_requested(position: Vector2i, faction_id: int)

# Fog of war signals
signal visibility_updated(faction_id: int)

# Camera signals
signal camera_moved(position: Vector3)
signal camera_zoomed(zoom_level: float)
