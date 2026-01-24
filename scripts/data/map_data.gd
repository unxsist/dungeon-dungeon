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
