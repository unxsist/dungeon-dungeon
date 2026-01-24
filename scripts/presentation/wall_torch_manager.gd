class_name WallTorchManager
extends Node3D
## Manages torch lights on walls adjacent to claimed territory.
## Torches are spaced naturally with minimum distance between them.
## Uses shadow-casting ceiling plane to prevent light from illuminating wall tops.

## Reference to the map data
var map_data: MapData = null

## Torch configuration
@export var torch_min_spacing: float = 3.0  ## Minimum tiles between torches
@export var torch_max_spacing: float = 4.0  ## Maximum tiles between torches (for variation)
@export var torch_energy: float = 1.4  ## Base light energy
@export var torch_range: float = 6.0  ## Light range in units (shorter to not reach wall tops)
@export var torch_color: Color = Color(1.0, 0.7, 0.4)  ## Warm orange fire color
@export var torch_height_fraction: float = 0.35  ## Height on wall as fraction of WALL_HEIGHT (lower position)
@export var torch_offset_from_wall: float = 0.6  ## Distance from wall face

## Flickering configuration
@export var flicker_speed_1: float = 8.0  ## Primary flicker frequency
@export var flicker_speed_2: float = 13.0  ## Secondary flicker frequency
@export var flicker_speed_3: float = 21.0  ## Tertiary flicker frequency
@export var flicker_amount_1: float = 0.08  ## Primary flicker amplitude
@export var flicker_amount_2: float = 0.05  ## Secondary flicker amplitude
@export var flicker_amount_3: float = 0.03  ## Tertiary flicker amplitude

## Wall height constant (must match TileRenderer)
const WALL_HEIGHT := 3.0

## Container for torch lights
var torch_container: Node3D

## Dictionary of torch lights: { "wall_pos,direction": OmniLight3D }
## Key format: "x,y,dx,dy" where (x,y) is wall position and (dx,dy) is direction to claimed tile
var torch_lights: Dictionary = {}

## Set of all eligible torch positions (for spacing calculation)
## Each entry is { "pos": Vector2i, "dir": Vector2i, "world_pos": Vector3 }
var eligible_positions: Array[Dictionary] = []

## Time accumulator for flickering animation
var time: float = 0.0


func _ready() -> void:
	torch_container = Node3D.new()
	torch_container.name = "TorchContainer"
	add_child(torch_container)
	
	# Connect to map events
	GameEvents.map_loaded.connect(_on_map_loaded)
	GameEvents.tile_changed.connect(_on_tile_changed)
	GameEvents.tile_ownership_changed.connect(_on_tile_ownership_changed)


func _process(delta: float) -> void:
	if torch_lights.is_empty():
		return
	
	time += delta
	
	# Update flickering for all torches
	for light: OmniLight3D in torch_lights.values():
		var flicker := _calculate_flicker(light)
		light.light_energy = torch_energy * flicker


## Calculate flicker multiplier using multiple sine waves for organic effect
## Each torch has a slightly different phase based on its position
func _calculate_flicker(light: OmniLight3D) -> float:
	# Get phase offset from light metadata (set during creation)
	var phase_offset: float = light.get_meta("phase_offset", 0.0)
	var t := time + phase_offset
	
	# Combine multiple sine waves for organic flickering
	var flicker := 1.0
	flicker += sin(t * flicker_speed_1) * flicker_amount_1
	flicker += sin(t * flicker_speed_2) * flicker_amount_2
	flicker += sin(t * flicker_speed_3) * flicker_amount_3
	
	return flicker


## Handle map loaded event
func _on_map_loaded(data: Resource) -> void:
	map_data = data as MapData
	if map_data:
		_rebuild_all_torches()


## Handle tile type change
func _on_tile_changed(_pos: Vector2i, _old_type: int, _new_type: int) -> void:
	if not map_data:
		return
	# Rebuild all torches when tile types change (affects eligibility)
	_rebuild_all_torches()


## Handle tile ownership change
func _on_tile_ownership_changed(_pos: Vector2i, _old_faction: int, _new_faction: int) -> void:
	if not map_data:
		return
	# Rebuild all torches when ownership changes
	_rebuild_all_torches()


## Rebuild all torches using spacing algorithm
func _rebuild_all_torches() -> void:
	# Clear existing torches
	for light: OmniLight3D in torch_lights.values():
		if is_instance_valid(light):
			light.queue_free()
	torch_lights.clear()
	eligible_positions.clear()
	
	if not map_data:
		return
	
	# Step 1: Collect all eligible torch positions (walls adjacent to claimed tiles)
	_collect_eligible_positions()
	
	# Step 2: Place torches with minimum spacing
	_place_torches_with_spacing()


