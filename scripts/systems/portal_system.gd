class_name PortalSystem
extends Node
## Manages portal creature spawning.
## Portals auto-spawn creatures when claimed by a faction.

## Reference to map data
var map_data: MapData = null

## Active spawn timers per portal position
var spawn_timers: Dictionary = {}  # { Vector2i: float (time_until_spawn) }

## Creature count per portal: { Vector2i: int }
var portal_creature_counts: Dictionary = {}


func _ready() -> void:
	GameEvents.map_loaded.connect(_on_map_loaded)
	GameEvents.tile_ownership_changed.connect(_on_tile_ownership_changed)
	GameEvents.creature_despawned.connect(_on_creature_despawned)


func _process(delta: float) -> void:
	if not map_data:
		return
	
	_update_spawn_timers(delta)


## Handle map loaded
func _on_map_loaded(data: Resource) -> void:
	map_data = data as MapData
	if not map_data:
		return
	
	# Clear existing state
	spawn_timers.clear()
	portal_creature_counts.clear()
	
	# Initialize portals that are already claimed
	for portal_pos in map_data.get_all_portal_positions():
		var tile: Variant = map_data.get_tile(portal_pos)
		if tile and tile["faction_id"] >= 0:
			_activate_portal(portal_pos, tile["faction_id"])


## Handle tile ownership change - detect portal claiming
func _on_tile_ownership_changed(pos: Vector2i, old_faction: int, new_faction: int) -> void:
	if not map_data:
		return
	
	if not map_data.is_portal(pos):
		return
	
	# Portal claimed
	if old_faction < 0 and new_faction >= 0:
		_activate_portal(pos, new_faction)
		GameEvents.portal_claimed.emit(pos, new_faction)
	# Portal stolen by another faction
	elif old_faction >= 0 and new_faction >= 0 and old_faction != new_faction:
		_deactivate_portal(pos)
		_activate_portal(pos, new_faction)
		GameEvents.portal_claimed.emit(pos, new_faction)
	# Portal lost (faction -1 should not happen normally but handle it)
	elif new_faction < 0:
		_deactivate_portal(pos)


## Activate a portal for spawning
func _activate_portal(pos: Vector2i, faction_id: int) -> void:
	var config: Variant = map_data.get_portal_config(pos)
	if not config:
		# Use default config if none specified
		config = {
			"position": pos,
			"spawn_rate": 60.0,
			"max_creatures": 8,
			"creature_types": ["IMP"]
		}
	
	# Initialize spawn timer with some delay before first spawn
	spawn_timers[pos] = config.get("spawn_rate", 60.0) * 0.5
	portal_creature_counts[pos] = _count_portal_creatures(pos, faction_id)
	
	GameEvents.portal_spawn_started.emit(pos, faction_id)


## Deactivate a portal
func _deactivate_portal(pos: Vector2i) -> void:
	spawn_timers.erase(pos)
	portal_creature_counts.erase(pos)


## Update spawn timers and spawn creatures
func _update_spawn_timers(delta: float) -> void:
	var portals_to_spawn: Array[Vector2i] = []
	
	for pos in spawn_timers.keys():
		spawn_timers[pos] -= delta
		if spawn_timers[pos] <= 0:
			portals_to_spawn.append(pos)
	
	for pos in portals_to_spawn:
		_try_spawn_creature(pos)


## Try to spawn a creature at a portal
func _try_spawn_creature(pos: Vector2i) -> void:
	var tile: Variant = map_data.get_tile(pos)
	if not tile or tile["faction_id"] < 0:
		spawn_timers.erase(pos)
		return
	
	var faction_id: int = tile["faction_id"]
	var config: Variant = map_data.get_portal_config(pos)
	if not config:
		config = {
			"spawn_rate": 60.0,
			"max_creatures": 8,
			"creature_types": ["IMP"]
		}
	
	var max_creatures: int = config.get("max_creatures", 8)
	var spawn_rate: float = config.get("spawn_rate", 60.0)
	var creature_types: Array = config.get("creature_types", ["IMP"])
	
	# Check creature limit
	var current_count: int = portal_creature_counts.get(pos, 0)
	if current_count >= max_creatures:
		# Still reset timer but don't spawn
		spawn_timers[pos] = spawn_rate
		return
	
	# Pick a random creature type from available types
	var type_name: String = creature_types[randi() % creature_types.size()]
	var creature_type := _get_creature_type_from_name(type_name)
	
	# Create creature data
	var creature := CreatureData.new()
	creature.creature_type = creature_type
	creature.faction_id = faction_id
	creature.tile_position = pos
	creature.world_position = map_data.tile_to_world(pos)
	creature.state = CreatureTypes.State.IDLE
	creature.portal_origin = pos  # Track which portal spawned this creature
	
	# Add to map data
	map_data.add_creature(creature)
	
	# Update count
	portal_creature_counts[pos] = current_count + 1
	
	# Reset timer
	spawn_timers[pos] = spawn_rate
	
	# Emit events
	GameEvents.portal_creature_spawned.emit(pos, creature)
	GameEvents.creature_spawned.emit(creature)


## Handle creature despawned - update portal counts
func _on_creature_despawned(creature_id: int) -> void:
	if not map_data:
		return
	
	# Find creature to get portal origin
	var creature := map_data.get_creature(creature_id)
	if creature and creature.portal_origin != Vector2i(-1, -1):
		var portal_pos := creature.portal_origin
		if portal_creature_counts.has(portal_pos):
			portal_creature_counts[portal_pos] = maxi(0, portal_creature_counts[portal_pos] - 1)


## Get creature type enum from string name
func _get_creature_type_from_name(name: String) -> CreatureTypes.Type:
	# Use the built-in from_string which handles unknown types gracefully
	return CreatureTypes.from_string(name)


## Count existing creatures from a portal for a faction
func _count_portal_creatures(portal_pos: Vector2i, faction_id: int) -> int:
	var count := 0
	for creature in map_data.creatures:
		if creature.faction_id == faction_id and creature.portal_origin == portal_pos:
			count += 1
	return count


## Get spawn info for a portal (for UI display)
func get_portal_spawn_info(pos: Vector2i) -> Dictionary:
	var tile: Variant = map_data.get_tile(pos)
	if not tile or not map_data.is_portal(pos):
		return {}
	
	var config: Variant = map_data.get_portal_config(pos)
	if not config:
		config = {
			"spawn_rate": 60.0,
			"max_creatures": 8,
			"creature_types": ["IMP"]
		}
	
	return {
		"position": pos,
		"faction_id": tile["faction_id"],
		"is_active": spawn_timers.has(pos),
		"time_until_spawn": spawn_timers.get(pos, -1.0),
		"current_creatures": portal_creature_counts.get(pos, 0),
		"max_creatures": config.get("max_creatures", 8),
		"creature_types": config.get("creature_types", ["IMP"])
	}
