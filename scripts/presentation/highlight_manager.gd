class_name HighlightManager
extends Node
## Manages tile highlighting and fog of war visuals using shaders.

## Reference to the TileRenderer
@export var tile_renderer: TileRenderer

## Reference to the FogSystem
@export var fog_system: FogSystem

## Reference to the SelectionSystem (for debug view)
@export var selection_system: SelectionSystem

## The highlight shader
var highlight_shader: Shader

## Cache of shader materials per tile
var highlight_materials: Dictionary = {}

## Currently highlighted tile
var current_highlight: Vector2i = Vector2i(-1, -1)

## Currently selected tiles
var current_selection: Array[Vector2i] = []

## Debug mode - shows all diggable walls
var debug_diggable_enabled: bool = false
var debug_diggable_tiles: Array[Vector2i] = []

## Highlight colors
@export var hover_color: Color = Color(1.0, 1.0, 0.0, 0.6)
@export var selection_color: Color = Color(0.3, 0.7, 1.0, 0.5)
@export var dig_color: Color = Color(1.0, 0.5, 0.0, 0.6)
@export var claim_color: Color = Color(0.0, 1.0, 0.5, 0.6)
@export var debug_diggable_color: Color = Color(0.0, 1.0, 0.0, 0.3)
@export var room_valid_color: Color = Color(0.2, 0.8, 0.2, 0.5)
@export var room_invalid_color: Color = Color(0.8, 0.2, 0.2, 0.5)
@export var room_existing_color: Color = Color(0.5, 0.5, 0.5, 0.3)  # Dimmed color for existing room tiles

## Room placement preview state
var room_preview_tiles: Array[Vector2i] = []
var room_preview_existing_tiles: Array[Vector2i] = []  # Tiles already part of same room type
var room_preview_valid: bool = false


func _ready() -> void:
	# Load the highlight shader
	highlight_shader = load("res://shaders/tile_highlight.gdshader")
	
	# Connect to game events
	GameEvents.tile_hovered.connect(_on_tile_hovered)
	GameEvents.tile_unhovered.connect(_on_tile_unhovered)
	GameEvents.tiles_selected.connect(_on_tiles_selected)
	GameEvents.selection_cleared.connect(_on_selection_cleared)
	GameEvents.tile_changed.connect(_on_tile_changed)
	GameEvents.visibility_updated.connect(_on_visibility_updated)
	GameEvents.room_placement_preview.connect(_on_room_placement_preview)
	GameEvents.room_placement_cancelled.connect(_on_room_placement_cancelled)
	GameEvents.room_created.connect(_on_room_created)


func _unhandled_input(event: InputEvent) -> void:
	# Toggle debug view with F3
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F3:
			toggle_debug_diggable()


## Handle tile hover
func _on_tile_hovered(pos: Vector2i) -> void:
	# Clear previous highlight
	if current_highlight != Vector2i(-1, -1) and current_highlight != pos:
		_set_tile_highlighted(current_highlight, false)
	
	current_highlight = pos
	_set_tile_highlighted(pos, true)


## Handle tile unhover
func _on_tile_unhovered() -> void:
	if current_highlight != Vector2i(-1, -1):
		# Always remove hover border (selection uses different shader parameter)
		_set_tile_highlighted(current_highlight, false)
		current_highlight = Vector2i(-1, -1)


## Handle tiles selected
func _on_tiles_selected(positions: Array[Vector2i]) -> void:
	# Clear previous selection highlights (except debug tiles)
	for pos in current_selection:
		if pos != current_highlight and pos not in positions:
			_set_tile_selected(pos, false)
	
	current_selection = positions.duplicate()
	
	# Apply new selection highlights
	for pos in current_selection:
		_set_tile_selected(pos, true)


## Handle selection cleared
func _on_selection_cleared() -> void:
	for pos in current_selection:
		_set_tile_selected(pos, false)
	current_selection.clear()


## Handle tile changed - need to refresh materials
func _on_tile_changed(pos: Vector2i, _old_type: int, _new_type: int) -> void:
	# Collect all affected positions (the changed tile and its neighbors)
	# because TileRenderer recreates neighbor meshes too
	var affected_positions: Array[Vector2i] = [pos]
	for dir: Vector2i in MapData.DIRECTIONS:
		affected_positions.append(pos + dir)
	
	# Invalidate materials for all affected tiles
	for affected_pos in affected_positions:
		_invalidate_tile_material(affected_pos)
	
	# Re-apply highlights for all affected tiles
	for affected_pos in affected_positions:
		if affected_pos == current_highlight:
			_set_tile_highlighted(affected_pos, true)
		if affected_pos in current_selection:
			_set_tile_selected(affected_pos, true)
	
	# Update debug view if enabled
	if debug_diggable_enabled:
		_refresh_debug_diggable()


## Invalidate cached material for a tile
func _invalidate_tile_material(pos: Vector2i) -> void:
	if highlight_materials.has(pos):
		highlight_materials.erase(pos)


