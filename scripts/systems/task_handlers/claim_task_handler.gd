class_name ClaimTaskHandler
extends BaseTaskHandler
## Handler for tile claiming tasks.


## Safe distance from enemy creatures (in tiles)
const ENEMY_SAFE_DISTANCE := 1


## Find a claimable tile adjacent to faction territory
func find_target(creature: CreatureData, excluded_tiles: Array[Vector2i] = []) -> Vector2i:
	if not pathfinding or not map_data:
		return Vector2i(-1, -1)
	
	# Find nearest claimable tile that is:
	# 1. A FLOOR tile (unclaimed)
	# 2. Adjacent to faction territory
	# 3. Not already being claimed by another creature (excluded_tiles)
	# 4. Not within safe distance of an enemy creature
	return pathfinding.find_nearest_tile(creature.tile_position, func(pos: Vector2i, tile: Dictionary) -> bool:
		# Skip tiles already being worked on
		if pos in excluded_tiles:
			return false
		# Must be claimable (FLOOR type)
		if not TileTypes.is_claimable(tile["type"]):
			return false
		# Must be adjacent to faction territory
		if not map_data.is_adjacent_to_faction(pos, creature.faction_id):
			return false
		# Must be safe distance from enemy creatures
		if _is_near_enemy(pos, creature.faction_id):
			return false
		return true
	)


## Check if a position is within safe distance of an enemy creature
func _is_near_enemy(pos: Vector2i, my_faction_id: int) -> bool:
	if not map_data:
		return false
	
	for other_creature in map_data.creatures:
		# Skip creatures from same faction
		if other_creature.faction_id == my_faction_id:
			continue
		
		# Check Manhattan distance
		var dist: int = absi(pos.x - other_creature.tile_position.x) + absi(pos.y - other_creature.tile_position.y)
		if dist <= ENEMY_SAFE_DISTANCE:
			return true
	
	return false


## Execute claiming work
func execute(creature: CreatureData, task: Dictionary, delta: float) -> float:
	if not map_data:
		return 0.0
	
	var target_pos: Vector2i = task.get("target_pos", Vector2i(-1, -1))
	if target_pos == Vector2i(-1, -1):
		return 0.0
	
	# Get creature's claiming skill strength
	var claim_strength := creature.get_skill_strength("claiming")
	
	# Calculate progress for this frame
	# Skill strength is in "units per second", so multiply by delta
	var progress := claim_strength * delta
	
	# Apply progress to the map's claim tracking
	var completed := map_data.add_claim_progress(target_pos, creature.faction_id, progress)
	
	# Emit progress event
	var current_progress := map_data.get_claim_progress(target_pos)
	GameEvents.tile_claim_progress.emit(target_pos, creature.faction_id, current_progress)
	
	# Update task progress
	task["progress"] = current_progress
	
	if completed:
		return 100.0  # Signal completion
	
	return progress


## Check if claiming is complete
func is_complete(creature: CreatureData, task: Dictionary) -> bool:
	var target_pos: Vector2i = task.get("target_pos", Vector2i(-1, -1))
	if target_pos == Vector2i(-1, -1):
		return true  # Invalid task, mark as complete
	
	# Check if tile is now claimed
	var tile = map_data.get_tile(target_pos)
	if tile and tile["type"] == TileTypes.Type.CLAIMED:
		return true
	
	# Check progress
	return map_data.get_claim_progress(target_pos) >= 100.0


## Complete the claiming - convert tile to CLAIMED
func on_complete(creature: CreatureData, task: Dictionary) -> void:
	if not map_data:
		return
	
	var target_pos: Vector2i = task.get("target_pos", Vector2i(-1, -1))
	if target_pos == Vector2i(-1, -1):
		return
	
	# Change tile type to CLAIMED
	var type_result: Variant = map_data.set_tile_type(target_pos, TileTypes.Type.CLAIMED)
	if type_result:
		GameEvents.tile_changed.emit(target_pos, type_result[0], type_result[1])
	
	# Set faction ownership
	var faction_result: Variant = map_data.set_tile_faction(target_pos, creature.faction_id)
	if faction_result:
		GameEvents.tile_ownership_changed.emit(target_pos, faction_result[0], faction_result[1])
	
	# Clear claim progress tracking
	map_data.clear_claim_progress(target_pos)


## Cancel claiming - clear progress
func on_cancel(creature: CreatureData, task: Dictionary) -> void:
	if not map_data:
		return
	
	var target_pos: Vector2i = task.get("target_pos", Vector2i(-1, -1))
	if target_pos == Vector2i(-1, -1):
		return
	
	# Don't clear progress immediately - allow other creatures to continue
	# Progress will decay over time if no one works on it (future feature)


## XP reward scales with level (harder tiles could give more XP in future)
func get_xp_reward(task: Dictionary) -> int:
	return 15  # Claiming XP reward


## Override: Imp stands ON the tile being claimed, not adjacent to it
func get_work_position(target_pos: Vector2i, creature: CreatureData) -> Vector2i:
	# For claiming, the creature stands directly on the target tile
	return target_pos


## Override: Check if creature is standing on the target tile
func is_in_work_position(creature: CreatureData, task: Dictionary) -> bool:
	var target_pos: Vector2i = task.get("target_pos", Vector2i(-1, -1))
	if target_pos == Vector2i(-1, -1):
		return false
	
	# Creature must be ON the target tile
	return creature.tile_position == target_pos
