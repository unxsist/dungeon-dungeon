class_name CursorLight
extends Node3D
## Manages a dynamic light that follows the cursor position.
## Creates atmospheric lighting in the dark dungeon environment.
## Light floats at a fixed height above the map for even illumination.

## Light configuration
@export var light_energy: float = 1.8
@export var light_range: float = 18.0  # Larger range since light is higher up
@export var light_color: Color = Color(1.0, 0.85, 0.6)  # Warm torch-like color
@export var light_height: float = 10.0  # Fixed height above the map (Y=0 plane)

## Movement configuration
@export var follow_speed: float = 15.0  # How fast the light follows the cursor

## Internal state
var omni_light: OmniLight3D
var target_position: Vector3 = Vector3.ZERO
var is_active: bool = false


func _ready() -> void:
	_create_light()
	_connect_signals()


func _create_light() -> void:
	omni_light = OmniLight3D.new()
	omni_light.light_color = light_color
	omni_light.light_energy = light_energy
	omni_light.omni_range = light_range
	omni_light.omni_attenuation = 0.8  # Gentler falloff for smoother lighting
	omni_light.shadow_enabled = false  # No shadows for clean cursor light
	omni_light.light_bake_mode = Light3D.BAKE_DISABLED
	add_child(omni_light)


func _connect_signals() -> void:
	GameEvents.cursor_world_position_changed.connect(_on_cursor_world_position_changed)


func _on_cursor_world_position_changed(world_pos: Vector3, is_valid: bool) -> void:
	if not is_valid:
		# Cursor left the map - keep light at last position
		return
	
	# Position light at fixed height, only follow X/Z from cursor
	# This creates even illumination regardless of floor/wall height
	target_position = Vector3(world_pos.x, light_height, world_pos.z)
	
	# If this is the first activation, snap to position immediately
	if not is_active:
		omni_light.global_position = target_position
		is_active = true


func _process(delta: float) -> void:
	if not omni_light or not is_active:
		return
	
	# Smoothly interpolate position to follow cursor
	omni_light.global_position = omni_light.global_position.lerp(
		target_position,
		1.0 - exp(-follow_speed * delta)
	)


## Update light color at runtime
func set_light_color(color: Color) -> void:
	light_color = color
	if omni_light:
		omni_light.light_color = color


## Update light energy at runtime
func set_light_energy(energy: float) -> void:
	light_energy = energy
	if omni_light:
		omni_light.light_energy = energy


## Update light range at runtime
func set_light_range(range_value: float) -> void:
	light_range = range_value
	if omni_light:
		omni_light.omni_range = range_value
