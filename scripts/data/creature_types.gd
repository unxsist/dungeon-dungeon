class_name CreatureTypes
extends RefCounted
## Static definitions for creature types and their properties.

enum Type {
	IMP,  ## Worker creature - claims, digs, carries
}

## States a creature can be in
enum State {
	IDLE,      ## No current task, waiting
	WALKING,   ## Moving to a destination
	WORKING,   ## Performing a task at location
	WANDERING, ## Random movement on claimed tiles
}

## Size categories for creatures (relative to wall height of 3.0 units)
enum Size {
	TINY,    ## 55% of wall height (~1.65 units) - Imps, small workers
	SMALL,   ## 70% of wall height (~2.1 units) - Goblins, etc
	MEDIUM,  ## 85% of wall height (~2.55 units) - Orcs, humanoids
	LARGE,   ## 100% of wall height (3.0 units) - Trolls, large creatures
}

## Wall height reference (must match TileRenderer.WALL_HEIGHT)
const WALL_HEIGHT := 3.0

## Size multipliers relative to wall height
const SIZE_MULTIPLIERS := {
	Size.TINY: 0.55,
	Size.SMALL: 0.70,
	Size.MEDIUM: 0.85,
	Size.LARGE: 1.00,
}

## Base properties for each creature type
const DEFINITIONS := {
	Type.IMP: {
		"name": "Imp",
		"size": Size.TINY,  # Smallest creatures
		"base_health": 20,
		"health_per_level": 5,
		"base_armor": 0,
		"armor_per_level": 0,
		"base_speed": 1.5,  # Tiles per second at level 1 (slower)
		"speed_per_level": 0.2,  # Speed increase per level
		"skills": ["claiming", "digging", "carrying"],
		"xp_per_level": [0, 100, 250, 500, 850, 1300, 1900, 2600, 3500, 4500],  # XP thresholds for levels 1-10
	},
}

## Convert string name to Type enum
static func from_string(type_name: String) -> Type:
	match type_name.to_lower():
		"imp": return Type.IMP
		_:
			push_warning("Unknown creature type: %s, defaulting to IMP" % type_name)
			return Type.IMP


## Convert Type enum to string name
static func to_string_name(type: Type) -> String:
	return DEFINITIONS[type]["name"].to_lower()


## Get display name for a creature type
static func get_display_name(type: Type) -> String:
	return DEFINITIONS[type]["name"]


## Get base health for a creature type
static func get_base_health(type: Type) -> int:
	return DEFINITIONS[type]["base_health"]


## Get health at a specific level
static func get_health_at_level(type: Type, level: int) -> int:
	var base: int = DEFINITIONS[type]["base_health"]
	var per_level: int = DEFINITIONS[type]["health_per_level"]
	return base + (level - 1) * per_level


## Get base armor for a creature type
static func get_base_armor(type: Type) -> int:
	return DEFINITIONS[type]["base_armor"]


## Get armor at a specific level
static func get_armor_at_level(type: Type, level: int) -> int:
	var base: int = DEFINITIONS[type]["base_armor"]
	var per_level: int = DEFINITIONS[type]["armor_per_level"]
	return base + (level - 1) * per_level


## Get base movement speed (tiles per second)
static func get_base_speed(type: Type) -> float:
	return DEFINITIONS[type]["base_speed"]


## Get movement speed at a specific level (tiles per second)
static func get_speed_at_level(type: Type, level: int) -> float:
	var base: float = DEFINITIONS[type]["base_speed"]
	var per_level: float = DEFINITIONS[type].get("speed_per_level", 0.0)
	return base + (level - 1) * per_level


## Get skills available to this creature type
static func get_skills(type: Type) -> Array:
	return DEFINITIONS[type]["skills"]


## Check if creature type has a specific skill
static func has_skill(type: Type, skill_name: String) -> bool:
	return skill_name in DEFINITIONS[type]["skills"]


## Get XP required for a specific level (1-10)
static func get_xp_for_level(type: Type, level: int) -> int:
	var thresholds: Array = DEFINITIONS[type]["xp_per_level"]
	var clamped_level := clampi(level, 1, thresholds.size())
	return thresholds[clamped_level - 1]


## Get level from XP amount
static func get_level_from_xp(type: Type, xp: int) -> int:
	var thresholds: Array = DEFINITIONS[type]["xp_per_level"]
	var level := 1
	for i in range(thresholds.size()):
		if xp >= thresholds[i]:
			level = i + 1
		else:
			break
	return level


## Get maximum level
static func get_max_level() -> int:
	return 10


## Get size category for a creature type
static func get_size(type: Type) -> Size:
	return DEFINITIONS[type]["size"]


## Get target height in world units for a creature type
static func get_height(type: Type) -> float:
	var size: Size = DEFINITIONS[type]["size"]
	return WALL_HEIGHT * SIZE_MULTIPLIERS[size]


## Get size multiplier for a creature type
static func get_size_multiplier(type: Type) -> float:
	var size: Size = DEFINITIONS[type]["size"]
	return SIZE_MULTIPLIERS[size]
