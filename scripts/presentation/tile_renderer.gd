class_name TileRenderer
extends Node3D
## Renders the tile map using MeshInstance3D nodes.
## Supports procedural mesh generation with edge variations.

## Reference to the map data
var map_data: MapData = null

## Container for tile mesh instances
var tile_container: Node3D

## Materials for different tile types and factions
var materials: Dictionary = {}

## Mesh instances keyed by position
var tile_meshes: Dictionary = {}

## Border mesh around map bounds
var border_mesh: MeshInstance3D

## Wall height for raised tiles
const WALL_HEIGHT := 3.0

## Floor offset (slightly above 0 to prevent z-fighting)
const FLOOR_Y := 0.01

## Edge variation settings
const EDGE_SUBDIVISIONS := 4  ## Number of subdivisions per edge
const EDGE_VARIATION_AMOUNT := 0.15  ## Max displacement as fraction of tile size
const HEIGHT_VARIATION_AMOUNT := 0.1  ## Max height variation for walls
const WALL_FACE_VARIATION_AMOUNT := 0.05  ## Subtle side face deformation
const FLOOR_HEIGHT_VARIATION := 0.08  ## Subtle floor deformation for dungeon feel

## Border shading settings
@export var border_padding: float = 20.0
@export var border_fade_distance: float = 12.0
@export var border_y: float = -0.02

var border_shader: Shader

## Floor shaders and textures
var unclaimed_floor_shader: Shader
var unclaimed_floor_texture: Texture2D
var claimed_floor_shader: Shader
var claimed_floor_texture: Texture2D

## Wall shader and texture
var diggable_wall_shader: Shader
var diggable_wall_texture: Texture2D

## Rock shader and texture
var rock_shader: Shader
var rock_texture: Texture2D

## Noise generator for procedural variations
var noise: FastNoiseLite


func _ready() -> void:
	tile_container = $TileContainer
	_setup_noise()
	_setup_materials()
	_setup_border_shader()
	
	# Connect to map events
	GameEvents.map_loaded.connect(_on_map_loaded)
	GameEvents.tile_changed.connect(_on_tile_changed)
	GameEvents.tile_ownership_changed.connect(_on_tile_ownership_changed)


## Setup noise generator for procedural variations
func _setup_noise() -> void:
	noise = FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise.seed = 12345  # Fixed seed for consistency
	noise.frequency = 0.5


