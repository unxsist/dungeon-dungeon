class_name CreatureInfoPanel
extends PanelContainer
## UI panel for displaying creature information when clicked.

## Reference to creature renderer (for click detection)
var creature_renderer: CreatureRenderer = null

## Reference to camera (for ray casting)
var camera: Camera3D = null

## Currently displayed creature
var current_creature: CreatureData = null

## UI elements
@onready var name_label: Label = $MarginContainer/VBoxContainer/NameLabel
@onready var level_label: Label = $MarginContainer/VBoxContainer/LevelLabel
@onready var health_bar: ProgressBar = $MarginContainer/VBoxContainer/HealthContainer/HealthBar
@onready var health_label: Label = $MarginContainer/VBoxContainer/HealthContainer/HealthLabel
@onready var happiness_bar: ProgressBar = $MarginContainer/VBoxContainer/HappinessContainer/HappinessBar
@onready var happiness_label: Label = $MarginContainer/VBoxContainer/HappinessContainer/HappinessLabel
@onready var state_label: Label = $MarginContainer/VBoxContainer/StateLabel
@onready var task_label: Label = $MarginContainer/VBoxContainer/TaskLabel


func _ready() -> void:
	# Start hidden
	visible = false
	
	# Connect to creature events
	GameEvents.creature_despawned.connect(_on_creature_despawned)
	GameEvents.creature_state_changed.connect(_on_creature_state_changed)
	GameEvents.creature_health_changed.connect(_on_creature_health_changed)
	GameEvents.creature_happiness_changed.connect(_on_creature_happiness_changed)
	GameEvents.creature_leveled_up.connect(_on_creature_leveled_up)
	GameEvents.creature_task_started.connect(_on_creature_task_changed)
	GameEvents.creature_task_completed.connect(_on_creature_task_changed)


## Set references (called from main or parent scene)
func set_references(renderer: CreatureRenderer, cam: Camera3D) -> void:
	creature_renderer = renderer
	camera = cam


## Handle input for creature clicking
func _unhandled_input(event: InputEvent) -> void:
	if not creature_renderer or not camera:
		return
	
	if event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		
		# Left click to select creature
		if mouse_event.button_index == MOUSE_BUTTON_LEFT and mouse_event.pressed:
			var creature_id := creature_renderer.find_creature_at_screen_position(
				mouse_event.position, 
				camera
			)
			
			if creature_id >= 0:
				_show_creature(creature_id)
				get_viewport().set_input_as_handled()
			elif visible:
				# Clicked elsewhere - hide panel
				_hide_panel()


## Show information for a creature
func _show_creature(creature_id: int) -> void:
	if not creature_renderer or not creature_renderer.map_data:
		return
	
	current_creature = creature_renderer.map_data.get_creature(creature_id)
	if not current_creature:
		return
	
	_update_display()
	visible = true
	
	# Emit click event
	GameEvents.creature_clicked.emit(creature_id)


## Hide the panel
func _hide_panel() -> void:
	current_creature = null
	visible = false


## Update all display elements
func _update_display() -> void:
	if not current_creature:
		return
	
	# Name
	var display_name := current_creature.get_display_name()
	var faction_name := "Unknown"
	if creature_renderer and creature_renderer.map_data:
		var faction := creature_renderer.map_data.get_faction(current_creature.faction_id)
		if faction:
			faction_name = faction.faction_name
	name_label.text = "%s (%s)" % [display_name, faction_name]
	
	# Level
	level_label.text = "Level %d" % current_creature.level
	
	# Health
	health_bar.max_value = current_creature.max_health
	health_bar.value = current_creature.health
	health_label.text = "%d / %d" % [current_creature.health, current_creature.max_health]
	
	# Happiness
	happiness_bar.max_value = 100.0
	happiness_bar.value = current_creature.happiness
	happiness_label.text = "%d%%" % int(current_creature.happiness)
	
	# State
	state_label.text = "State: %s" % _get_state_name(current_creature.state)
	
	# Task
	if current_creature.current_task.is_empty():
		task_label.text = "Task: None"
	else:
		var task_type: TaskTypes.Type = current_creature.current_task.get("type", TaskTypes.Type.CLAIM)
		var task_name := TaskTypes.get_display_name(task_type)
		var progress: float = current_creature.current_task.get("progress", 0.0)
		task_label.text = "Task: %s (%d%%)" % [task_name, int(progress)]


## Get readable state name
func _get_state_name(state: CreatureTypes.State) -> String:
	match state:
		CreatureTypes.State.IDLE:
			return "Idle"
		CreatureTypes.State.WALKING:
			return "Walking"
		CreatureTypes.State.WORKING:
			return "Working"
		CreatureTypes.State.WANDERING:
			return "Wandering"
	return "Unknown"


## Handle creature despawn
func _on_creature_despawned(creature_id: int) -> void:
	if current_creature and current_creature.id == creature_id:
		_hide_panel()


## Handle state change
func _on_creature_state_changed(creature_id: int, _old_state: int, _new_state: int) -> void:
	if current_creature and current_creature.id == creature_id:
		_update_display()


## Handle health change
func _on_creature_health_changed(creature_id: int, _old_health: int, _new_health: int) -> void:
	if current_creature and current_creature.id == creature_id:
		_update_display()


## Handle happiness change
func _on_creature_happiness_changed(creature_id: int, _happiness: float) -> void:
	if current_creature and current_creature.id == creature_id:
		_update_display()


## Handle level up
func _on_creature_leveled_up(creature_id: int, _new_level: int) -> void:
	if current_creature and current_creature.id == creature_id:
		_update_display()


## Handle task change
func _on_creature_task_changed(creature_id: int, _task: Dictionary) -> void:
	if current_creature and current_creature.id == creature_id:
		_update_display()


## Update display periodically when visible
func _process(_delta: float) -> void:
	if visible and current_creature:
		_update_display()
