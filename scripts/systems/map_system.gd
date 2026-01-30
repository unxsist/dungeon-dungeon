class_name MapSystem
extends Node
## System responsible for loading, managing, and saving map data.

signal map_ready(map_data: MapData)

## Currently loaded map data
var current_map: MapData = null

## Path to currently loaded map file
var current_map_path: String = ""


func _ready() -> void:
	# Connect to game events
	# Note: dig_requested is no longer used - digging is now handled via
	# the dig marking system (dig_marked signal) and task system
	GameEvents.claim_requested.connect(_on_claim_requested)
	GameEvents.map_save_requested.connect(_on_save_requested)
	GameEvents.map_load_requested.connect(_on_load_requested)


## Load a map from a JSON file
func load_map(path: String) -> MapData:
	var file := FileAccess.open(path, FileAccess.READ)
	if not file:
		push_error("Failed to open map file: %s" % path)
		return null
	
	var json_text := file.get_as_text()
	file.close()
	
	var json := JSON.new()
	var error := json.parse(json_text)
	if error != OK:
		push_error("Failed to parse map JSON: %s at line %d" % [json.get_error_message(), json.get_error_line()])
		return null
	
	var data: Dictionary = json.data
	current_map = _parse_map_data(data)
	current_map.source_file = path
	current_map_path = path
	
	GameEvents.map_loaded.emit(current_map)
	map_ready.emit(current_map)
	
	return current_map


## Parse map data from JSON dictionary
func _parse_map_data(data: Dictionary) -> MapData:
	var map := MapData.new()
	
	# Parse metadata
	var meta: Dictionary = data.get("meta", {})
	map.map_name = meta.get("name", "Unnamed")
	map.width = meta.get("width", 20)
	map.height = meta.get("height", 20)
	map.tile_size = meta.get("tile_size", 4.0)
	
	# Initialize with default rock tiles
	map.initialize(map.width, map.height, TileTypes.Type.ROCK)
	
	# Parse tiles
	var tiles_array: Array = data.get("tiles", [])
	for tile_data in tiles_array:
		var pos := Vector2i(tile_data.get("x", 0), tile_data.get("y", 0))
		var type_str: String = tile_data.get("type", "rock")
		var tile_type := TileTypes.from_string(type_str)
		
		var faction_id: int = -1
		if tile_data.has("faction_id") and tile_data["faction_id"] != null:
			faction_id = tile_data["faction_id"]
		
		var tile := {
			"type": tile_type,
			"faction_id": faction_id,
			"health": tile_data.get("health", TileTypes.get_property(tile_type, "default_health")),
			"variation": tile_data.get("variation", randi() % 4),
		}
		
		map.set_tile(pos, tile)
	
	# Parse factions
	var factions_array: Array = data.get("factions", [])
	for faction_data in factions_array:
		var faction := FactionData.from_dict(faction_data)
		map.factions.append(faction)
		# Parse starting gold for this faction
		var starting_gold: int = faction_data.get("starting_gold", 0)
		map.faction_gold[faction.id] = starting_gold
	
	# Parse spawn points
	var spawns_array: Array = data.get("spawn_points", [])
	for spawn_data in spawns_array:
		map.spawn_points.append({
			"faction_id": spawn_data.get("faction_id", 0),
			"position": Vector2i(spawn_data.get("x", 0), spawn_data.get("y", 0)),
		})
	
	# Parse creatures
	var creatures_array: Array = data.get("creatures", [])
	for creature_data in creatures_array:
		var creature := CreatureData.from_dict(creature_data, map.next_creature_id)
		map.add_creature(creature)
	
	# Parse claim progress (if saved mid-game)
	var claim_progress_data: Dictionary = data.get("claim_progress", {})
	for pos_str in claim_progress_data.keys():
		# Position stored as "x,y" string in JSON
		var parts: PackedStringArray = pos_str.split(",")
		if parts.size() == 2:
			var pos := Vector2i(int(parts[0]), int(parts[1]))
			var progress_data: Dictionary = claim_progress_data[pos_str]
			map.claim_progress[pos] = {
				"faction_id": progress_data.get("faction_id", 0),
				"progress": progress_data.get("progress", 0.0),
			}
	
	# Parse dig markings (if saved mid-game)
	var dig_markings_data: Dictionary = data.get("dig_markings", {})
	for pos_str in dig_markings_data.keys():
		var parts: PackedStringArray = pos_str.split(",")
		if parts.size() == 2:
			var pos := Vector2i(int(parts[0]), int(parts[1]))
			map.marked_for_digging[pos] = dig_markings_data[pos_str]
	
	# Parse portal configurations
	var portals_array: Array = data.get("portals", [])
	for portal_data in portals_array:
		map.portal_configs.append({
			"position": Vector2i(portal_data.get("x", 0), portal_data.get("y", 0)),
			"spawn_rate": portal_data.get("spawn_rate", 15.0),
			"max_creatures": portal_data.get("max_creatures", 10),
			"creature_types": portal_data.get("creature_types", ["imp"]),
		})
	
	# Parse rooms (if saved mid-game)
	var rooms_array: Array = data.get("rooms", [])
	for room_data_dict in rooms_array:
		var room := RoomData.from_dict(room_data_dict)
		map.add_room(room)
	
	return map


