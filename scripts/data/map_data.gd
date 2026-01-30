class_name MapData
extends Resource
## Data class representing the entire map state.
## Stores tile data in a dictionary keyed by Vector2i positions.

## Map metadata
@export var map_name: String = "Unnamed"
@export var width: int = 20
@export var height: int = 20
@export var tile_size: float = 4.0

## Tile data storage: Dictionary[Vector2i, Dictionary]
## Each tile dictionary contains: type, faction_id, health, variation
var tiles: Dictionary = {}

## Faction data
var factions: Array[FactionData] = []

## Spawn points: Array of { faction_id: int, position: Vector2i }
var spawn_points: Array[Dictionary] = []

## Creatures on the map
var creatures: Array[CreatureData] = []

## Next creature ID (auto-increment)
var next_creature_id: int = 0

## Claim progress for tiles being claimed: Dictionary[Vector2i, Dictionary]
## Each entry: { "faction_id": int, "progress": float (0-100) }
var claim_progress: Dictionary = {}

## Original map file path (for delta saves)
var source_file: String = ""

# Cardinal directions for neighbor lookups
const DIRECTIONS := [
	Vector2i(0, -1),  # North
	Vector2i(1, 0),   # East
	Vector2i(0, 1),   # South
	Vector2i(-1, 0),  # West
]

const DIRECTIONS_8 := [
	Vector2i(0, -1),   # North
	Vector2i(1, -1),   # Northeast
	Vector2i(1, 0),    # East
	Vector2i(1, 1),    # Southeast
	Vector2i(0, 1),    # South
	Vector2i(-1, 1),   # Southwest
	Vector2i(-1, 0),   # West
	Vector2i(-1, -1),  # Northwest
]


## Initialize an empty map with given dimensions
func initialize(w: int, h: int, default_type: TileTypes.Type = TileTypes.Type.ROCK) -> void:
	width = w
	height = h
	tiles.clear()
	
	for y in range(height):
		for x in range(width):
			var pos := Vector2i(x, y)
			tiles[pos] = _create_tile_data(default_type)


## Create default tile data dictionary
func _create_tile_data(type: TileTypes.Type, faction_id: int = -1, variation: int = 0) -> Dictionary:
	return {
		"type": type,
		"faction_id": faction_id,
		"health": TileTypes.get_property(type, "default_health"),
		"variation": variation,
	}


## Check if position is within map bounds
func is_valid_position(pos: Vector2i) -> bool:
	return pos.x >= 0 and pos.x < width and pos.y >= 0 and pos.y < height


## Get tile data at position, returns null if invalid
func get_tile(pos: Vector2i) -> Variant:
	if tiles.has(pos):
		return tiles[pos]
	return null


## Set tile data at position
func set_tile(pos: Vector2i, data: Dictionary) -> void:
	if is_valid_position(pos):
		tiles[pos] = data


## Get tile type at position
func get_tile_type(pos: Vector2i) -> TileTypes.Type:
	var tile = get_tile(pos)
	if tile:
		return tile["type"] as TileTypes.Type
	return TileTypes.Type.ROCK


## Set tile type at position (preserves other data)
## Returns [old_type, new_type] if changed, null otherwise
func set_tile_type(pos: Vector2i, type: TileTypes.Type) -> Variant:
	var tile = get_tile(pos)
	if tile:
		var old_type = tile["type"]
		tile["type"] = type
		# Reset health if type changed
		if old_type != type:
			tile["health"] = TileTypes.get_property(type, "default_health")
			return [old_type, type]
	return null


## Get faction ID at position (-1 for unclaimed)
func get_tile_faction(pos: Vector2i) -> int:
	var tile = get_tile(pos)
	if tile:
		return tile["faction_id"]
	return -1


## Set faction ownership at position
## Returns [old_faction, new_faction] if changed, null otherwise
func set_tile_faction(pos: Vector2i, faction_id: int) -> Variant:
	var tile = get_tile(pos)
	if tile:
		var old_faction = tile["faction_id"]
		tile["faction_id"] = faction_id
		if old_faction != faction_id:
			return [old_faction, faction_id]
	return null


