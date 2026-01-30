class_name CreatureData
extends Resource
## Data class representing an individual creature instance.

## Unique identifier for this creature
@export var id: int = 0

## Creature type (from CreatureTypes.Type)
@export var creature_type: CreatureTypes.Type = CreatureTypes.Type.IMP

## Owning faction ID
@export var faction_id: int = 0

## Current tile position on the 2D grid
@export var tile_position: Vector2i = Vector2i.ZERO

## World position in 3D space
var world_position: Vector3 = Vector3.ZERO

## Interpolated 2D position for smooth visual movement
var visual_position: Vector2 = Vector2.ZERO

## Portal that spawned this creature (for tracking portal creature limits)
## Vector2i(-1, -1) if not spawned from a portal
var portal_origin: Vector2i = Vector2i(-1, -1)

## Current level (1-10)
@export var level: int = 1

## Current experience points
@export var xp: int = 0

## Current health
@export var health: int = 20

## Maximum health (calculated from type and level)
var max_health: int = 20

## Current armor value
var armor: int = 0

## Happiness level (0-100)
@export var happiness: float = 100.0

## Current state
var state: CreatureTypes.State = CreatureTypes.State.IDLE

## Current task being performed (Dictionary with task info)
var current_task: Dictionary = {}

## Current path to follow (array of tile positions)
var current_path: Array[Vector2i] = []

## Current index in the path
var path_index: int = 0

## Target tile for current task
var target_tile: Vector2i = Vector2i(-1, -1)


## Initialize creature from type and level
func initialize(type: CreatureTypes.Type, init_level: int = 1) -> void:
	creature_type = type
	level = clampi(init_level, 1, CreatureTypes.get_max_level())
	xp = CreatureTypes.get_xp_for_level(type, level)
	_update_stats()


## Update derived stats based on type and level
func _update_stats() -> void:
	max_health = CreatureTypes.get_health_at_level(creature_type, level)
	health = mini(health, max_health)
	armor = CreatureTypes.get_armor_at_level(creature_type, level)


## Get skill strength for a given skill name
func get_skill_strength(skill_name: String) -> float:
	if CreatureTypes.has_skill(creature_type, skill_name):
		return SkillData.get_strength_by_name(skill_name, level)
	return 0.0


## Get movement speed (tiles per second) - scales with level
func get_speed() -> float:
	return CreatureTypes.get_speed_at_level(creature_type, level)


## Get display name
func get_display_name() -> String:
	return CreatureTypes.get_display_name(creature_type)


## Add experience points and handle leveling
func add_xp(amount: int) -> bool:
	xp += amount
	var new_level := CreatureTypes.get_level_from_xp(creature_type, xp)
	if new_level > level:
		level = new_level
		_update_stats()
		return true  # Leveled up
	return false


## Take damage (returns true if creature dies)
func take_damage(amount: int) -> bool:
	var actual_damage := maxi(1, amount - armor)
	health -= actual_damage
	return health <= 0


## Heal the creature
func heal(amount: int) -> void:
	health = mini(health + amount, max_health)


## Check if creature has a specific skill
func has_skill(skill_name: String) -> bool:
	return CreatureTypes.has_skill(creature_type, skill_name)


## Set state and clear task if going idle
func set_state(new_state: CreatureTypes.State) -> void:
	state = new_state
	if new_state == CreatureTypes.State.IDLE:
		current_task.clear()
		current_path.clear()
		path_index = 0
		target_tile = Vector2i(-1, -1)


## Check if creature is busy (has a task or moving)
func is_busy() -> bool:
	return state != CreatureTypes.State.IDLE


## Clear current path
func clear_path() -> void:
	current_path.clear()
	path_index = 0


## Check if creature has reached end of path
func has_reached_destination() -> bool:
	return current_path.is_empty() or path_index >= current_path.size()


## Create a CreatureData from a dictionary (from JSON)
static func from_dict(data: Dictionary, creature_id: int) -> CreatureData:
	var creature := CreatureData.new()
	creature.id = creature_id
	creature.creature_type = CreatureTypes.from_string(data.get("type", "imp"))
	creature.faction_id = data.get("faction_id", 0)
	creature.tile_position = Vector2i(data.get("x", 0), data.get("y", 0))
	creature.visual_position = Vector2(creature.tile_position)
	creature.level = clampi(data.get("level", 1), 1, CreatureTypes.get_max_level())
	creature.xp = data.get("xp", CreatureTypes.get_xp_for_level(creature.creature_type, creature.level))
	creature.happiness = data.get("happiness", 100.0)
	creature._update_stats()
	creature.health = data.get("health", creature.max_health)
	return creature


## Convert to dictionary for saving
func to_dict() -> Dictionary:
	return {
		"type": CreatureTypes.to_string_name(creature_type),
		"faction_id": faction_id,
		"x": tile_position.x,
		"y": tile_position.y,
		"level": level,
		"xp": xp,
		"health": health,
		"happiness": happiness,
	}
