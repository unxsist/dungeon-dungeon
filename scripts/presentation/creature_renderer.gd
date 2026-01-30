class_name CreatureRenderer
extends Node3D
## Renders creatures as billboarded sprites in the 3D world.

## Reference to map data
var map_data: MapData = null

## Container for creature sprites
@onready var sprite_container: Node3D = $SpriteContainer

## Dictionary of creature sprites: { creature_id: Sprite3D }
var creature_sprites: Dictionary = {}

## Loaded textures cache: { creature_type: Texture2D }
var texture_cache: Dictionary = {}

## Animation time tracking for working bounce: { creature_id: float }
var animation_time: Dictionary = {}

## Spawn animation tracking: { creature_id: { "progress": float, "start_scale": Vector3 } }
var spawn_animations: Dictionary = {}

## Spawn animation settings
const SPAWN_ANIMATION_DURATION := 0.5  ## Seconds for spawn animation
const SPAWN_START_SCALE := Vector3(0.1, 0.1, 0.1)  ## Start very small
const SPAWN_OVERSHOOT := 1.2  ## Bounce overshoot multiplier

## Working animation settings
const WORK_BOUNCE_HEIGHT := 0.15  ## How high the bounce goes
const WORK_BOUNCE_SPEED := 8.0    ## Bounces per second
const WORK_SQUASH_AMOUNT := 0.1   ## How much to squash/stretch

## Height offset for sprites (to stand on ground)
## Should match TileRenderer.FLOOR_Y (0.01) for proper alignment
const SPRITE_HEIGHT_OFFSET := 0.01

## Sprite scale (uniform)
const SPRITE_SCALE := Vector3(1.0, 1.0, 1.0)

## Texture paths per creature type
const CREATURE_TEXTURES := {
	CreatureTypes.Type.IMP: "res://resources/creatures/imp.png",
}


func _ready() -> void:
	# Create sprite container if not in scene
	if not has_node("SpriteContainer"):
		sprite_container = Node3D.new()
		sprite_container.name = "SpriteContainer"
		add_child(sprite_container)
	
	GameEvents.map_loaded.connect(_on_map_loaded)
	GameEvents.creature_spawned.connect(_on_creature_spawned)
	GameEvents.creature_despawned.connect(_on_creature_despawned)
	GameEvents.creature_state_changed.connect(_on_creature_state_changed)
	GameEvents.portal_creature_spawned.connect(_on_portal_creature_spawned)


## Initialize when map is loaded
func _on_map_loaded(data: MapData) -> void:
	map_data = data
	
	# Clear existing sprites
	for sprite in creature_sprites.values():
		sprite.queue_free()
	creature_sprites.clear()


## Create sprite for a new creature
func _on_creature_spawned(creature: CreatureData) -> void:
	if creature_sprites.has(creature.id):
		return  # Already exists
	
	var sprite := _create_creature_sprite(creature)
	creature_sprites[creature.id] = sprite
	sprite_container.add_child(sprite)
	
	# Set initial position
	_update_sprite_position(sprite, creature)
	
	print("CreatureRenderer: Created sprite for creature %d at position %s" % [creature.id, creature.visual_position])


## Handle creature spawning from portal with special effect
func _on_portal_creature_spawned(portal_pos: Vector2i, creature: CreatureData) -> void:
	# Start spawn animation for this creature
	if creature_sprites.has(creature.id):
		var sprite: Node3D = creature_sprites[creature.id]
		
		# Initialize spawn animation
		spawn_animations[creature.id] = {
			"progress": 0.0,
			"start_scale": SPAWN_START_SCALE,
			"target_scale": sprite.scale
		}
		
		# Start with small scale
		sprite.scale = SPAWN_START_SCALE
		
		# Create spawn particles effect
		_create_spawn_particles(portal_pos, creature)
		
		print("CreatureRenderer: Starting spawn animation for creature %d from portal %s" % [creature.id, portal_pos])


## Remove sprite for despawned creature
func _on_creature_despawned(creature_id: int) -> void:
	if not creature_sprites.has(creature_id):
		return
	
	var sprite: Node3D = creature_sprites[creature_id]
	sprite.queue_free()
	creature_sprites.erase(creature_id)


## Update animation when creature state changes
func _on_creature_state_changed(creature_id: int, old_state: int, new_state: int) -> void:
	if not creature_sprites.has(creature_id):
		return
	
	var sprite = creature_sprites[creature_id]
	_update_sprite_animation(sprite, new_state as CreatureTypes.State)


## Update all creature positions each frame
func _process(delta: float) -> void:
	if not map_data:
		return
	
	# Update spawn animations
	_update_spawn_animations(delta)
	
	for creature in map_data.creatures:
		if creature_sprites.has(creature.id):
			var sprite: Node3D = creature_sprites[creature.id]
			_update_sprite_position(sprite, creature)
			
			# Skip working animation if spawn animation is active
			if spawn_animations.has(creature.id):
				continue
			
			# Animate working creatures with a bounce
			if creature.state == CreatureTypes.State.WORKING:
				_animate_working(sprite, creature, delta)
			else:
				# Reset animation when not working
				animation_time.erase(creature.id)
				sprite.scale = SPRITE_SCALE


