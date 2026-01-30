class_name PathfindingSystem
extends Node
## System for A* pathfinding on the tile grid using AStar2D.

## Reference to map data
var map_data: MapData = null

## AStar2D instance for pathfinding
var astar: AStar2D = AStar2D.new()

## Mapping from Vector2i tile position to AStar point ID
var tile_to_point: Dictionary = {}

## Mapping from AStar point ID to Vector2i tile position
var point_to_tile: Dictionary = {}

## Next point ID for AStar
var next_point_id: int = 0


func _ready() -> void:
	GameEvents.map_loaded.connect(_on_map_loaded)
	GameEvents.tile_changed.connect(_on_tile_changed)


## Initialize pathfinding when map is loaded
func _on_map_loaded(data: MapData) -> void:
	map_data = data
	rebuild_graph()


## Rebuild the entire navigation graph
func rebuild_graph() -> void:
	if not map_data:
		return
	
	astar.clear()
	tile_to_point.clear()
	point_to_tile.clear()
	next_point_id = 0
	
	# First pass: add all walkable tiles as points
	for pos in map_data.tiles.keys():
		var tile: Dictionary = map_data.tiles[pos]
		if TileTypes.is_walkable(tile["type"]):
			_add_point(pos)
	
	# Second pass: connect adjacent walkable tiles
	for pos in tile_to_point.keys():
		_connect_neighbors(pos)


## Add a point for a tile position
func _add_point(pos: Vector2i) -> int:
	if tile_to_point.has(pos):
		return tile_to_point[pos]
	
	var point_id := next_point_id
	next_point_id += 1
	
	# Use tile position as the point position (scaled for distance calculations)
	astar.add_point(point_id, Vector2(pos))
	tile_to_point[pos] = point_id
	point_to_tile[point_id] = pos
	
	return point_id


## Remove a point for a tile position
func _remove_point(pos: Vector2i) -> void:
	if not tile_to_point.has(pos):
		return
	
	var point_id: int = tile_to_point[pos]
	astar.remove_point(point_id)
	tile_to_point.erase(pos)
	point_to_tile.erase(point_id)


## Connect a tile to its walkable neighbors
func _connect_neighbors(pos: Vector2i) -> void:
	if not tile_to_point.has(pos):
		return
	
	var point_id: int = tile_to_point[pos]
	
	for dir in MapData.DIRECTIONS:
		var neighbor_pos: Vector2i = pos + dir
		if tile_to_point.has(neighbor_pos):
			var neighbor_id: int = tile_to_point[neighbor_pos]
			if not astar.are_points_connected(point_id, neighbor_id):
				astar.connect_points(point_id, neighbor_id)


## Handle tile type changes
func _on_tile_changed(position: Vector2i, old_type: int, new_type: int) -> void:
	var was_walkable := TileTypes.is_walkable(old_type as TileTypes.Type)
	var is_walkable := TileTypes.is_walkable(new_type as TileTypes.Type)
	
	if was_walkable and not is_walkable:
		# Tile became unwalkable - remove from graph
		_remove_point(position)
	elif not was_walkable and is_walkable:
		# Tile became walkable - add to graph
		_add_point(position)
		_connect_neighbors(position)
		# Also update neighbors to connect to this new point
		for dir in MapData.DIRECTIONS:
			var neighbor_pos: Vector2i = position + dir
			if tile_to_point.has(neighbor_pos):
				_connect_neighbors(neighbor_pos)