## Setup materials for tile types
func _setup_materials() -> void:
	# Rock material - textured with triplanar mapping and depth from luminance
	rock_shader = load("res://shaders/rock.gdshader")
	rock_texture = load("res://resources/textures/rock.png")
	var rock_mat := ShaderMaterial.new()
	rock_mat.shader = rock_shader
	rock_mat.set_shader_parameter("albedo_texture", rock_texture)
	rock_mat.set_shader_parameter("texture_scale", 1.0)
	rock_mat.set_shader_parameter("roughness", 0.9)
	rock_mat.set_shader_parameter("top_darkening", 0.25)  # Darken top face
	rock_mat.set_shader_parameter("normal_strength", 1.2)  # Depth from light/dark
	rock_mat.set_shader_parameter("normal_sample_offset", 0.004)
	rock_mat.set_shader_parameter("deformation_strength", 0.3)
	rock_mat.set_shader_parameter("noise_scale", 0.2)
	rock_mat.set_shader_parameter("procedural_blend", 0.15)
	rock_mat.set_shader_parameter("brightness_variation", 0.05)
	rock_mat.set_shader_parameter("top_rotation_variation", 0.3)  # Smooth UV rotation on top
	rock_mat.set_shader_parameter("top_offset_variation", 0.15)  # Smooth UV offset on top
	rock_mat.set_shader_parameter("triplanar_sharpness", 4.0)  # Sharp blending between faces
	materials["rock"] = rock_mat
	
	# Wall material - textured diggable wall
	diggable_wall_shader = load("res://shaders/diggable_wall.gdshader")
	diggable_wall_texture = load("res://resources/textures/diggable_wall.png")
	var wall_mat := ShaderMaterial.new()
	wall_mat.shader = diggable_wall_shader
	wall_mat.set_shader_parameter("albedo_texture", diggable_wall_texture)
	wall_mat.set_shader_parameter("texture_scale", 1.0)
	wall_mat.set_shader_parameter("tint_color", Color(0.9, 0.85, 0.8))
	wall_mat.set_shader_parameter("tint_strength", 0.1)
	wall_mat.set_shader_parameter("roughness", 0.85)
	wall_mat.set_shader_parameter("normal_strength", 1.2)
	wall_mat.set_shader_parameter("deformation_strength", 0.5)
	wall_mat.set_shader_parameter("noise_scale", 0.3)
	wall_mat.set_shader_parameter("procedural_blend", 0.3)
	wall_mat.set_shader_parameter("brightness_variation", 0.08)
	wall_mat.set_shader_parameter("top_rotation_variation", 0.3)  # Smooth UV rotation on top
	wall_mat.set_shader_parameter("top_offset_variation", 0.15)  # Smooth UV offset on top
	wall_mat.set_shader_parameter("triplanar_sharpness", 4.0)  # Sharp blending between faces
	materials["wall"] = wall_mat
	
	# Floor material - textured loose sand/dirt with deformation
	unclaimed_floor_shader = load("res://shaders/unclaimed_floor.gdshader")
	unclaimed_floor_texture = load("res://resources/textures/unclaimed_floor.png")
	var floor_mat := ShaderMaterial.new()
	floor_mat.shader = unclaimed_floor_shader
	floor_mat.set_shader_parameter("albedo_texture", unclaimed_floor_texture)
	floor_mat.set_shader_parameter("texture_scale", 1.0)
	floor_mat.set_shader_parameter("tint_color", Color(1.0, 0.98, 0.95))
	floor_mat.set_shader_parameter("tint_strength", 0.05)
	floor_mat.set_shader_parameter("roughness", 0.85)
	floor_mat.set_shader_parameter("deformation_strength", 1.5)  # Higher for messy sand look
	floor_mat.set_shader_parameter("noise_scale", 0.5)
	floor_mat.set_shader_parameter("uv_distortion_amount", 0.15)  # Loose sand UV distortion
	floor_mat.set_shader_parameter("uv_distortion_scale", 0.3)
	floor_mat.set_shader_parameter("rotation_variation", 0.4)  # Per-tile rotation variation
	floor_mat.set_shader_parameter("offset_variation", 0.25)  # Per-tile offset variation
	floor_mat.set_shader_parameter("normal_strength", 1.5)
	floor_mat.set_shader_parameter("brightness_variation", 0.1)
	materials["floor"] = floor_mat
	
	# Claimed floor shader and texture
	claimed_floor_shader = load("res://shaders/claimed_floor.gdshader")
	claimed_floor_texture = load("res://resources/textures/claimed_player.png")
	
	# Claimed materials by faction (will be generated dynamically)
	materials["claimed"] = {}


## Setup border shader
func _setup_border_shader() -> void:
	border_shader = load("res://shaders/map_border.gdshader")


## Player faction ID constant
const PLAYER_FACTION_ID := 0


## Get or create material for claimed tile
func _get_claimed_material(faction_id: int) -> ShaderMaterial:
	if materials["claimed"].has(faction_id):
		return materials["claimed"][faction_id]
	
	var mat := ShaderMaterial.new()
	mat.shader = claimed_floor_shader
	
	# Set the claimed floor texture
	mat.set_shader_parameter("albedo_texture", claimed_floor_texture)
	
	# Get faction color if available
	var faction_color := Color(0.3, 0.3, 0.5)  # Default blue-gray
	var is_player := faction_id == PLAYER_FACTION_ID
	
	if map_data:
		var faction := map_data.get_faction(faction_id)
		if faction:
			faction_color = faction.color
	
	# For enemy factions, use bright red
	if not is_player:
		faction_color = Color(1.0, 0.2, 0.15)  # Bright red for enemies
	
	# Set shader parameters
	mat.set_shader_parameter("faction_color", faction_color)
	mat.set_shader_parameter("faction_mix", 0.15 if is_player else 0.2)
	mat.set_shader_parameter("color_replace_strength", 0.0 if is_player else 0.95)  # Replace cyan crystal with red for enemies
	mat.set_shader_parameter("roughness", 0.65)
	mat.set_shader_parameter("normal_strength", 1.5)
	mat.set_shader_parameter("brightness_variation", 0.06)
	mat.set_shader_parameter("saturation_variation", 0.04)
	# Procedural deformation for dungeon floor feel
	mat.set_shader_parameter("deformation_strength", 0.6)
	mat.set_shader_parameter("noise_scale", 0.4)
	mat.set_shader_parameter("procedural_blend", 0.4)
	
	materials["claimed"][faction_id] = mat
	return mat


