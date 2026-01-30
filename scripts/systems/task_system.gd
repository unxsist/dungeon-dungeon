class_name TaskSystem
extends Node
## System for managing and assigning tasks to creatures.

## Reference to map data
var map_data: MapData = null

## Reference to pathfinding system
var pathfinding: PathfindingSystem = null

## Task handlers indexed by TaskTypes.Type
var handlers: Dictionary = {}

## Active tasks per faction: { faction_id: Array[Dictionary] }
var faction_tasks: Dictionary = {}

## Tasks assigned to creatures: { creature_id: Dictionary }
var assigned_tasks: Dictionary = {}


func _ready() -> void:
	GameEvents.map_loaded.connect(_on_map_loaded)
	GameEvents.dig_unmarked.connect(_on_dig_unmarked)
	
	# Initialize task handlers
	_register_handlers()


## Register all task handlers
func _register_handlers() -> void:
	handlers[TaskTypes.Type.CLAIM] = ClaimTaskHandler.new()
	handlers[TaskTypes.Type.DIG] = DigTaskHandler.new()
	handlers[TaskTypes.Type.CARRY] = CarryTaskHandler.new()


## Initialize when map is loaded
func _on_map_loaded(data: MapData) -> void:
	map_data = data
	faction_tasks.clear()
	assigned_tasks.clear()
	
	# Initialize task queues for each faction
	for faction in map_data.factions:
		faction_tasks[faction.id] = []


## Set pathfinding reference (called by scene setup)
func set_pathfinding(pathfinder: PathfindingSystem) -> void:
	pathfinding = pathfinder
	
	# Initialize handlers with references
	for handler in handlers.values():
		handler.initialize(map_data, pathfinding)


## Request a task for an idle creature
## Returns task dictionary or empty dict if no task available
func request_task(creature: CreatureData) -> Dictionary:
	if not map_data or not pathfinding:
		return {}
	
	# Get task types this creature can perform, sorted by priority
	var available_tasks := TaskTypes.get_creature_tasks_by_priority(creature.creature_type)
	
	# Try each task type in priority order
	for task_type in available_tasks:
		var handler: BaseTaskHandler = handlers.get(task_type)
		if not handler:
			continue
		
		# Ensure handler has current references
		handler.initialize(map_data, pathfinding)
		
		# Check if there's a pending task in the queue for this type
		var queued_task := _find_queued_task(creature.faction_id, task_type, creature)
		if not queued_task.is_empty():
			_assign_task(creature, queued_task)
			return queued_task
		
		# For auto-assign tasks, try to find a target automatically
		if TaskTypes.is_auto_assign(task_type):
			# Get list of tiles already being worked on
			# For tasks that allow multiple creatures (like DIG), don't exclude targets
			# because the handler/slot system manages multi-creature access
			var excluded: Array[Vector2i] = []
			if not TaskTypes.allows_multiple_creatures(task_type):
				excluded = _get_all_claimed_targets()
			
			var target := handler.find_target(creature, excluded)
			if target != Vector2i(-1, -1):
				# Create and assign new task
				var task := TaskTypes.create_task(task_type, target, creature.faction_id)
				_assign_task(creature, task)
				return task
	
	return {}


## Find a queued task of a specific type that the creature can do
func _find_queued_task(faction_id: int, task_type: TaskTypes.Type, creature: CreatureData) -> Dictionary:
	if not faction_tasks.has(faction_id):
		return {}
	
	var tasks: Array = faction_tasks[faction_id]
	for i in range(tasks.size()):
		var task: Dictionary = tasks[i]
		if task["type"] != task_type:
			continue
		if task["state"] != TaskTypes.State.PENDING:
			continue
		
		# Check if creature can reach the target
		var handler: BaseTaskHandler = handlers.get(task_type)
		if handler:
			var work_pos := handler.get_work_position(task["target_pos"], creature)
			if work_pos == Vector2i(-1, -1):
				continue  # Can't reach this task
		
		# Remove from queue and return
		tasks.remove_at(i)
		return task
	
	return {}


## Check if a target is already being worked on by another creature
func _is_target_claimed(target: Vector2i, faction_id: int) -> bool:
	for creature_id in assigned_tasks.keys():
		var task: Dictionary = assigned_tasks[creature_id]
		if task["faction_id"] != faction_id:
			continue
		if task["target_pos"] == target:
			return true
	return false


## Get all targets currently being worked on by a faction
func _get_claimed_targets(faction_id: int) -> Array[Vector2i]:
	var targets: Array[Vector2i] = []
	for creature_id in assigned_tasks.keys():
		var task: Dictionary = assigned_tasks[creature_id]
		if task["faction_id"] == faction_id:
			targets.append(task["target_pos"])
	return targets


## Get all targets currently being worked on by ANY faction
func _get_all_claimed_targets() -> Array[Vector2i]:
	var targets: Array[Vector2i] = []
	for creature_id in assigned_tasks.keys():
		var task: Dictionary = assigned_tasks[creature_id]
		targets.append(task["target_pos"])
	return targets


## Assign a task to a creature
func _assign_task(creature: CreatureData, task: Dictionary) -> void:
	task["state"] = TaskTypes.State.ASSIGNED
	task["assigned_creature_id"] = creature.id
	assigned_tasks[creature.id] = task
	creature.current_task = task
	
	GameEvents.creature_task_started.emit(creature.id, task)


