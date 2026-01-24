shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded;

uniform vec4 inner_color : source_color = vec4(0.0, 0.0, 0.0, 0.0);
uniform vec4 outer_color : source_color = vec4(0.15, 0.08, 0.04, 1.0);
uniform float fade_distance : hint_range(1.0, 50.0) = 12.0;

uniform vec3 bounds_min = vec3(0.0, 0.0, 0.0);
uniform vec3 bounds_max = vec3(40.0, 0.0, 40.0);

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	// Distance outside the map bounds on XZ plane
	float dx = 0.0;
	if (world_pos.x < bounds_min.x) {
		dx = bounds_min.x - world_pos.x;
	} else if (world_pos.x > bounds_max.x) {
		dx = world_pos.x - bounds_max.x;
	}

	float dz = 0.0;
	if (world_pos.z < bounds_min.z) {
		dz = bounds_min.z - world_pos.z;
	} else if (world_pos.z > bounds_max.z) {
		dz = world_pos.z - bounds_max.z;
	}

	float distance_outside = max(dx, dz);
	float t = clamp(distance_outside / max(fade_distance, 0.001), 0.0, 1.0);

	vec3 color = mix(inner_color.rgb, outer_color.rgb, t);
	float alpha = mix(inner_color.a, outer_color.a, t);

	ALBEDO = color;
	ALPHA = alpha;
}
