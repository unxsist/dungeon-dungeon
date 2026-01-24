shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

// Base material properties
uniform vec4 albedo_color : source_color = vec4(0.5, 0.5, 0.5, 1.0);
uniform float roughness : hint_range(0.0, 1.0) = 0.8;
uniform float metallic : hint_range(0.0, 1.0) = 0.0;

// Fog of war states: 0 = hidden, 1 = explored, 2 = visible
uniform int visibility_state = 2;

// Fog colors
uniform vec4 hidden_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform vec4 explored_tint : source_color = vec4(0.3, 0.3, 0.35, 1.0);

// Hidden tiles are fully black
// Explored tiles are desaturated and darkened
// Visible tiles are normal

void fragment() {
	vec3 final_color = albedo_color.rgb;
	float final_roughness = roughness;
	
	if (visibility_state == 0) {
		// Hidden - completely black
		final_color = hidden_color.rgb;
		final_roughness = 1.0;
	} else if (visibility_state == 1) {
		// Explored - desaturated and darkened
		// Convert to grayscale
		float gray = dot(final_color, vec3(0.299, 0.587, 0.114));
		vec3 grayscale = vec3(gray);
		
		// Mix with explored tint
		final_color = mix(grayscale, explored_tint.rgb, 0.5) * 0.5;
		final_roughness = min(roughness + 0.2, 1.0);
	}
	// visibility_state == 2 (visible) - use normal color
	
	ALBEDO = final_color;
	ROUGHNESS = final_roughness;
	METALLIC = metallic;
}
