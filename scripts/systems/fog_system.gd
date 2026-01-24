class_name FogSystem
extends Node
## Manages fog of war visibility per faction.

## Visibility states
enum Visibility { HIDDEN, EXPLORED, VISIBLE }

## Fog state storage: { Vector2i: { faction_id: Visibility } }
var fog_state: Dictionary = {}

## Reference to map data
var map_data: MapData = null

## Active faction (player's faction for rendering)
@export var active_faction_id: int = 0

## Default sight range for faction-owned tiles
@export var base_sight_range: int = 3

## Whether fog of war is enabled
@export var fog_enabled: bool = true


func _ready() -> void:
	GameEvents.map_loaded.connect(_on_map_loaded)
	GameEvents.tile_changed.connect(_on_tile_changed)
	GameEvents.tile_ownership_changed.connect(_on_tile_ownership_changed)


func _on_map_loaded(data: Resource) -> void:
	map_data = data as MapData
	if map_data:
		_initialize_fog()
		_update_all_visibility()


## Initialize fog state for all tiles
func _initialize_fog() -> void:
	fog_state.clear()
	
	for pos in map_data.tiles.keys():
		fog_state[pos] = {}
		for faction in map_data.factions:
			fog_state[pos][faction.id] = Visibility.HIDDEN


## Update visibility when tile changes
func _on_tile_changed(pos: Vector2i, _old_type: int, _new_type: int) -> void:
	# Recalculate visibility around this tile
	_update_visibility_around(pos)


## Update visibility when ownership changes
func _on_tile_ownership_changed(pos: Vector2i, _old_faction: int, new_faction: int) -> void:
	# New owner gets visibility from this tile
	if new_faction >= 0:
		_update_visibility_for_faction(new_faction)
	
	GameEvents.visibility_updated.emit(active_faction_id)


## Update visibility for all factions
func _update_all_visibility() -> void:
	for faction in map_data.factions:
		_update_visibility_for_faction(faction.id)
	
	GameEvents.visibility_updated.emit(active_faction_id)


## Update visibility for a specific faction
func _update_visibility_for_faction(faction_id: int) -> void:
	# First, demote all VISIBLE to EXPLORED
	for pos in fog_state.keys():
		if fog_state[pos].get(faction_id, Visibility.HIDDEN) == Visibility.VISIBLE:
			fog_state[pos][faction_id] = Visibility.EXPLORED
	
	# Get all tiles owned by this faction
	var owned_tiles := map_data.get_faction_tiles(faction_id)
	
	# Calculate visible tiles from each owned tile
	for owned_pos in owned_tiles:
		_reveal_from_position(owned_pos, faction_id, base_sight_range)


## Reveal tiles visible from a position
func _reveal_from_position(source: Vector2i, faction_id: int, sight_range: int) -> void:
	# Use flood fill with line-of-sight checks
	var to_check: Array[Vector2i] = [source]
	var checked: Dictionary = {}
	
	while to_check.size() > 0:
		var pos: Vector2i = to_check.pop_front()
		
		if checked.has(pos):
			continue
		checked[pos] = true
		
		# Check distance
		var distance := _tile_distance(source, pos)
		if distance > sight_range:
			continue
		
		# Check if position is valid
		if not map_data.is_valid_position(pos):
			continue
		
		# Set as visible
		if fog_state.has(pos):
			fog_state[pos][faction_id] = Visibility.VISIBLE
		
		# Check if this tile blocks sight
		var tile: Variant = map_data.get_tile(pos)
		if tile and TileTypes.blocks_sight(tile["type"]):
			# Still visible but don't propagate through
			continue
		
		# Add neighbors to check
		for dir: Vector2i in MapData.DIRECTIONS:
			var neighbor: Vector2i = pos + dir
			if not checked.has(neighbor):
				to_check.append(neighbor)


## Calculate Manhattan distance between tiles
func _tile_distance(a: Vector2i, b: Vector2i) -> int:
	return abs(a.x - b.x) + abs(a.y - b.y)


## Update visibility around a specific position
func _update_visibility_around(pos: Vector2i) -> void:
	# Update for all factions that might see this tile
	for faction in map_data.factions:
		# Check if faction has any tiles in sight range
		var faction_tiles := map_data.get_faction_tiles(faction.id)
		for owned_pos in faction_tiles:
			if _tile_distance(pos, owned_pos) <= base_sight_range:
				_update_visibility_for_faction(faction.id)
				break
	
	GameEvents.visibility_updated.emit(active_faction_id)


## Get visibility state for a tile for the active faction
func get_visibility(pos: Vector2i) -> Visibility:
	if not fog_enabled:
		return Visibility.VISIBLE
	
	if fog_state.has(pos) and fog_state[pos].has(active_faction_id):
		return fog_state[pos][active_faction_id]
	return Visibility.HIDDEN


## Get visibility for a specific faction
func get_visibility_for_faction(pos: Vector2i, faction_id: int) -> Visibility:
	if not fog_enabled:
		return Visibility.VISIBLE
	
	if fog_state.has(pos) and fog_state[pos].has(faction_id):
		return fog_state[pos][faction_id]
	return Visibility.HIDDEN


## Check if tile is visible to active faction
func is_visible(pos: Vector2i) -> bool:
	return get_visibility(pos) == Visibility.VISIBLE


## Check if tile has been explored by active faction
func is_explored(pos: Vector2i) -> bool:
	var vis := get_visibility(pos)
	return vis == Visibility.VISIBLE or vis == Visibility.EXPLORED


## Toggle fog of war on/off
func set_fog_enabled(enabled: bool) -> void:
	fog_enabled = enabled
	GameEvents.visibility_updated.emit(active_faction_id)


## Get fog state for saving
func get_fog_state_for_save() -> Dictionary:
	var save_data := {}
	for pos in fog_state.keys():
		var key := "%d,%d" % [pos.x, pos.y]
		save_data[key] = fog_state[pos].duplicate()
	return save_data


## Load fog state from save
func load_fog_state(data: Dictionary) -> void:
	fog_state.clear()
	for key: String in data.keys():
		var parts: PackedStringArray = key.split(",")
		if parts.size() == 2:
			var pos := Vector2i(int(parts[0]), int(parts[1]))
			fog_state[pos] = data[key]
	
	GameEvents.visibility_updated.emit(active_faction_id)