## Update spawn animations for all creatures being spawned
func _update_spawn_animations(delta: float) -> void:
	var completed_ids: Array[int] = []
	
	for creature_id in spawn_animations.keys():
		var anim: Dictionary = spawn_animations[creature_id]
		anim["progress"] += delta / SPAWN_ANIMATION_DURATION
		
		if anim["progress"] >= 1.0:
			# Animation complete
			completed_ids.append(creature_id)
			if creature_sprites.has(creature_id):
				creature_sprites[creature_id].scale = anim["target_scale"]
		else:
			# Elastic ease-out animation
			var t: float = anim["progress"]
			var ease_t := _elastic_ease_out(t)
			
			if creature_sprites.has(creature_id):
				var sprite: Node3D = creature_sprites[creature_id]
				var target_scale: Vector3 = anim["target_scale"]
				var start_scale: Vector3 = anim["start_scale"]
				sprite.scale = start_scale.lerp(target_scale, ease_t)
	
	# Remove completed animations
	for id in completed_ids:
		spawn_animations.erase(id)


## Animate a working creature with a bounce/wiggle
func _animate_working(sprite: Node3D, creature: CreatureData, delta: float) -> void:
	# Track animation time
	if not animation_time.has(creature.id):
		animation_time[creature.id] = 0.0
	
	animation_time[creature.id] += delta * WORK_BOUNCE_SPEED
	var t: float = animation_time[creature.id]
	
	# Bounce height using sin wave (always positive - bouncing up)
	var bounce: float = absf(sin(t * PI)) * WORK_BOUNCE_HEIGHT
	
	# Apply bounce to Y position
	sprite.global_position.y = SPRITE_HEIGHT_OFFSET + bounce
	
	# Squash and stretch effect
	var squash: float = 1.0 - sin(t * PI) * WORK_SQUASH_AMOUNT
	var stretch: float = 1.0 + sin(t * PI) * WORK_SQUASH_AMOUNT
	sprite.scale = Vector3(SPRITE_SCALE.x * stretch, SPRITE_SCALE.y * squash, SPRITE_SCALE.z)


## Create a sprite for a creature
func _create_creature_sprite(creature: CreatureData) -> Node3D:
	var sprite := Sprite3D.new()
	sprite.name = "Creature_%d" % creature.id
	
	# Billboard mode - always face camera (Paper Mario style)
	sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	
	# Load the creature texture
	var texture := _get_creature_texture(creature.creature_type)
	sprite.texture = texture
	
	# Enable transparency
	sprite.transparent = true
	sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	
	# Calculate pixel size based on creature's target height
	# pixel_size = target_height / texture_height
	var target_height: float = CreatureTypes.get_height(creature.creature_type)
	var texture_height: float = float(texture.get_height()) if texture else 64.0
	var pixel_size: float = target_height / texture_height
	sprite.pixel_size = pixel_size
	
	# Set scale
	sprite.scale = SPRITE_SCALE
	
	# Center horizontally, anchor at bottom for proper ground alignment
	sprite.centered = true
	if texture:
		# Offset sprite up by half its height so it stands on the ground
		sprite.offset = Vector2(0, texture_height / 2.0)
	
	# Apply faction color modulation
	var faction_color := Color.WHITE
	if map_data:
		var faction := map_data.get_faction(creature.faction_id)
		if faction:
			# Blend white with faction color for a subtle tint
			faction_color = Color.WHITE.lerp(faction.color, 0.3)
	sprite.modulate = faction_color
	
	# Double-sided rendering so sprite is visible from behind too
	sprite.double_sided = true
	
	# Store creature reference for later
	sprite.set_meta("creature_id", creature.id)
	
	print("CreatureRenderer: Creature %d size=%s target_height=%.2f pixel_size=%.4f" % [
		creature.id, 
		CreatureTypes.Size.keys()[CreatureTypes.get_size(creature.creature_type)],
		target_height,
		pixel_size
	])
	
	return sprite


## Get or load texture for a creature type
func _get_creature_texture(creature_type: CreatureTypes.Type) -> Texture2D:
	# Check cache first
	if texture_cache.has(creature_type):
		return texture_cache[creature_type]
	
	# Load texture
	var texture_path: String = CREATURE_TEXTURES.get(creature_type, "")
	if texture_path.is_empty():
		push_warning("No texture defined for creature type: %s" % creature_type)
		return _create_fallback_texture()
	
	var texture: Texture2D = load(texture_path)
	if texture:
		print("CreatureRenderer: Loaded texture %s (%dx%d)" % [texture_path, texture.get_width(), texture.get_height()])
		texture_cache[creature_type] = texture
	else:
		push_warning("Failed to load creature texture: %s" % texture_path)
		texture = _create_fallback_texture()
		texture_cache[creature_type] = texture
	
	return texture