## Set tile highlight state (hover border)
func _set_tile_highlighted(pos: Vector2i, highlighted: bool) -> void:
	if not tile_renderer:
		return
	
	var mesh := tile_renderer.get_tile_mesh(pos)
	if not mesh:
		return
	
	var mat := _get_or_create_highlight_material(pos, mesh)
	if mat:
		# Only show border on hover, NOT full highlight
		mat.set_shader_parameter("show_hover_border", highlighted)
		mat.set_shader_parameter("hover_border_color", hover_color)
		
		# Force visibility for hover to work (ignore fog for interaction feedback)
		if highlighted:
			mat.set_shader_parameter("visibility_state", 2)
		
		# Always keep selection/highlight off for hover unless explicitly selected
		var is_in_selection := current_selection.has(pos)
		if not is_in_selection and not (debug_diggable_enabled and pos in debug_diggable_tiles):
			mat.set_shader_parameter("is_highlighted", false)
			mat.set_shader_parameter("is_selected", false)


## Set tile selection state (full highlight for digging)
func _set_tile_selected(pos: Vector2i, selected: bool) -> void:
	if not tile_renderer:
		return
	
	var mesh := tile_renderer.get_tile_mesh(pos)
	if not mesh:
		return
	
	var mat := _get_or_create_highlight_material(pos, mesh)
	if mat:
		mat.set_shader_parameter("is_selected", selected)
		mat.set_shader_parameter("is_highlighted", selected)  # Full highlight on selection
		mat.set_shader_parameter("selection_color", selection_color)
		mat.set_shader_parameter("highlight_color", selection_color)
		
		# Force visibility for selection to work (ignore fog for interaction feedback)
		if selected:
			mat.set_shader_parameter("visibility_state", 2)


## Set tile debug highlight (shows diggable walls)
func _set_tile_debug_diggable(pos: Vector2i, enabled: bool) -> void:
	if not tile_renderer:
		return
	
	var mesh := tile_renderer.get_tile_mesh(pos)
	if not mesh:
		return
	
	var mat := _get_or_create_highlight_material(pos, mesh)
	if mat:
		mat.set_shader_parameter("show_edge", enabled)
		mat.set_shader_parameter("edge_color", debug_diggable_color)
		
		# Force visibility to VISIBLE for debug mode (ignore fog of war)
		if enabled:
			mat.set_shader_parameter("visibility_state", 2)


## Get or create a shader material for a tile
func _get_or_create_highlight_material(pos: Vector2i, mesh: MeshInstance3D) -> ShaderMaterial:
	# Check cache - but verify the mesh still has our material
	if highlight_materials.has(pos):
		var cached_mat: ShaderMaterial = highlight_materials[pos]
		# Verify the mesh's overlay is still our cached material
		if mesh.material_overlay == cached_mat:
			return cached_mat
		else:
			# Mesh was recreated, invalidate cache
			highlight_materials.erase(pos)
	
	# Get current material to extract base color
	var current_mat := mesh.material_override
	var base_color := Color(0.5, 0.5, 0.5)
	var roughness := 0.8
	
	if current_mat is StandardMaterial3D:
		base_color = current_mat.albedo_color
		roughness = current_mat.roughness
	
	# Create new shader material with all parameters explicitly set
	var shader_mat := ShaderMaterial.new()
	shader_mat.shader = highlight_shader
	shader_mat.set_shader_parameter("albedo_color", base_color)
	shader_mat.set_shader_parameter("roughness", roughness)
	# Highlight states - all off by default
	shader_mat.set_shader_parameter("is_highlighted", false)
	shader_mat.set_shader_parameter("is_selected", false)
	shader_mat.set_shader_parameter("show_hover_border", false)
	shader_mat.set_shader_parameter("show_edge", false)
	shader_mat.set_shader_parameter("overlay_only", true)
	# Colors
	shader_mat.set_shader_parameter("highlight_color", selection_color)
	shader_mat.set_shader_parameter("selection_color", selection_color)
	shader_mat.set_shader_parameter("hover_border_color", hover_color)
	shader_mat.set_shader_parameter("edge_color", debug_diggable_color)
	
	# Set initial fog state
	var vis_state := 2  # Default to visible
	if fog_system:
		var visibility := fog_system.get_visibility(pos)
		match visibility:
			FogSystem.Visibility.HIDDEN:
				vis_state = 0
			FogSystem.Visibility.EXPLORED:
				vis_state = 1
			FogSystem.Visibility.VISIBLE:
				vis_state = 2
	shader_mat.set_shader_parameter("visibility_state", vis_state)
	
	# Apply as overlay so base material stays intact
	mesh.material_overlay = shader_mat
	
	# Cache it
	highlight_materials[pos] = shader_mat
	
	return shader_mat


## Set highlight color based on action type
func set_action_highlight(action: String) -> void:
	match action:
		"dig":
			hover_color = dig_color
		"claim":
			hover_color = claim_color
		_:
			hover_color = Color(1.0, 1.0, 0.0, 0.6)
	
	# Update current highlight
	if current_highlight != Vector2i(-1, -1):
		_set_tile_highlighted(current_highlight, true)


