class_name CreatureSystem
extends Node
## Main system for managing creatures - spawning, movement, state machine, and updates.

## Reference to map data
var map_data: MapData = null

## Reference to pathfinding system
var pathfinding: PathfindingSystem = null

## Reference to task system
var task_system: TaskSystem = null

## Wander cooldown range (seconds)
const WANDER_COOLDOWN_MIN := 2.0
const WANDER_COOLDOWN_MAX := 5.0

## Creature wander timers: { creature_id: float }
var wander_timers: Dictionary = {}

## Creature wander targets (visual positions): { creature_id: Vector2 }
var wander_targets: Dictionary = {}

## Creature work targets (visual positions): { creature_id: Vector2 }
var work_targets: Dictionary = {}

## Happiness decay rate per second
const HAPPINESS_DECAY_RATE := 0.1


func _ready() -> void:
	GameEvents.map_loaded.connect(_on_map_loaded)
	GameEvents.dig_marked.connect(_on_dig_marked)
	GameEvents.creature_state_changed.connect(_on_creature_state_changed)


## Initialize when map is loaded
func _on_map_loaded(data: MapData) -> void:
	map_data = data
	wander_timers.clear()
	wander_targets.clear()
	work_targets.clear()
	
	# Defer spawn events to ensure all map_loaded handlers complete first
	# This prevents race conditions with CreatureRenderer clearing sprites
	call_deferred("_emit_initial_spawns")


## Emit spawn events for creatures loaded with the map
func _emit_initial_spawns() -> void:
	if not map_data:
		return
	
	for creature in map_data.creatures:
		# Initialize visual position based on tile position
		creature.visual_position = _tile_to_visual_position(creature.tile_position)
		GameEvents.creature_spawned.emit(creature)
	
	print("CreatureSystem: Spawned %d creatures" % map_data.creatures.size())


## Set system references (called by scene setup)
func set_references(pathfinder: PathfindingSystem, task_sys: TaskSystem) -> void:
	pathfinding = pathfinder
	task_system = task_sys


## Process all creatures each frame
func _process(delta: float) -> void:
	if not map_data:
		return
	
	for creature in map_data.creatures:
		_process_creature(creature, delta)


## Process a single creature
func _process_creature(creature: CreatureData, delta: float) -> void:
	match creature.state:
		CreatureTypes.State.IDLE:
			_process_idle(creature, delta)
		CreatureTypes.State.WALKING:
			_process_walking(creature, delta)
		CreatureTypes.State.WORKING:
			_process_working(creature, delta)
		CreatureTypes.State.WANDERING:
			_process_wandering(creature, delta)
	
	# Process happiness decay (slow)
	_process_happiness(creature, delta)


## Process idle creature - try to get a task
func _process_idle(creature: CreatureData, delta: float) -> void:
	if not task_system:
		# No task system - start wandering
		_start_wandering(creature)
		return
	
	# Try to get a task
	var task := task_system.request_task(creature)
	
	if task.is_empty():
		# No task available - start wandering
		_start_wandering(creature)
		return
	
	# Got a task - pathfind to work position
	var work_pos := task_system.get_work_position(creature)
	if work_pos == Vector2i(-1, -1):
		# Can't reach work position
		task_system.cancel_task(creature)
		_start_wandering(creature)
		return
	
	# Set up path to work position
	creature.target_tile = work_pos
	creature.current_path = pathfinding.find_path(creature.tile_position, work_pos)
	creature.path_index = 0
	
	if creature.current_path.is_empty() and creature.tile_position != work_pos:
		# Can't find path
		task_system.cancel_task(creature)
		_start_wandering(creature)
		return
	
	# Start walking to task
	_set_creature_state(creature, CreatureTypes.State.WALKING)


## Process walking creature - move along path
func _process_walking(creature: CreatureData, delta: float) -> void:
	if creature.has_reached_destination():
		# Arrived at destination
		if creature.current_task.is_empty():
			# Was just wandering
			_set_creature_state(creature, CreatureTypes.State.IDLE)
		elif task_system and task_system.is_creature_in_work_position(creature):
			# Arrived at work position tile - calculate exact work position and start working
			_calculate_work_target(creature)
			_set_creature_state(creature, CreatureTypes.State.WORKING)
		else:
			# Something went wrong - go idle
			_set_creature_state(creature, CreatureTypes.State.IDLE)
		return
	
	_process_movement(creature, delta)


