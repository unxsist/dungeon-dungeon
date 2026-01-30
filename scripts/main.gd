extends Node
## Main scene controller - initializes the game and loads the map.

## Path to the default map to load
@export var default_map_path: String = "res://maps/test_map.json"

## Reference to the GameWorld scene
@onready var game_world: Node3D = $GameWorld

## Reference to the MapSystem
@onready var map_system: MapSystem = $GameWorld/Systems/MapSystem

## Reference to the FogSystem
@onready var fog_system: FogSystem = $GameWorld/Systems/FogSystem

## Reference to the PathfindingSystem
@onready var pathfinding_system: PathfindingSystem = $GameWorld/Systems/PathfindingSystem

## Reference to the TaskSystem
@onready var task_system: TaskSystem = $GameWorld/Systems/TaskSystem

## Reference to the CreatureSystem
@onready var creature_system: CreatureSystem = $GameWorld/Systems/CreatureSystem

## Reference to the CreatureRenderer
@onready var creature_renderer: CreatureRenderer = $GameWorld/CreatureRenderer

## Reference to the Camera
@onready var camera: Camera3D = $GameWorld/CameraPivot/Camera3D

## Reference to the CreatureInfoPanel
@onready var creature_info_panel: CreatureInfoPanel = $UI/CreatureInfoPanel

## Reference to RoomSystem
@onready var room_system: RoomSystem = $GameWorld/Systems/RoomSystem

## Reference to ActionHandler
@onready var action_handler: ActionHandler = $GameWorld/Systems/ActionHandler

## Reference to RoomPanel
@onready var room_panel: RoomPanel = $UI/RoomPanel


func _ready() -> void:
	# Print controls help
	_print_controls()
	
	# Wire up creature systems
	_setup_creature_systems()
	
	# Wire up room systems
	_setup_room_systems()
	
	# Load the default map
	if default_map_path and FileAccess.file_exists(default_map_path):
		print("Loading map: ", default_map_path)
		map_system.load_map(default_map_path)
	else:
		# Generate a test map if no map file exists
		print("No map file found, generating test map...")
		map_system.generate_test_map(20, 20)


## Wire up creature-related systems
func _setup_creature_systems() -> void:
	# TaskSystem needs pathfinding reference
	task_system.set_pathfinding(pathfinding_system)
	
	# CreatureSystem needs references to pathfinding and task system
	creature_system.set_references(pathfinding_system, task_system)
	
	# CreatureInfoPanel needs references for click detection
	if creature_info_panel:
		creature_info_panel.set_references(creature_renderer, camera)


## Wire up room-related systems
func _setup_room_systems() -> void:
	# RoomPanel needs RoomSystem reference
	if room_panel and room_system:
		room_panel.set_room_system(room_system)
	
	# ActionHandler needs RoomSystem reference
	if action_handler and room_system:
		action_handler.set_room_system(room_system)


func _print_controls() -> void:
	print("")
	print("=== DUNGEON DUNGEON CONTROLS ===")
	print("Camera: WASD/Arrow keys to pan, Mouse wheel to zoom")
	print("        Middle mouse drag to pan, Edge pan enabled")
	print("")
	print("Selection: Left click to select tile")
	print("           Left click + drag for area selection")
	print("")
	print("Actions: Right click to perform action on tile")
	print("         1 = Dig mode (dig out walls)")
	print("         2 = Claim mode (claim floor tiles)")
	print("         R = Toggle room building panel")
	print("         Esc = Cancel selection/placement")
	print("")
	print("Save/Load: F5 = Quick save, F9 = Quick load")
	print("Debug: F3 = Toggle fog of war")
	print("================================")
	print("")


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		var key_event := event as InputEventKey
		
		# Quick save with F5
		if key_event.keycode == KEY_F5:
			_quick_save()
		
		# Quick load with F9
		elif key_event.keycode == KEY_F9:
			_quick_load()
		
		# Toggle fog of war with F3
		elif key_event.keycode == KEY_F3:
			_toggle_fog()


func _quick_save() -> void:
	var save_path := "user://saves/quicksave.json"
	if map_system.save_map(save_path):
		print("Game saved to: ", save_path)
	else:
		print("Failed to save game!")


func _quick_load() -> void:
	var save_path := "user://saves/quicksave.json"
	if FileAccess.file_exists(save_path):
		print("Loading save: ", save_path)
		map_system.load_save(save_path)
		print("Game loaded!")
	else:
		print("No save file found at: ", save_path)


func _toggle_fog() -> void:
	if fog_system:
		fog_system.fog_enabled = not fog_system.fog_enabled
		print("Fog of war: ", "ON" if fog_system.fog_enabled else "OFF")
