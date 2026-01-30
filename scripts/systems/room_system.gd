class_name RoomSystem
extends Node
## Manages room creation, validation, and removal.
## Handles room building mode and placement preview.

## Reference to map data
var map_data: MapData = null

## Current room placement state
var is_placing_room: bool = false
var placement_room_type: RoomTypes.Type = RoomTypes.Type.LAIR
var placement_tiles: Array[Vector2i] = []
var placement_start: Vector2i = Vector2i(-1, -1)

## Player faction ID constant
const PLAYER_FACTION_ID := 0


func _ready() -> void:
	GameEvents.map_loaded.connect(_on_map_loaded)


## Handle map loaded
func _on_map_loaded(data: Resource) -> void:
	map_data = data as MapData
	cancel_placement()


## Start room placement mode
func start_placement(room_type: RoomTypes.Type) -> void:
	is_placing_room = true
	placement_room_type = room_type
	placement_tiles.clear()
	placement_start = Vector2i(-1, -1)
	GameEvents.room_placement_started.emit(room_type)


## Cancel room placement mode
func cancel_placement() -> void:
	if is_placing_room:
		is_placing_room = false
		placement_tiles.clear()
		placement_start = Vector2i(-1, -1)
		GameEvents.room_placement_cancelled.emit()


## Update room placement preview based on selection rectangle
func update_placement_preview(start_pos: Vector2i, end_pos: Vector2i) -> void:
	if not is_placing_room or not map_data:
		return
	
	placement_start = start_pos
	
	# Get all tiles in the selection rectangle
	var min_x := mini(start_pos.x, end_pos.x)
	var max_x := maxi(start_pos.x, end_pos.x)
	var min_y := mini(start_pos.y, end_pos.y)
	var max_y := maxi(start_pos.y, end_pos.y)
	
	# Filter tiles - separate into new tiles and existing same-type tiles
	var new_tiles: Array[Vector2i] = []
	var existing_tiles: Array[Vector2i] = []  # Tiles already part of same room type
	var has_conflict := false
	
	for y in range(min_y, max_y + 1):
		for x in range(min_x, max_x + 1):
			var pos := Vector2i(x, y)
			var room := map_data.get_room_at(pos)
			if room:
				if room.room_type == placement_room_type and room.faction_id == PLAYER_FACTION_ID:
					# Same room type - this tile is already placed
					existing_tiles.append(pos)
					continue
				else:
					# Different room type - conflict!
					has_conflict = true
			new_tiles.append(pos)
	
	placement_tiles = new_tiles
	
	# Validate placement (only new tiles)
	var is_valid := not has_conflict and _validate_placement(placement_tiles, PLAYER_FACTION_ID)
	
	# Cost is only for new tiles
	var cost := RoomTypes.calculate_cost(placement_room_type, placement_tiles.size())
	
	GameEvents.room_placement_preview.emit(new_tiles, existing_tiles, is_valid, cost)


## Try to confirm room placement with current selection
## Returns true if room was created successfully
func confirm_placement() -> bool:
	if not is_placing_room or not map_data:
		return false
	
	if placement_tiles.is_empty():
		return false
	
	# Check for conflicts with different room types
	for pos in placement_tiles:
		var room := map_data.get_room_at(pos)
		if room:
			if room.room_type != placement_room_type or room.faction_id != PLAYER_FACTION_ID:
				return false  # Conflict with different room type
	
	# Validate placement
	if not _validate_placement(placement_tiles, PLAYER_FACTION_ID):
		return false
	
	# Check cost (only for new tiles, not existing room tiles)
	var cost := RoomTypes.calculate_cost(placement_room_type, placement_tiles.size())
	if not map_data.can_afford(PLAYER_FACTION_ID, cost):
		return false
	
	# Create the room (will merge with adjacent same-type rooms)
	var room := _create_room(placement_room_type, placement_tiles, PLAYER_FACTION_ID)
	if room:
		# Spend gold
		map_data.spend_gold(PLAYER_FACTION_ID, cost)
		
		# End placement mode
		is_placing_room = false
		placement_tiles.clear()
		placement_start = Vector2i(-1, -1)
		
		return true
	
	return false


## Validate room placement
## Returns true if placement is valid
func _validate_placement(tiles: Array[Vector2i], faction_id: int) -> bool:
	if tiles.is_empty():
		return false
	
	# Check each tile
	for pos in tiles:
		if not _is_valid_room_tile(pos, faction_id):
			return false
	
	# Check connectivity (all tiles must form a contiguous region)
	if not _are_tiles_connected(tiles):
		return false
	
	return true


## Check if a single tile is valid for room placement
## Note: Tiles already part of the same room type are filtered out before this check
func _is_valid_room_tile(pos: Vector2i, faction_id: int) -> bool:
	if not map_data.is_valid_position(pos):
		return false
	
	var tile: Variant = map_data.get_tile(pos)
	if not tile:
		return false
	
	# Must be a claimed tile
	if tile["type"] != TileTypes.Type.CLAIMED:
		return false
	
	# Must be owned by the faction
	if tile["faction_id"] != faction_id:
		return false
	
	# Check if part of an existing room
	var existing_room := map_data.get_room_at(pos)
	if existing_room:
		# Only valid if same room type and faction (will be merged)
		if existing_room.room_type != placement_room_type or existing_room.faction_id != faction_id:
			return false
	
	return true