## Find a path between two tile positions
## Returns empty array if no path exists
func find_path(from: Vector2i, to: Vector2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	
	if not tile_to_point.has(from) or not tile_to_point.has(to):
		return result
	
	var from_id: int = tile_to_point[from]
	var to_id: int = tile_to_point[to]
	
	var path: PackedVector2Array = astar.get_point_path(from_id, to_id)
	
	for point in path:
		result.append(Vector2i(point))
	
	return result


## Find path within faction territory only (for wandering)
## This temporarily disables points outside faction territory
func find_path_in_territory(from: Vector2i, to: Vector2i, faction_id: int) -> Array[Vector2i]:
	if not map_data:
		return []
	
	# Store original disabled states
	var disabled_points: Array[int] = []
	
	# Disable all points outside faction territory
	for pos in tile_to_point.keys():
		var tile_faction := map_data.get_tile_faction(pos)
		if tile_faction != faction_id:
			var point_id: int = tile_to_point[pos]
			if not astar.is_point_disabled(point_id):
				astar.set_point_disabled(point_id, true)
				disabled_points.append(point_id)
	
	# Find path
	var result := find_path(from, to)
	
	# Re-enable disabled points
	for point_id in disabled_points:
		astar.set_point_disabled(point_id, false)
	
	return result


## Get a random walkable neighbor tile for wandering
func get_random_walkable_neighbor(pos: Vector2i, faction_id: int = -1) -> Vector2i:
	if not map_data:
		return Vector2i(-1, -1)
	
	var candidates: Array[Vector2i] = []
	
	for dir in MapData.DIRECTIONS:
		var neighbor_pos: Vector2i = pos + dir
		if not map_data.is_valid_position(neighbor_pos):
			continue
		
		var tile = map_data.get_tile(neighbor_pos)
		if not tile or not TileTypes.is_walkable(tile["type"]):
			continue
		
		# If faction specified, only consider tiles of that faction
		if faction_id >= 0 and tile["faction_id"] != faction_id:
			continue
		
		candidates.append(neighbor_pos)
	
	if candidates.is_empty():
		return Vector2i(-1, -1)
	
	return candidates[randi() % candidates.size()]


## Find nearest tile matching a condition
## condition_func takes (Vector2i, Dictionary) -> bool
func find_nearest_tile(from: Vector2i, condition: Callable, max_distance: int = 50) -> Vector2i:
	if not map_data:
		return Vector2i(-1, -1)
	
	# BFS to find nearest matching tile
	var visited: Dictionary = {}
	var queue: Array[Vector2i] = [from]
	visited[from] = true
	
	while not queue.is_empty():
		var current: Vector2i = queue.pop_front()
		
		# Check distance limit
		var dist := absi(current.x - from.x) + absi(current.y - from.y)
		if dist > max_distance:
			continue
		
		# Check if this tile matches condition
		var tile = map_data.get_tile(current)
		if tile and condition.call(current, tile):
			return current
		
		# Add walkable neighbors to queue
		for dir in MapData.DIRECTIONS:
			var neighbor_pos: Vector2i = current + dir
			if visited.has(neighbor_pos):
				continue
			if not map_data.is_valid_position(neighbor_pos):
				continue
			
			visited[neighbor_pos] = true
			
			# Only expand through walkable tiles (or the target itself)
			var neighbor_tile = map_data.get_tile(neighbor_pos)
			if neighbor_tile:
				# Check if target matches condition (even if not walkable)
				if condition.call(neighbor_pos, neighbor_tile):
					return neighbor_pos
				# Only add to queue if walkable
				if TileTypes.is_walkable(neighbor_tile["type"]):
					queue.append(neighbor_pos)
	
	return Vector2i(-1, -1)


## Find nearest claimable tile adjacent to faction territory
func find_nearest_claimable(from: Vector2i, faction_id: int) -> Vector2i:
	return find_nearest_tile(from, func(pos: Vector2i, tile: Dictionary) -> bool:
		# Must be claimable (FLOOR type)
		if not TileTypes.is_claimable(tile["type"]):
			return false
		# Must be adjacent to faction territory
		return map_data.is_adjacent_to_faction(pos, faction_id)
	)


## Find nearest diggable tile adjacent to faction territory
func find_nearest_diggable(from: Vector2i, faction_id: int) -> Vector2i:
	return find_nearest_tile(from, func(pos: Vector2i, tile: Dictionary) -> bool:
		# Must be diggable (WALL type)
		if not TileTypes.is_diggable(tile["type"]):
			return false
		# Must be adjacent to faction territory
		return map_data.is_adjacent_to_faction(pos, faction_id)
	)


## Check if a path exists between two points
func has_path(from: Vector2i, to: Vector2i) -> bool:
	if not tile_to_point.has(from) or not tile_to_point.has(to):
		return false
	
	var from_id: int = tile_to_point[from]
	var to_id: int = tile_to_point[to]
	
	return astar.get_point_path(from_id, to_id).size() > 0


## Get path length (number of tiles)
func get_path_length(from: Vector2i, to: Vector2i) -> int:
	var path := find_path(from, to)
	return path.size()
