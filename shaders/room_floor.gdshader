shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

// Room type color
uniform vec4 room_color : source_color = vec4(0.6, 0.4, 0.3, 1.0);
uniform float color_mix : hint_range(0.0, 1.0) = 0.4;

// Base texture (claimed floor as base)
uniform sampler2D albedo_texture : source_color, filter_linear_mipmap, repeat_enable;

// Material properties
uniform float roughness : hint_range(0.0, 1.0) = 0.75;
uniform float metallic : hint_range(0.0, 1.0) = 0.0;

// Subtle emission for room identification
uniform float emission_strength : hint_range(0.0, 0.3) = 0.05;

// Normal map derived from texture
uniform float normal_strength : hint_range(0.0, 3.0) = 1.2;
uniform float normal_sample_offset : hint_range(0.001, 0.01) = 0.003;

// Procedural deformation
uniform float deformation_strength : hint_range(0.0, 2.0) = 0.5;
uniform float noise_scale : hint_range(0.1, 2.0) = 0.4;
uniform float procedural_blend : hint_range(0.0, 1.0) = 0.3;

// Per-tile variation
uniform float brightness_variation : hint_range(0.0, 0.15) = 0.08;

// Border settings
// Edge flags packed into a vec4: x=north, y=east, z=south, w=west (1.0 = edge, 0.0 = no edge)
uniform vec4 edge_flags = vec4(0.0, 0.0, 0.0, 0.0);
uniform float border_width : hint_range(0.05, 0.4) = 0.15;
uniform float border_softness : hint_range(0.01, 0.2) = 0.08;
uniform float border_darkness : hint_range(0.0, 1.0) = 0.6;
uniform float border_noise_scale : hint_range(1.0, 10.0) = 4.0;
uniform float border_noise_strength : hint_range(0.0, 0.15) = 0.08;

varying float tile_seed;
varying vec3 world_pos;

