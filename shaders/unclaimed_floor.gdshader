shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

// Texture input
uniform sampler2D albedo_texture : source_color, filter_linear_mipmap, repeat_enable;
uniform float texture_scale : hint_range(0.5, 4.0) = 1.0;

// Tint color for subtle adjustment
uniform vec4 tint_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float tint_strength : hint_range(0.0, 0.5) = 0.0;

// Material properties
uniform float roughness : hint_range(0.0, 1.0) = 0.8;
uniform float metallic : hint_range(0.0, 1.0) = 0.0;

// Deformation/normal map settings (higher for messy sand look)
uniform float deformation_strength : hint_range(0.0, 3.0) = 1.5;
uniform float noise_scale : hint_range(0.1, 2.0) = 0.5;

// UV distortion for loose sand effect
uniform float uv_distortion_amount : hint_range(0.0, 0.3) = 0.15;
uniform float uv_distortion_scale : hint_range(0.1, 2.0) = 0.3;

// Per-tile rotation/offset variation
uniform float rotation_variation : hint_range(0.0, 1.0) = 0.4;  // Max rotation as fraction of PI
uniform float offset_variation : hint_range(0.0, 0.5) = 0.25;

// Normal map from texture
uniform float normal_strength : hint_range(0.0, 3.0) = 1.5;
uniform float normal_sample_offset : hint_range(0.001, 0.02) = 0.005;

// Per-tile brightness variation
uniform float brightness_variation : hint_range(0.0, 0.2) = 0.1;

// World position for seamless effects
varying vec3 world_pos;
varying vec2 tile_id;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	// Calculate tile ID for per-tile variation (tile size = 4.0)
	tile_id = floor(world_pos.xz / 4.0);
}

// Hash functions
float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

vec2 hash2(vec2 p) {
	return vec2(
		fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123),
		fract(sin(dot(p, vec2(269.5, 183.3))) * 43758.5453123)
	);
}

// Smooth noise
float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	
	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));
	
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

// Smooth 2D noise for UV distortion
vec2 noise2(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	
	vec2 a = hash2(i);
	vec2 b = hash2(i + vec2(1.0, 0.0));
	vec2 c = hash2(i + vec2(0.0, 1.0));
	vec2 d = hash2(i + vec2(1.0, 1.0));
	
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

// FBM for organic variation
float fbm(vec2 p) {
	float value = 0.0;
	float amplitude = 0.5;
	float frequency = 1.0;
	float max_value = 0.0;
	
	for (int i = 0; i < 4; i++) {
		value += amplitude * noise(p * frequency);
		max_value += amplitude;
		amplitude *= 0.5;
		frequency *= 2.0;
	}
	
	return value / max_value;
}

// Rotate UV around center
vec2 rotate_uv(vec2 uv, float angle, vec2 center) {
	float s = sin(angle);
	float c = cos(angle);
	uv -= center;
	return vec2(uv.x * c - uv.y * s, uv.x * s + uv.y * c) + center;
}

// Get smooth per-tile rotation using world-space noise (for seamless blending)
float get_smooth_rotation(vec2 world_xz) {
	// Use large-scale noise for gradual rotation changes
	float rot_noise = noise(world_xz * 0.15 + vec2(500.0, 500.0));
	return (rot_noise - 0.5) * 2.0 * 3.14159 * rotation_variation;
}

// Get smooth per-tile offset using world-space noise
vec2 get_smooth_offset(vec2 world_xz) {
	vec2 offset_noise = noise2(world_xz * 0.12 + vec2(200.0, 300.0));
	return (offset_noise - 0.5) * 2.0 * offset_variation;
}

// Get luminance for normal derivation
float get_height(vec2 uv) {
	vec3 color = texture(albedo_texture, uv).rgb;
	return dot(color, vec3(0.299, 0.587, 0.114));
}

// Derive normal from texture using Sobel filter
vec3 derive_texture_normal(vec2 uv) {
	float offset = normal_sample_offset;
	
	float tl = get_height(uv + vec2(-offset, -offset));
	float t  = get_height(uv + vec2(0.0, -offset));
	float tr = get_height(uv + vec2(offset, -offset));
	float l  = get_height(uv + vec2(-offset, 0.0));
	float r  = get_height(uv + vec2(offset, 0.0));
	float bl = get_height(uv + vec2(-offset, offset));
	float b  = get_height(uv + vec2(0.0, offset));
	float br = get_height(uv + vec2(offset, offset));
	
	float dx = (tr + 2.0 * r + br) - (tl + 2.0 * l + bl);
	float dy = (bl + 2.0 * b + br) - (tl + 2.0 * t + tr);
	
	vec3 normal = normalize(vec3(-dx * normal_strength, -dy * normal_strength, 1.0));
	return normal * 0.5 + 0.5;
}

// Derive normal from procedural noise
vec3 derive_procedural_normal(vec2 pos, float strength) {
	float epsilon = 0.05;
	
	float h_center = fbm(pos * noise_scale);
	float h_right = fbm((pos + vec2(epsilon, 0.0)) * noise_scale);
	float h_up = fbm((pos + vec2(0.0, epsilon)) * noise_scale);
	
	float dx = (h_right - h_center) / epsilon;
	float dz = (h_up - h_center) / epsilon;
	
	vec3 normal = normalize(vec3(-dx * strength, 1.0, -dz * strength));
	return normal * 0.5 + 0.5;
}

void fragment() {
	vec2 world_xz = world_pos.xz;
	
	// Base UV from world position (seamless tiling)
	vec2 base_uv = world_xz * texture_scale / 4.0;
	
	// Apply smooth UV distortion for loose sand effect
	vec2 distortion = (noise2(world_xz * uv_distortion_scale) - 0.5) * 2.0 * uv_distortion_amount;
	
	// Apply smooth rotation based on world position
	float rotation = get_smooth_rotation(world_xz);
	vec2 rotated_uv = rotate_uv(base_uv + distortion, rotation, base_uv);
	
	// Apply smooth offset
	vec2 offset = get_smooth_offset(world_xz);
	vec2 final_uv = rotated_uv + offset;
	
	// Sample texture
	vec4 tex = texture(albedo_texture, final_uv);
	vec3 base_color = tex.rgb;
	
	// Apply tint
	base_color = mix(base_color, tint_color.rgb * base_color, tint_strength);
	
	// Per-tile brightness variation using smooth noise
	float brightness_noise = noise(world_xz * 0.2 + vec2(800.0, 900.0));
	float brightness_offset = (brightness_noise - 0.5) * 2.0 * brightness_variation;
	base_color *= (1.0 + brightness_offset);
	
	ALBEDO = base_color;
	ROUGHNESS = roughness;
	METALLIC = metallic;
	
	// Derive normals from texture
	vec3 texture_normal = derive_texture_normal(final_uv);
	
	// Derive procedural normal for additional messy deformation
	vec3 procedural_normal = derive_procedural_normal(world_xz, deformation_strength);
	
	// Blend texture and procedural normals (more procedural for messy look)
	vec3 tex_n = texture_normal * 2.0 - 1.0;
	vec3 proc_n = procedural_normal * 2.0 - 1.0;
	
	// Heavier blend towards procedural for loose sand effect
	vec3 blended_normal = normalize(vec3(
		tex_n.xy * 0.4 + proc_n.xy * 0.6,
		tex_n.z * proc_n.z
	));
	
	NORMAL_MAP = blended_normal * 0.5 + 0.5;
	NORMAL_MAP_DEPTH = 1.0;
}
