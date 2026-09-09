shader_type spatial;
render_mode cull_disabled, shadows_disabled;

uniform sampler2D metal_texture : source_color, filter_linear_mipmap, repeat_enable;
uniform vec3 color : source_color = vec3(0.337, 0.655, 0.784);
uniform float metallic_value : hint_range(0.0, 1.0) = 0.8;
uniform float roughness_value : hint_range(0.0, 1.0) = 0.4;
uniform float specular_value : hint_range(0.0, 1.0) = 0.5;
uniform float texture_influence : hint_range(0.0, 1.0) = 1.0;
uniform bool triplanar = false;
uniform float triplanar_scale = 1.0;

varying vec3 obj_pos;
varying vec3 obj_normal;

void vertex() {
	obj_pos = VERTEX;
	obj_normal = NORMAL;
}

void fragment() {
	vec3 tex;
	if (triplanar) {
		vec3 bw = abs(normalize(obj_normal));
		bw /= (bw.x + bw.y + bw.z);
		vec3 sx = texture(metal_texture, obj_pos.zy * triplanar_scale).rgb;
		vec3 sy = texture(metal_texture, obj_pos.xz * triplanar_scale).rgb;
		vec3 sz = texture(metal_texture, obj_pos.xy * triplanar_scale).rgb;
		tex = sx * bw.x + sy * bw.y + sz * bw.z;
	} else {
		tex = texture(metal_texture, UV).rgb;
	}
	// Overlay blend to tint the metal texture.
	vec3 blended;
	for (int i = 0; i < 3; i++) {
		if (tex[i] < 0.5) {
			blended[i] = 2.0 * tex[i] * color[i];
		} else {
			blended[i] = 1.0 - 2.0 * (1.0 - tex[i]) * (1.0 - color[i]);
		}
	}
	ALBEDO = mix(color, blended, texture_influence);
	METALLIC = metallic_value;
	ROUGHNESS = roughness_value;
	SPECULAR = specular_value;
	if (!FRONT_FACING) {
		NORMAL = -NORMAL;
	}
}
