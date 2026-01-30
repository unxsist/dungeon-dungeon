class_name ResourceBar
extends PanelContainer
## UI component displaying player resources (gold) in the top-right corner.

## Reference to map data
var map_data: MapData = null

## Player faction ID
const PLAYER_FACTION_ID := 0

## UI elements
@onready var gold_label: Label = $MarginContainer/HBoxContainer/GoldLabel
@onready var gold_value: Label = $MarginContainer/HBoxContainer/GoldValue


func _ready() -> void:
	# Connect to events
	GameEvents.map_loaded.connect(_on_map_loaded)
	GameEvents.gold_changed.connect(_on_gold_changed)
	
	# Start with default display
	_update_display()


## Handle map loaded
func _on_map_loaded(data: Resource) -> void:
	map_data = data as MapData
	_update_display()


## Handle gold change
func _on_gold_changed(faction_id: int, _old_amount: int, _new_amount: int) -> void:
	if faction_id == PLAYER_FACTION_ID:
		_update_display()


## Update the gold display
func _update_display() -> void:
	if not map_data:
		gold_value.text = "0"
		return
	
	var gold := map_data.get_gold(PLAYER_FACTION_ID)
	gold_value.text = _format_gold(gold)


## Format gold with thousands separator
func _format_gold(amount: int) -> String:
	var str_amount := str(amount)
	var result := ""
	var count := 0
	
	# Process from right to left
	for i in range(str_amount.length() - 1, -1, -1):
		if count > 0 and count % 3 == 0:
			result = "," + result
		result = str_amount[i] + result
		count += 1
	
	return result
