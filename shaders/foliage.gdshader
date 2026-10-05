shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_burley;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform vec3 tint : source_color = vec3(1.0);
uniform float alpha_cut = 0.45;
uniform float wind_strength = 0.12;
uniform float wind_speed = 1.3;
uniform float translucency = 0.5;
uniform float fade_start = 0.0;
uniform float fade_end = 0.0;
uniform bool is_grass = false;
uniform float near_fade = 3.0;

varying float v_rand;
varying float v_ao;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float inst = hash(MODEL_MATRIX[3].xz);
	v_rand = fract(inst + COLOR.b);
	v_ao = COLOR.g;
	float sway = COLOR.r;
	float t = TIME * wind_speed + inst * 6.28;
	vec3 wind = vec3(sin(t + wp.x * 0.05), 0.0, cos(t * 0.8 + wp.z * 0.05)) * wind_strength * sway;
	wind += vec3(sin(TIME * 4.0 + wp.x * 0.7 + wp.y), 0.0, cos(TIME * 3.3 + wp.z * 0.7)) * wind_strength * 0.25 * sway * sway;
	VERTEX += (inverse(mat3(MODEL_MATRIX)) * wind);
}

void fragment() {
	vec4 a = texture(albedo_tex, UV);
	vec2 tuv = UV * vec2(textureSize(albedo_tex, 0));
	float lod = max(0.0, 0.5 * log2(max(dot(dFdx(tuv), dFdx(tuv)), dot(dFdy(tuv), dFdy(tuv)))));
	a.a *= 1.0 + lod * 0.3;
	if (a.a < alpha_cut) {
		discard;
	}
	vec3 col = a.rgb * tint;
	col *= mix(vec3(0.85, 0.95, 0.8), vec3(1.1, 1.05, 0.85), v_rand);
	col *= mix(0.55, 1.0, v_ao);
	float dist = length(VERTEX);
	if (fade_end > 0.0 && dist > fade_end) {
		discard;
	}
	if (near_fade > 0.0) {
		float dither = fract(dot(FRAGCOORD.xy, vec2(0.75, 0.375)) + fract(FRAGCOORD.y * 0.5) * 0.5);
		if (dist < near_fade * (0.35 + 0.65 * dither)) {
			discard;
		}
	}
	ALBEDO = col;
	ROUGHNESS = 0.8;
	SPECULAR = 0.25;
	BACKLIGHT = col * translucency;
	if (!FRONT_FACING) {
		NORMAL = -NORMAL;
	}
}