## Get neighboring tiles (4-directional)
func get_neighbors(pos: Vector2i) -> Dictionary:
	var neighbors := {}
	for dir: Vector2i in DIRECTIONS:
		var neighbor_pos: Vector2i = pos + dir
		if is_valid_position(neighbor_pos):
			neighbors[dir] = get_tile(neighbor_pos)
	return neighbors


## Get neighboring tiles (8-directional)
func get_neighbors_8(pos: Vector2i) -> Dictionary:
	var neighbors := {}
	for dir: Vector2i in DIRECTIONS_8:
		var neighbor_pos: Vector2i = pos + dir
		if is_valid_position(neighbor_pos):
			neighbors[dir] = get_tile(neighbor_pos)
	return neighbors


## Get walkable neighbors for pathfinding
func get_walkable_neighbors(pos: Vector2i) -> Array[Vector2i]:
	var walkable: Array[Vector2i] = []
	for dir: Vector2i in DIRECTIONS:
		var neighbor_pos: Vector2i = pos + dir
		if is_valid_position(neighbor_pos):
			var tile: Variant = get_tile(neighbor_pos)
			if tile and TileTypes.is_walkable(tile["type"]):
				walkable.append(neighbor_pos)
	return walkable


## Check if tile is adjacent to faction territory
func is_adjacent_to_faction(pos: Vector2i, faction_id: int) -> bool:
	for dir: Vector2i in DIRECTIONS:
		var neighbor_pos: Vector2i = pos + dir
		if get_tile_faction(neighbor_pos) == faction_id:
			return true
	return false


## Get all tiles owned by a faction
func get_faction_tiles(faction_id: int) -> Array[Vector2i]:
	var faction_tiles: Array[Vector2i] = []
	for pos in tiles.keys():
		if tiles[pos]["faction_id"] == faction_id:
			faction_tiles.append(pos)
	return faction_tiles


## Get faction by ID
func get_faction(faction_id: int) -> FactionData:
	for faction in factions:
		if faction.id == faction_id:
			return faction
	return null


## Convert world position to tile position
func world_to_tile(world_pos: Vector3) -> Vector2i:
	return Vector2i(
		int(floor(world_pos.x / tile_size)),
		int(floor(world_pos.z / tile_size))
	)


## Convert tile position to world position (center of tile)
func tile_to_world(tile_pos: Vector2i) -> Vector3:
	return Vector3(
		tile_pos.x * tile_size + tile_size * 0.5,
		0.0,
		tile_pos.y * tile_size + tile_size * 0.5
	)


## Get map bounds in world coordinates
func get_world_bounds() -> AABB:
	return AABB(
		Vector3.ZERO,
		Vector3(width * tile_size, 10.0, height * tile_size)
	)


# ============================================================================
# Creature Management
# ============================================================================

## Add a creature to the map
func add_creature(creature: CreatureData) -> void:
	if creature.id == 0:
		creature.id = next_creature_id
		next_creature_id += 1
	else:
		next_creature_id = maxi(next_creature_id, creature.id + 1)
	creatures.append(creature)


## Remove a creature from the map
func remove_creature(creature_id: int) -> CreatureData:
	for i in range(creatures.size()):
		if creatures[i].id == creature_id:
			return creatures.pop_at(i)
	return null


## Get creature by ID
func get_creature(creature_id: int) -> CreatureData:
	for creature in creatures:
		if creature.id == creature_id:
			return creature
	return null


## Get all creatures at a tile position
func get_creatures_at(pos: Vector2i) -> Array[CreatureData]:
	var result: Array[CreatureData] = []
	for creature in creatures:
		if creature.tile_position == pos:
			result.append(creature)
	return result


## Get all creatures belonging to a faction
func get_faction_creatures(faction_id: int) -> Array[CreatureData]:
	var result: Array[CreatureData] = []
	for creature in creatures:
		if creature.faction_id == faction_id:
			result.append(creature)
	return result


## Get creatures of a specific type belonging to a faction
func get_faction_creatures_of_type(faction_id: int, creature_type: CreatureTypes.Type) -> Array[CreatureData]:
	var result: Array[CreatureData] = []
	for creature in creatures:
		if creature.faction_id == faction_id and creature.creature_type == creature_type:
			result.append(creature)
	return result


# ============================================================================
# Claim Progress Management
# ============================================================================