## Process working creature - execute task
func _process_working(creature: CreatureData, delta: float) -> void:
	if creature.current_task.is_empty():
		_set_creature_state(creature, CreatureTypes.State.IDLE)
		return
	
	if not task_system:
		_set_creature_state(creature, CreatureTypes.State.IDLE)
		return
	
	# Move toward work position if not there yet
	if work_targets.has(creature.id):
		var target_pos: Vector2 = work_targets[creature.id]
		var distance := creature.visual_position.distance_to(target_pos)
		
		if distance > 0.1:
			# Still walking to work position
			var direction := (target_pos - creature.visual_position).normalized()
			var move_speed := creature.get_speed() * map_data.tile_size
			creature.visual_position += direction * move_speed * delta
			
			# Don't execute work while walking to position
			return
		else:
			# Arrived at work position
			creature.visual_position = target_pos
			work_targets.erase(creature.id)
	
	# Execute task work
	task_system.execute_task(creature, delta)
	
	# Task system will set state to IDLE when complete


## Process wandering creature - free roaming within faction territory
func _process_wandering(creature: CreatureData, delta: float) -> void:
	# Update wander timer
	if not wander_timers.has(creature.id):
		wander_timers[creature.id] = randf_range(WANDER_COOLDOWN_MIN, WANDER_COOLDOWN_MAX)
	
	# Check if we have a wander target
	var has_target := wander_targets.has(creature.id)
	var target_pos: Vector2 = wander_targets.get(creature.id, Vector2.ZERO)
	
	# Move toward target if we have one
	if has_target:
		var direction := (target_pos - creature.visual_position).normalized()
		var move_speed := creature.get_speed() * map_data.tile_size  # Convert tiles/sec to units/sec
		
		creature.visual_position += direction * move_speed * delta
		
		# Update tile position based on visual position
		var new_tile := _visual_to_tile_position(creature.visual_position)
		if new_tile != creature.tile_position:
			var old_tile := creature.tile_position
			creature.tile_position = new_tile
			GameEvents.creature_moved.emit(creature.id, old_tile, new_tile)
		
		# Check if reached target
		if creature.visual_position.distance_to(target_pos) < 0.5:
			wander_targets.erase(creature.id)
			has_target = false
	
	# Pick new target when timer expires or we have no target
	wander_timers[creature.id] -= delta
	if wander_timers[creature.id] <= 0 or not has_target:
		wander_timers[creature.id] = randf_range(WANDER_COOLDOWN_MIN, WANDER_COOLDOWN_MAX)
		
		# 30% chance to check for tasks instead of wandering more
		if randf() < 0.3:
			wander_targets.erase(creature.id)
			_set_creature_state(creature, CreatureTypes.State.IDLE)
			return
		
		# Pick a random point within a walkable tile in faction territory
		_pick_wander_target(creature)


## Process movement along path
func _process_movement(creature: CreatureData, delta: float) -> void:
	if creature.path_index >= creature.current_path.size():
		return
	
	var target_tile: Vector2i = creature.current_path[creature.path_index]
	var target_pos := _tile_to_visual_position(target_tile)
	
	var direction := (target_pos - creature.visual_position).normalized()
	var move_speed := creature.get_speed() * map_data.tile_size  # Convert tiles/sec to units/sec
	
	creature.visual_position += direction * move_speed * delta
	
	# Check if reached current path node
	if creature.visual_position.distance_to(target_pos) < 0.1:
		var old_tile := creature.tile_position
		creature.tile_position = target_tile
		creature.visual_position = target_pos
		creature.path_index += 1
		
		if old_tile != target_tile:
			GameEvents.creature_moved.emit(creature.id, old_tile, target_tile)


## Process happiness decay
func _process_happiness(creature: CreatureData, delta: float) -> void:
	# Slow happiness decay
	var old_happiness := creature.happiness
	creature.happiness = maxf(0.0, creature.happiness - HAPPINESS_DECAY_RATE * delta)
	
	# Emit event on significant change (every 5%)
	if int(old_happiness / 5.0) != int(creature.happiness / 5.0):
		GameEvents.creature_happiness_changed.emit(creature.id, creature.happiness)


## Calculate the exact visual work position for a creature's task
## Takes into account dig slot index to spread multiple creatures along a wall face
func _calculate_work_target(creature: CreatureData) -> void:
	if not map_data:
		return
	
	var task := creature.current_task
	if task.is_empty():
		return
	
	# For dig tasks, calculate position based on slot index
	if task.get("type") == TaskTypes.Type.DIG:
		var dig_face: Variant = task.get("dig_face")
		var slot_index: int = task.get("dig_slot_index", 0)
		
		if dig_face != null and dig_face is Vector2i:
			var tile_center := _tile_to_visual_position(creature.tile_position)
			
			# Direction toward the wall
			var toward_wall := -Vector2(dig_face)
			# Direction perpendicular to wall (for spreading creatures along the face)
			var along_wall := Vector2(-toward_wall.y, toward_wall.x)
			
			# Offset toward wall (35% of tile)
			var wall_offset := toward_wall * map_data.tile_size * 0.35
			
			# Spread along wall based on slot index (0, 1, 2 -> -1, 0, 1 positions)
			# Each slot is spaced 25% of tile width apart
			var spread_offset := along_wall * (slot_index - 1) * map_data.tile_size * 0.25
			
			work_targets[creature.id] = tile_center + wall_offset + spread_offset


