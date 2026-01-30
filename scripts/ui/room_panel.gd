class_name RoomPanel
extends PanelContainer
## UI panel for selecting room types to build.
## Shown/hidden with 'R' key.

## Reference to room system
var room_system: RoomSystem = null

## Reference to map data
var map_data: MapData = null

## Player faction ID
const PLAYER_FACTION_ID := 0

## UI elements
@onready var room_buttons_container: HBoxContainer = $MarginContainer/VBoxContainer/RoomButtonsContainer
@onready var info_label: Label = $MarginContainer/VBoxContainer/InfoContainer/InfoLabel
@onready var cost_label: Label = $MarginContainer/VBoxContainer/InfoContainer/CostLabel

## Room button references
var room_buttons: Dictionary = {}  # { RoomTypes.Type: Button }


func _ready() -> void:
	# Start hidden
	visible = false
	
	# Connect to events
	GameEvents.map_loaded.connect(_on_map_loaded)
	GameEvents.gold_changed.connect(_on_gold_changed)
	GameEvents.room_placement_started.connect(_on_placement_started)
	GameEvents.room_placement_cancelled.connect(_on_placement_cancelled)
	GameEvents.room_placement_preview.connect(_on_placement_preview)
	GameEvents.room_created.connect(_on_room_created)
	
	# Create room buttons
	_create_room_buttons()


## Set room system reference
func set_room_system(system: RoomSystem) -> void:
	room_system = system


## Handle map loaded
func _on_map_loaded(data: Resource) -> void:
	map_data = data as MapData
	_update_button_states()


## Handle gold changed
func _on_gold_changed(faction_id: int, _old_amount: int, _new_amount: int) -> void:
	if faction_id == PLAYER_FACTION_ID:
		_update_button_states()


## Create buttons for each room type
func _create_room_buttons() -> void:
	# Clear existing buttons
	for child in room_buttons_container.get_children():
		child.queue_free()
	room_buttons.clear()
	
	# Create a button for each room type
	for room_type in RoomTypes.get_all_types():
		var button := Button.new()
		button.name = RoomTypes.get_display_name(room_type)
		button.text = RoomTypes.get_display_name(room_type)
		button.custom_minimum_size = Vector2(100, 40)
		button.pressed.connect(_on_room_button_pressed.bind(room_type))
		
		# Add mouse enter/exit for hover info
		button.mouse_entered.connect(_on_room_button_hover.bind(room_type))
		button.mouse_exited.connect(_on_room_button_unhover)
		
		room_buttons_container.add_child(button)
		room_buttons[room_type] = button
	
	# Add cancel button
	var cancel_button := Button.new()
	cancel_button.name = "CancelButton"
	cancel_button.text = "Cancel"
	cancel_button.custom_minimum_size = Vector2(80, 40)
	cancel_button.pressed.connect(_on_cancel_pressed)
	cancel_button.visible = false
	room_buttons_container.add_child(cancel_button)


## Toggle panel visibility
func toggle() -> void:
	visible = not visible
	if visible:
		_update_button_states()
		_clear_info()
	elif room_system and room_system.is_placing_room:
		room_system.cancel_placement()


## Handle room button pressed
func _on_room_button_pressed(room_type: RoomTypes.Type) -> void:
	if not room_system:
		return
	
	# Check if we can afford at least one tile
	var cost_per_tile := RoomTypes.get_cost_per_tile(room_type)
	if map_data and not map_data.can_afford(PLAYER_FACTION_ID, cost_per_tile):
		_show_info("Not enough gold!", Color.RED)
		return
	
	room_system.start_placement(room_type)


## Handle cancel button pressed
func _on_cancel_pressed() -> void:
	if room_system:
		room_system.cancel_placement()