## Check if all tiles are connected (4-directionally)
func _are_tiles_connected(tiles: Array[Vector2i]) -> bool:
	if tiles.size() <= 1:
		return true
	
	# Use flood fill from first tile
	var tile_set: Dictionary = {}
	for tile in tiles:
		tile_set[tile] = true
	
	var visited: Dictionary = {}
	var queue: Array[Vector2i] = [tiles[0]]
	visited[tiles[0]] = true
	
	while not queue.is_empty():
		var current: Vector2i = queue.pop_front()
		
		for dir: Vector2i in MapData.DIRECTIONS:
			var neighbor: Vector2i = current + dir
			if tile_set.has(neighbor) and not visited.has(neighbor):
				visited[neighbor] = true
				queue.append(neighbor)
	
	return visited.size() == tiles.size()


## Create a room from validated tiles, merging with adjacent rooms of the same type
func _create_room(room_type: RoomTypes.Type, tiles: Array[Vector2i], faction_id: int) -> RoomData:
	# Find all adjacent rooms of the same type that should be merged
	var rooms_to_merge: Array[RoomData] = []
	var rooms_seen: Dictionary = {}  # Track room IDs we've already added
	
	for tile_pos in tiles:
		for dir: Vector2i in MapData.DIRECTIONS:
			var neighbor_pos: Vector2i = tile_pos + dir
			var adjacent_room := map_data.get_room_at(neighbor_pos)
			
			if adjacent_room and not rooms_seen.has(adjacent_room.id):
				# Check if same type and faction
				if adjacent_room.room_type == room_type and adjacent_room.faction_id == faction_id:
					rooms_to_merge.append(adjacent_room)
					rooms_seen[adjacent_room.id] = true
	
	# Collect all tiles: new tiles + tiles from rooms being merged
	var all_tiles: Array[Vector2i] = tiles.duplicate()
	for room in rooms_to_merge:
		for tile_pos: Vector2i in room.tiles:
			if not all_tiles.has(tile_pos):
				all_tiles.append(tile_pos)
	
	# Remove old rooms (emit events for each)
	for room in rooms_to_merge:
		map_data.remove_room(room.id)
		GameEvents.room_removed.emit(room)
	
	# Create the merged room
	var room := RoomData.new()
	room.room_type = room_type
	room.faction_id = faction_id
	room.tiles = all_tiles
	
	# Add to map data
	map_data.add_room(room)
	
	# Emit room created event
	GameEvents.room_created.emit(room)
	
	return room


## Remove a room by ID
func remove_room(room_id: int) -> bool:
	if not map_data:
		return false
	
	var room := map_data.remove_room(room_id)
	if room:
		GameEvents.room_removed.emit(room)
		return true
	
	return false


## Remove a room at a specific tile position
func remove_room_at(pos: Vector2i) -> bool:
	if not map_data:
		return false
	
	var room := map_data.get_room_at(pos)
	if room:
		return remove_room(room.id)
	
	return false


## Sell a room by ID and receive a refund
func sell_room(room_id: int) -> bool:
	if not map_data:
		return false
	
	var room := map_data.get_room(room_id)
	if not room:
		return false
	
	# Calculate refund (50% of original cost)
	var refund := room.get_sell_refund()
	var faction_id := room.faction_id
	
	# Remove the room
	var removed_room := map_data.remove_room(room_id)
	if removed_room:
		# Give gold back
		map_data.add_gold(faction_id, refund)
		
		# Emit events
		GameEvents.room_sold.emit(removed_room, refund)
		GameEvents.room_removed.emit(removed_room)
		return true
	
	return false


## Sell a room at a specific tile position
func sell_room_at(pos: Vector2i) -> bool:
	if not map_data:
		return false
	
	var room := map_data.get_room_at(pos)
	if room:
		return sell_room(room.id)
	
	return false


## Get room info at a position (for UI display)
func get_room_info_at(pos: Vector2i) -> Dictionary:
	if not map_data:
		return {}
	
	var room := map_data.get_room_at(pos)
	if not room:
		return {}
	
	return {
		"id": room.id,
		"type": room.room_type,
		"type_name": RoomTypes.get_display_name(room.room_type),
		"size": room.get_size(),
		"faction_id": room.faction_id,
		"level": room.level,
		"total_cost": room.get_total_cost(),
		"bounds": room.get_bounds(),
		"center": room.get_center(),
	}


## Check if player can afford a room of given type and size
func can_afford_room(room_type: RoomTypes.Type, tile_count: int) -> bool:
	if not map_data:
		return false
	
	var cost := RoomTypes.calculate_cost(room_type, tile_count)
	return map_data.can_afford(PLAYER_FACTION_ID, cost)


## Get placement preview info
func get_placement_preview_info() -> Dictionary:
	if not is_placing_room:
		return {}
	
	# Check for conflicts with different room types
	var has_conflict := false
	for pos in placement_tiles:
		var room := map_data.get_room_at(pos)
		if room:
			if room.room_type != placement_room_type or room.faction_id != PLAYER_FACTION_ID:
				has_conflict = true
				break
	
	var is_valid := not has_conflict and _validate_placement(placement_tiles, PLAYER_FACTION_ID)
	var cost := RoomTypes.calculate_cost(placement_room_type, placement_tiles.size())
	var can_afford := map_data.can_afford(PLAYER_FACTION_ID, cost) if map_data else false
	
	return {
		"room_type": placement_room_type,
		"type_name": RoomTypes.get_display_name(placement_room_type),
		"tiles": placement_tiles.duplicate(),
		"tile_count": placement_tiles.size(),
		"functional_tiles": RoomTypes.get_functional_tiles(placement_room_type),
		"is_functional": RoomTypes.is_functional(placement_room_type, placement_tiles.size()),
		"cost": cost,
		"is_valid": is_valid,
		"can_afford": can_afford,
	}