## Handle map loaded event
func _on_map_loaded(data: Resource) -> void:
	map_data = data as MapData
	if map_data:
		# Clear claimed materials cache (factions may have changed)
		materials["claimed"] = {}
		render_map()
		_update_border_mesh()


## Render the entire map
func render_map() -> void:
	if not map_data:
		return
	
	# Clear existing meshes
	_clear_meshes()
	
	# Generate mesh for each tile
	for pos in map_data.tiles.keys():
		_create_tile_mesh(pos)

	_update_border_mesh()


## Clear all tile meshes
func _clear_meshes() -> void:
	for mesh in tile_meshes.values():
		if is_instance_valid(mesh):
			mesh.queue_free()
	tile_meshes.clear()

	if border_mesh and is_instance_valid(border_mesh):
		border_mesh.queue_free()
		border_mesh = null


## Create mesh for a single tile
func _create_tile_mesh(pos: Vector2i) -> void:
	var tile = map_data.get_tile(pos)
	if not tile:
		return
	
	var tile_type: TileTypes.Type = tile["type"]
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "Tile_%d_%d" % [pos.x, pos.y]
	
	# Create mesh based on tile type
	match tile_type:
		TileTypes.Type.ROCK, TileTypes.Type.WALL:
			mesh_instance.mesh = _create_wall_mesh(pos, tile)
			mesh_instance.material_override = _get_material_for_tile(tile)
		TileTypes.Type.FLOOR:
			mesh_instance.mesh = _create_floor_mesh(pos, tile)
			mesh_instance.material_override = _get_material_for_tile(tile)
		TileTypes.Type.CLAIMED:
			# Calculate tile seed for per-tile variation (hash of position)
			var tile_seed := _get_tile_seed(pos)
			mesh_instance.mesh = _create_floor_mesh(pos, tile, tile_seed)
			mesh_instance.material_override = _get_material_for_tile(tile)
	
	# Position the mesh
	var world_pos := map_data.tile_to_world(pos)
	world_pos.y = 0  # Base at ground level
	mesh_instance.position = world_pos - Vector3(map_data.tile_size * 0.5, 0, map_data.tile_size * 0.5)
	
	# Add to scene
	tile_container.add_child(mesh_instance)
	tile_meshes[pos] = mesh_instance
	
	# Store tile position in metadata
	mesh_instance.set_meta("tile_pos", pos)


## Update border mesh around map bounds
func _update_border_mesh() -> void:
	if not map_data:
		return

	if not border_mesh or not is_instance_valid(border_mesh):
		border_mesh = MeshInstance3D.new()
		border_mesh.name = "MapBorder"
		add_child(border_mesh)

	var bounds := map_data.get_world_bounds()
	var bounds_min := bounds.position
	var bounds_max := bounds.position + bounds.size

	# Create a plane larger than the map bounds
	var size_x := bounds.size.x + border_padding * 2.0
	var size_z := bounds.size.z + border_padding * 2.0
	var plane := PlaneMesh.new()
	plane.size = Vector2(size_x, size_z)
	border_mesh.mesh = plane

	# Center it around the map
	var center := bounds.position + bounds.size * 0.5
	border_mesh.position = Vector3(center.x, border_y, center.z)

	# Apply border shader material
	var mat := ShaderMaterial.new()
	mat.shader = border_shader
	mat.set_shader_parameter("bounds_min", bounds_min)
	mat.set_shader_parameter("bounds_max", bounds_max)
	mat.set_shader_parameter("fade_distance", border_fade_distance)
	mat.set_shader_parameter("inner_color", Color(0.0, 0.0, 0.0, 0.0))
	mat.set_shader_parameter("outer_color", Color(0.12, 0.06, 0.03, 1.0))
	border_mesh.material_override = mat


