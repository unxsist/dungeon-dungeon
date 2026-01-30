class_name ActionHandler
extends Node
## Handles player actions on tiles (digging, claiming, building rooms, etc.)

## Current action mode
enum ActionMode { NONE, DIG, CLAIM, BUILD_ROOM, SELL_ROOM }
var current_mode: ActionMode = ActionMode.DIG

## Player faction ID
@export var player_faction_id: int = 0

## Reference to SelectionSystem (set in _ready)
var selection_system: SelectionSystem

## Reference to RoomSystem (set externally or found in tree)
var room_system: RoomSystem

## Reference to MapData
var map_data: MapData = null

## Track tiles we've marked for digging (to detect unmarking on deselection)
var _marked_tiles: Array[Vector2i] = []

## Room building state
var _room_drag_start: Vector2i = Vector2i(-1, -1)
var _is_room_dragging: bool = false


func _ready() -> void:
	# Connect to events
	GameEvents.map_loaded.connect(_on_map_loaded)
	GameEvents.tile_clicked.connect(_on_tile_clicked)
	GameEvents.tiles_selected.connect(_on_tiles_selected)
	GameEvents.room_placement_started.connect(_on_room_placement_started)
	GameEvents.room_placement_cancelled.connect(_on_room_placement_cancelled)
	
	# Find SelectionSystem sibling
	await get_tree().process_frame
	selection_system = get_parent().get_node_or_null("SelectionSystem") as SelectionSystem
	room_system = get_parent().get_node_or_null("RoomSystem") as RoomSystem


func _on_map_loaded(data: Resource) -> void:
	map_data = data as MapData


func _unhandled_input(event: InputEvent) -> void:
	# Handle room building mode input
	if current_mode == ActionMode.BUILD_ROOM:
		_handle_room_building_input(event)
		return
	
	# Handle sell room mode input
	if current_mode == ActionMode.SELL_ROOM:
		_handle_sell_room_input(event)
		return
	
	# Number keys to switch modes
	if event is InputEventKey and event.pressed:
		var key_event := event as InputEventKey
		match key_event.keycode:
			KEY_1:
				set_action_mode(ActionMode.DIG)
			KEY_2:
				set_action_mode(ActionMode.CLAIM)
			KEY_3:
				set_action_mode(ActionMode.SELL_ROOM)
			KEY_ESCAPE:
				set_action_mode(ActionMode.NONE)
				if selection_system:
					selection_system.clear_selection()


## Set the current action mode
func set_action_mode(mode: ActionMode) -> void:
	current_mode = mode
	print("Action mode: ", ActionMode.keys()[mode])


## Handle tile click (right-click to deselect/unmark)
func _on_tile_clicked(pos: Vector2i, button: int) -> void:
	if button == MOUSE_BUTTON_RIGHT:
		# Right-click unmarks a tile if it's marked
		if current_mode == ActionMode.DIG and map_data:
			if map_data.is_marked_for_digging(pos):
				map_data.unmark_for_digging(pos)
				GameEvents.dig_unmarked.emit(pos)


## Handle area selection - automatically mark/perform action on selected tiles
func _on_tiles_selected(positions: Array[Vector2i]) -> void:
	if not map_data:
		return
	
	# In DIG mode, selecting walls marks them for digging
	if current_mode == ActionMode.DIG:
		# Find tiles that were marked but are now deselected (unmark them)
		var tiles_to_unmark: Array[Vector2i] = []
		for pos in _marked_tiles:
			if pos not in positions:
				tiles_to_unmark.append(pos)
		
		# Unmark deselected tiles
		for pos in tiles_to_unmark:
			if map_data.is_marked_for_digging(pos):
				map_data.unmark_for_digging(pos)
				GameEvents.dig_unmarked.emit(pos)
		
		# Mark newly selected tiles
		for pos in positions:
			var tile = map_data.get_tile(pos)
			if tile and TileTypes.is_diggable(tile["type"]):
				# Only mark if not already marked
				if not map_data.is_marked_for_digging(pos):
					if map_data.mark_for_digging(pos, player_faction_id):
						GameEvents.dig_marked.emit(pos, player_faction_id)
		
		# Update tracked marked tiles to match current selection
		_marked_tiles.clear()
		for pos in positions:
			var tile = map_data.get_tile(pos)
			if tile and TileTypes.is_diggable(tile["type"]) and map_data.is_marked_for_digging(pos):
				_marked_tiles.append(pos)


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


