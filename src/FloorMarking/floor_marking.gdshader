shader_type spatial;
render_mode unshaded, cull_disabled;

uniform vec4 primary_color : source_color = vec4(0.95, 0.72, 0.02, 1.0);
uniform vec4 secondary_color : source_color = vec4(0.1, 0.1, 0.1, 1.0);
// 0 = solid, 1 = hazard diagonals, 2 = dashed line, 3 = border outline, 4 = straight stripes.
uniform int style = 1;
uniform float stripe_size = 0.3;
uniform float border_width = 0.1;
uniform vec2 marking_size = vec2(2.0, 8.0);

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec4 col = primary_color;

	if (style == 1) {
		// World-space diagonals: neighbouring quads share phase, so corners
		// (even overlapping ones) read as one continuous hazard band.
		float t = fract((world_pos.x + world_pos.z) / (stripe_size * 2.0));
		col = t < 0.5 ? primary_color : secondary_color;
	} else if (style == 2) {
		// Dashes run along the longer axis, centred on the shorter one.
		bool long_x = marking_size.x >= marking_size.y;
		float along = long_x ? world_pos.x : world_pos.z;
		float across = long_x ? UV.y : UV.x;
		float dash = fract(along / (stripe_size * 2.0));
		float center = step(0.4, across) * step(across, 0.6);
		col = mix(primary_color, secondary_color, step(dash, 0.5) * center);
	} else if (style == 3) {
		// Outline only; the interior is discarded so the floor shows through.
		vec2 bw = vec2(border_width) / marking_size;
		bool in_border = UV.x < bw.x || UV.x > 1.0 - bw.x || UV.y < bw.y || UV.y > 1.0 - bw.y;
		if (!in_border) {
			discard;
		}
		col = primary_color;
	} else if (style == 4) {
		bool long_x = marking_size.x >= marking_size.y;
		float along_m = long_x ? UV.x * marking_size.x : UV.y * marking_size.y;
		float t = fract(along_m / (stripe_size * 2.0));
		col = t < 0.5 ? primary_color : secondary_color;
	}

	if (col.a < 0.5) {
		discard;
	}
	ALBEDO = col.rgb;
}
