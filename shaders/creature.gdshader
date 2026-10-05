shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

// Rest-pose attributes from the generator (skinning-stable texturing)
varying vec3 v_rest;
varying vec3 v_rnormal;
varying flat float v_region;

uniform vec3 color_main : source_color = vec3(0.35, 0.32, 0.25);
uniform vec3 color_belly : source_color = vec3(0.65, 0.6, 0.5);
uniform vec3 color_pattern : source_color = vec3(0.15, 0.13, 0.1);
uniform int pattern_type = 1; // 0 none, 1 stripes, 2 spots, 3 saddle bands, 4 mottled
uniform float pattern_scale = 1.0;
uniform float pattern_strength = 0.7;
uniform vec3 eye_color : source_color = vec3(0.85, 0.6, 0.1);
uniform vec3 tooth_color : source_color = vec3(0.85, 0.8, 0.68);
uniform vec3 keratin_color : source_color = vec3(0.18, 0.15, 0.12);
uniform vec3 top_color : source_color = vec3(0.35, 0.28, 0.2);
uniform vec3 bottom_color : source_color = vec3(0.25, 0.22, 0.18);
uniform vec3 boots_color : source_color = vec3(0.18, 0.13, 0.1);
uniform vec3 hair_color : source_color = vec3(0.12, 0.08, 0.05);
uniform vec3 glow_color : source_color = vec3(1.0, 0.25, 0.05);
uniform float corruption = 0.0;
uniform float glow = 0.0;
uniform float wet = 0.0;
uniform float tex_scale = 4.0; // texture repeats per meter (scaled by creature size)
uniform float bump_strength = 1.0;
uniform float bump_height = 0.008; // meters
uniform float roughness_base = 0.62;
uniform float hurt_flash = 0.0;
uniform float select_flash = 0.0;
uniform float body_scale = 1.0;
uniform sampler2D skin_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D wrinkle_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform float use_wrinkle = 0.0;

void vertex() {
	v_rest = CUSTOM0.xyz;
	v_region = CUSTOM0.w;
	v_rnormal = CUSTOM1.xyz;
}

vec4 triplanar(sampler2D t, vec3 p, vec3 n) {
	vec3 w = pow(abs(n), vec3(4.0));
	w /= (w.x + w.y + w.z + 1e-5);
	return texture(t, p.zy) * w.x + texture(t, p.xz) * w.y + texture(t, p.xy) * w.z;
}