## Generate a simple test map programmatically
func generate_test_map(w: int = 20, h: int = 20) -> MapData:
	var map := MapData.new()
	map.map_name = "Generated Test Map"
	map.width = w
	map.height = h
	map.tile_size = 4.0
	
	# Initialize all as rock
	map.initialize(w, h, TileTypes.Type.ROCK)
	
	# Create border of rock, interior of wall
	for y in range(h):
		for x in range(w):
			var pos := Vector2i(x, y)
			if x == 0 or x == w - 1 or y == 0 or y == h - 1:
				# Border is rock (already set)
				pass
			else:
				# Interior is wall (diggable)
				map.set_tile(pos, {
					"type": TileTypes.Type.WALL,
					"faction_id": -1,
					"health": 100,
					"variation": randi() % 4,
				})
	
	# Create a small starting room for player
	var room_center := Vector2i(w / 4, h / 2)
	_carve_room(map, room_center, 3, 0)  # Faction 0 = player
	
	# Create a small room for enemy
	var enemy_room := Vector2i(3 * w / 4, h / 2)
	_carve_room(map, enemy_room, 2, 1)  # Faction 1 = enemy

	# Create a corridor between rooms (unclaimed floor)
	for x in range(room_center.x + 4, enemy_room.x - 2):
		var corridor_pos := Vector2i(x, room_center.y)
		map.set_tile(corridor_pos, {
			"type": TileTypes.Type.FLOOR,
			"faction_id": -1,
			"health": -1,
			"variation": randi() % 4,
		})

	# Add a diggable wall cluster for testing
	for y in range(2, 6):
		for x in range(2, 6):
			map.set_tile(Vector2i(x, y), {
				"type": TileTypes.Type.WALL,
				"faction_id": -1,
				"health": 100,
				"variation": randi() % 4,
			})
	
	# Add factions
	var player_faction := FactionData.new()
	player_faction.id = 0
	player_faction.faction_name = "Player"
	player_faction.color = Color("#3366ff")
	player_faction.is_player_controlled = true
	map.factions.append(player_faction)
	
	var enemy_faction := FactionData.new()
	enemy_faction.id = 1
	enemy_faction.faction_name = "Enemy"
	enemy_faction.color = Color("#ff3333")
	enemy_faction.is_player_controlled = false
	map.factions.append(enemy_faction)
	
	# Add spawn points
	map.spawn_points.append({"faction_id": 0, "position": room_center})
	map.spawn_points.append({"faction_id": 1, "position": enemy_room})
	
	# Add starting Imps for player faction
	for i in range(3):
		var imp := CreatureData.new()
		imp.initialize(CreatureTypes.Type.IMP, 1)
		imp.faction_id = 0
		imp.tile_position = room_center + Vector2i(i - 1, 0)
		imp.visual_position = Vector2(imp.tile_position) * map.tile_size + Vector2(map.tile_size, map.tile_size) / 2.0
		map.add_creature(imp)
	
	# Add starting Imps for enemy faction
	for i in range(2):
		var imp := CreatureData.new()
		imp.initialize(CreatureTypes.Type.IMP, 1)
		imp.faction_id = 1
		imp.tile_position = enemy_room + Vector2i(i, 0)
		imp.visual_position = Vector2(imp.tile_position) * map.tile_size + Vector2(map.tile_size, map.tile_size) / 2.0
		map.add_creature(imp)
	
	current_map = map
	GameEvents.map_loaded.emit(current_map)
	map_ready.emit(current_map)
	
	return map


## Helper to carve out a room
func _carve_room(map: MapData, center: Vector2i, radius: int, faction_id: int) -> void:
	for dy in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			var pos := center + Vector2i(dx, dy)
			if map.is_valid_position(pos):
				map.set_tile(pos, {
					"type": TileTypes.Type.CLAIMED,
					"faction_id": faction_id,
					"health": -1,
					"variation": randi() % 4,
				})


## Handle claim request
func _on_claim_requested(position: Vector2i, faction_id: int) -> void:
	if not current_map:
		return
	
	var tile = current_map.get_tile(position)
	if not tile:
		return
	
	var tile_type: TileTypes.Type = tile["type"]
	
	# Can only claim floor tiles adjacent to existing territory
	if not TileTypes.is_claimable(tile_type):
		return
	
	if not current_map.is_adjacent_to_faction(position, faction_id):
		return
	
	var type_result: Variant = current_map.set_tile_type(position, TileTypes.Type.CLAIMED)
	if type_result:
		GameEvents.tile_changed.emit(position, type_result[0], type_result[1])
	
	var faction_result: Variant = current_map.set_tile_faction(position, faction_id)
	if faction_result:
		GameEvents.tile_ownership_changed.emit(position, faction_result[0], faction_result[1])


