class_name SelectionSystem
extends Node
## Handles tile selection via mouse input.
## Supports single tile hover/click and area selection.

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

## Currently selected tiles
var selected_tiles: Array[Vector2i] = []

## Mouse button used for selection
const SELECT_BUTTON := MOUSE_BUTTON_LEFT
const ACTION_BUTTON := MOUSE_BUTTON_RIGHT

## Collision mask for wall raycasts
const WALL_RAYCAST_MASK := 1


func _ready() -> void:
	GameEvents.map_loaded.connect(_on_map_loaded)


func _on_map_loaded(data: Resource) -> void:
	map_data = data as MapData


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
	var tile_pos := _get_selectable_tile_pos(mouse_pos)
	
	if tile_pos != hovered_tile:
		if hovered_tile != Vector2i(-1, -1):
			GameEvents.tile_unhovered.emit()
		
		hovered_tile = tile_pos
		
		if hovered_tile != Vector2i(-1, -1):
			GameEvents.tile_hovered.emit(hovered_tile)


## Convert screen position to tile position
func screen_to_tile(screen_pos: Vector2) -> Vector2i:
	if not camera_controller or not map_data:
		return Vector2i(-1, -1)
	
	var camera := camera_controller.get_camera()
	if not camera:
		return Vector2i(-1, -1)
	
	var ray_origin := camera.project_ray_origin(screen_pos)
	var ray_dir := camera.project_ray_normal(screen_pos)
	var ray_end := ray_origin + ray_dir * 1000.0

	# First try physics raycast against tile meshes (any face)
	var world := get_viewport().get_world_3d()
	if not world:
		return Vector2i(-1, -1)
	var space_state: PhysicsDirectSpaceState3D = world.direct_space_state
	var query := PhysicsRayQueryParameters3D.create(ray_origin, ray_end)
	query.collide_with_areas = false
	query.collide_with_bodies = true
	query.collision_mask = WALL_RAYCAST_MASK
	var hit: Dictionary = space_state.intersect_ray(query)
	if hit and hit.has("collider"):
		var collider: Object = hit["collider"]
		if collider and collider.has_meta("tile_pos"):
			return collider.get_meta("tile_pos")
		if collider and collider.get_parent() and collider.get_parent().has_meta("tile_pos"):
			return collider.get_parent().get_meta("tile_pos")
	
	# Intersect with ground plane (y = 0)
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


## Handle mouse button events
func _handle_mouse_button(event: InputEventMouseButton) -> void:
	if event.button_index == SELECT_BUTTON:
		if event.pressed:
			var tile_pos := _get_selectable_tile_pos(event.position)
			if tile_pos == Vector2i(-1, -1):
				clear_selection()
				return
			
			# Start selection (diggable walls only)
			is_selecting = true
			selection_start = tile_pos
			selection_end = tile_pos
		else:
			# End selection
			is_selecting = false
			var tile_pos := _get_selectable_tile_pos(event.position)
			if tile_pos == Vector2i(-1, -1):
				clear_selection()
				return
			
			selection_end = tile_pos
			_update_selection()
			if selected_tiles.size() > 0:
				GameEvents.tiles_selected.emit(selected_tiles)
	
	elif event.button_index == ACTION_BUTTON and event.pressed:
		# Right click - perform action on tile
		var tile_pos := screen_to_tile(event.position)
		if tile_pos != Vector2i(-1, -1):
			GameEvents.tile_clicked.emit(tile_pos, ACTION_BUTTON)


## Handle selection drag
func _handle_selection_drag(event: InputEventMouseMotion) -> void:
	var tile_pos := _get_selectable_tile_pos(event.position)
	if tile_pos != selection_end:
		selection_end = tile_pos
		_update_selection()


## Update selected tiles based on selection rectangle
func _update_selection() -> void:
	selected_tiles.clear()
	
	if selection_start == Vector2i(-1, -1):
		return
	
	# Handle single tile selection
	if selection_end == Vector2i(-1, -1):
		if map_data.is_valid_position(selection_start):
			var tile = map_data.get_tile(selection_start)
			if tile and _is_selectable_tile(tile["type"]):
				selected_tiles.append(selection_start)
		return
	
	# Calculate rectangle bounds
	var min_x := mini(selection_start.x, selection_end.x)
	var max_x := maxi(selection_start.x, selection_end.x)
	var min_y := mini(selection_start.y, selection_end.y)
	var max_y := maxi(selection_start.y, selection_end.y)
	
	# Clamp to map bounds
	min_x = maxi(0, min_x)
	max_x = mini(map_data.width - 1, max_x)
	min_y = maxi(0, min_y)
	max_y = mini(map_data.height - 1, max_y)
	
	# Add only selectable tiles (ROCK or WALL) in rectangle
	for y in range(min_y, max_y + 1):
		for x in range(min_x, max_x + 1):
			var pos := Vector2i(x, y)
			var tile = map_data.get_tile(pos)
			if tile and _is_selectable_tile(tile["type"]):
				selected_tiles.append(pos)


## Clear current selection
func clear_selection() -> void:
	selected_tiles.clear()
	selection_start = Vector2i(-1, -1)
	selection_end = Vector2i(-1, -1)
	GameEvents.selection_cleared.emit()


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


## Convert screen position to a selectable tile (diggable only)
func _get_selectable_tile_pos(screen_pos: Vector2) -> Vector2i:
	var tile_pos := screen_to_tile(screen_pos)
	if tile_pos == Vector2i(-1, -1):
		return tile_pos
	
	var tile = map_data.get_tile(tile_pos)
	if tile and _is_selectable_tile(tile["type"]):
		return tile_pos
	
	return Vector2i(-1, -1)
