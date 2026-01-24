class_name SelectionSystem
extends Node
## Handles tile selection via mouse input.
## Uses geometric ray-AABB intersection for reliable tile picking.
## Supports single tile toggle and additive area selection.

## Reference to the camera controller
@export var camera_controller: CameraController

## Reference to the map data (set via signal)
var map_data: MapData = null

## Currently hovered tile position (-1, -1 if none)
var hovered_tile: Vector2i = Vector2i(-1, -1)

## Selection state
var is_selecting: bool = false
var selection_start: Vector2i = Vector2i(-1, -1)
var selection_end: Vector2i = Vector2i(-1, -1)

## Currently selected tiles (persistent across selections)
var selected_tiles: Array[Vector2i] = []

## Tiles being added in current drag operation
var pending_tiles: Array[Vector2i] = []

## Whether current drag started on a selected tile (for deselection)
var is_deselecting: bool = false

## Mouse button used for selection
const SELECT_BUTTON := MOUSE_BUTTON_LEFT
const ACTION_BUTTON := MOUSE_BUTTON_RIGHT

## Wall geometry constants (must match TileRenderer)
const WALL_HEIGHT := 3.0
const HEIGHT_VARIATION_AMOUNT := 0.1


func _ready() -> void:
	GameEvents.map_loaded.connect(_on_map_loaded)
	GameEvents.tile_changed.connect(_on_tile_changed)


func _on_map_loaded(data: Resource) -> void:
	map_data = data as MapData
	# Clear selection when map changes
	selected_tiles.clear()
	pending_tiles.clear()


## Handle tile type change - remove from selection if no longer diggable
func _on_tile_changed(pos: Vector2i, _old_type: int, new_type: int) -> void:
	# Check if the tile is still diggable
	if not _is_selectable_tile(new_type as TileTypes.Type):
		# Remove from selection if present
		var idx := selected_tiles.find(pos)
		if idx >= 0:
			selected_tiles.remove_at(idx)
			# Notify about updated selection
			GameEvents.tiles_selected.emit(selected_tiles)


func _process(_delta: float) -> void:
	if not map_data or not camera_controller:
		return
	
	_update_hover()


func _unhandled_input(event: InputEvent) -> void:
	if not map_data or not camera_controller:
		return
	
	if event is InputEventMouseButton:
		_handle_mouse_button(event as InputEventMouseButton)
	elif event is InputEventMouseMotion and is_selecting:
		_handle_selection_drag(event as InputEventMouseMotion)


## Update hovered tile based on mouse position
func _update_hover() -> void:
	var mouse_pos := get_viewport().get_mouse_position()
	var tile_pos := screen_to_tile(mouse_pos)
	
	# Only show hover for diggable tiles
	if tile_pos != Vector2i(-1, -1):
		var tile = map_data.get_tile(tile_pos)
		if not tile or not _is_selectable_tile(tile["type"]):
			tile_pos = Vector2i(-1, -1)
	
	if tile_pos != hovered_tile:
		if hovered_tile != Vector2i(-1, -1):
			GameEvents.tile_unhovered.emit()
		
		hovered_tile = tile_pos
		
		if hovered_tile != Vector2i(-1, -1):
			GameEvents.tile_hovered.emit(hovered_tile)


## Convert screen position to tile position using geometric ray-AABB intersection.
## This is more reliable than physics raycasts as it doesn't depend on collision timing.
func screen_to_tile(screen_pos: Vector2) -> Vector2i:
	if not camera_controller or not map_data:
		return Vector2i(-1, -1)
	
	var camera := camera_controller.get_camera()
	if not camera:
		return Vector2i(-1, -1)
	
	var ray_origin := camera.project_ray_origin(screen_pos)
	var ray_dir := camera.project_ray_normal(screen_pos)
	
	var closest_dist := INF
	var closest_tile := Vector2i(-1, -1)
	
	# Get tiles to test (optimized: only check tiles near camera view)
	var tiles_to_test := _get_tiles_in_view(ray_origin)
	
	# Test wall tiles first (ROCK and WALL - non-walkable)
	for pos in tiles_to_test:
		var tile = map_data.get_tile(pos)
		if tile and not TileTypes.is_walkable(tile["type"]):
			var aabb := _get_tile_aabb(pos, false)
			var dist := _ray_intersects_aabb(ray_origin, ray_dir, aabb)
			if dist > 0.0 and dist < closest_dist:
				closest_dist = dist
				closest_tile = pos
	
	# If we hit a wall, return it
	if closest_tile != Vector2i(-1, -1):
		return closest_tile
	
	# Fall back to ground plane intersection for floor tiles
	var plane := Plane(Vector3.UP, 0)
	var plane_hit: Variant = plane.intersects_ray(ray_origin, ray_dir)
	
	if plane_hit is Vector3:
		var hit_pos := plane_hit as Vector3
		var tile_pos := Vector2i(
			int(floor(hit_pos.x / map_data.tile_size)),
			int(floor(hit_pos.z / map_data.tile_size))
		)
		
		if map_data.is_valid_position(tile_pos):
			return tile_pos
	
	return Vector2i(-1, -1)