## Handle save request
func _on_save_requested() -> void:
	if current_map:
		save_map("user://saves/quicksave.json")


## Handle load request
func _on_load_requested(path: String) -> void:
	load_map(path)


## Save current map state
func save_map(path: String) -> bool:
	if not current_map:
		push_error("No map loaded to save")
		return false
	
	# Ensure directory exists
	var dir := DirAccess.open("user://")
	if dir and not dir.dir_exists("saves"):
		dir.make_dir("saves")
	
	var save_data := _build_save_data()
	
	var file := FileAccess.open(path, FileAccess.WRITE)
	if not file:
		push_error("Failed to open save file: %s" % path)
		return false
	
	file.store_string(JSON.stringify(save_data, "\t"))
	file.close()
	
	print("Map saved to: %s" % path)
	return true


## Build save data dictionary
func _build_save_data() -> Dictionary:
	var tile_states: Array[Dictionary] = []
	
	# Only save tiles that differ from default (rock)
	# In a full implementation, we'd compare against the original map
	for pos in current_map.tiles.keys():
		var tile = current_map.tiles[pos]
		if tile["type"] != TileTypes.Type.ROCK:
			tile_states.append({
				"x": pos.x,
				"y": pos.y,
				"type": TileTypes.to_string_name(tile["type"]),
				"faction_id": tile["faction_id"] if tile["faction_id"] >= 0 else null,
				"health": tile["health"],
				"variation": tile["variation"],
			})
	
	var factions_data: Array[Dictionary] = []
	for faction in current_map.factions:
		var faction_dict := faction.to_dict()
		# Include current gold in save
		faction_dict["starting_gold"] = current_map.get_gold(faction.id)
		factions_data.append(faction_dict)
	
	# Save creatures
	var creatures_data: Array[Dictionary] = []
	for creature in current_map.creatures:
		creatures_data.append(creature.to_dict())
	
	# Save claim progress (convert Vector2i keys to strings for JSON)
	var claim_progress_data: Dictionary = {}
	for pos in current_map.claim_progress.keys():
		var pos_str := "%d,%d" % [pos.x, pos.y]
		claim_progress_data[pos_str] = current_map.claim_progress[pos]
	
	# Save dig markings (convert Vector2i keys to strings for JSON)
	var dig_markings_data: Dictionary = {}
	for pos in current_map.marked_for_digging.keys():
		var pos_str := "%d,%d" % [pos.x, pos.y]
		dig_markings_data[pos_str] = current_map.marked_for_digging[pos]
	
	# Save portal configurations
	var portals_data: Array[Dictionary] = []
	for portal_config in current_map.portal_configs:
		portals_data.append({
			"x": portal_config["position"].x,
			"y": portal_config["position"].y,
			"spawn_rate": portal_config["spawn_rate"],
			"max_creatures": portal_config["max_creatures"],
			"creature_types": portal_config["creature_types"],
		})
	
	# Save rooms
	var rooms_data: Array[Dictionary] = []
	for room in current_map.rooms:
		rooms_data.append(room.to_dict())
	
	return {
		"meta": {
			"save_version": "1.0",
			"timestamp": Time.get_datetime_string_from_system(),
			"name": current_map.map_name,
			"width": current_map.width,
			"height": current_map.height,
			"tile_size": current_map.tile_size,
		},
		"source_file": current_map.source_file,
		"tiles": tile_states,
		"factions": factions_data,
		"spawn_points": current_map.spawn_points.map(func(sp): return {
			"faction_id": sp["faction_id"],
			"x": sp["position"].x,
			"y": sp["position"].y,
		}),
		"creatures": creatures_data,
		"claim_progress": claim_progress_data,
		"dig_markings": dig_markings_data,
		"portals": portals_data,
		"rooms": rooms_data,
	}


## Load a save file
func load_save(path: String) -> MapData:
	var file := FileAccess.open(path, FileAccess.READ)
	if not file:
		push_error("Failed to open save file: %s" % path)
		return null
	
	var json_text := file.get_as_text()
	file.close()
	
	var json := JSON.new()
	var error := json.parse(json_text)
	if error != OK:
		push_error("Failed to parse save JSON: %s" % json.get_error_message())
		return null
	
	var data: Dictionary = json.data
	
	# Load base map if specified
	var source_file: String = data.get("source_file", "")
	if source_file and FileAccess.file_exists(source_file):
		current_map = load_map(source_file)
	else:
		# Recreate from save data
		current_map = _parse_map_data(data)
	
	current_map_path = path
	
	GameEvents.map_loaded.emit(current_map)
	map_ready.emit(current_map)
	
	return current_map