## Clear all highlights
func clear_all_highlights() -> void:
	_on_selection_cleared()
	_on_tile_unhovered()


## Toggle debug view showing all diggable walls
func toggle_debug_diggable() -> void:
	debug_diggable_enabled = not debug_diggable_enabled
	
	if debug_diggable_enabled:
		_refresh_debug_diggable()
		print("[Debug] Showing all diggable walls (", debug_diggable_tiles.size(), " tiles)")
	else:
		# Clear debug highlights and restore fog state
		for pos in debug_diggable_tiles:
			_set_tile_debug_diggable(pos, false)
			# Restore proper fog state
			_update_fog_state(pos)
		debug_diggable_tiles.clear()
		print("[Debug] Diggable wall overlay disabled")


## Enable debug view showing all diggable walls
func enable_debug_diggable() -> void:
	if not debug_diggable_enabled:
		toggle_debug_diggable()


## Disable debug view
func disable_debug_diggable() -> void:
	if debug_diggable_enabled:
		toggle_debug_diggable()


## Refresh debug diggable tiles (call after map changes)
func _refresh_debug_diggable() -> void:
	if not selection_system:
		push_warning("HighlightManager: selection_system not set, cannot refresh debug view")
		return
	
	# Clear old highlights
	for pos in debug_diggable_tiles:
		_set_tile_debug_diggable(pos, false)
	
	# Get fresh list
	debug_diggable_tiles = selection_system.get_all_diggable_tiles()
	
	# Apply highlights
	for pos in debug_diggable_tiles:
		_set_tile_debug_diggable(pos, true)


## Handle visibility update from fog system
func _on_visibility_updated(_faction_id: int) -> void:
	_update_all_fog_states()


## Update fog of war state on all tile materials
func _update_all_fog_states() -> void:
	if not tile_renderer or not fog_system:
		return
	
	for pos in highlight_materials.keys():
		# Don't update fog state for tiles with active effects
		var skip_fog := false
		if pos == current_highlight:
			skip_fog = true
		if pos in current_selection:
			skip_fog = true
		if debug_diggable_enabled and pos in debug_diggable_tiles:
			skip_fog = true
		
		if not skip_fog:
			_update_fog_state(pos)


## Update fog state for a single tile
func _update_fog_state(pos: Vector2i) -> void:
	if not fog_system:
		return
	
	if not highlight_materials.has(pos):
		return
	
	var mat: ShaderMaterial = highlight_materials[pos]
	var visibility := fog_system.get_visibility(pos)
	
	# Map FogSystem.Visibility to shader visibility_state
	var vis_state: int
	match visibility:
		FogSystem.Visibility.HIDDEN:
			vis_state = 0
		FogSystem.Visibility.EXPLORED:
			vis_state = 1
		FogSystem.Visibility.VISIBLE:
			vis_state = 2
		_:
			vis_state = 2
	
	mat.set_shader_parameter("visibility_state", vis_state)


## Handle room placement preview
func _on_room_placement_preview(new_tiles: Array[Vector2i], existing_tiles: Array[Vector2i], is_valid: bool, _cost: int) -> void:
	# Clear previous preview tiles
	_clear_room_preview()
	
	# Store and highlight new preview tiles
	room_preview_tiles = new_tiles.duplicate()
	room_preview_existing_tiles = existing_tiles.duplicate()
	room_preview_valid = is_valid
	
	# Highlight new tiles with valid/invalid color
	var preview_color := room_valid_color if is_valid else room_invalid_color
	for pos in room_preview_tiles:
		_set_tile_room_preview(pos, true, preview_color)
	
	# Highlight existing same-type tiles with dimmed color (already placed)
	for pos in room_preview_existing_tiles:
		_set_tile_room_preview(pos, true, room_existing_color)


## Handle room placement cancelled
func _on_room_placement_cancelled() -> void:
	_clear_room_preview()


## Handle room created - clear preview
func _on_room_created(_room: RoomData) -> void:
	_clear_room_preview()


## Clear room preview highlights
func _clear_room_preview() -> void:
	for pos in room_preview_tiles:
		_set_tile_room_preview(pos, false, Color.WHITE)
		_update_fog_state(pos)
	room_preview_tiles.clear()
	
	for pos in room_preview_existing_tiles:
		_set_tile_room_preview(pos, false, Color.WHITE)
		_update_fog_state(pos)
	room_preview_existing_tiles.clear()


## Set room preview highlight on a tile
func _set_tile_room_preview(pos: Vector2i, enabled: bool, color: Color) -> void:
	if not tile_renderer:
		return
	
	var mesh := tile_renderer.get_tile_mesh(pos)
	if not mesh:
		return
	
	var mat := _get_or_create_highlight_material(pos, mesh)
	if mat:
		mat.set_shader_parameter("is_highlighted", enabled)
		mat.set_shader_parameter("is_selected", enabled)
		mat.set_shader_parameter("highlight_color", color)
		mat.set_shader_parameter("selection_color", color)
		
		# Force visibility for preview to work
		if enabled:
			mat.set_shader_parameter("visibility_state", 2)