## Get claim progress for a tile (0-100, or -1 if not being claimed)
func get_claim_progress(pos: Vector2i) -> float:
	if claim_progress.has(pos):
		return claim_progress[pos]["progress"]
	return -1.0


## Get the faction claiming a tile (-1 if not being claimed)
func get_claiming_faction(pos: Vector2i) -> int:
	if claim_progress.has(pos):
		return claim_progress[pos]["faction_id"]
	return -1


## Start or update claim progress for a tile
func set_claim_progress(pos: Vector2i, faction_id: int, progress: float) -> void:
	claim_progress[pos] = {
		"faction_id": faction_id,
		"progress": clampf(progress, 0.0, 100.0)
	}


## Add to claim progress (positive for claiming, negative for contesting)
## Returns true if claim reached 100%
func add_claim_progress(pos: Vector2i, faction_id: int, amount: float) -> bool:
	if not claim_progress.has(pos):
		claim_progress[pos] = {"faction_id": faction_id, "progress": 0.0}
	
	var current: Dictionary = claim_progress[pos]
	
	# If same faction, add progress
	if current["faction_id"] == faction_id:
		current["progress"] = clampf(current["progress"] + amount, 0.0, 100.0)
	else:
		# Different faction - reduce progress (contesting)
		current["progress"] = current["progress"] - amount
		if current["progress"] <= 0.0:
			# Faction takes over the claim
			current["faction_id"] = faction_id
			current["progress"] = absf(current["progress"])
	
	return current["progress"] >= 100.0


## Clear claim progress for a tile (after claiming completes)
func clear_claim_progress(pos: Vector2i) -> void:
	claim_progress.erase(pos)


## Get all tiles with active claim progress for a faction
func get_faction_claim_targets(faction_id: int) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for pos in claim_progress.keys():
		if claim_progress[pos]["faction_id"] == faction_id:
			result.append(pos)
	return result


# ============================================================================
# Dig Marking and Slot Management
# ============================================================================

## Tiles marked for digging: { Vector2i: int (faction_id) }
var marked_for_digging: Dictionary = {}

## Dig slots per wall face: { wall_pos: { direction: [creature_ids] } }
## direction is Vector2i (0,-1), (1,0), etc.
## Max 3 creatures per face
var dig_slots: Dictionary = {}

## Maximum creatures per dig slot (face)
const MAX_CREATURES_PER_DIG_SLOT := 3


## Mark a tile for digging by a faction
func mark_for_digging(pos: Vector2i, faction_id: int) -> bool:
	var tile = get_tile(pos)
	if not tile:
		return false
	if not TileTypes.is_diggable(tile["type"]):
		return false
	# Already marked
	if marked_for_digging.has(pos):
		return false
	
	marked_for_digging[pos] = faction_id
	return true


## Unmark a tile for digging
func unmark_for_digging(pos: Vector2i) -> void:
	marked_for_digging.erase(pos)
	# Also clear any dig slots for this wall
	dig_slots.erase(pos)


## Check if a tile is marked for digging
func is_marked_for_digging(pos: Vector2i) -> bool:
	return marked_for_digging.has(pos)


## Get the faction that marked a tile for digging (-1 if not marked)
func get_dig_marking_faction(pos: Vector2i) -> int:
	if marked_for_digging.has(pos):
		return marked_for_digging[pos]
	return -1


## Get all tiles marked for digging by a faction
func get_faction_dig_targets(faction_id: int) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for pos in marked_for_digging.keys():
		if marked_for_digging[pos] == faction_id:
			result.append(pos)
	return result


## Get creatures currently in a dig slot for a wall face
func get_dig_slot(wall_pos: Vector2i, direction: Vector2i) -> Array:
	if not dig_slots.has(wall_pos):
		return []
	if not dig_slots[wall_pos].has(direction):
		return []
	return dig_slots[wall_pos][direction]


## Check if a dig slot has room for more creatures
func has_available_dig_slot(wall_pos: Vector2i, direction: Vector2i) -> bool:
	var slot := get_dig_slot(wall_pos, direction)
	return slot.size() < MAX_CREATURES_PER_DIG_SLOT


