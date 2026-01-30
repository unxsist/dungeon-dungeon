class_name CameraController
extends Node3D
## Camera controller with pan, zoom, and edge panning support.
## The camera is a child of this pivot node for easy angle management.

## Movement speed (units per second)
@export var move_speed: float = 30.0

## Zoom speed
@export var zoom_speed: float = 5.0

## Zoom smoothing (higher = snappier)
@export var zoom_smooth_speed: float = 8.0

## Minimum and maximum zoom distance
@export var zoom_min: float = 6.0
@export var zoom_max: float = 60.0

## Edge pan margin in pixels
@export var edge_pan_margin: int = 50

## Edge pan speed multiplier
@export var edge_pan_speed: float = 0.7

## Soft bound elasticity (0 = hard bounds, 1 = no bounds)
@export var soft_bound_strength: float = 0.1

## Extra padding around map bounds
@export var bounds_padding: float = 20.0

## Camera angle from horizontal (degrees)
@export var camera_angle: float = 60.0

## Camera tilt limits (degrees)
@export var camera_angle_min: float = 35.0
@export var camera_angle_max: float = 75.0

## Rotation speed for middle mouse drag
@export var rotate_speed: float = 0.15
@export var tilt_speed: float = 0.12

## Current zoom level (distance from pivot)
var current_zoom: float = 30.0
var target_zoom: float = 30.0

## Map bounds (set by MapSystem)
var map_bounds: AABB = AABB(Vector3.ZERO, Vector3(100, 10, 100))
var base_map_bounds: AABB = AABB(Vector3.ZERO, Vector3(100, 10, 100))

## Camera node reference
var camera: Camera3D

## Movement input vector
var _move_input := Vector2.ZERO

## Is middle mouse button held for dragging
var _is_dragging := false

## Last mouse position for drag calculation
var _last_mouse_pos := Vector2.ZERO

## Current yaw rotation (degrees)
var _yaw_degrees: float = 0.0


func _ready() -> void:
	camera = $Camera3D
	
	# Setup camera angle
	_setup_camera()
	
	# Connect to map loaded event to get bounds
	GameEvents.map_loaded.connect(_on_map_loaded)


## Setup camera angle and initial position
func _setup_camera() -> void:
	if camera:
		# Position camera based on angle and zoom
		target_zoom = current_zoom
		_update_camera_position()


## Update camera position based on zoom and angle
func _update_camera_position() -> void:
	if not camera:
		return
	
	# Calculate camera offset based on angle and zoom
	var angle_rad := deg_to_rad(camera_angle)
	var y_offset := current_zoom * sin(angle_rad)
	var z_offset := -current_zoom * cos(angle_rad)
	
	var offset := Vector3(0, y_offset, z_offset)
	offset = offset.rotated(Vector3.UP, deg_to_rad(_yaw_degrees))
	camera.position = offset
	camera.look_at(global_position, Vector3.UP)


func _process(delta: float) -> void:
	_update_zoom(delta)
	_handle_keyboard_input()
	_handle_edge_pan()
	_apply_movement(delta)
	_apply_soft_bounds(delta)


func _unhandled_input(event: InputEvent) -> void:
	# Mouse wheel zoom
	if event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		
		if mouse_event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom(-1)
		elif mouse_event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom(1)
		elif mouse_event.button_index == MOUSE_BUTTON_MIDDLE:
			_is_dragging = mouse_event.pressed
			_last_mouse_pos = mouse_event.position
	
	# Middle mouse drag
	if event is InputEventMouseMotion and _is_dragging:
		var motion := event as InputEventMouseMotion
		var drag_delta := motion.position - _last_mouse_pos
		_last_mouse_pos = motion.position
		# Rotate/tilt camera instead of panning
		_yaw_degrees -= drag_delta.x * rotate_speed
		camera_angle = clamp(camera_angle + drag_delta.y * tilt_speed, camera_angle_min, camera_angle_max)
		_update_camera_position()


## Handle keyboard movement input
func _handle_keyboard_input() -> void:
	_move_input = Vector2.ZERO
	
	# WASD
	if Input.is_action_pressed("ui_up") or Input.is_key_pressed(KEY_W):
		_move_input.y -= 1
	if Input.is_action_pressed("ui_down") or Input.is_key_pressed(KEY_S):
		_move_input.y += 1
	if Input.is_action_pressed("ui_left") or Input.is_key_pressed(KEY_A):
		_move_input.x -= 1
	if Input.is_action_pressed("ui_right") or Input.is_key_pressed(KEY_D):
		_move_input.x += 1
	
	_move_input = _move_input.normalized()


