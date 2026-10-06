shader_type spatial;
render_mode blend_mix, depth_draw_always, cull_disabled, diffuse_burley, specular_schlick_ggx;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform sampler2D depth_tex : hint_depth_texture, filter_linear;
uniform sampler2D normal_a : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D normal_b : hint_normal, filter_linear_mipmap, repeat_enable;
uniform vec3 shallow_color : source_color = vec3(0.12, 0.32, 0.30);
uniform vec3 deep_color : source_color = vec3(0.02, 0.07, 0.10);
uniform vec3 foam_color : source_color = vec3(0.85, 0.88, 0.85);
uniform float wave_height = 0.35;
uniform float choppy = 1.0;
uniform float murk = 0.08;
uniform vec3 tint : source_color = vec3(1.0);

varying vec3 w_pos;

vec3 gerstner(vec2 p, vec2 dir, float amp, float wl, float t) {
	float k = 6.28318 / wl;
	float c = sqrt(9.8 / k);
	vec2 d = normalize(dir);
	float f = k * (dot(d, p) - c * t);
	return vec3(d.x * amp * cos(f) * 0.6, amp * sin(f), d.y * amp * cos(f) * 0.6);
}

void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 off = vec3(0.0);
	float t = TIME;
	off += gerstner(wp.xz, vec2(1.0, 0.3), wave_height, 22.0, t);
	off += gerstner(wp.xz, vec2(-0.4, 1.0), wave_height * 0.6, 13.0, t);
	off += gerstner(wp.xz, vec2(0.7, -0.8), wave_height * 0.35, 7.0, t);
	float fade = 1.0 - smoothstep(150.0, 600.0, length(wp.xz - (INV_VIEW_MATRIX[3].xz)));
	VERTEX += off * fade;
	w_pos = wp + off * fade;
}

void fragment() {
	vec2 uv_a = w_pos.xz * 0.045 + TIME * vec2(0.012, 0.008);
	vec2 uv_b = w_pos.xz * 0.11 - TIME * vec2(0.01, 0.015);
	vec3 na = texture(normal_a, uv_a).xyz;
	vec3 nb = texture(normal_b, uv_b).xyz;
	vec3 nm = normalize(mix(na, nb, 0.5) * 2.0 - 1.0);
	NORMAL_MAP = vec3(nm.xy * choppy * 0.5 + 0.5, 1.0);
	NORMAL_MAP_DEPTH = 0.7;
	float depth = textureLod(depth_tex, SCREEN_UV, 0.0).r;
	vec4 ndc = vec4(SCREEN_UV * 2.0 - 1.0, depth, 1.0);
	vec4 vpos = INV_PROJECTION_MATRIX * ndc;
	vpos.xyz /= vpos.w;
	float water_depth = max(0.0, -vpos.z + VERTEX.z);
	float d = 1.0 - exp(-water_depth * murk);
	vec2 refr_uv = SCREEN_UV + nm.xy * 0.02 * (1.0 - exp(-water_depth * 0.5));
	vec3 refr = textureLod(screen_tex, refr_uv, 0.0).rgb;
	vec3 water = mix(shallow_color, deep_color, smoothstep(0.0, 1.0, d));
	vec3 col = mix(refr * shallow_color * 2.2, water, clamp(d * 1.3, 0.0, 1.0));
	float foam = (1.0 - smoothstep(0.0, 0.9, water_depth)) * (0.55 + 0.45 * sin(TIME * 2.0 + w_pos.x * 0.7 + w_pos.z * 0.5));
	col = mix(col, foam_color, clamp(foam, 0.0, 1.0) * 0.6);
	if (!FRONT_FACING) {
		col = deep_color * 1.5;
	}
	ALBEDO = col * tint;
	ROUGHNESS = 0.04;
	METALLIC = 0.0;
	SPECULAR = 0.6;
	ALPHA = 1.0;
}