## Create a wall/rock mesh (raised box) with organic deformations
func _create_wall_mesh(pos: Vector2i, _tile: Dictionary) -> Mesh:
	var size := map_data.tile_size
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	
	var h := WALL_HEIGHT
	
	# Get neighbors to determine which faces to render
	var neighbors := map_data.get_neighbors(pos)
	
	# Generate subdivided top face with height variations
	var subdivs := EDGE_SUBDIVISIONS
	var step := size / subdivs
	
	# Create vertex grid for top face with height variation
	# Use WORLD coordinates for noise to ensure adjacent tiles share edge vertices
	var top_vertices: Array[Vector3] = []
	for z in range(subdivs + 1):
		for x in range(subdivs + 1):
			var vx := x * step
			var vz := z * step
			
			# Calculate world position for consistent noise across tile boundaries
			var world_x := pos.x * size + vx
			var world_z := pos.y * size + vz
			
			# Height variation using world coordinates (shared edges get same values)
			var height_var := noise.get_noise_2d(world_x * 0.3, world_z * 0.3)
			var vy := h + height_var * HEIGHT_VARIATION_AMOUNT * size
			
			top_vertices.append(Vector3(vx, vy, vz))
	
	# Create top face triangles
	for z in range(subdivs):
		for x in range(subdivs):
			var i := z * (subdivs + 1) + x
			var v0 := top_vertices[i]
			var v1 := top_vertices[i + 1]
			var v2 := top_vertices[i + subdivs + 2]
			var v3 := top_vertices[i + subdivs + 1]
			
			_add_quad_with_vertices(st, v0, v1, v2, v3)
	
	# Side faces - only render if adjacent to floor/claimed tile
	# Use the edge vertices from top face for seamless connection
	
	# North face (negative Z)
	if _should_render_wall_face(pos, Vector2i(0, -1), neighbors):
		_add_wall_face(st, pos, size, h, 
			Vector2i(0, -1),  # Direction
			top_vertices, subdivs)
	
	# South face (positive Z)
	if _should_render_wall_face(pos, Vector2i(0, 1), neighbors):
		_add_wall_face(st, pos, size, h,
			Vector2i(0, 1),
			top_vertices, subdivs)
	
	# West face (negative X)
	if _should_render_wall_face(pos, Vector2i(-1, 0), neighbors):
		_add_wall_face(st, pos, size, h,
			Vector2i(-1, 0),
			top_vertices, subdivs)
	
	# East face (positive X)
	if _should_render_wall_face(pos, Vector2i(1, 0), neighbors):
		_add_wall_face(st, pos, size, h,
			Vector2i(1, 0),
			top_vertices, subdivs)
	
	st.generate_normals()
	return st.commit()


## Add a wall face with subdivisions matching the top surface
func _add_wall_face(st: SurfaceTool, pos: Vector2i, size: float, height: float, 
		direction: Vector2i, top_vertices: Array[Vector3], subdivs: int) -> void:
	
	var normal := Vector3(direction.x, 0, direction.y)
	
	# Get the edge vertices from top face based on direction
	# Bottom vertices use floor height sampling to match adjacent floor deformation
	var edge_top: Array[Vector3] = []
	var edge_bottom: Array[Vector3] = []
	
	if direction == Vector2i(0, -1):  # North
		for x in range(subdivs + 1):
			var top_v := top_vertices[x]
			edge_top.append(top_v)
			# Sample floor height at world position for bottom vertex
			var world_x := pos.x * size + top_v.x
			var world_z := pos.y * size + top_v.z
			var floor_y := _get_floor_height_at(world_x, world_z)
			edge_bottom.append(Vector3(top_v.x, floor_y, top_v.z))
		# Reverse for correct winding
		edge_top.reverse()
		edge_bottom.reverse()
		
	elif direction == Vector2i(0, 1):  # South
		for x in range(subdivs + 1):
			var idx := subdivs * (subdivs + 1) + x
			var top_v := top_vertices[idx]
			edge_top.append(top_v)
			var world_x := pos.x * size + top_v.x
			var world_z := pos.y * size + top_v.z
			var floor_y := _get_floor_height_at(world_x, world_z)
			edge_bottom.append(Vector3(top_v.x, floor_y, top_v.z))
			
	elif direction == Vector2i(-1, 0):  # West
		for z in range(subdivs + 1):
			var idx := z * (subdivs + 1)
			var top_v := top_vertices[idx]
			edge_top.append(top_v)
			var world_x := pos.x * size + top_v.x
			var world_z := pos.y * size + top_v.z
			var floor_y := _get_floor_height_at(world_x, world_z)
			edge_bottom.append(Vector3(top_v.x, floor_y, top_v.z))
		# Reverse for correct winding
		edge_top.reverse()
		edge_bottom.reverse()
		
	elif direction == Vector2i(1, 0):  # East
		for z in range(subdivs + 1):
			var idx := z * (subdivs + 1) + subdivs
			var top_v := top_vertices[idx]
			edge_top.append(top_v)
			var world_x := pos.x * size + top_v.x
			var world_z := pos.y * size + top_v.z
			var floor_y := _get_floor_height_at(world_x, world_z)
			edge_bottom.append(Vector3(top_v.x, floor_y, top_v.z))
	
	# Create quads along the wall face with continuous UVs
	for i in range(subdivs):
		var t0 := edge_top[i]
		var t1 := edge_top[i + 1]
		var b0 := edge_bottom[i]
		var b1 := edge_bottom[i + 1]
		
		# Apply subtle deformation along the face normal using world coordinates.
		# Only deform the bottom edge to keep the top seam tight with the top face.
		# Skip deformation at corners (first and last vertices) to prevent gaps where faces meet.
		var is_first := (i == 0)
		var is_last := (i == subdivs - 1)
		if not is_first:
			b0 = _offset_wall_face_vertex(pos, b0, size, normal)
		if not is_last:
			b1 = _offset_wall_face_vertex(pos, b1, size, normal)
		
		# Calculate continuous UVs across the entire face (not per-subdivision)
		var u0 := float(i) / float(subdivs)
		var u1 := float(i + 1) / float(subdivs)
		var uv_t0 := Vector2(u0, 0.0)
		var uv_t1 := Vector2(u1, 0.0)
		var uv_b1 := Vector2(u1, 1.0)
		var uv_b0 := Vector2(u0, 1.0)
		
		_add_quad(st, t0, t1, b1, b0, normal, uv_t0, uv_t1, uv_b1, uv_b0)