## Handle edge panning
func _handle_edge_pan() -> void:
	var viewport := get_viewport()
	if not viewport:
		return
	
	var mouse_pos := viewport.get_mouse_position()
	var viewport_size := viewport.get_visible_rect().size
	
	var edge_input := Vector2.ZERO
	
	# Check edges
	if mouse_pos.x < edge_pan_margin:
		edge_input.x = -1.0 * (1.0 - mouse_pos.x / edge_pan_margin)
	elif mouse_pos.x > viewport_size.x - edge_pan_margin:
		edge_input.x = 1.0 * (1.0 - (viewport_size.x - mouse_pos.x) / edge_pan_margin)
	
	if mouse_pos.y < edge_pan_margin:
		edge_input.y = -1.0 * (1.0 - mouse_pos.y / edge_pan_margin)
	elif mouse_pos.y > viewport_size.y - edge_pan_margin:
		edge_input.y = 1.0 * (1.0 - (viewport_size.y - mouse_pos.y) / edge_pan_margin)
	
	# Add edge pan to movement (with reduced speed)
	if edge_input.length() > 0:
		_move_input += edge_input * edge_pan_speed


## Apply movement
func _apply_movement(delta: float) -> void:
	if _move_input.length() > 0:
		# Scale speed by zoom level (faster when zoomed out)
		# Use fixed reference of 15.0 for consistent feel regardless of zoom_min setting
		var speed_scale := current_zoom / 15.0
		# Move relative to camera POV (yaw)
		var input_vec := Vector3(-_move_input.x, 0, -_move_input.y)
		var yaw_basis := Basis(Vector3.UP, deg_to_rad(_yaw_degrees))
		var movement := yaw_basis * input_vec * move_speed * speed_scale * delta
		position += movement
		
		GameEvents.camera_moved.emit(position)


## Apply soft bounds
func _apply_soft_bounds(delta: float) -> void:
	var target_pos := position
	var bounds_min := map_bounds.position
	var bounds_max := map_bounds.position + map_bounds.size
	
	# Calculate overshoot
	var overshoot := Vector3.ZERO
	
	if position.x < bounds_min.x:
		overshoot.x = bounds_min.x - position.x
	elif position.x > bounds_max.x:
		overshoot.x = bounds_max.x - position.x
	
	if position.z < bounds_min.z:
		overshoot.z = bounds_min.z - position.z
	elif position.z > bounds_max.z:
		overshoot.z = bounds_max.z - position.z
	
	# Apply elastic return
	if overshoot.length() > 0:
		var return_strength := 1.0 - soft_bound_strength
		position += overshoot * return_strength * delta * 5.0


## Handle zoom
func _zoom(direction: int) -> void:
	target_zoom += direction * zoom_speed
	target_zoom = clamp(target_zoom, zoom_min, zoom_max)
	GameEvents.camera_zoomed.emit(target_zoom)


## Smoothly update zoom level
func _update_zoom(delta: float) -> void:
	if is_equal_approx(current_zoom, target_zoom):
		return
	
	var t := 1.0 - exp(-zoom_smooth_speed * delta)
	current_zoom = lerp(current_zoom, target_zoom, t)
	_update_camera_position()
	_update_map_bounds()


## Handle map loaded - update bounds
func _on_map_loaded(map_data: Resource) -> void:
	var data := map_data as MapData
	if data:
		base_map_bounds = data.get_world_bounds()
		_update_map_bounds()
		
		# Center camera on map
		var center := map_bounds.position + map_bounds.size * 0.5
		position = Vector3(center.x, 0, center.z)
		_update_camera_position()


## Update map bounds with padding and zoom allowance
func _update_map_bounds() -> void:
	var zoom_padding := current_zoom * 0.6
	var pad := Vector3(bounds_padding + zoom_padding, 0.0, bounds_padding + zoom_padding)
	map_bounds = AABB(base_map_bounds.position - pad, base_map_bounds.size + pad * 2.0)


## Set camera position directly
func set_camera_position(pos: Vector3) -> void:
	position = Vector3(pos.x, 0, pos.z)


## Get the camera node
func get_camera() -> Camera3D:
	return camera


## Project screen position to world position on ground plane
func screen_to_world(screen_pos: Vector2) -> Vector3:
	if not camera:
		return Vector3.ZERO
	
	var ray_origin := camera.project_ray_origin(screen_pos)
	var ray_dir := camera.project_ray_normal(screen_pos)
	
	# Intersect with ground plane (y = 0)
	var plane := Plane(Vector3.UP, 0)
	var hit = plane.intersects_ray(ray_origin, ray_dir)
	
	if hit:
		return hit
	return Vector3.ZERO
