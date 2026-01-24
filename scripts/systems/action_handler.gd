class_name ActionHandler
extends Node
## Handles player actions on tiles (digging, claiming, etc.)

## Current action mode
enum ActionMode { NONE, DIG, CLAIM }
var current_mode: ActionMode = ActionMode.DIG

## Player faction ID
@export var player_faction_id: int = 0

## Reference to SelectionSystem (set in _ready)
var selection_system: SelectionSystem

## Reference to MapData
var map_data: MapData = null


func _ready() -> void:
	# Connect to events
	GameEvents.map_loaded.connect(_on_map_loaded)
	GameEvents.tile_clicked.connect(_on_tile_clicked)
	GameEvents.tiles_selected.connect(_on_tiles_selected)
	
	# Find SelectionSystem sibling
	await get_tree().process_frame
	selection_system = get_parent().get_node_or_null("SelectionSystem") as SelectionSystem


func _on_map_loaded(data: Resource) -> void:
	map_data = data as MapData


func _unhandled_input(event: InputEvent) -> void:
	# Number keys to switch modes
	if event is InputEventKey and event.pressed:
		var key_event := event as InputEventKey
		match key_event.keycode:
			KEY_1:
				set_action_mode(ActionMode.DIG)
			KEY_2:
				set_action_mode(ActionMode.CLAIM)
			KEY_ESCAPE:
				set_action_mode(ActionMode.NONE)
				if selection_system:
					selection_system.clear_selection()


## Set the current action mode
func set_action_mode(mode: ActionMode) -> void:
	current_mode = mode
	print("Action mode: ", ActionMode.keys()[mode])


## Handle tile click (right-click for action)
func _on_tile_clicked(pos: Vector2i, button: int) -> void:
	if button == MOUSE_BUTTON_RIGHT:
		_perform_action_on_tile(pos)


## Handle area selection (perform action on all selected tiles)
func _on_tiles_selected(positions: Array[Vector2i]) -> void:
	# Don't auto-perform on selection, wait for right-click
	pass


## Perform current action on a single tile
func _perform_action_on_tile(pos: Vector2i) -> void:
	if not map_data:
		return
	
	match current_mode:
		ActionMode.DIG:
			_try_dig(pos)
		ActionMode.CLAIM:
			_try_claim(pos)


## Perform action on multiple tiles
func perform_action_on_selection() -> void:
	if not selection_system:
		return
	
	var selected: Array[Vector2i] = selection_system.get_selected_tiles()
	for pos in selected:
		_perform_action_on_tile(pos)


## Try to dig a tile
func _try_dig(pos: Vector2i) -> void:
	var tile = map_data.get_tile(pos)
	if not tile:
		return
	
	var tile_type: TileTypes.Type = tile["type"]
	if TileTypes.is_diggable(tile_type):
		GameEvents.dig_requested.emit(pos)
		print("Digging tile at: ", pos)
	else:
		print("Cannot dig tile at: ", pos, " (type: ", TileTypes.to_string_name(tile_type), ")")


## Try to claim a tile
func _try_claim(pos: Vector2i) -> void:
	var tile = map_data.get_tile(pos)
	if not tile:
		return
	
	var tile_type: TileTypes.Type = tile["type"]
	if TileTypes.is_claimable(tile_type):
		# Check adjacency
		if map_data.is_adjacent_to_faction(pos, player_faction_id):
			GameEvents.claim_requested.emit(pos, player_faction_id)
			print("Claiming tile at: ", pos)
		else:
			print("Cannot claim tile at: ", pos, " (not adjacent to territory)")
	else:
		print("Cannot claim tile at: ", pos, " (type: ", TileTypes.to_string_name(tile_type), ")")


## Get current action mode name
func get_mode_name() -> String:
	return ActionMode.keys()[current_mode]