## Claim a dig slot for a creature
## Returns the slot index (0, 1, 2) if successful, -1 if slot is full or invalid
func claim_dig_slot(wall_pos: Vector2i, direction: Vector2i, creature_id: int) -> int:
	# Validate the adjacent tile is walkable (valid dig face)
	var adjacent_pos := wall_pos + direction
	var adjacent_tile = get_tile(adjacent_pos)
	if not adjacent_tile or not TileTypes.is_walkable(adjacent_tile["type"]):
		return -1
	
	# Initialize slot structure if needed
	if not dig_slots.has(wall_pos):
		dig_slots[wall_pos] = {}
	if not dig_slots[wall_pos].has(direction):
		dig_slots[wall_pos][direction] = []
	
	var slot: Array = dig_slots[wall_pos][direction]
	
	# Check if creature already has this slot
	var existing_index := slot.find(creature_id)
	if existing_index != -1:
		return existing_index
	
	# Check if slot is full
	if slot.size() >= MAX_CREATURES_PER_DIG_SLOT:
		return -1
	
	var slot_index := slot.size()
	slot.append(creature_id)
	return slot_index


## Release a dig slot when creature stops digging
func release_dig_slot(wall_pos: Vector2i, direction: Vector2i, creature_id: int) -> void:
	if not dig_slots.has(wall_pos):
		return
	if not dig_slots[wall_pos].has(direction):
		return
	
	var slot: Array = dig_slots[wall_pos][direction]
	slot.erase(creature_id)
	
	# Clean up empty structures
	if slot.is_empty():
		dig_slots[wall_pos].erase(direction)
	if dig_slots[wall_pos].is_empty():
		dig_slots.erase(wall_pos)


## Release all dig slots for a creature (used when creature dies or task is cancelled)
func release_all_dig_slots_for_creature(creature_id: int) -> void:
	for wall_pos in dig_slots.keys():
		for direction in dig_slots[wall_pos].keys():
			var slot: Array = dig_slots[wall_pos][direction]
			slot.erase(creature_id)
		# Clean up empty directions
		var empty_dirs: Array[Vector2i] = []
		for direction in dig_slots[wall_pos].keys():
			if dig_slots[wall_pos][direction].is_empty():
				empty_dirs.append(direction)
		for direction in empty_dirs:
			dig_slots[wall_pos].erase(direction)
	# Clean up empty walls
	var empty_walls: Array[Vector2i] = []
	for wall_pos in dig_slots.keys():
		if dig_slots[wall_pos].is_empty():
			empty_walls.append(wall_pos)
	for wall_pos in empty_walls:
		dig_slots.erase(wall_pos)


## Get an available dig face for a wall (returns direction with available slots)
## Returns Vector2i.ZERO if no face is available
func get_available_dig_face(wall_pos: Vector2i) -> Vector2i:
	for direction: Vector2i in DIRECTIONS:
		var adjacent_pos: Vector2i = wall_pos + direction
		var adjacent_tile = get_tile(adjacent_pos)
		
		# Face must be adjacent to a walkable tile
		if not adjacent_tile or not TileTypes.is_walkable(adjacent_tile["type"]):
			continue
		
		# Check if this face has available slots
		if has_available_dig_slot(wall_pos, direction):
			return direction
	
	return Vector2i.ZERO


## Get all available dig faces for a wall
func get_all_available_dig_faces(wall_pos: Vector2i) -> Array[Vector2i]:
	var faces: Array[Vector2i] = []
	for direction: Vector2i in DIRECTIONS:
		var adjacent_pos: Vector2i = wall_pos + direction
		var adjacent_tile = get_tile(adjacent_pos)
		
		# Face must be adjacent to a walkable tile
		if not adjacent_tile or not TileTypes.is_walkable(adjacent_tile["type"]):
			continue
		
		# Check if this face has available slots
		if has_available_dig_slot(wall_pos, direction):
			faces.append(direction)
	
	return faces


## Get total number of creatures digging a wall (across all faces)
func get_total_diggers_on_wall(wall_pos: Vector2i) -> int:
	if not dig_slots.has(wall_pos):
		return 0
	
	var total := 0
	for direction in dig_slots[wall_pos].keys():
		total += dig_slots[wall_pos][direction].size()
	return total


## Clear all dig data for a wall (called when wall is destroyed)
func clear_dig_data(wall_pos: Vector2i) -> void:
	marked_for_digging.erase(wall_pos)
	dig_slots.erase(wall_pos)
