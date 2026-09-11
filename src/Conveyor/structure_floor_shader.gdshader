shader_type spatial;
render_mode cull_disabled;

uniform sampler2D base_color_texture : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D normal_texture : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D orm_texture : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform vec3 color_tint : source_color = vec3(1.0, 1.0, 1.0);
uniform float brightness : hint_range(0.5, 6.0) = 4.0;
uniform float texture_scale : hint_range(0.1, 10.0) = 2.0;

void fragment() {
	vec2 uv = UV * texture_scale;
	ALBEDO = texture(base_color_texture, uv).rgb * color_tint * brightness;
	NORMAL_MAP = texture(normal_texture, uv).rgb;
	vec3 orm = texture(orm_texture, uv).rgb;
	AO = orm.r;
	ROUGHNESS = orm.g;
	METALLIC = orm.b;
	if (!FRONT_FACING) {
		NORMAL = -NORMAL;
	}
}
