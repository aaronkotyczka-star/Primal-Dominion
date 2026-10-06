shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

#include "res://shaders/creature_common.gdshaderinc"

// Rest-pose attributes from the generator (skinning-stable texturing)
varying vec3 v_rest;
varying vec3 v_rnormal;
varying flat float v_region;
varying float v_occ;
varying vec4 v_mask; // r: fur/hair coverage, g: tunic, b: trousers, a: leather

uniform vec3 eye_color : source_color = vec3(0.85, 0.6, 0.1);
uniform vec3 tooth_color : source_color = vec3(0.85, 0.8, 0.68);
uniform vec3 keratin_color : source_color = vec3(0.18, 0.15, 0.12);
uniform vec3 top_color : source_color = vec3(0.35, 0.28, 0.2);
uniform vec3 bottom_color : source_color = vec3(0.25, 0.22, 0.18);
uniform vec3 boots_color : source_color = vec3(0.18, 0.13, 0.1);
uniform float wet = 0.0;
uniform float tex_scale = 4.0; // texture repeats per meter (scaled by creature size)
uniform float bump_strength = 1.0;
uniform float bump_height = 0.008; // meters
uniform float roughness_base = 0.62;
uniform float pupil_slit = 1.0;
uniform float fur_len = 0.0;
uniform sampler2D skin_tex : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D wrinkle_tex : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D cloth_tex : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D leather_tex : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float use_wrinkle = 0.0;

void vertex() {
	v_rest = CUSTOM0.xyz;
	v_region = CUSTOM0.w;
	v_rnormal = CUSTOM1.xyz;
	v_occ = CUSTOM1.w;
	v_mask = CUSTOM2;
}

vec4 triplanar(sampler2D t, vec3 p, vec3 n) {
	vec3 w = pow(abs(n), vec3(4.0));
	w /= (w.x + w.y + w.z + 1e-5);
	return texture(t, p.zy) * w.x + texture(t, p.xz) * w.y + texture(t, p.xy) * w.z;
}

