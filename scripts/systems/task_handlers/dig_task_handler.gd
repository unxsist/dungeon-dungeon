class_name DigTaskHandler
extends BaseTaskHandler
## Handler for wall digging tasks.
## Supports multiple creatures digging the same wall from different faces.
## Up to 3 creatures can dig from each exposed face of a wall.


## Find a diggable tile marked for digging by the creature's faction
## Only returns tiles with available dig slots
func find_target(creature: CreatureData, excluded_tiles: Array[Vector2i] = []) -> Vector2i:
	if not pathfinding or not map_data:
		return Vector2i(-1, -1)
	
	var marked_tiles := map_data.get_faction_dig_targets(creature.faction_id)
	if marked_tiles.is_empty():
		return Vector2i(-1, -1)
	
	# Find nearest wall that is:
	# 1. Marked for digging by this creature's faction
	# 2. Still diggable (is a WALL)
	# 3. Has available dig slots
	var result := pathfinding.find_nearest_tile(creature.tile_position, func(pos: Vector2i, tile: Dictionary) -> bool:
		if pos in excluded_tiles:
			return false
		
		# Must be marked for digging by this faction
		if not map_data.is_marked_for_digging(pos):
			return false
		if map_data.get_dig_marking_faction(pos) != creature.faction_id:
			return false
		
		# Must still be a diggable wall
		if not TileTypes.is_diggable(tile["type"]):
			return false
		
		# Must have an available dig face
		var available_face := map_data.get_available_dig_face(pos)
		if available_face == Vector2i.ZERO:
			return false
		
		return true
	)
	
	return result


## Override get_work_position to claim a dig slot
## Returns the tile position the creature should stand on (adjacent to wall)
func get_work_position(target_pos: Vector2i, creature: CreatureData) -> Vector2i:
	if not map_data:
		return Vector2i(-1, -1)
	
	# Find all available faces and pick the best one (closest to creature)
	var available_faces := map_data.get_all_available_dig_faces(target_pos)
	if available_faces.is_empty():
		return Vector2i(-1, -1)
	
	var best_face := Vector2i.ZERO
	var best_distance := INF
	
	for face in available_faces:
		var work_pos := target_pos + face
		
		# Check if creature can reach this position
		var path := pathfinding.find_path(creature.tile_position, work_pos)
		if path.is_empty() and creature.tile_position != work_pos:
			continue
		
		var dist := path.size() if not path.is_empty() else 0
		if dist < best_distance:
			best_distance = dist
			best_face = face
	
	if best_face == Vector2i.ZERO:
		return Vector2i(-1, -1)
	
	# Claim the dig slot for this face and get slot index
	var slot_index := map_data.claim_dig_slot(target_pos, best_face, creature.id)
	if slot_index == -1:
		return Vector2i(-1, -1)
	
	# Store the claimed face and slot index in the creature's task
	creature.current_task["dig_face"] = best_face
	creature.current_task["dig_slot_index"] = slot_index
	
	return target_pos + best_face


## Execute digging work
func execute(creature: CreatureData, task: Dictionary, delta: float) -> float:
	if not map_data:
		return 0.0
	
	var target_pos: Vector2i = task.get("target_pos", Vector2i(-1, -1))
	if target_pos == Vector2i(-1, -1):
		return 0.0
	
	var tile = map_data.get_tile(target_pos)
	if not tile:
		return 0.0
	
	# Get creature's digging skill strength
	var dig_strength := creature.get_skill_strength("digging")
	
	# Calculate damage for this frame
	var damage := dig_strength * delta
	
	# Apply damage to wall health (stored as float for precision, displayed as int)
	# Use float health to avoid truncation errors with small delta values
	var current_health: float = tile.get("health_float", float(tile.get("health", 100)))
	var new_health := maxf(0.0, current_health - damage)
	tile["health_float"] = new_health
	tile["health"] = int(new_health)  # Integer version for display/checks
	
	# Emit progress event for visual feedback
	GameEvents.dig_progress.emit(target_pos, int(new_health), 100)
	
	# Calculate progress as percentage of damage dealt
	var progress := (damage / 100.0) * 100.0  # Assuming 100 total health
	task["progress"] = task.get("progress", 0.0) + progress
	
	if new_health <= 0:
		return 100.0  # Signal completion
	
	return progress


## Check if digging is complete
func is_complete(creature: CreatureData, task: Dictionary) -> bool:
	var target_pos: Vector2i = task.get("target_pos", Vector2i(-1, -1))
	if target_pos == Vector2i(-1, -1):
		return true  # Invalid task
	
	var tile = map_data.get_tile(target_pos)
	if not tile:
		return true  # Tile doesn't exist
	
	# Check if tile is already a floor (was dug by another creature)
	if tile["type"] != TileTypes.Type.WALL:
		return true
	
	# Check if health depleted
	return tile.get("health", 100) <= 0


## Complete digging - convert wall to floor and clean up dig data
func on_complete(creature: CreatureData, task: Dictionary) -> void:
	if not map_data:
		return
	
	var target_pos: Vector2i = task.get("target_pos", Vector2i(-1, -1))
	if target_pos == Vector2i(-1, -1):
		return
	
	# Release dig slot for this creature
	_release_creature_dig_slot(creature, task)
	
	# Only convert to floor if it's still a wall (another creature might have finished first)
	var tile = map_data.get_tile(target_pos)
	if tile and tile["type"] == TileTypes.Type.WALL:
		# Change tile type to FLOOR
		var type_result: Variant = map_data.set_tile_type(target_pos, TileTypes.Type.FLOOR)
		if type_result:
			GameEvents.tile_changed.emit(target_pos, type_result[0], type_result[1])
			GameEvents.dig_completed.emit(target_pos)
		
		# Clear all dig data for this wall (marking and remaining slots)
		map_data.clear_dig_data(target_pos)


## Called when task is cancelled - release the dig slot
func on_cancel(creature: CreatureData, task: Dictionary) -> void:
	_release_creature_dig_slot(creature, task)


## Helper to release a creature's dig slot
func _release_creature_dig_slot(creature: CreatureData, task: Dictionary) -> void:
	if not map_data:
		return
	
	var target_pos: Vector2i = task.get("target_pos", Vector2i(-1, -1))
	if target_pos == Vector2i(-1, -1):
		return
	
	var dig_face: Variant = task.get("dig_face")
	if dig_face != null and dig_face is Vector2i:
		map_data.release_dig_slot(target_pos, dig_face, creature.id)


## XP reward for digging
func get_xp_reward(task: Dictionary) -> int:
	return 20  # Digging gives more XP than claiming