## Execute work on the creature's current task
## Called each frame by CreatureSystem when creature is in WORKING state
func execute_task(creature: CreatureData, delta: float) -> void:
	if not assigned_tasks.has(creature.id):
		return
	
	var task: Dictionary = assigned_tasks[creature.id]
	var task_type: TaskTypes.Type = task["type"]
	var handler: BaseTaskHandler = handlers.get(task_type)
	
	if not handler:
		_fail_task(creature, task)
		return
	
	# Ensure handler has current references
	handler.initialize(map_data, pathfinding)
	
	# Mark task as in progress
	task["state"] = TaskTypes.State.IN_PROGRESS
	
	# Execute work
	handler.execute(creature, task, delta)
	
	# Check completion
	if handler.is_complete(creature, task):
		_complete_task(creature, task, handler)


## Complete a task successfully
func _complete_task(creature: CreatureData, task: Dictionary, handler: BaseTaskHandler) -> void:
	task["state"] = TaskTypes.State.COMPLETED
	
	# Run completion logic
	handler.on_complete(creature, task)
	
	# Award XP
	var xp_reward := handler.get_xp_reward(task)
	var leveled_up := creature.add_xp(xp_reward)
	if leveled_up:
		GameEvents.creature_leveled_up.emit(creature.id, creature.level)
	
	# Clean up
	assigned_tasks.erase(creature.id)
	creature.current_task.clear()
	creature.set_state(CreatureTypes.State.IDLE)
	
	GameEvents.creature_task_completed.emit(creature.id, task)


## Fail a task
func _fail_task(creature: CreatureData, task: Dictionary) -> void:
	task["state"] = TaskTypes.State.FAILED
	
	var handler: BaseTaskHandler = handlers.get(task["type"])
	if handler:
		handler.on_cancel(creature, task)
	
	assigned_tasks.erase(creature.id)
	creature.current_task.clear()
	creature.set_state(CreatureTypes.State.IDLE)


## Cancel a creature's current task
func cancel_task(creature: CreatureData) -> void:
	if not assigned_tasks.has(creature.id):
		return
	
	var task: Dictionary = assigned_tasks[creature.id]
	task["state"] = TaskTypes.State.CANCELLED
	
	var handler: BaseTaskHandler = handlers.get(task["type"])
	if handler:
		handler.on_cancel(creature, task)
	
	assigned_tasks.erase(creature.id)
	creature.current_task.clear()
	
	var old_state := creature.state
	creature.set_state(CreatureTypes.State.IDLE)
	if old_state != CreatureTypes.State.IDLE:
		GameEvents.creature_state_changed.emit(creature.id, old_state, CreatureTypes.State.IDLE)


## Add a task to the queue (for player-initiated tasks like dig marking)
func queue_task(task_type: TaskTypes.Type, target_pos: Vector2i, faction_id: int) -> void:
	if not faction_tasks.has(faction_id):
		faction_tasks[faction_id] = []
	
	var task := TaskTypes.create_task(task_type, target_pos, faction_id)
	faction_tasks[faction_id].append(task)


## Get the handler for a task type
func get_handler(task_type: TaskTypes.Type) -> BaseTaskHandler:
	return handlers.get(task_type)


## Get work position for a creature's current task
func get_work_position(creature: CreatureData) -> Vector2i:
	if creature.current_task.is_empty():
		return Vector2i(-1, -1)
	
	var task_type: TaskTypes.Type = creature.current_task["type"]
	var handler: BaseTaskHandler = handlers.get(task_type)
	
	if not handler:
		return Vector2i(-1, -1)
	
	handler.initialize(map_data, pathfinding)
	return handler.get_work_position(creature.current_task["target_pos"], creature)


## Check if creature is in position to work
func is_creature_in_work_position(creature: CreatureData) -> bool:
	if creature.current_task.is_empty():
		return false
	
	var task_type: TaskTypes.Type = creature.current_task["type"]
	var handler: BaseTaskHandler = handlers.get(task_type)
	
	if not handler:
		return false
	
	handler.initialize(map_data, pathfinding)
	return handler.is_in_work_position(creature, creature.current_task)


## Handle dig unmarked event - cancel all dig tasks for this position
func _on_dig_unmarked(position: Vector2i) -> void:
	cancel_tasks_at_position(TaskTypes.Type.DIG, position)


## Cancel all tasks of a specific type targeting a position
func cancel_tasks_at_position(task_type: TaskTypes.Type, target_pos: Vector2i) -> void:
	if not map_data:
		return
	
	# Cancel assigned tasks (creatures currently working or walking to this target)
	var creatures_to_cancel: Array[int] = []
	for creature_id in assigned_tasks.keys():
		var task: Dictionary = assigned_tasks[creature_id]
		if task["type"] == task_type and task["target_pos"] == target_pos:
			creatures_to_cancel.append(creature_id)
	
	for creature_id in creatures_to_cancel:
		var creature := map_data.get_creature(creature_id)
		if creature:
			cancel_task(creature)
	
	# Remove from faction task queues (pending tasks not yet assigned)
	for faction_id in faction_tasks.keys():
		var tasks: Array = faction_tasks[faction_id]
		var i := tasks.size() - 1
		while i >= 0:
			var task: Dictionary = tasks[i]
			if task["type"] == task_type and task["target_pos"] == target_pos:
				tasks.remove_at(i)
			i -= 1