void fragment() {
	int reg = int(v_region + 0.5);
	vec3 rp = v_rest / body_scale;
	vec3 rn = normalize(v_rnormal);
	float sc = tex_scale;
	float dorsal = smoothstep(-0.1, 0.8, rn.y);
	// skin relief: scales get larger over the back, finer on belly/face; mammals use a wrinkle network
	vec4 sk = triplanar(skin_tex, v_rest * sc * mix(1.35, 0.85, dorsal), rn);
	vec4 sk2 = triplanar(skin_tex, v_rest * sc * 2.7 + 0.37, rn);
	vec4 wk = triplanar(wrinkle_tex, v_rest * sc * 0.35, rn);
	float hs = mix(sk2.r, sk.r, smoothstep(0.25, 0.75, fbm3(rp * 2.0 + 3.0) * 0.6 + dorsal * 0.5));
	float h = mix(hs, wk.r, use_wrinkle);
	vec3 col = coat_color(rp, rn);
	float rough = roughness_base + (1.0 - h) * 0.15;
	float spec = 0.4;
	float metal = 0.0;
	float bump = 1.0;
	float sss = 0.08;
	vec3 emis = vec3(0.0);
	// crevices darker, scale tops slightly lighter and individually tinted
	col *= mix(0.72 + 0.36 * h, 0.86 + 0.2 * h, use_wrinkle);
	col *= 1.0 + (sk.g - 0.5) * 0.14 * (1.0 - use_wrinkle);
	if (human_skin > 0.5) {
		// smooth skin: fine pores, warm subsurface, slight sheen
		h = 0.5 + (wk.r - 0.5) * 0.25;
		col = coat_color(rp, rn) * (0.95 + 0.08 * wk.g);
		rough = 0.48 + 0.12 * wk.b;
		spec = 0.35;
		bump = 0.35;
		sss = 0.45;
	}
	// under fur/hair the skin is hidden: use the coat colour, darker towards the roots
	float furm = v_mask.r * step(0.001, fur_len);
	if (human_skin > 0.5) {
		float hm = smoothstep(0.08, 0.3, v_mask.r);
		col = mix(col, hair_color * (0.55 + 0.4 * wk.b), hm);
		rough = mix(rough, 0.6, hm);
		sss *= 1.0 - hm;
		furm = 0.0;
	}
	if (furm > 0.05) {
		col = mix(col, coat_color(rp, rn) * 0.55, smoothstep(0.05, 0.4, furm));
		rough = mix(rough, 0.9, furm);
		bump = mix(bump, 0.1, furm);
		spec = mix(spec, 0.2, furm);
	}
	if (reg == 1) {
		float th = UV.y;
		float slit = abs(fract(UV.x * 2.0 + 0.25) - 0.5);
		float ps = mix(0.13, 0.05, human_skin);
		float is = mix(0.33, 0.165, human_skin);
		float pupil = 1.0 - smoothstep(ps * 0.75, ps, th + slit * 0.18 * pupil_slit);
		float iris = 1.0 - smoothstep(is * 0.9, is, th);
		float irisd = 0.55 + 0.6 * vnoise(vec3(UV.x * 40.0, th * 30.0, 0.0));
		vec3 sclera = mix(vec3(0.06, 0.05, 0.04), vec3(0.82, 0.78, 0.74), human_skin);
		col = mix(sclera, eye_color * irisd * (1.0 - 0.5 * smoothstep(is * 0.6, is, th)), iris);
		col = mix(col, vec3(0.01), pupil);
		rough = 0.04;
		spec = 1.0;
		bump = 0.0;
		sss = 0.0;
		emis = eye_color * glow * 1.5;
	} else if (reg == 2) {
		col = tooth_color * (0.9 + 0.2 * vnoise(rp * 40.0));
		rough = 0.35;
		bump = 0.1;
		sss = 0.2;
	} else if (reg == 3) {
		col = keratin_color * (0.8 + 0.35 * vnoise(rp * 25.0));
		rough = 0.4;
		bump = 0.2;
		sss = 0.0;
	} else if (reg == 11) {
		col = mix(vec3(0.25, 0.07, 0.07), vec3(0.4, 0.12, 0.12), human_skin) * (0.8 + 0.3 * vnoise(rp * 20.0));
		rough = 0.25;
		spec = 0.6;
		bump = 0.05;
		sss = 0.5;
	} else if (reg == 5) {
		float barb = sin(rp.z * 140.0 * pattern_scale + rp.y * 40.0 + vnoise(rp * 9.0) * 4.0) * 0.5 + 0.5;
		col = mix(col, col * 0.7, barb * 0.35);
		rough = 0.85;
		spec = 0.2;
		bump = 0.15;
		sss = 0.0;
	} else if (reg == 10) {
		col = hair_color * (0.6 + 0.5 * wk.b);
		rough = 0.65;
		bump = 0.5;
		sss = 0.0;
	}
	// clothing (smooth masks from the generator, crisp hem line per pixel)
	float leather = max(smoothstep(0.45, 0.55, v_mask.a), float(reg == 9));
	float top = max(smoothstep(0.45, 0.55, v_mask.g), float(reg == 7)) * (1.0 - leather);
	float bottom = max(smoothstep(0.45, 0.55, v_mask.b), float(reg == 8)) * (1.0 - leather) * (1.0 - top);
	if (top + bottom + leather > 0.01) {
		vec4 ct = triplanar(cloth_tex, v_rest * 22.0, rn);
		vec4 cf = triplanar(cloth_tex, v_rest * 2.5, rn);
		vec4 lt = triplanar(leather_tex, v_rest * 6.0, rn);
		float fold = cf.b;
		vec3 cloth = (top_color * top + bottom_color * bottom) / max(top + bottom, 1e-3);
		cloth *= (0.88 + 0.16 * ct.r) * (0.85 + 0.3 * fold) * (0.95 + 0.1 * ct.g);
		vec3 lcol = boots_color * (0.75 + 0.35 * lt.r) * (0.85 + 0.3 * lt.b);
		float cw = top + bottom;
		col = mix(col, cloth, cw);
		col = mix(col, lcol, leather);
		h = mix(h, mix(ct.r * 0.6 + fold * 0.4, lt.r, leather / max(cw + leather, 1e-3)), clamp(cw + leather, 0.0, 1.0));
		rough = mix(rough, mix(0.9, 0.55, leather / max(cw + leather, 1e-3)), clamp(cw + leather, 0.0, 1.0));
		spec = mix(spec, 0.25, clamp(cw + leather, 0.0, 1.0));
		bump = mix(bump, 0.5, clamp(cw + leather, 0.0, 1.0));
		sss *= 1.0 - clamp(cw + leather, 0.0, 1.0);
	}
	// demonic corruption: dark veins with glowing cracks
	if (corruption > 0.0 && reg == 0) {
		col = mix(col, col * vec3(0.35, 0.2, 0.22), corruption * 0.7);
		emis += corruption_emission(rp, TIME);
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
	float occ = clamp(v_occ, 0.0, 1.0);
	col *= mix(1.0, 0.5, occ);
	AO = 1.0 - occ * 0.8;
	AO_LIGHT_AFFECT = 0.3;
	ALBEDO = mix(col, vec3(1.0, 0.15, 0.1), hurt_flash * 0.5) + vec3(0.25, 0.35, 0.6) * select_flash;
	ROUGHNESS = clamp(rough, 0.02, 1.0);
	SPECULAR = spec;
	METALLIC = metal;
	SSS_STRENGTH = sss;
	BACKLIGHT = col * vec3(0.5, 0.25, 0.18) * sss;
	EMISSION = emis + vec3(0.8, 0.1, 0.05) * hurt_flash * 0.3;
}