float hash3(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float vnoise(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash3(i), hash3(i + vec3(1, 0, 0)), f.x), mix(hash3(i + vec3(0, 1, 0)), hash3(i + vec3(1, 1, 0)), f.x), f.y),
			mix(mix(hash3(i + vec3(0, 0, 1)), hash3(i + vec3(1, 0, 1)), f.x), mix(hash3(i + vec3(0, 1, 1)), hash3(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

void fragment() {
	int reg = int(v_region + 0.5);
	vec3 rp = v_rest / body_scale;
	vec3 rn = normalize(v_rnormal);
	float sc = tex_scale;
	vec4 sk = triplanar(skin_tex, v_rest * sc, rn);
	vec4 wk = triplanar(wrinkle_tex, v_rest * sc * 0.35, rn);
	float h = mix(sk.r, wk.r, use_wrinkle);
	float n1 = vnoise(rp * 3.0 * pattern_scale);
	float n2 = vnoise(rp * 9.0 * pattern_scale + 7.0);
	vec3 col = color_main;
	float dorsal = smoothstep(-0.15, 0.7, rn.y);
	float belly = smoothstep(0.05, -0.65, rn.y);
	float pat = 0.0;
	if (pattern_type == 1) {
		pat = smoothstep(0.55, 0.75, sin((rp.z * 6.0 + n1 * 2.5) * pattern_scale) * 0.5 + 0.5) * dorsal;
	} else if (pattern_type == 2) {
		pat = smoothstep(0.62, 0.72, vnoise(rp * 7.0 * pattern_scale)) * (0.4 + dorsal);
	} else if (pattern_type == 3) {
		pat = smoothstep(0.5, 0.65, sin((rp.z * 2.5 + n1) * pattern_scale) * 0.5 + 0.5) * smoothstep(0.1, 0.9, rn.y);
	} else if (pattern_type == 4) {
		pat = smoothstep(0.45, 0.7, n1 * 0.6 + n2 * 0.4);
	}
	col = mix(col, color_pattern, clamp(pat * pattern_strength, 0.0, 1.0));
	col = mix(col, color_belly, belly * 0.85);
	col *= 0.86 + 0.2 * h + (sk.g - 0.5) * 0.08 * (1.0 - use_wrinkle);
	float rough = roughness_base + (1.0 - h) * 0.15;
	float spec = 0.4;
	float metal = 0.0;
	float bump = 1.0;
	vec3 emis = vec3(0.0);
	if (reg == 1) {
		vec3 en = normalize(v_rnormal);
		col = eye_color * 0.6;
		rough = 0.05;
		spec = 0.9;
		bump = 0.0;
		emis = eye_color * glow * 1.5;
	} else if (reg == 2) {
		col = tooth_color * (0.9 + 0.2 * n2);
		rough = 0.35;
		bump = 0.1;
	} else if (reg == 3) {
		col = keratin_color * (0.85 + 0.3 * n2);
		rough = 0.4;
		bump = 0.2;
	} else if (reg == 7) {
		col = top_color * (0.85 + 0.25 * wk.b);
		rough = 0.85;
		bump = 0.25;
	} else if (reg == 8) {
		col = bottom_color * (0.85 + 0.25 * wk.b);
		rough = 0.85;
		bump = 0.25;
	} else if (reg == 9) {
		col = boots_color * (0.8 + 0.3 * wk.g);
		rough = 0.6;
		bump = 0.3;
	} else if (reg == 10) {
		col = hair_color * (0.7 + 0.5 * wk.b);
		rough = 0.7;
		bump = 0.5;
	}
	// demonic corruption: dark veins with glowing cracks
	if (corruption > 0.0 && reg == 0) {
		float v = 1.0 - abs(vnoise(rp * 4.0) * 2.0 - 1.0);
		float crack = smoothstep(0.93, 0.985, v) * corruption;
		col = mix(col, col * vec3(0.35, 0.2, 0.22), corruption * 0.7);
		emis += glow_color * crack * (2.0 + sin(TIME * 2.5 + rp.z * 3.0));
	}
	if (glow > 0.0 && reg == 0) {
		emis += glow_color * smoothstep(0.6, 0.9, h) * glow * 0.6;
	}
	// wetness darkens and smooths
	col *= mix(1.0, 0.6, wet);
	rough = mix(rough, 0.15, wet);
	// bump via surface gradient (no tangents needed), height in world meters
	float fade = clamp(1.0 - length(VERTEX) / 45.0, 0.0, 1.0);
	float bh = h * bump_height * bump * bump_strength * fade;
	vec3 dpdx = dFdx(VERTEX);
	vec3 dpdy = dFdy(VERTEX);
	float dhx = dFdx(bh);
	float dhy = dFdy(bh);
	vec3 r1 = cross(dpdy, NORMAL);
	vec3 r2 = cross(NORMAL, dpdx);
	float det = dot(dpdx, r1);
	vec3 grad = sign(det) * (dhx * r1 + dhy * r2);
	NORMAL = normalize(abs(det) * NORMAL - grad);
	ALBEDO = mix(col, vec3(1.0, 0.15, 0.1), hurt_flash * 0.5) + vec3(0.25, 0.35, 0.6) * select_flash;
	ROUGHNESS = clamp(rough, 0.02, 1.0);
	SPECULAR = spec;
	METALLIC = metal;
	EMISSION = emis + vec3(0.8, 0.1, 0.05) * hurt_flash * 0.3;
}
