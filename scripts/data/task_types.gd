class_name TaskTypes
extends RefCounted
## Static definitions for task types and creature capabilities.

## Task type enum - extensible for future creature types
enum Type {
	CLAIM,      ## Claim a tile for faction
	DIG,        ## Dig out a wall
	CARRY,      ## Carry resources/items (placeholder)
	# Future task types:
	# PATROL,   ## Guard patrols
	# GUARD,    ## Stationary guard duty
	# RESEARCH, ## Research spells/upgrades
}

## Task state enum
enum State {
	PENDING,     ## Task created, not started
	ASSIGNED,    ## Assigned to a creature
	IN_PROGRESS, ## Creature working on it
	COMPLETED,   ## Task finished successfully
	CANCELLED,   ## Task was cancelled
	FAILED,      ## Task failed (path blocked, etc.)
}

## Which creature types can perform which tasks
const CREATURE_CAPABILITIES := {
	CreatureTypes.Type.IMP: [Type.CLAIM, Type.DIG, Type.CARRY],
	# Future creatures:
	# CreatureTypes.Type.WARLOCK: [Type.RESEARCH, Type.PATROL],
	# CreatureTypes.Type.TROLL: [Type.GUARD, Type.CARRY],
}

## Task definitions with properties
const DEFINITIONS := {
	Type.CLAIM: {
		"name": "claim",
		"display_name": "Claim Tile",
		"description": "Claim an unclaimed tile for the faction",
		"required_skill": "claiming",
		"priority": 10,  # Higher = more important
		"auto_assign": true,  # System finds targets automatically
	},
	Type.DIG: {
		"name": "dig",
		"display_name": "Dig Tile",
		"description": "Dig out a wall tile",
		"required_skill": "digging",
		"priority": 20,  # Digging is higher priority than claiming
		"auto_assign": true,  # Imps auto-find marked tiles; slot system handles multi-creature
		"allows_multiple": true,  # Multiple creatures can work same target (via slot system)
	},
	Type.CARRY: {
		"name": "carry",
		"display_name": "Carry Item",
		"description": "Transport items between locations",
		"required_skill": "carrying",
		"priority": 5,
		"auto_assign": true,
	},
}


## Convert string name to Type enum
static func from_string(type_name: String) -> Type:
	match type_name.to_lower():
		"claim": return Type.CLAIM
		"dig": return Type.DIG
		"carry": return Type.CARRY
		_:
			push_warning("Unknown task type: %s, defaulting to CLAIM" % type_name)
			return Type.CLAIM


## Convert Type enum to string name
static func to_string_name(type: Type) -> String:
	return DEFINITIONS[type]["name"]


## Get display name for a task type
static func get_display_name(type: Type) -> String:
	return DEFINITIONS[type]["display_name"]


## Get required skill for a task type
static func get_required_skill(type: Type) -> String:
	return DEFINITIONS[type]["required_skill"]


## Get priority for a task type (higher = more important)
static func get_priority(type: Type) -> int:
	return DEFINITIONS[type]["priority"]


## Check if task type auto-assigns targets
static func is_auto_assign(type: Type) -> bool:
	return DEFINITIONS[type]["auto_assign"]


## Check if task type allows multiple creatures on same target
static func allows_multiple_creatures(type: Type) -> bool:
	return DEFINITIONS[type].get("allows_multiple", false)


## Check if a creature type can perform a task type
static func can_creature_perform(creature_type: CreatureTypes.Type, task_type: Type) -> bool:
	if not CREATURE_CAPABILITIES.has(creature_type):
		return false
	return task_type in CREATURE_CAPABILITIES[creature_type]


## Get all task types a creature can perform
static func get_creature_tasks(creature_type: CreatureTypes.Type) -> Array:
	if CREATURE_CAPABILITIES.has(creature_type):
		return CREATURE_CAPABILITIES[creature_type].duplicate()
	return []


## Get all task types a creature can perform, sorted by priority (highest first)
static func get_creature_tasks_by_priority(creature_type: CreatureTypes.Type) -> Array:
	var tasks := get_creature_tasks(creature_type)
	tasks.sort_custom(func(a, b): return get_priority(a) > get_priority(b))
	return tasks


## Create a task dictionary
static func create_task(type: Type, target_pos: Vector2i, faction_id: int, additional_data: Dictionary = {}) -> Dictionary:
	var task := {
		"type": type,
		"target_pos": target_pos,
		"faction_id": faction_id,
		"state": State.PENDING,
		"assigned_creature_id": -1,
		"progress": 0.0,
		"created_at": Time.get_ticks_msec(),
	}
	task.merge(additional_data)
	return task