## Collect all wall faces adjacent to claimed tiles
func _collect_eligible_positions() -> void:
	for pos in map_data.tiles.keys():
		var tile = map_data.get_tile(pos)
		if not tile:
			continue
		
		var tile_type: TileTypes.Type = tile["type"]
		
		# Only walls and rocks can have torches
		if tile_type != TileTypes.Type.WALL and tile_type != TileTypes.Type.ROCK:
			continue
		
		var neighbors := map_data.get_neighbors(pos)
		
		for dir: Vector2i in MapData.DIRECTIONS:
			if not neighbors.has(dir):
				continue
			
			var neighbor = neighbors[dir]
			if not neighbor:
				continue
			
			var neighbor_type: TileTypes.Type = neighbor["type"]
			if neighbor_type != TileTypes.Type.CLAIMED:
				continue
			
			# This is an eligible position
			var world_pos := _calculate_torch_position(pos, dir)
			eligible_positions.append({
				"pos": pos,
				"dir": dir,
				"world_pos": world_pos
			})
	
	# Sort positions deterministically for consistent placement
	eligible_positions.sort_custom(_compare_positions)


## Deterministic position comparison for sorting
func _compare_positions(a: Dictionary, b: Dictionary) -> bool:
	# Sort by a deterministic hash to get consistent but varied ordering
	var hash_a := _position_hash(a["pos"], a["dir"])
	var hash_b := _position_hash(b["pos"], b["dir"])
	return hash_a < hash_b


## Generate deterministic hash for a position
func _position_hash(pos: Vector2i, dir: Vector2i) -> int:
	var hash_val := pos.x * 73856093
	hash_val ^= pos.y * 19349663
	hash_val ^= dir.x * 83492791
	hash_val ^= dir.y * 47101137
	return hash_val


## Place torches ensuring minimum spacing
func _place_torches_with_spacing() -> void:
	var placed_positions: Array[Vector3] = []
	
	for entry in eligible_positions:
		var world_pos: Vector3 = entry["world_pos"]
		var wall_pos: Vector2i = entry["pos"]
		var direction: Vector2i = entry["dir"]
		
		# Check distance to all already-placed torches
		var min_distance := _get_min_distance_to_placed(world_pos, placed_positions)
		
		# Determine spacing threshold with some variation based on position
		var hash_val := _position_hash(wall_pos, direction)
		var variation := fmod(absf(float(hash_val) * 0.0000001), 1.0)
		var spacing_threshold := torch_min_spacing + variation * (torch_max_spacing - torch_min_spacing)
		spacing_threshold *= map_data.tile_size  # Convert to world units
		
		# Place torch if far enough from others
		if min_distance >= spacing_threshold:
			_create_torch(wall_pos, direction)
			placed_positions.append(world_pos)


## Get minimum distance from a position to any placed torch
func _get_min_distance_to_placed(pos: Vector3, placed: Array[Vector3]) -> float:
	if placed.is_empty():
		return INF
	
	var min_dist := INF
	for placed_pos in placed:
		var dist := pos.distance_to(placed_pos)
		if dist < min_dist:
			min_dist = dist
	
	return min_dist


## Create a torch light at the specified wall face
func _create_torch(wall_pos: Vector2i, direction: Vector2i) -> void:
	var torch_key := _get_torch_key(wall_pos, direction)
	
	# Don't create if already exists
	if torch_lights.has(torch_key):
		return
	
	var light := OmniLight3D.new()
	light.name = "Torch_%s" % torch_key
	light.light_color = torch_color
	light.light_energy = torch_energy
	light.omni_range = torch_range
	light.omni_attenuation = 1.2  # Steeper falloff so light fades before reaching wall tops
	light.shadow_enabled = false  # No shadows for performance
	light.light_bake_mode = Light3D.BAKE_DISABLED
	
	# Calculate world position for the torch
	var world_pos := _calculate_torch_position(wall_pos, direction)
	light.position = world_pos
	
	# Store phase offset for varied flickering (based on position hash)
	var phase_hash := wall_pos.x * 12345 + wall_pos.y * 67890 + direction.x * 11111 + direction.y * 22222
	var phase_offset := fmod(float(phase_hash) * 0.001, TAU)
	light.set_meta("phase_offset", phase_offset)
	light.set_meta("wall_pos", wall_pos)
	light.set_meta("direction", direction)
	
	torch_container.add_child(light)
	torch_lights[torch_key] = light


## Calculate world position for a torch on a wall face
func _calculate_torch_position(wall_pos: Vector2i, direction: Vector2i) -> Vector3:
	var tile_size := map_data.tile_size
	
	# Start at center of wall tile
	var base_pos := map_data.tile_to_world(wall_pos)
	
	# Move to the face in the direction of the claimed tile
	var face_offset := Vector3(direction.x, 0, direction.y) * (tile_size * 0.5 + torch_offset_from_wall)
	
	# Set height on wall
	var height := WALL_HEIGHT * torch_height_fraction
	
	return Vector3(base_pos.x + face_offset.x, height, base_pos.z + face_offset.z)


## Generate a unique key for a torch at a wall face
func _get_torch_key(wall_pos: Vector2i, direction: Vector2i) -> String:
	return "%d,%d,%d,%d" % [wall_pos.x, wall_pos.y, direction.x, direction.y]


## Get torch count (for debugging)
func get_torch_count() -> int:
	return torch_lights.size()
