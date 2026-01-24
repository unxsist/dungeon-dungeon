shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_burley, specular_schlick_ggx;

// Texture inputs
uniform sampler2D albedo_texture : source_color, filter_linear_mipmap, repeat_enable;
uniform float texture_scale : hint_range(0.1, 4.0) = 1.0;

// Tint color for subtle color adjustment
uniform vec4 tint_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float tint_strength : hint_range(0.0, 1.0) = 0.0;

// Material properties
uniform float roughness : hint_range(0.0, 1.0) = 0.85;
uniform float metallic : hint_range(0.0, 1.0) = 0.0;

// Normal map settings
uniform float normal_strength : hint_range(0.0, 3.0) = 1.2;
uniform float normal_sample_offset : hint_range(0.001, 0.02) = 0.005;

// Procedural deformation settings (for organic wall feel)
uniform float deformation_strength : hint_range(0.0, 2.0) = 0.5;
uniform float noise_scale : hint_range(0.1, 2.0) = 0.3;
uniform float procedural_blend : hint_range(0.0, 1.0) = 0.3;

// Per-tile variation
uniform float brightness_variation : hint_range(0.0, 0.2) = 0.08;

// Top face UV variation (smooth transitions)
uniform float top_rotation_variation : hint_range(0.0, 1.0) = 0.3;
uniform float top_offset_variation : hint_range(0.0, 0.3) = 0.15;

// Triplanar blend sharpness
uniform float triplanar_sharpness : hint_range(1.0, 16.0) = 4.0;

// World position and normal
varying vec3 world_pos;
varying vec3 world_normal;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

// Hash functions
float hash2(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

vec2 hash2_vec(vec2 p) {
	return vec2(
		fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123),
		fract(sin(dot(p, vec2(269.5, 183.3))) * 43758.5453123)
	);
}

// Smooth noise function (value noise)
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

// Smooth 2D noise
vec2 noise2(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	
	vec2 a = hash2_vec(i);
	vec2 b = hash2_vec(i + vec2(1.0, 0.0));
	vec2 c = hash2_vec(i + vec2(0.0, 1.0));
	vec2 d = hash2_vec(i + vec2(1.0, 1.0));
	
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

// Fractal Brownian Motion
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

// Rotate UV around a point
vec2 rotate_uv(vec2 uv, float angle, vec2 center) {
	float s = sin(angle);
	float c = cos(angle);
	uv -= center;
	return vec2(uv.x * c - uv.y * s, uv.x * s + uv.y * c) + center;
}

// Get smooth rotation for top face
float get_smooth_rotation(vec2 world_xz) {
	float rot_noise = noise(world_xz * 0.12 + vec2(500.0, 500.0));
	return (rot_noise - 0.5) * 2.0 * 3.14159 * top_rotation_variation;
}

// Get smooth offset for top face
vec2 get_smooth_offset(vec2 world_xz) {
	vec2 offset_noise = noise2(world_xz * 0.1 + vec2(200.0, 300.0));
	return (offset_noise - 0.5) * 2.0 * top_offset_variation;
}

// Get luminance for height derivation
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

// Calculate triplanar blend weights
vec3 get_triplanar_weights(vec3 normal) {
	vec3 weights = abs(normal);
	weights = pow(weights, vec3(triplanar_sharpness));
	weights /= (weights.x + weights.y + weights.z);
	return weights;
}

void fragment() {
	// Triplanar blend weights based on world normal
	vec3 blend = get_triplanar_weights(world_normal);
	
	// Calculate base UVs for each axis projection
	float scale = texture_scale / 4.0;
	vec2 uv_x = world_pos.zy * scale;  // YZ plane (side faces facing X)
	vec2 uv_z = world_pos.xy * scale;  // XY plane (side faces facing Z)
	
	// Top face UV with smooth rotation/offset variation
	vec2 base_uv_y = world_pos.xz * scale;
	float rotation = get_smooth_rotation(world_pos.xz);
	vec2 rotated_uv = rotate_uv(base_uv_y, rotation, base_uv_y);
	vec2 offset = get_smooth_offset(world_pos.xz);
	vec2 uv_y = rotated_uv + offset;
	
	// Sample texture with triplanar projection
	vec3 tex_x = texture(albedo_texture, uv_x).rgb;
	vec3 tex_y = texture(albedo_texture, uv_y).rgb;
	vec3 tex_z = texture(albedo_texture, uv_z).rgb;
	
	// Blend textures based on normal direction
	vec3 base_color = tex_x * blend.x + tex_y * blend.y + tex_z * blend.z;
	
	// Apply tint
	base_color = mix(base_color, tint_color.rgb * base_color, tint_strength);
	
	// Per-tile brightness variation
	float brightness_noise = noise(world_pos.xz * 0.2 + vec2(800.0, 900.0));
	float brightness_offset = (brightness_noise - 0.5) * 2.0 * brightness_variation;
	base_color *= (1.0 + brightness_offset);
	
	ALBEDO = base_color;
	ROUGHNESS = roughness;
	METALLIC = metallic;
	
	// Derive normals with triplanar projection
	vec3 norm_x = derive_texture_normal(uv_x);
	vec3 norm_y = derive_texture_normal(uv_y);
	vec3 norm_z = derive_texture_normal(uv_z);
	
	// Blend texture normals
	vec3 texture_normal = norm_x * blend.x + norm_y * blend.y + norm_z * blend.z;
	
	// Add procedural variation
	vec2 proc_uv = uv_y;
	if (blend.x > blend.y && blend.x > blend.z) {
		proc_uv = uv_x;
	} else if (blend.z > blend.y) {
		proc_uv = uv_z;
	}
	vec3 procedural_normal = derive_procedural_normal(proc_uv * 4.0, deformation_strength);
	
	// Blend texture and procedural normals
	vec3 tex_n = texture_normal * 2.0 - 1.0;
	vec3 proc_n = procedural_normal * 2.0 - 1.0;
	
	vec3 blended_normal = normalize(vec3(
		tex_n.xy * (1.0 - procedural_blend) + proc_n.xy * procedural_blend,
		tex_n.z * proc_n.z
	));
	
	NORMAL_MAP = blended_normal * 0.5 + 0.5;
	NORMAL_MAP_DEPTH = 1.0;
}