## Try to mark a tile for digging (or unmark if already marked)
func _try_dig(pos: Vector2i) -> void:
	var tile = map_data.get_tile(pos)
	if not tile:
		return
	
	var tile_type: TileTypes.Type = tile["type"]
	if not TileTypes.is_diggable(tile_type):
		return
	
	# Toggle marking - if already marked, unmark it
	if map_data.is_marked_for_digging(pos):
		map_data.unmark_for_digging(pos)
		GameEvents.dig_unmarked.emit(pos)
	else:
		# Mark for digging by player's faction
		if map_data.mark_for_digging(pos, player_faction_id):
			GameEvents.dig_marked.emit(pos, player_faction_id)


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


## Handle room placement started event
func _on_room_placement_started(_room_type: int) -> void:
	set_action_mode(ActionMode.BUILD_ROOM)


## Handle room placement cancelled event
func _on_room_placement_cancelled() -> void:
	_room_drag_start = Vector2i(-1, -1)
	_is_room_dragging = false
	set_action_mode(ActionMode.DIG)


## Handle input during room building mode
func _handle_room_building_input(event: InputEvent) -> void:
	if not room_system or not map_data:
		return
	
	# Cancel with Escape or right-click
	if event is InputEventKey:
		var key_event := event as InputEventKey
		if key_event.pressed and key_event.keycode == KEY_ESCAPE:
			room_system.cancel_placement()
			get_viewport().set_input_as_handled()
			return
	
	if event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		
		# Right-click cancels
		if mouse_event.button_index == MOUSE_BUTTON_RIGHT and mouse_event.pressed:
			room_system.cancel_placement()
			get_viewport().set_input_as_handled()
			return
		
		# Left-click starts/confirms drag
		if mouse_event.button_index == MOUSE_BUTTON_LEFT:
			var current_tile := _get_tile_at_mouse()
			
			if mouse_event.pressed:
				# Start drag
				_room_drag_start = current_tile
				_is_room_dragging = true
				if current_tile != Vector2i(-1, -1):
					room_system.update_placement_preview(current_tile, current_tile)
				get_viewport().set_input_as_handled()
			else:
				# End drag - confirm placement
				if _is_room_dragging and _room_drag_start != Vector2i(-1, -1):
					var end_tile := current_tile if current_tile != Vector2i(-1, -1) else _room_drag_start
					room_system.update_placement_preview(_room_drag_start, end_tile)
					room_system.confirm_placement()
				_is_room_dragging = false
				_room_drag_start = Vector2i(-1, -1)
				get_viewport().set_input_as_handled()
	
	# Update preview during drag
	if event is InputEventMouseMotion and _is_room_dragging:
		var current_tile := _get_tile_at_mouse()
		if current_tile != Vector2i(-1, -1) and _room_drag_start != Vector2i(-1, -1):
			room_system.update_placement_preview(_room_drag_start, current_tile)


## Get tile position at current mouse position
func _get_tile_at_mouse() -> Vector2i:
	if not selection_system:
		return Vector2i(-1, -1)
	
	# Use selection system's current hover position
	var hover_pos := selection_system.get_current_hover_tile()
	if hover_pos != Vector2i(-1, -1):
		return hover_pos
	
	return Vector2i(-1, -1)


## Set room system reference
func set_room_system(system: RoomSystem) -> void:
	room_system = system


## Handle input during sell room mode
func _handle_sell_room_input(event: InputEvent) -> void:
	if not room_system or not map_data:
		return
	
	# Escape exits sell mode
	if event is InputEventKey:
		var key_event := event as InputEventKey
		if key_event.pressed and key_event.keycode == KEY_ESCAPE:
			set_action_mode(ActionMode.DIG)
			get_viewport().set_input_as_handled()
			return
	
	# Left-click sells room at cursor
	if event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		
		if mouse_event.button_index == MOUSE_BUTTON_LEFT and mouse_event.pressed:
			var current_tile := _get_tile_at_mouse()
			if current_tile != Vector2i(-1, -1):
				# Check if there's a room at this position that belongs to player
				var room := map_data.get_room_at(current_tile)
				if room and room.faction_id == player_faction_id:
					room_system.sell_room_at(current_tile)
			get_viewport().set_input_as_handled()
		
		# Right-click exits sell mode
		if mouse_event.button_index == MOUSE_BUTTON_RIGHT and mouse_event.pressed:
			set_action_mode(ActionMode.DIG)
			get_viewport().set_input_as_handled()