## Offset a wall face vertex along the face normal with smooth noise
func _offset_wall_face_vertex(pos: Vector2i, local_v: Vector3, size: float, normal: Vector3) -> Vector3:
	# Use world coordinates so adjacent tiles match along shared edges
	var world_x := pos.x * size + local_v.x
	var world_z := pos.y * size + local_v.z
	var noise_val := noise.get_noise_2d(world_x * 0.6 + 1000.0, world_z * 0.6 + 1000.0)
	var offset := noise_val * WALL_FACE_VARIATION_AMOUNT * size
	return local_v + normal * offset


## Get floor height at a world position (matches floor mesh deformation)
func _get_floor_height_at(world_x: float, world_z: float) -> float:
	var height_var := noise.get_noise_2d(world_x * 0.5, world_z * 0.5)
	return FLOOR_Y + height_var * FLOOR_HEIGHT_VARIATION


## Check if wall face should be rendered (adjacent to walkable tile)
func _should_render_wall_face(pos: Vector2i, direction: Vector2i, neighbors: Dictionary) -> bool:
	if not neighbors.has(direction):
		return true  # Edge of map, render face to avoid see-through
	
	var neighbor = neighbors[direction]
	if neighbor:
		var neighbor_type: TileTypes.Type = neighbor["type"]
		return TileTypes.is_walkable(neighbor_type)
	return false


## Generate a deterministic seed for a tile position (for per-tile variation)
func _get_tile_seed(pos: Vector2i) -> float:
	# Simple hash combining x and y coordinates
	return float(pos.x * 73856093 ^ pos.y * 19349663)


## Create a floor mesh with organic deformations
## tile_seed: Optional seed for per-tile variation (passed via UV2 for shader use)
func _create_floor_mesh(pos: Vector2i, _tile: Dictionary, tile_seed: float = 0.0) -> Mesh:
	var size := map_data.tile_size
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	
	var subdivs := EDGE_SUBDIVISIONS
	var step := size / subdivs
	
	# Generate vertex grid with height variations
	# Use WORLD coordinates for noise to ensure adjacent tiles share edge vertices
	var vertices: Array[Vector3] = []
	for z in range(subdivs + 1):
		for x in range(subdivs + 1):
			var vx := x * step
			var vz := z * step
			
			# Calculate world position for consistent noise across tile boundaries
			var world_x := pos.x * size + vx
			var world_z := pos.y * size + vz
			
			# Subtle height variation using world coordinates (shared edges get same values)
			# Wall bottom edges sample this same height for seamless connection
			var vy := _get_floor_height_at(world_x, world_z)
			
			vertices.append(Vector3(vx, vy, vz))
	
	# Create triangles from vertex grid
	for z in range(subdivs):
		for x in range(subdivs):
			var i := z * (subdivs + 1) + x
			var v0 := vertices[i]
			var v1 := vertices[i + 1]
			var v2 := vertices[i + subdivs + 2]
			var v3 := vertices[i + subdivs + 1]
			
			_add_quad_with_vertices(st, v0, v1, v2, v3, tile_seed)
	
	st.generate_normals()
	return st.commit()