## Get tiles that are potentially visible from the camera position.
## This optimization prevents testing all tiles every frame.
func _get_tiles_in_view(camera_pos: Vector3) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	
	# Calculate a reasonable check radius based on camera height/zoom
	var check_radius := camera_controller.current_zoom * 1.5
	var center_tile := map_data.world_to_tile(camera_controller.global_position)
	
	# Calculate tile range to check
	var tile_radius := int(ceil(check_radius / map_data.tile_size)) + 2
	var min_x := maxi(0, center_tile.x - tile_radius)
	var max_x := mini(map_data.width - 1, center_tile.x + tile_radius)
	var min_y := maxi(0, center_tile.y - tile_radius)
	var max_y := mini(map_data.height - 1, center_tile.y + tile_radius)
	
	for y in range(min_y, max_y + 1):
		for x in range(min_x, max_x + 1):
			result.append(Vector2i(x, y))
	
	return result


## Compute the world-space AABB for a tile based on its type.
func _get_tile_aabb(pos: Vector2i, is_floor: bool) -> AABB:
	var world_pos := Vector3(pos.x * map_data.tile_size, 0.0, pos.y * map_data.tile_size)
	var size := map_data.tile_size
	
	if is_floor:
		# Floor: thin box at ground level
		return AABB(world_pos, Vector3(size, 0.1, size))
	else:
		# Wall: raised box with height variation accounted for
		var height := WALL_HEIGHT + HEIGHT_VARIATION_AMOUNT * size
		return AABB(world_pos, Vector3(size, height, size))


## Ray-AABB intersection test using the slab method.
## Returns the distance to intersection, or -1.0 if no hit.
func _ray_intersects_aabb(ray_origin: Vector3, ray_dir: Vector3, aabb: AABB) -> float:
	# Handle zero direction components to avoid division by zero
	var inv_dir := Vector3.ZERO
	inv_dir.x = 1.0 / ray_dir.x if abs(ray_dir.x) > 0.0001 else INF
	inv_dir.y = 1.0 / ray_dir.y if abs(ray_dir.y) > 0.0001 else INF
	inv_dir.z = 1.0 / ray_dir.z if abs(ray_dir.z) > 0.0001 else INF
	
	var aabb_min := aabb.position
	var aabb_max := aabb.position + aabb.size
	
	# Calculate intersection distances for each axis
	var t1 := (aabb_min.x - ray_origin.x) * inv_dir.x
	var t2 := (aabb_max.x - ray_origin.x) * inv_dir.x
	var t3 := (aabb_min.y - ray_origin.y) * inv_dir.y
	var t4 := (aabb_max.y - ray_origin.y) * inv_dir.y
	var t5 := (aabb_min.z - ray_origin.z) * inv_dir.z
	var t6 := (aabb_max.z - ray_origin.z) * inv_dir.z
	
	# Find the largest minimum and smallest maximum
	var tmin := maxf(maxf(minf(t1, t2), minf(t3, t4)), minf(t5, t6))
	var tmax := minf(minf(maxf(t1, t2), maxf(t3, t4)), maxf(t5, t6))
	
	# If tmax < 0, the AABB is behind the ray
	if tmax < 0.0:
		return -1.0
	
	# If tmin > tmax, the ray doesn't intersect
	if tmin > tmax:
		return -1.0
	
	# Return the entry distance (tmin if positive, else tmax)
	return tmin if tmin >= 0.0 else tmax


## Handle mouse button events
func _handle_mouse_button(event: InputEventMouseButton) -> void:
	if event.button_index == SELECT_BUTTON:
		if event.pressed:
			# Get the tile under cursor
			var tile_pos := screen_to_tile(event.position)
			
			# Check if clicking on a selectable tile
			var is_selectable := false
			if tile_pos != Vector2i(-1, -1):
				var tile = map_data.get_tile(tile_pos)
				is_selectable = tile and _is_selectable_tile(tile["type"])
			
			# Determine if we're deselecting (clicking on already selected tile)
			is_deselecting = is_selectable and tile_pos in selected_tiles
			
			# Start selection drag
			is_selecting = true
			selection_start = tile_pos
			selection_end = tile_pos
			pending_tiles.clear()
			
			_update_pending_selection()
		else:
			# End selection - apply pending changes
			is_selecting = false
			_apply_pending_selection()
			pending_tiles.clear()
			
			# Emit final selection state
			GameEvents.tiles_selected.emit(selected_tiles)
	
	elif event.button_index == ACTION_BUTTON and event.pressed:
		# Right click - perform action on tile
		var tile_pos := screen_to_tile(event.position)
		if tile_pos != Vector2i(-1, -1):
			GameEvents.tile_clicked.emit(tile_pos, ACTION_BUTTON)


