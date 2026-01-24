shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_burley, specular_schlick_ggx;

// Base material properties
uniform vec4 albedo_color : source_color = vec4(0.5, 0.5, 0.5, 1.0);
uniform float roughness : hint_range(0.0, 1.0) = 0.8;
uniform float metallic : hint_range(0.0, 1.0) = 0.0;

// Overlay-only mode (for material_overlay usage)
uniform bool overlay_only = false;

// Highlight properties
uniform bool is_highlighted = false;
uniform vec4 highlight_color : source_color = vec4(1.0, 1.0, 0.0, 0.6);
uniform float pulse_speed : hint_range(0.5, 10.0) = 3.0;
uniform float pulse_intensity : hint_range(0.0, 1.0) = 0.4;
uniform float emission_strength : hint_range(0.0, 2.0) = 0.5;

// Selection properties (for area selection)
uniform bool is_selected = false;
uniform vec4 selection_color : source_color = vec4(0.3, 0.7, 1.0, 0.5);

// Edge highlight for better visibility
uniform bool show_edge = false;
uniform vec4 edge_color : source_color = vec4(1.0, 1.0, 1.0, 0.8);
uniform float edge_width : hint_range(0.01, 0.2) = 0.05;

// Hover border (shown on all faces)
uniform bool show_hover_border = false;
uniform vec4 hover_border_color : source_color = vec4(1.0, 1.0, 1.0, 0.8);
uniform float hover_border_width : hint_range(0.01, 0.15) = 0.08;

// Fog of war: 0 = hidden, 1 = explored, 2 = visible
uniform int visibility_state = 2;
uniform vec4 explored_tint : source_color = vec4(0.3, 0.3, 0.35, 1.0);

varying vec3 world_vertex;
varying vec2 tile_uv;

void vertex() {
	world_vertex = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	tile_uv = UV;
}

void fragment() {
	// Base color
	vec3 base_color = overlay_only ? vec3(0.0) : albedo_color.rgb;
	vec3 final_emission = vec3(0.0);
	float final_roughness = roughness;
	float effect_mask = 0.0;
	
	// Apply fog of war first
	if (visibility_state == 0) {
		// Hidden - completely black
		ALBEDO = vec3(0.02, 0.02, 0.03);
		ROUGHNESS = 1.0;
		METALLIC = 0.0;
		EMISSION = vec3(0.0);
		ALPHA = overlay_only ? 0.0 : 1.0;
	} else {
		if (visibility_state == 1) {
			// Explored - desaturated and darkened
			float gray = dot(base_color, vec3(0.299, 0.587, 0.114));
			vec3 grayscale = vec3(gray);
			base_color = mix(grayscale, explored_tint.rgb, 0.5) * 0.5;
			final_roughness = min(roughness + 0.2, 1.0);
		}
		// visibility_state == 2 (visible) - use normal color
		
		// Calculate pulse
		float pulse = sin(TIME * pulse_speed) * 0.5 + 0.5;
		float pulse_factor = mix(1.0 - pulse_intensity, 1.0, pulse);
		
		// Apply highlight (allow for explored/visible tiles)
		if (is_highlighted && visibility_state != 0) {
			// Pulse the highlight
			float highlight_amount = highlight_color.a * pulse_factor;
			base_color = mix(base_color, highlight_color.rgb, highlight_amount);
			
			// Add emission for glow effect
			final_emission = highlight_color.rgb * emission_strength * pulse_factor;
			effect_mask = max(effect_mask, highlight_amount);
		}
		
		// Apply selection overlay (allow for explored/visible tiles)
		if (is_selected && visibility_state != 0) {
			float selection_amount = selection_color.a * (0.7 + 0.3 * pulse);
			base_color = mix(base_color, selection_color.rgb, selection_amount * 0.5);
			final_emission += selection_color.rgb * emission_strength * 0.5;
			effect_mask = max(effect_mask, selection_amount);
		}
		
		// Edge highlight - shown on all faces
		if (show_edge && visibility_state != 0) {
			float edge_x = smoothstep(0.0, edge_width, tile_uv.x) * smoothstep(0.0, edge_width, 1.0 - tile_uv.x);
			float edge_y = smoothstep(0.0, edge_width, tile_uv.y) * smoothstep(0.0, edge_width, 1.0 - tile_uv.y);
			float edge_factor = 1.0 - (edge_x * edge_y);
			
			if (edge_factor > 0.5) {
				base_color = mix(base_color, edge_color.rgb, edge_color.a * edge_factor);
				final_emission += edge_color.rgb * 0.3 * edge_factor;
				effect_mask = max(effect_mask, edge_color.a * edge_factor);
			}
		}
		
		// Hover border - shown on all faces
		if (show_hover_border && !is_highlighted && visibility_state != 0) {
			// Edge distance in UV space (0 at edge, 0.5 at center)
			float edge_dist = min(min(tile_uv.x, 1.0 - tile_uv.x), min(tile_uv.y, 1.0 - tile_uv.y));
			float border = 1.0 - smoothstep(0.0, hover_border_width, edge_dist);

			base_color = mix(base_color, hover_border_color.rgb, border * hover_border_color.a);
			final_emission += hover_border_color.rgb * 0.3 * border;
			effect_mask = max(effect_mask, hover_border_color.a * border);
		}
		
		ALBEDO = base_color;
		ROUGHNESS = final_roughness;
		METALLIC = metallic;
		EMISSION = final_emission;
		ALPHA = overlay_only ? clamp(effect_mask, 0.0, 1.0) : 1.0;
	}
}
