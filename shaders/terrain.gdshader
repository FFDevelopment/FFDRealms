shader_type spatial;
// Opaque, Compatibility-friendly terrain; no screen/depth textures or tessellation.
uniform sampler2D land_tint : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D land_blend : filter_linear_mipmap, repeat_disable;
uniform sampler2D grass_map : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D path_map : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D stone_map : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D cobble_map : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D grass_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D path_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D stone_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D cobble_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform bool use_detail = true;
uniform bool use_normal_maps = true;

void fragment() {
    vec3 layers = texture(land_blend, UV2).rgb;
    vec4 weights = vec4(max(0.0, 1.0 - layers.r - layers.g - layers.b), layers);
    weights /= max(dot(weights, vec4(1.0)), 0.001);
    vec3 detail = vec3(1.0);
    if (use_detail) {
        detail = texture(grass_map, UV * 0.28).rgb * weights.x
            + texture(path_map, UV * 0.38).rgb * weights.y
            + texture(stone_map, UV * 0.56).rgb * weights.z
            + texture(cobble_map, UV * 0.22).rgb * weights.w;
    }
    ALBEDO = texture(land_tint, UV2).rgb * detail;
    ROUGHNESS = 0.97;
    SPECULAR = 0.16;
    if (use_normal_maps) {
        NORMAL_MAP = texture(grass_normal, UV * 0.28).rgb * weights.x
            + texture(path_normal, UV * 0.38).rgb * weights.y
            + texture(stone_normal, UV * 0.56).rgb * weights.z
            + texture(cobble_normal, UV * 0.22).rgb * weights.w;
        NORMAL_MAP_DEPTH = 0.48;
    }
}
