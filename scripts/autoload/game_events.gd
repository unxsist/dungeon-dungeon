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

# Creature signals
signal creature_spawned(creature_data: CreatureData)
signal creature_despawned(creature_id: int)
signal creature_moved(creature_id: int, from_tile: Vector2i, to_tile: Vector2i)
signal creature_state_changed(creature_id: int, old_state: int, new_state: int)
signal creature_task_started(creature_id: int, task: Dictionary)
signal creature_task_completed(creature_id: int, task: Dictionary)
signal creature_leveled_up(creature_id: int, new_level: int)
signal creature_clicked(creature_id: int)
signal creature_health_changed(creature_id: int, old_health: int, new_health: int)
signal creature_happiness_changed(creature_id: int, happiness: float)

# Tile claiming signals (progress-based)
signal tile_claim_progress(position: Vector2i, faction_id: int, progress: float)
signal tile_claim_started(position: Vector2i, faction_id: int)
signal tile_claim_completed(position: Vector2i, faction_id: int)

# Tile digging signals (marking and progress)
signal dig_marked(position: Vector2i, faction_id: int)
signal dig_unmarked(position: Vector2i)
signal dig_progress(position: Vector2i, health: int, max_health: int)
signal dig_completed(position: Vector2i)

# Room signals
signal room_created(room_data: RoomData)
signal room_removed(room_id: int)
signal room_sold(room_data: RoomData, refund: int)
signal room_placement_started(room_type: int)
signal room_placement_cancelled()
signal room_placement_preview(new_tiles: Array[Vector2i], existing_tiles: Array[Vector2i], is_valid: bool, cost: int)

# Portal signals
signal portal_claimed(position: Vector2i, faction_id: int)
signal portal_spawn_started(position: Vector2i, faction_id: int)
signal portal_creature_spawned(position: Vector2i, creature_data: CreatureData)

# Economy signals
signal gold_changed(faction_id: int, old_amount: int, new_amount: int)