void vertex() {
	tile_seed = UV2.x;
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float hash(float n) {
	return fract(sin(n) * 43758.5453123);
}

float hash2(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	
	float a = hash2(i);
	float b = hash2(i + vec2(1.0, 0.0));
	float c = hash2(i + vec2(0.0, 1.0));
	float d = hash2(i + vec2(1.0, 1.0));
	
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

float fbm(vec2 p) {
	float value = 0.0;
	float amplitude = 0.5;
	float frequency = 1.0;
	float max_value = 0.0;
	
	for (int i = 0; i < 3; i++) {
		value += amplitude * noise(p * frequency);
		max_value += amplitude;
		amplitude *= 0.5;
		frequency *= 2.0;
	}
	
	return value / max_value;
}

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

float get_height(vec2 uv) {
	vec3 color = texture(albedo_texture, uv).rgb;
	return dot(color, vec3(0.299, 0.587, 0.114));
}

vec3 derive_normal(vec2 uv) {
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

// Calculate border intensity based on edge flags and UV position
float calculate_border(vec2 uv, vec2 world_xz) {
	float border = 0.0;
	
	// Add noise to make border rugged (using world coords for consistency across tiles)
	float edge_noise = (fbm(world_xz * border_noise_scale) - 0.5) * 2.0 * border_noise_strength;
	
	// Check each edge
	// North edge (UV.y = 0)
	if (edge_flags.x > 0.5) {
		float dist = uv.y;
		float adjusted_width = border_width + edge_noise;
		float edge_border = 1.0 - smoothstep(adjusted_width - border_softness, adjusted_width + border_softness, dist);
		border = max(border, edge_border);
	}
	
	// East edge (UV.x = 1)
	if (edge_flags.y > 0.5) {
		float dist = 1.0 - uv.x;
		float adjusted_width = border_width + edge_noise;
		float edge_border = 1.0 - smoothstep(adjusted_width - border_softness, adjusted_width + border_softness, dist);
		border = max(border, edge_border);
	}
	
	// South edge (UV.y = 1)
	if (edge_flags.z > 0.5) {
		float dist = 1.0 - uv.y;
		float adjusted_width = border_width + edge_noise;
		float edge_border = 1.0 - smoothstep(adjusted_width - border_softness, adjusted_width + border_softness, dist);
		border = max(border, edge_border);
	}
	
	// West edge (UV.x = 0)
	if (edge_flags.w > 0.5) {
		float dist = uv.x;
		float adjusted_width = border_width + edge_noise;
		float edge_border = 1.0 - smoothstep(adjusted_width - border_softness, adjusted_width + border_softness, dist);
		border = max(border, edge_border);
	}
	
	// Handle corners - if two adjacent edges are borders, darken the corner more
	// Northwest corner
	if (edge_flags.x > 0.5 && edge_flags.w > 0.5) {
		float corner_dist = length(uv);
		float adjusted_width = border_width * 1.2 + edge_noise;
		float corner_border = 1.0 - smoothstep(adjusted_width - border_softness, adjusted_width + border_softness, corner_dist);
		border = max(border, corner_border);
	}
	
	// Northeast corner
	if (edge_flags.x > 0.5 && edge_flags.y > 0.5) {
		float corner_dist = length(vec2(1.0 - uv.x, uv.y));
		float adjusted_width = border_width * 1.2 + edge_noise;
		float corner_border = 1.0 - smoothstep(adjusted_width - border_softness, adjusted_width + border_softness, corner_dist);
		border = max(border, corner_border);
	}
	
	// Southeast corner
	if (edge_flags.z > 0.5 && edge_flags.y > 0.5) {
		float corner_dist = length(vec2(1.0 - uv.x, 1.0 - uv.y));
		float adjusted_width = border_width * 1.2 + edge_noise;
		float corner_border = 1.0 - smoothstep(adjusted_width - border_softness, adjusted_width + border_softness, corner_dist);
		border = max(border, corner_border);
	}
	
	// Southwest corner
	if (edge_flags.z > 0.5 && edge_flags.w > 0.5) {
		float corner_dist = length(vec2(uv.x, 1.0 - uv.y));
		float adjusted_width = border_width * 1.2 + edge_noise;
		float corner_border = 1.0 - smoothstep(adjusted_width - border_softness, adjusted_width + border_softness, corner_dist);
		border = max(border, corner_border);
	}
	
	return clamp(border, 0.0, 1.0);
}

void fragment() {
	// Sample base texture
	vec4 tex = texture(albedo_texture, UV);
	
	// Mix with room color
	vec3 base_color = mix(tex.rgb, room_color.rgb * tex.rgb, color_mix);
	
	// Also tint toward room color for a more distinct look
	base_color = mix(base_color, room_color.rgb * 0.8, color_mix * 0.3);
	
	// Per-tile brightness variation
	float brightness_offset = (hash(tile_seed) - 0.5) * 2.0 * brightness_variation;
	base_color *= (1.0 + brightness_offset);
	
	// Apply border darkening
	float border = calculate_border(UV, world_pos.xz);
	base_color *= mix(1.0, 1.0 - border_darkness, border);
	
	ALBEDO = base_color;
	ROUGHNESS = roughness;
	METALLIC = metallic;
	
	// Subtle room glow (reduced in border areas)
	EMISSION = room_color.rgb * emission_strength * (1.0 - border * 0.5);
	
	// Normal mapping
	vec3 texture_normal = derive_normal(UV);
	vec3 procedural_normal = derive_procedural_normal(world_pos.xz, deformation_strength);
	
	vec3 tex_n = texture_normal * 2.0 - 1.0;
	vec3 proc_n = procedural_normal * 2.0 - 1.0;
	
	vec3 blended_normal = normalize(vec3(
		tex_n.xy * (1.0 - procedural_blend) + proc_n.xy * procedural_blend,
		tex_n.z * proc_n.z
	));
	
	NORMAL_MAP = blended_normal * 0.5 + 0.5;
	NORMAL_MAP_DEPTH = 1.0;
}
