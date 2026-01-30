class_name BaseTaskHandler
extends RefCounted
## Base class for task handlers. Extend this to create handlers for specific task types.

## Reference to the map data
var map_data: MapData = null

## Reference to pathfinding system
var pathfinding: PathfindingSystem = null


## Initialize the handler with required references
func initialize(map: MapData, pathfinder: PathfindingSystem) -> void:
	map_data = map
	pathfinding = pathfinder


## Find a target for this task type for a given creature
## excluded_tiles: tiles already being worked on by other creatures
## Returns Vector2i(-1, -1) if no valid target found
## Override in subclasses
func find_target(creature: CreatureData, excluded_tiles: Array[Vector2i] = []) -> Vector2i:
	return Vector2i(-1, -1)


## Execute the task work for one frame
## Returns progress amount (0-100 scale per call, accumulated over time)
## Override in subclasses
func execute(creature: CreatureData, task: Dictionary, delta: float) -> float:
	return 0.0


## Check if the task is complete
## Override in subclasses
func is_complete(creature: CreatureData, task: Dictionary) -> bool:
	return task.get("progress", 0.0) >= 100.0


## Called when task is completed successfully
## Override in subclasses for completion logic
func on_complete(creature: CreatureData, task: Dictionary) -> void:
	pass


## Called when task is cancelled or fails
## Override in subclasses for cleanup
func on_cancel(creature: CreatureData, task: Dictionary) -> void:
	pass


## Get the tile position the creature needs to stand on to perform the task
## By default, creatures need to stand adjacent to the target
## Override for tasks that require standing ON the target
func get_work_position(target_pos: Vector2i, creature: CreatureData) -> Vector2i:
	if not map_data:
		return Vector2i(-1, -1)
	
	# Find the nearest walkable tile adjacent to target that creature can reach
	var best_pos := Vector2i(-1, -1)
	var best_distance := INF
	
	for dir in MapData.DIRECTIONS:
		var adjacent: Vector2i = target_pos + dir
		if not map_data.is_valid_position(adjacent):
			continue
		
		var tile = map_data.get_tile(adjacent)
		if not tile or not TileTypes.is_walkable(tile["type"]):
			continue
		
		# Check if creature can reach this position
		var path := pathfinding.find_path(creature.tile_position, adjacent)
		if path.is_empty() and creature.tile_position != adjacent:
			continue
		
		var dist := path.size()
		if dist < best_distance:
			best_distance = dist
			best_pos = adjacent
	
	return best_pos


## Check if creature is in position to work on the task
func is_in_work_position(creature: CreatureData, task: Dictionary) -> bool:
	var target_pos: Vector2i = task.get("target_pos", Vector2i(-1, -1))
	if target_pos == Vector2i(-1, -1):
		return false
	
	# Check if adjacent to target
	var diff := creature.tile_position - target_pos
	return absi(diff.x) + absi(diff.y) == 1


## Calculate XP reward for completing this task
## Override in subclasses for task-specific rewards
func get_xp_reward(task: Dictionary) -> int:
	return 10  # Base XP reward
