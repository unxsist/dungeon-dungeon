class_name RoomTypes
extends RefCounted
## Static definitions for room types and their properties.

enum Type {
	LAIR,           ## Creatures sleep here to restore energy
	HATCHERY,       ## Spawns food for hungry creatures
	TREASURY,       ## Stores gold - expands gold capacity
	TRAINING_ROOM,  ## Creatures train here to level up
	LIBRARY,        ## Warlocks research spells here
}

## Room definitions with properties
const DEFINITIONS := {
	Type.LAIR: {
		"name": "lair",
		"display_name": "Lair",
		"description": "Creatures sleep here to restore energy and happiness",
		"functional_tiles": 9,    # Tiles needed to become functional (3x3)
		"cost_per_tile": 150,     # Gold cost per tile
		"color": Color(0.6, 0.4, 0.3),  # Brownish for hay/bedding
		"texture": "res://resources/assets/rooms/lair.png",
	},
	Type.HATCHERY: {
		"name": "hatchery",
		"display_name": "Hatchery",
		"description": "Spawns food for hungry creatures",
		"functional_tiles": 9,
		"cost_per_tile": 200,
		"color": Color(0.4, 0.5, 0.3),  # Greenish for organic/food
		"texture": "res://resources/assets/rooms/hatchery.png",
	},
	Type.TREASURY: {
		"name": "treasury",
		"display_name": "Treasury",
		"description": "Stores gold and increases maximum capacity",
		"functional_tiles": 9,
		"cost_per_tile": 100,
		"color": Color(0.8, 0.7, 0.2),  # Golden yellow
		"texture": "",  # No custom texture yet, uses claimed floor
	},
	Type.TRAINING_ROOM: {
		"name": "training_room",
		"display_name": "Training Room",
		"description": "Creatures train here to gain experience and level up",
		"functional_tiles": 16,   # 4x4 needed to function
		"cost_per_tile": 250,
		"color": Color(0.5, 0.3, 0.3),  # Reddish brown for combat
		"texture": "",  # No custom texture yet, uses claimed floor
	},
	Type.LIBRARY: {
		"name": "library",
		"display_name": "Library",
		"description": "Warlocks research spells and new abilities here",
		"functional_tiles": 16,
		"cost_per_tile": 300,
		"color": Color(0.3, 0.3, 0.6),  # Blue-ish for magic/knowledge
		"texture": "",  # No custom texture yet, uses claimed floor
	},
}


## Convert string name to Type enum
static func from_string(type_name: String) -> Type:
	match type_name.to_lower():
		"lair": return Type.LAIR
		"hatchery": return Type.HATCHERY
		"treasury": return Type.TREASURY
		"training_room": return Type.TRAINING_ROOM
		"library": return Type.LIBRARY
		_:
			push_warning("Unknown room type: %s, defaulting to LAIR" % type_name)
			return Type.LAIR


## Convert Type enum to string name
static func to_string_name(type: Type) -> String:
	return DEFINITIONS[type]["name"]


## Get display name for a room type
static func get_display_name(type: Type) -> String:
	return DEFINITIONS[type]["display_name"]


## Get description for a room type
static func get_description(type: Type) -> String:
	return DEFINITIONS[type]["description"]


## Get cost per tile for a room type
static func get_cost_per_tile(type: Type) -> int:
	return DEFINITIONS[type]["cost_per_tile"]


## Get tiles required for a room to become functional
static func get_functional_tiles(type: Type) -> int:
	return DEFINITIONS[type]["functional_tiles"]


## Check if a room with given tile count is functional
static func is_functional(type: Type, tile_count: int) -> bool:
	return tile_count >= get_functional_tiles(type)


## Calculate total cost for a given number of tiles
static func calculate_cost(type: Type, tile_count: int) -> int:
	return tile_count * get_cost_per_tile(type)


## Get the color associated with a room type
static func get_color(type: Type) -> Color:
	return DEFINITIONS[type]["color"]


## Get the texture path for a room type (empty string if no custom texture)
static func get_texture_path(type: Type) -> String:
	return DEFINITIONS[type].get("texture", "")


## Get all room types as an array
static func get_all_types() -> Array:
	return [Type.LAIR, Type.HATCHERY, Type.TREASURY, Type.TRAINING_ROOM, Type.LIBRARY]