## Create a simple fallback texture if the real one can't be loaded
func _create_fallback_texture() -> ImageTexture:
	var size := 64
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	image.fill(Color(1.0, 0.3, 0.3, 1.0))  # Bright red so it's visible
	return ImageTexture.create_from_image(image)


## Update sprite position from creature data
func _update_sprite_position(sprite: Node3D, creature: CreatureData) -> void:
	# Convert 2D visual position to 3D world position
	sprite.global_position = Vector3(
		creature.visual_position.x,
		SPRITE_HEIGHT_OFFSET,
		creature.visual_position.y
	)


## Update sprite animation based on state
func _update_sprite_animation(sprite: Node3D, state: CreatureTypes.State) -> void:
	# For placeholder sprites, we could change color/scale based on state
	# With real AnimatedSprite3D, this would play different animations
	
	match state:
		CreatureTypes.State.IDLE:
			sprite.scale = SPRITE_SCALE
		CreatureTypes.State.WALKING:
			sprite.scale = SPRITE_SCALE * 1.05  # Slightly larger when moving
		CreatureTypes.State.WORKING:
			sprite.scale = SPRITE_SCALE * 0.95  # Slightly smaller when working
		CreatureTypes.State.WANDERING:
			sprite.scale = SPRITE_SCALE


## Get sprite for a creature
func get_sprite(creature_id: int) -> Node3D:
	return creature_sprites.get(creature_id)


## Find creature at screen position (for clicking)
func find_creature_at_screen_position(screen_pos: Vector2, camera: Camera3D) -> int:
	if not camera or not map_data:
		return -1
	
	# Project ray from camera
	var ray_origin := camera.project_ray_origin(screen_pos)
	var ray_direction := camera.project_ray_normal(screen_pos)
	
	# Check each creature sprite
	var closest_id := -1
	var closest_dist := INF
	
	for creature in map_data.creatures:
		var sprite_pos := Vector3(
			creature.visual_position.x,
			SPRITE_HEIGHT_OFFSET,
			creature.visual_position.y
		)
		
		# Simple sphere collision check
		var to_sprite := sprite_pos - ray_origin
		var projection := to_sprite.dot(ray_direction)
		
		if projection < 0:
			continue  # Behind camera
		
		var closest_point := ray_origin + ray_direction * projection
		var distance := closest_point.distance_to(sprite_pos)
		
		# Check if within sprite bounds (rough approximation)
		if distance < 1.5:  # Radius for clicking
			if projection < closest_dist:
				closest_dist = projection
				closest_id = creature.id
	
	return closest_id


## Elastic ease-out for bouncy spawn animation
func _elastic_ease_out(t: float) -> float:
	if t <= 0.0:
		return 0.0
	if t >= 1.0:
		return 1.0
	
	var p := 0.3
	var s := p / 4.0
	return pow(2.0, -10.0 * t) * sin((t - s) * TAU / p) + 1.0


## Create particle burst effect at spawn location
func _create_spawn_particles(portal_pos: Vector2i, creature: CreatureData) -> void:
	if not map_data:
		return
	
	var world_pos := map_data.tile_to_world(portal_pos)
	
	# Create a temporary particle system
	var particles := GPUParticles3D.new()
	particles.name = "SpawnParticles_%d" % creature.id
	particles.position = world_pos + Vector3(0, 0.5, 0)
	particles.emitting = true
	particles.one_shot = true
	particles.explosiveness = 1.0
	particles.amount = 16
	particles.lifetime = 0.8
	
	# Create particle material
	var material := ParticleProcessMaterial.new()
	material.direction = Vector3(0, 1, 0)
	material.spread = 45.0
	material.initial_velocity_min = 2.0
	material.initial_velocity_max = 4.0
	material.gravity = Vector3(0, -5, 0)
	material.scale_min = 0.1
	material.scale_max = 0.3
	
	# Color based on faction
	var faction_color := Color(0.2, 0.8, 0.5)  # Default green
	if map_data:
		var faction := map_data.get_faction(creature.faction_id)
		if faction:
			faction_color = faction.color
	
	material.color = faction_color
	particles.process_material = material
	
	# Create a simple mesh for particles
	var mesh := SphereMesh.new()
	mesh.radius = 0.1
	mesh.height = 0.2
	
	var mesh_material := StandardMaterial3D.new()
	mesh_material.albedo_color = faction_color
	mesh_material.emission_enabled = true
	mesh_material.emission = faction_color
	mesh_material.emission_energy_multiplier = 2.0
	mesh.material = mesh_material
	
	particles.draw_pass_1 = mesh
	
	add_child(particles)
	
	# Auto-remove after particles finish
	var timer := get_tree().create_timer(1.5)
	timer.timeout.connect(func(): particles.queue_free())
