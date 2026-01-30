class_name SkillData
extends RefCounted
## Static definitions for creature skills and their properties.

## Skill type enum
enum Skill {
	CLAIMING,   ## Claiming tiles for faction
	DIGGING,    ## Digging out walls
	CARRYING,   ## Carrying resources/items
}

## Skill definitions with base strength and level scaling
const DEFINITIONS := {
	Skill.CLAIMING: {
		"name": "claiming",
		"display_name": "Claiming",
		"description": "Speed at which tiles are claimed",
		"base_strength": 10.0,      # Base claim progress per second
		"level_multiplier": 2.0,    # Additional per level
	},
	Skill.DIGGING: {
		"name": "digging",
		"display_name": "Digging",
		"description": "Speed at which walls are dug out",
		"base_strength": 20.0,      # Base dig damage per second (5 seconds to dig 100 health wall at level 1)
		"level_multiplier": 2.0,    # +2 damage/sec per level (level 10 = 38 damage/sec = ~2.6 seconds)
	},
	Skill.CARRYING: {
		"name": "carrying",
		"display_name": "Carrying",
		"description": "Amount of items that can be carried",
		"base_strength": 1.0,       # Base carry capacity
		"level_multiplier": 0.5,    # Additional capacity per level
	},
}

## Convert string name to Skill enum
static func from_string(skill_name: String) -> Skill:
	match skill_name.to_lower():
		"claiming": return Skill.CLAIMING
		"digging": return Skill.DIGGING
		"carrying": return Skill.CARRYING
		_:
			push_warning("Unknown skill: %s, defaulting to CLAIMING" % skill_name)
			return Skill.CLAIMING


## Convert Skill enum to string name
static func to_string_name(skill: Skill) -> String:
	return DEFINITIONS[skill]["name"]


## Get display name for a skill
static func get_display_name(skill: Skill) -> String:
	return DEFINITIONS[skill]["display_name"]


## Get base strength for a skill
static func get_base_strength(skill: Skill) -> float:
	return DEFINITIONS[skill]["base_strength"]


## Get level multiplier for a skill
static func get_level_multiplier(skill: Skill) -> float:
	return DEFINITIONS[skill]["level_multiplier"]


## Calculate skill strength at a given level
## Formula: base_strength + (level - 1) * level_multiplier
static func get_strength_at_level(skill: Skill, level: int) -> float:
	var base: float = DEFINITIONS[skill]["base_strength"]
	var multiplier: float = DEFINITIONS[skill]["level_multiplier"]
	return base + (level - 1) * multiplier


## Calculate skill strength from string name and level
static func get_strength_by_name(skill_name: String, level: int) -> float:
	var skill := from_string(skill_name)
	return get_strength_at_level(skill, level)


## Get all skill names as strings
static func get_all_skill_names() -> Array[String]:
	var names: Array[String] = []
	for skill_key in DEFINITIONS.keys():
		names.append(DEFINITIONS[skill_key]["name"])
	return names
