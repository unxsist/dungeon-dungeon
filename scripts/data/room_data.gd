class_name RoomData
extends Resource
## Data class representing a single room instance.

## Unique room identifier
@export var id: int = 0

## Type of room (Lair, Hatchery, etc.)
@export var room_type: RoomTypes.Type = RoomTypes.Type.LAIR

## Tiles that belong to this room
@export var tiles: Array[Vector2i] = []

## Faction that owns this room
@export var faction_id: int = 0

## Room level (for future upgrades)
@export var level: int = 1


## Get the number of tiles in this room
func get_size() -> int:
	return tiles.size()


## Get the total cost that was paid for this room
func get_total_cost() -> int:
	return RoomTypes.calculate_cost(room_type, tiles.size())


## Get the refund amount when selling this room (50% of cost)
func get_sell_refund() -> int:
	return get_total_cost() / 2


## Check if a position is part of this room
func contains_tile(pos: Vector2i) -> bool:
	return pos in tiles


## Get the bounding rectangle of this room
func get_bounds() -> Rect2i:
	if tiles.is_empty():
		return Rect2i()
	
	var min_x := tiles[0].x
	var max_x := tiles[0].x
	var min_y := tiles[0].y
	var max_y := tiles[0].y
	
	for tile in tiles:
		min_x = mini(min_x, tile.x)
		max_x = maxi(max_x, tile.x)
		min_y = mini(min_y, tile.y)
		max_y = maxi(max_y, tile.y)
	
	return Rect2i(min_x, min_y, max_x - min_x + 1, max_y - min_y + 1)


## Get the center position of the room (approximate)
func get_center() -> Vector2i:
	if tiles.is_empty():
		return Vector2i.ZERO
	
	var sum := Vector2i.ZERO
	for tile in tiles:
		sum += tile
	return sum / tiles.size()


## Create RoomData from a dictionary (for loading from JSON)
static func from_dict(data: Dictionary) -> RoomData:
	var room := RoomData.new()
	room.id = data.get("id", 0)
	room.room_type = RoomTypes.from_string(data.get("room_type", "lair"))
	room.faction_id = data.get("faction_id", 0)
	room.level = data.get("level", 1)
	
	# Parse tiles array
	var tiles_data: Array = data.get("tiles", [])
	for tile_data in tiles_data:
		if tile_data is Dictionary:
			room.tiles.append(Vector2i(tile_data.get("x", 0), tile_data.get("y", 0)))
		elif tile_data is Array and tile_data.size() >= 2:
			room.tiles.append(Vector2i(tile_data[0], tile_data[1]))
	
	return room


## Convert to dictionary (for saving to JSON)
func to_dict() -> Dictionary:
	var tiles_data: Array[Dictionary] = []
	for tile in tiles:
		tiles_data.append({"x": tile.x, "y": tile.y})
	
	return {
		"id": id,
		"room_type": RoomTypes.to_string_name(room_type),
		"tiles": tiles_data,
		"faction_id": faction_id,
		"level": level,
	}
