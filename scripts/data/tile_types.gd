class_name TileTypes
extends RefCounted
## Static definitions for tile types and their properties.

enum Type {
	ROCK,    ## Indestructible bedrock
	WALL,    ## Diggable earth/stone
	FLOOR,   ## Dug out, walkable, can be claimed
	CLAIMED  ## Owned by a faction
}

## Properties for each tile type
const PROPERTIES := {
	Type.ROCK: {
		"name": "rock",
		"walkable": false,
		"diggable": false,
		"claimable": false,
		"blocks_sight": true,
		"default_health": -1,  # Indestructible
	},
	Type.WALL: {
		"name": "wall",
		"walkable": false,
		"diggable": true,
		"claimable": false,
		"blocks_sight": true,
		"default_health": 100,
	},
	Type.FLOOR: {
		"name": "floor",
		"walkable": true,
		"diggable": false,
		"claimable": true,
		"blocks_sight": false,
		"default_health": -1,
	},
	Type.CLAIMED: {
		"name": "claimed",
		"walkable": true,
		"diggable": false,
		"claimable": false,
		"blocks_sight": false,
		"default_health": -1,
	},
}

## Convert string name to Type enum
static func from_string(type_name: String) -> Type:
	match type_name.to_lower():
		"rock": return Type.ROCK
		"wall": return Type.WALL
		"floor": return Type.FLOOR
		"claimed": return Type.CLAIMED
		_: 
			push_warning("Unknown tile type: %s, defaulting to ROCK" % type_name)
			return Type.ROCK

## Convert Type enum to string name
static func to_string_name(type: Type) -> String:
	return PROPERTIES[type]["name"]

## Get property for a tile type
static func get_property(type: Type, property: String) -> Variant:
	if PROPERTIES.has(type) and PROPERTIES[type].has(property):
		return PROPERTIES[type][property]
	return null

## Check if tile type is walkable
static func is_walkable(type: Type) -> bool:
	return PROPERTIES[type]["walkable"]

## Check if tile type is diggable
static func is_diggable(type: Type) -> bool:
	return PROPERTIES[type]["diggable"]

## Check if tile type can be claimed
static func is_claimable(type: Type) -> bool:
	return PROPERTIES[type]["claimable"]

## Check if tile type blocks line of sight
static func blocks_sight(type: Type) -> bool:
	return PROPERTIES[type]["blocks_sight"]
