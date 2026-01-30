shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

// Portal colors
uniform vec4 unclaimed_color : source_color = vec4(0.5, 0.2, 0.8, 1.0);  // Purple when unclaimed
uniform vec4 claimed_color : source_color = vec4(0.2, 0.8, 0.5, 1.0);    // Green when claimed

// Is the portal claimed?
uniform float is_claimed : hint_range(0.0, 1.0) = 0.0;

// Animation
uniform float time_scale : hint_range(0.1, 3.0) = 1.0;

// Material properties
uniform float roughness : hint_range(0.0, 1.0) = 0.3;
uniform float metallic : hint_range(0.0, 1.0) = 0.2;

// Emission/glow
uniform float emission_strength : hint_range(0.0, 5.0) = 2.0;
uniform float pulse_strength : hint_range(0.0, 1.0) = 0.3;

// Swirl effect
uniform float swirl_speed : hint_range(0.1, 3.0) = 0.5;
uniform float swirl_intensity : hint_range(0.0, 1.0) = 0.5;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

// Simple hash function
float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
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

// Fractal noise
float fbm(vec2 p) {
	float value = 0.0;
	float amplitude = 0.5;
	
	for (int i = 0; i < 4; i++) {
		value += amplitude * noise(p);
		p *= 2.0;
		amplitude *= 0.5;
	}
	
	return value;
}

void fragment() {
	// Current portal color based on claimed state
	vec4 portal_color = mix(unclaimed_color, claimed_color, is_claimed);
	
	// Center of the tile (assuming UV is 0-1 per tile)
	vec2 centered_uv = UV - 0.5;
	float dist_from_center = length(centered_uv);
	
	// Animated time
	float t = TIME * time_scale;
	
	// Swirl effect
	float angle = atan(centered_uv.y, centered_uv.x);
	float swirl = sin(angle * 4.0 + t * swirl_speed + dist_from_center * 10.0) * swirl_intensity;
	
	// Radial gradient (brighter in center)
	float radial = 1.0 - smoothstep(0.0, 0.5, dist_from_center);
	
	// Magical energy patterns using world position for seamless effect
	vec2 noise_pos = world_pos.xz * 0.5;
	float energy = fbm(noise_pos + vec2(t * 0.3, t * 0.2));
	energy += fbm(noise_pos * 2.0 - vec2(t * 0.5, 0.0)) * 0.5;
	energy = energy * 0.5 + 0.5;
	
	// Pulsing effect
	float pulse = sin(t * 2.0) * 0.5 + 0.5;
	pulse = mix(1.0, pulse, pulse_strength);
	
	// Combine effects
	float intensity = radial * (0.7 + energy * 0.3 + swirl * 0.2) * pulse;
	
	// Portal ring effect (brighter at edges)
	float ring = smoothstep(0.3, 0.4, dist_from_center) * smoothstep(0.5, 0.45, dist_from_center);
	intensity += ring * 0.5;
	
	// Base albedo - darker with magical tint
	vec3 base_color = portal_color.rgb * 0.3;
	base_color += energy * portal_color.rgb * 0.2;
	
	ALBEDO = base_color;
	ROUGHNESS = roughness;
	METALLIC = metallic;
	
	// Strong emission for magical glow
	vec3 emission = portal_color.rgb * intensity * emission_strength;
	
	// Add some sparkle/shimmer
	float sparkle = pow(noise(world_pos.xz * 10.0 + t), 8.0) * radial;
	emission += vec3(1.0) * sparkle * 2.0;
	
	EMISSION = emission;
}
