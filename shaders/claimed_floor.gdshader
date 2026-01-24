shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

// Texture inputs
uniform sampler2D albedo_texture : source_color, filter_linear_mipmap, repeat_enable;

// Faction color mixing
uniform vec4 faction_color : source_color = vec4(0.3, 0.3, 0.5, 1.0);
uniform float faction_mix : hint_range(0.0, 1.0) = 0.25;
uniform float color_replace_strength : hint_range(0.0, 1.0) = 0.0;  // For replacing cyan with faction color

// Material properties
uniform float roughness : hint_range(0.0, 1.0) = 0.7;
uniform float metallic : hint_range(0.0, 1.0) = 0.0;

// Normal map derived from texture (Sobel filter)
uniform float normal_strength : hint_range(0.0, 3.0) = 1.5;
uniform float normal_sample_offset : hint_range(0.001, 0.01) = 0.003;

// Per-tile variation (passed via UV2.x)
uniform float brightness_variation : hint_range(0.0, 0.15) = 0.06;
uniform float saturation_variation : hint_range(0.0, 0.15) = 0.04;

varying float tile_seed;

void vertex() {
	// Read per-tile seed from UV2.x (set during mesh generation)
	tile_seed = UV2.x;
}

// Simple hash function for pseudo-random values
float hash(float n) {
	return fract(sin(n) * 43758.5453123);
}

// Adjust saturation of a color
vec3 adjust_saturation(vec3 color, float adjustment) {
	float gray = dot(color, vec3(0.299, 0.587, 0.114));
	return mix(vec3(gray), color, 1.0 + adjustment);
}

// Get luminance from color (used for height in normal derivation)
float get_height(vec2 uv) {
	vec3 color = texture(albedo_texture, uv).rgb;
	return dot(color, vec3(0.299, 0.587, 0.114));
}

// Derive normal map from albedo texture using Sobel filter
vec3 derive_normal(vec2 uv) {
	float offset = normal_sample_offset;
	
	// Sample heights in a 3x3 grid (Sobel kernel)
	float tl = get_height(uv + vec2(-offset, -offset));
	float t  = get_height(uv + vec2(0.0, -offset));
	float tr = get_height(uv + vec2(offset, -offset));
	float l  = get_height(uv + vec2(-offset, 0.0));
	float r  = get_height(uv + vec2(offset, 0.0));
	float bl = get_height(uv + vec2(-offset, offset));
	float b  = get_height(uv + vec2(0.0, offset));
	float br = get_height(uv + vec2(offset, offset));
	
	// Sobel filter for gradient
	float dx = (tr + 2.0 * r + br) - (tl + 2.0 * l + bl);
	float dy = (bl + 2.0 * b + br) - (tl + 2.0 * t + tr);
	
	// Construct normal (flip Y for correct orientation)
	vec3 normal = normalize(vec3(-dx * normal_strength, -dy * normal_strength, 1.0));
	
	// Convert from [-1,1] to [0,1] range for NORMAL_MAP
	return normal * 0.5 + 0.5;
}

void fragment() {
	// Sample albedo texture
	vec4 tex = texture(albedo_texture, UV);
	
	// Detect cyan/blue areas (the crystal) based on color
	// Cyan has high G and B, low R
	float cyan_amount = min(tex.g, tex.b) - tex.r * 0.5;
	cyan_amount = clamp(cyan_amount * 2.0, 0.0, 1.0);
	
	// Replace cyan areas with faction color (preserving luminance)
	float tex_luminance = dot(tex.rgb, vec3(0.299, 0.587, 0.114));
	vec3 replaced_color = faction_color.rgb * (tex_luminance * 1.5 + 0.3);
	
	// Blend between original and replaced based on cyan detection and strength
	vec3 base_color = mix(tex.rgb, replaced_color, cyan_amount * color_replace_strength);
	
	// Also apply subtle overall faction tint to non-crystal areas
	base_color = mix(base_color, faction_color.rgb * base_color, faction_mix * (1.0 - cyan_amount));
	
	// Per-tile variations using the seed
	float brightness_offset = (hash(tile_seed) - 0.5) * 2.0 * brightness_variation;
	float saturation_offset = (hash(tile_seed + 100.0) - 0.5) * 2.0 * saturation_variation;
	
	// Apply brightness variation
	base_color *= (1.0 + brightness_offset);
	
	// Apply saturation variation
	base_color = adjust_saturation(base_color, saturation_offset);
	
	ALBEDO = base_color;
	ROUGHNESS = roughness;
	METALLIC = metallic;
	
	// Derive and apply normal map from texture luminance
	NORMAL_MAP = derive_normal(UV);
	NORMAL_MAP_DEPTH = 1.0;
}
