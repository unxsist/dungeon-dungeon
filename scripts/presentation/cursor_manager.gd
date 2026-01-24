class_name CursorManager
extends CanvasLayer
## Manages custom mouse cursors based on game state.
## Renders a sprite at the cursor position instead of using system cursor.
## Changes cursor when hovering over diggable walls.

## Preloaded cursor textures
var default_cursor: Texture2D
var digging_cursor: Texture2D

## The sprite that displays the cursor
var cursor_sprite: Sprite2D

## Hotspot offset (the pixel that acts as the click point, relative to sprite center)
## For default cursor: tip of the pointing finger
@export var default_hotspot: Vector2 = Vector2(240, 160)
## For digging cursor: tip of the shovel
@export var digging_hotspot: Vector2 = Vector2(75, 305)

## Current hotspot being used
var current_hotspot: Vector2

## Scale for the cursor sprites
@export var cursor_scale: float = 0.15


func _ready() -> void:
	# Render above everything
	layer = 100
	
	# Load cursor textures
	default_cursor = preload("res://resources/assets/cursor.png")
	digging_cursor = preload("res://resources/assets/digging_cursor.png")
	
	# Create the cursor sprite
	cursor_sprite = Sprite2D.new()
	cursor_sprite.texture = default_cursor
	cursor_sprite.scale = Vector2(cursor_scale, cursor_scale)
	add_child(cursor_sprite)
	
	# Set initial hotspot
	current_hotspot = default_hotspot
	
	# Hide the system cursor
	Input.set_mouse_mode(Input.MOUSE_MODE_HIDDEN)
	
	# Connect to hover events from SelectionSystem
	GameEvents.tile_hovered.connect(_on_tile_hovered)
	GameEvents.tile_unhovered.connect(_on_tile_unhovered)


func _process(_delta: float) -> void:
	# Update cursor sprite position to follow mouse
	var mouse_pos := get_viewport().get_mouse_position()
	# Offset by hotspot so the "tip" is at the actual mouse position
	cursor_sprite.position = mouse_pos + (cursor_sprite.texture.get_size() * 0.5 - current_hotspot) * cursor_scale


func _on_tile_hovered(_pos: Vector2i) -> void:
	# Change to digging cursor when hovering over a diggable wall
	cursor_sprite.texture = digging_cursor
	current_hotspot = digging_hotspot


func _on_tile_unhovered() -> void:
	# Restore default cursor
	cursor_sprite.texture = default_cursor
	current_hotspot = default_hotspot


func _exit_tree() -> void:
	# Restore system cursor when this node is removed
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