## Handle room button hover
func _on_room_button_hover(room_type: RoomTypes.Type) -> void:
	var description := RoomTypes.get_description(room_type)
	var functional_tiles := RoomTypes.get_functional_tiles(room_type)
	var cost_per_tile := RoomTypes.get_cost_per_tile(room_type)
	
	info_label.text = description
	cost_label.text = "%d gold/tile (functional at %d+ tiles)" % [cost_per_tile, functional_tiles]


## Handle room button unhover
func _on_room_button_unhover() -> void:
	if not room_system or not room_system.is_placing_room:
		_clear_info()


## Clear info labels
func _clear_info() -> void:
	info_label.text = "Hover over a room type for info"
	cost_label.text = ""


## Show info message
func _show_info(message: String, color: Color = Color.WHITE) -> void:
	info_label.text = message
	info_label.modulate = color
	cost_label.text = ""


## Update button enabled states based on gold
func _update_button_states() -> void:
	if not map_data:
		return
	
	var current_gold := map_data.get_gold(PLAYER_FACTION_ID)
	
	for room_type in room_buttons.keys():
		var button: Button = room_buttons[room_type]
		var cost_per_tile := RoomTypes.get_cost_per_tile(room_type)
		button.disabled = current_gold < cost_per_tile
		
		# Update tooltip
		if button.disabled:
			button.tooltip_text = "Need %d gold (have %d)" % [cost_per_tile, current_gold]
		else:
			button.tooltip_text = RoomTypes.get_description(room_type)


## Handle placement started
func _on_placement_started(room_type: int) -> void:
	# Show cancel button
	var cancel_button := room_buttons_container.get_node_or_null("CancelButton")
	if cancel_button:
		cancel_button.visible = true
	
	# Update info
	var type_enum := room_type as RoomTypes.Type
	var type_name := RoomTypes.get_display_name(type_enum)
	info_label.text = "Placing %s - Click and drag to select tiles" % type_name
	info_label.modulate = Color.WHITE
	cost_label.text = "Right-click or press Escape to cancel"


## Handle placement cancelled
func _on_placement_cancelled() -> void:
	# Hide cancel button
	var cancel_button := room_buttons_container.get_node_or_null("CancelButton")
	if cancel_button:
		cancel_button.visible = false
	
	_clear_info()


## Handle placement preview
func _on_placement_preview(_new_tiles: Array[Vector2i], _existing_tiles: Array[Vector2i], is_valid: bool, cost: int) -> void:
	if not room_system:
		return
	
	var preview_info := room_system.get_placement_preview_info()
	if preview_info.is_empty():
		return
	
	var tile_count: int = preview_info.get("tile_count", 0)
	var functional_tiles: int = preview_info.get("functional_tiles", 9)
	var is_functional: bool = preview_info.get("is_functional", false)
	var can_afford: bool = preview_info.get("can_afford", false)
	var type_name: String = preview_info.get("type_name", "Room")
	
	# Build status message
	var status_parts: Array[String] = []
	
	if not is_functional:
		status_parts.append("Need %d tiles to be functional" % functional_tiles)
	
	if not can_afford:
		status_parts.append("Not enough gold")
	
	if is_valid:
		var functional_note := " (functional)" if is_functional else " (not functional yet)"
		info_label.text = "%s: %d new tiles%s - Click to confirm" % [type_name, tile_count, functional_note]
		info_label.modulate = Color.GREEN if is_functional else Color.YELLOW
	else:
		var reason := ", ".join(status_parts) if not status_parts.is_empty() else "Invalid placement"
		info_label.text = "%s: %d new tiles - %s" % [type_name, tile_count, reason]
		info_label.modulate = Color.RED
	
	cost_label.text = "Cost: %d gold" % cost


## Handle room created
func _on_room_created(_room: RoomData) -> void:
	_clear_info()
	_update_button_states()
	
	# Hide cancel button
	var cancel_button := room_buttons_container.get_node_or_null("CancelButton")
	if cancel_button:
		cancel_button.visible = false


## Handle input (toggle with R key)
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_room_panel"):
		toggle()
		get_viewport().set_input_as_handled()
