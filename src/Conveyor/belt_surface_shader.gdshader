shader_type spatial;
render_mode cull_disabled;

uniform sampler2D belt_texture : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D belt_texture_alt : source_color, filter_linear_mipmap, repeat_enable;
uniform bool use_alternate_texture = false;
uniform float Scale = 1.0;
uniform float BeltPosition = 0.0;
uniform vec4 ColorMix : source_color = vec4(1.0, 1.0, 1.0, 1.0);

void fragment() {
	// UV.x = along belt travel (0-1 normalized over full loop).
	// UV.y = across belt width (0-1).
	// Scale tiles the texture along the belt. BeltPosition scrolls it.
	vec2 uv = vec2(UV.y, (1.0 - UV.x) * Scale + BeltPosition);
	vec3 tex;
	if (use_alternate_texture) {
		tex = texture(belt_texture_alt, uv).rgb;
	} else {
		tex = texture(belt_texture, uv).rgb;
	}
	if (!FRONT_FACING) {
		NORMAL = -NORMAL;
	}
	ALBEDO = tex * ColorMix.rgb;
	ROUGHNESS = 0.85;
}