## Add a quad to the surface tool with explicit normal and UVs
func _add_quad(st: SurfaceTool, v0: Vector3, v1: Vector3, v2: Vector3, v3: Vector3, normal: Vector3,
		uv0: Vector2 = Vector2(0, 0), uv1: Vector2 = Vector2(1, 0), 
		uv2: Vector2 = Vector2(1, 1), uv3: Vector2 = Vector2(0, 1)) -> void:
	st.set_normal(normal)
	
	# UV coordinates
	st.set_uv(uv0)
	st.add_vertex(v0)
	
	st.set_uv(uv1)
	st.add_vertex(v1)
	
	st.set_uv(uv2)
	st.add_vertex(v2)
	
	# Second triangle
	st.set_uv(uv0)
	st.add_vertex(v0)
	
	st.set_uv(uv2)
	st.add_vertex(v2)
	
	st.set_uv(uv3)
	st.add_vertex(v3)


## Add a quad with auto-calculated UVs based on local position
## tile_seed: Optional seed stored in UV2.x for per-tile shader variation
func _add_quad_with_vertices(st: SurfaceTool, v0: Vector3, v1: Vector3, v2: Vector3, v3: Vector3, tile_seed: float = 0.0) -> void:
	# Calculate normal from vertices
	var edge1 := v1 - v0
	var edge2 := v3 - v0
	var normal := edge1.cross(edge2).normalized()
	
	# Calculate UVs based on XZ position (assuming horizontal surface)
	var size := map_data.tile_size if map_data else 4.0
	
	# UV2 stores tile seed for per-tile variation in shaders
	var uv2 := Vector2(tile_seed, 0.0)
	
	st.set_normal(normal)
	
	st.set_uv(Vector2(v0.x / size, v0.z / size))
	st.set_uv2(uv2)
	st.add_vertex(v0)
	
	st.set_uv(Vector2(v1.x / size, v1.z / size))
	st.set_uv2(uv2)
	st.add_vertex(v1)
	
	st.set_uv(Vector2(v2.x / size, v2.z / size))
	st.set_uv2(uv2)
	st.add_vertex(v2)
	
	# Second triangle
	st.set_uv(Vector2(v0.x / size, v0.z / size))
	st.set_uv2(uv2)
	st.add_vertex(v0)
	
	st.set_uv(Vector2(v2.x / size, v2.z / size))
	st.set_uv2(uv2)
	st.add_vertex(v2)
	
	st.set_uv(Vector2(v3.x / size, v3.z / size))
	st.set_uv2(uv2)
	st.add_vertex(v3)


## Get material for a tile
func _get_material_for_tile(tile: Dictionary) -> Material:
	var tile_type: TileTypes.Type = tile["type"]
	
	match tile_type:
		TileTypes.Type.ROCK:
			return materials["rock"]
		TileTypes.Type.WALL:
			return materials["wall"]
		TileTypes.Type.FLOOR:
			return materials["floor"]
		TileTypes.Type.CLAIMED:
			return _get_claimed_material(tile["faction_id"])
	
	return materials["floor"]


## Handle tile type change
func _on_tile_changed(pos: Vector2i, _old_type: int, _new_type: int) -> void:
	_update_tile_and_neighbors(pos)


## Handle tile ownership change
func _on_tile_ownership_changed(pos: Vector2i, _old_faction: int, _new_faction: int) -> void:
	_update_tile(pos)


## Update a single tile mesh
func _update_tile(pos: Vector2i) -> void:
	# Remove old mesh
	if tile_meshes.has(pos):
		var old_mesh = tile_meshes[pos]
		if is_instance_valid(old_mesh):
			old_mesh.queue_free()
		tile_meshes.erase(pos)
	
	# Create new mesh
	_create_tile_mesh(pos)


## Update tile and its neighbors (for wall face visibility)
func _update_tile_and_neighbors(pos: Vector2i) -> void:
	_update_tile(pos)
	
	# Update neighbors as their wall faces may need to change
	for dir: Vector2i in MapData.DIRECTIONS:
		var neighbor_pos: Vector2i = pos + dir
		if map_data.is_valid_position(neighbor_pos):
			_update_tile(neighbor_pos)


## Get tile mesh at position
func get_tile_mesh(pos: Vector2i) -> MeshInstance3D:
	return tile_meshes.get(pos)
