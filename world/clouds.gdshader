shader_type spatial;
// Cheap blocky cloud layer. Two octaves of value noise sampled on an 8 m grid (blocky edges),
// softened with one unquantised octave, drifting with the wind. No texture reads, no lighting,
// no loops. Fades out toward the plane edges so the horizon stays clear.
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix, fog_disabled;

uniform vec4 cloud_tint : source_color = vec4(1.0, 0.98, 0.95, 1.0);
uniform float coverage : hint_range(0.0, 1.0) = 0.5;
uniform float opacity : hint_range(0.0, 1.0) = 0.9;
uniform float cell_size = 8.0;
uniform float feature_size = 56.0;
uniform vec2 wind_direction = vec2(1.0, 0.35);
uniform float wind_speed = 0.8;
uniform float half_extent = 300.0;

varying vec3 world_pos;
varying vec2 plane_xz;

float hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x),
			mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

void vertex() {
	vec4 world = MODEL_MATRIX * vec4(VERTEX, 1.0);
	world_pos = world.xyz;
	plane_xz = VERTEX.xz / half_extent;
}

void fragment() {
	// Noise is sampled at the cell origin, so every 8 m cell is one block. The wind moves the
	// sample position, not the grid, and the plane follows the camera, so the pattern stays put.
	vec2 wind = wind_direction * wind_speed * TIME;
	vec2 cell_origin = floor(world_pos.xz / cell_size) * cell_size;
	vec2 q = (cell_origin + wind) / feature_size;
	float blocky = 0.65 * value_noise(q) + 0.35 * value_noise(q * 2.3 + vec2(17.0, 9.0));
	float smooth_n = value_noise((world_pos.xz + wind) / feature_size);
	float n = mix(blocky, smooth_n, 0.2);

	float threshold = mix(0.74, 0.36, coverage);
	float body = smoothstep(threshold - 0.05, threshold + 0.05, n);
	float core = smoothstep(threshold, threshold + 0.25, n);
	vec3 base_shade = cloud_tint.rgb * vec3(0.8, 0.85, 0.92);

	float edge_fade = 1.0 - smoothstep(0.55, 1.0, max(abs(plane_xz.x), abs(plane_xz.y)));

	ALBEDO = mix(base_shade, cloud_tint.rgb, core);
	ALPHA = body * edge_fade * opacity;
}