## Start wandering behavior
func _start_wandering(creature: CreatureData) -> void:
	wander_timers[creature.id] = 0.0  # Immediate wander
	wander_targets.erase(creature.id)  # Clear any old target
	_set_creature_state(creature, CreatureTypes.State.WANDERING)


## Pick a random wander target for a creature
func _pick_wander_target(creature: CreatureData) -> void:
	if not pathfinding or not map_data:
		return
	
	# Get a random walkable neighboring tile (or current tile)
	var target_tile := pathfinding.get_random_walkable_neighbor(
		creature.tile_position, 
		creature.faction_id
	)
	
	# If no neighbor found, stay in current tile
	if target_tile == Vector2i(-1, -1):
		target_tile = creature.tile_position
	
	# Pick a random point within that tile (with some padding from edges)
	var tile_origin := Vector2(target_tile) * map_data.tile_size
	var padding := map_data.tile_size * 0.15  # Stay away from tile edges
	var random_offset := Vector2(
		randf_range(padding, map_data.tile_size - padding),
		randf_range(padding, map_data.tile_size - padding)
	)
	
	wander_targets[creature.id] = tile_origin + random_offset


## Handle dig marked event - interrupt wandering creatures to check for dig tasks
func _on_dig_marked(position: Vector2i, faction_id: int) -> void:
	if not map_data:
		return
	
	# Make wandering creatures of this faction check for tasks
	for creature in map_data.creatures:
		if creature.faction_id != faction_id:
			continue
		if creature.state == CreatureTypes.State.WANDERING:
			# Interrupt wandering - go back to idle to check for tasks
			_set_creature_state(creature, CreatureTypes.State.IDLE)


## Set creature state with event emission
func _set_creature_state(creature: CreatureData, new_state: CreatureTypes.State) -> void:
	var old_state := creature.state
	creature.set_state(new_state)
	
	if old_state != new_state:
		GameEvents.creature_state_changed.emit(creature.id, old_state, new_state)


## Handle creature state changes (including from external systems like TaskSystem)
func _on_creature_state_changed(creature_id: int, old_state: int, new_state: int) -> void:
	# Clean up work target when leaving WORKING state
	if old_state == CreatureTypes.State.WORKING and new_state != CreatureTypes.State.WORKING:
		work_targets.erase(creature_id)


## Convert tile position to visual position (2D world coordinates)
func _tile_to_visual_position(tile_pos: Vector2i) -> Vector2:
	if not map_data:
		return Vector2(tile_pos) * 4.0 + Vector2(2.0, 2.0)  # Default tile size
	return Vector2(tile_pos) * map_data.tile_size + Vector2(map_data.tile_size, map_data.tile_size) / 2.0


## Convert visual position to tile position
func _visual_to_tile_position(visual_pos: Vector2) -> Vector2i:
	if not map_data:
		return Vector2i(visual_pos / 4.0)
	return Vector2i(visual_pos / map_data.tile_size)


## Spawn a new creature
func spawn_creature(creature_type: CreatureTypes.Type, faction_id: int, tile_pos: Vector2i, level: int = 1) -> CreatureData:
	if not map_data:
		return null
	
	var creature := CreatureData.new()
	creature.initialize(creature_type, level)
	creature.faction_id = faction_id
	creature.tile_position = tile_pos
	creature.visual_position = _tile_to_visual_position(tile_pos)
	
	map_data.add_creature(creature)
	GameEvents.creature_spawned.emit(creature)
	
	return creature


## Despawn a creature
func despawn_creature(creature_id: int) -> void:
	if not map_data:
		return
	
	var creature := map_data.remove_creature(creature_id)
	if creature:
		# Cancel any active task
		if task_system and not creature.current_task.is_empty():
			task_system.cancel_task(creature)
		
		wander_timers.erase(creature_id)
		wander_targets.erase(creature_id)
		work_targets.erase(creature_id)
		GameEvents.creature_despawned.emit(creature_id)


## Get creature by ID
func get_creature(creature_id: int) -> CreatureData:
	if not map_data:
		return null
	return map_data.get_creature(creature_id)


## Get creatures at a tile position
func get_creatures_at(tile_pos: Vector2i) -> Array[CreatureData]:
	if not map_data:
		return []
	return map_data.get_creatures_at(tile_pos)


## Find creature at a visual position (for clicking)
func find_creature_at_visual_position(visual_pos: Vector2, radius: float = 1.0) -> CreatureData:
	if not map_data:
		return null
	
	var closest: CreatureData = null
	var closest_dist := INF
	
	for creature in map_data.creatures:
		var dist := creature.visual_position.distance_to(visual_pos)
		if dist < radius and dist < closest_dist:
			closest_dist = dist
			closest = creature
	
	return closest
