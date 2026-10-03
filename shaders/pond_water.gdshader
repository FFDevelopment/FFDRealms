shader_type spatial;
render_mode cull_disabled;

// Opaque water: no screen/depth textures, SSR, refraction, transparency or glow.
// The water plane and shore collision remain exactly where the original build put them.
uniform sampler2D ripple_map : filter_linear_mipmap, repeat_enable;
uniform sampler2D ripple_normal : hint_normal, filter_linear_mipmap, repeat_enable;
uniform bool use_normal_map = true;
uniform vec2 pond_size = vec2(12.0, 11.0);

void vertex() {
	VERTEX.y += sin(VERTEX.x * 2.0 + TIME) * 0.025;
}

void fragment() {
	vec2 near_edge = min(UV, vec2(1.0) - UV) * pond_size;
	float bank_distance = min(near_edge.x, near_edge.y);
	float shallow = 1.0 - smoothstep(0.0, 1.3, bank_distance);
	vec2 flow_a = UV * vec2(3.0, 2.75) + TIME * vec2(0.008, -0.006);
	vec2 flow_b = UV * vec2(2.0, 2.25) + TIME * vec2(-0.005, 0.009);
	float ripple = (texture(ripple_map, flow_a).r + texture(ripple_map, flow_b).r) * 0.5;
	vec3 deep_color = vec3(0.075, 0.170, 0.195);
	vec3 bank_color = vec3(0.125, 0.235, 0.230);
	ALBEDO = mix(deep_color, bank_color, shallow) + (ripple - 0.5) * 0.032;
	ROUGHNESS = 0.75;
	SPECULAR = 0.12;
	if (use_normal_map) {
		vec3 first = texture(ripple_normal, flow_a).rgb * 2.0 - 1.0;
		vec3 second = texture(ripple_normal, flow_b).rgb * 2.0 - 1.0;
		NORMAL_MAP = normalize(vec3((first.xy + second.xy) * 0.5, 1.0)) * 0.5 + 0.5;
		NORMAL_MAP_DEPTH = 0.35;
	}
}