## Handle selection drag
func _handle_selection_drag(event: InputEventMouseMotion) -> void:
	var tile_pos := screen_to_tile(event.position)
	if tile_pos != selection_end:
		selection_end = tile_pos
		_update_pending_selection()


## Update pending tiles based on selection rectangle.
## These will be added to or removed from selection on mouse release.
func _update_pending_selection() -> void:
	pending_tiles.clear()
	
	# Need at least a start position
	if selection_start == Vector2i(-1, -1):
		return
	
	# If end is invalid, use start as single selection
	var effective_end := selection_end
	if effective_end == Vector2i(-1, -1):
		effective_end = selection_start
	
	# Calculate rectangle bounds
	var min_x := mini(selection_start.x, effective_end.x)
	var max_x := maxi(selection_start.x, effective_end.x)
	var min_y := mini(selection_start.y, effective_end.y)
	var max_y := maxi(selection_start.y, effective_end.y)
	
	# Clamp to map bounds
	min_x = maxi(0, min_x)
	max_x = mini(map_data.width - 1, max_x)
	min_y = maxi(0, min_y)
	max_y = mini(map_data.height - 1, max_y)
	
	# Collect diggable tiles in rectangle
	for y in range(min_y, max_y + 1):
		for x in range(min_x, max_x + 1):
			var pos := Vector2i(x, y)
			var tile = map_data.get_tile(pos)
			if tile and _is_selectable_tile(tile["type"]):
				pending_tiles.append(pos)
	
	# Emit preview of what selection will look like
	var preview := _get_selection_preview()
	GameEvents.tiles_selected.emit(preview)


## Get a preview of what the selection will look like after applying pending changes.
func _get_selection_preview() -> Array[Vector2i]:
	var preview: Array[Vector2i] = []
	
	if is_deselecting:
		# Preview: current selection minus pending tiles
		for pos in selected_tiles:
			if pos not in pending_tiles:
				preview.append(pos)
	else:
		# Preview: current selection plus pending tiles
		for pos in selected_tiles:
			preview.append(pos)
		for pos in pending_tiles:
			if pos not in selected_tiles:
				preview.append(pos)
	
	return preview


## Apply pending selection changes to the actual selection.
func _apply_pending_selection() -> void:
	if is_deselecting:
		# Remove pending tiles from selection
		for pos in pending_tiles:
			var idx := selected_tiles.find(pos)
			if idx >= 0:
				selected_tiles.remove_at(idx)
	else:
		# Add pending tiles to selection
		for pos in pending_tiles:
			if pos not in selected_tiles:
				selected_tiles.append(pos)


## Clear current selection
func clear_selection() -> void:
	selected_tiles.clear()
	pending_tiles.clear()
	selection_start = Vector2i(-1, -1)
	selection_end = Vector2i(-1, -1)
	GameEvents.selection_cleared.emit()


## Toggle selection state of a single tile
func toggle_tile_selection(pos: Vector2i) -> void:
	if pos in selected_tiles:
		selected_tiles.erase(pos)
	else:
		var tile = map_data.get_tile(pos)
		if tile and _is_selectable_tile(tile["type"]):
			selected_tiles.append(pos)
	
	GameEvents.tiles_selected.emit(selected_tiles)


## Get currently hovered tile
func get_hovered_tile() -> Vector2i:
	return hovered_tile


## Get selected tiles
func get_selected_tiles() -> Array[Vector2i]:
	return selected_tiles


## Check if a tile is currently selected
func is_tile_selected(pos: Vector2i) -> bool:
	return pos in selected_tiles


## Check if currently in selection mode
func is_selecting_area() -> bool:
	return is_selecting


## Check if a tile type is selectable (only diggable walls)
func _is_selectable_tile(tile_type: TileTypes.Type) -> bool:
	return TileTypes.is_diggable(tile_type)


## Get all diggable tiles on the map (for debug view)
func get_all_diggable_tiles() -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	
	if not map_data:
		return result
	
	for pos in map_data.tiles.keys():
		var tile = map_data.get_tile(pos)
		if tile and _is_selectable_tile(tile["type"]):
			result.append(pos)
	
	return result
