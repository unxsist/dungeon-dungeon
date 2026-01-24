class_name FactionData
extends Resource
## Data class representing a faction (player or enemy).

@export var id: int = 0
@export var faction_name: String = "Unknown"
@export var color: Color = Color.WHITE
@export var is_player_controlled: bool = false

## Create a FactionData from a dictionary (from JSON)
static func from_dict(data: Dictionary) -> FactionData:
	var faction := FactionData.new()
	faction.id = data.get("id", 0)
	faction.faction_name = data.get("name", "Unknown")
	
	# Parse color from hex string or use default
	var color_str: String = data.get("color", "#ffffff")
	faction.color = Color.from_string(color_str, Color.WHITE)
	
	faction.is_player_controlled = data.get("is_player", false)
	return faction

## Convert to dictionary for saving
func to_dict() -> Dictionary:
	return {
		"id": id,
		"name": faction_name,
		"color": "#" + color.to_html(false),
		"is_player": is_player_controlled,
	}
