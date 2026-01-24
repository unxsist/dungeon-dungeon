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

// Procedural deformation settings (for dungeon floor feel)
uniform float deformation_strength : hint_range(0.0, 2.0) = 0.6;
uniform float noise_scale : hint_range(0.1, 2.0) = 0.4;
uniform float procedural_blend : hint_range(0.0, 1.0) = 0.4;  // Blend between texture and procedural normals

// Per-tile variation (passed via UV2.x)
uniform float brightness_variation : hint_range(0.0, 0.15) = 0.06;
uniform float saturation_variation : hint_range(0.0, 0.15) = 0.04;

varying float tile_seed;
varying vec3 world_pos;

void vertex() {
	// Read per-tile seed from UV2.x (set during mesh generation)
	tile_seed = UV2.x;
	// Pass world position for seamless procedural noise
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

// Simple hash function for pseudo-random values
float hash(float n) {
	return fract(sin(n) * 43758.5453123);
}

// Hash for 2D input (used for procedural noise)
float hash2(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

// Smooth noise function (value noise)
float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	
	// Cubic Hermite interpolation (smoothstep)
	vec2 u = f * f * (3.0 - 2.0 * f);
	
	// Four corners
	float a = hash2(i);
	float b = hash2(i + vec2(1.0, 0.0));
	float c = hash2(i + vec2(0.0, 1.0));
	float d = hash2(i + vec2(1.0, 1.0));
	
	// Bilinear interpolation
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

// Fractal Brownian Motion for organic-looking noise
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

// Derive normal from procedural height field
vec3 derive_procedural_normal(vec2 pos, float strength) {
	float epsilon = 0.05;
	
	// Sample heights around current position
	float h_center = fbm(pos * noise_scale);
	float h_right = fbm((pos + vec2(epsilon, 0.0)) * noise_scale);
	float h_up = fbm((pos + vec2(0.0, epsilon)) * noise_scale);
	
	// Calculate gradients
	float dx = (h_right - h_center) / epsilon;
	float dz = (h_up - h_center) / epsilon;
	
	// Construct normal vector (Y-up coordinate system)
	vec3 normal = normalize(vec3(-dx * strength, 1.0, -dz * strength));
	
	// Convert to tangent space normal map format [0,1]
	return normal * 0.5 + 0.5;
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
	
	// Derive normal map from texture luminance
	vec3 texture_normal = derive_normal(UV);
	
	// Derive procedural normal from world-space noise (seamless across tiles)
	vec3 procedural_normal = derive_procedural_normal(world_pos.xz, deformation_strength);
	
	// Blend texture-derived and procedural normals
	// Both are in [0,1] range, convert to [-1,1], blend, then convert back
	vec3 tex_n = texture_normal * 2.0 - 1.0;
	vec3 proc_n = procedural_normal * 2.0 - 1.0;
	
	// Blend using RNM (Reoriented Normal Mapping) for better results
	vec3 blended_normal = normalize(vec3(
		tex_n.xy * (1.0 - procedural_blend) + proc_n.xy * procedural_blend,
		tex_n.z * proc_n.z
	));
	
	// Convert back to [0,1] range
	NORMAL_MAP = blended_normal * 0.5 + 0.5;
	NORMAL_MAP_DEPTH = 1.0;
}
