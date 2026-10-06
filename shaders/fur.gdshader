shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

// Shell fur / hair / plumage: the body mesh is drawn again per shell, pushed out along the
// normal (and combed), and strands are cut out of each shell with a tapering strand map.

#include "res://shaders/creature_common.gdshaderinc"

uniform float shell = 0.5; // 0 = skin, 1 = strand tips
uniform float fur_len = 0.03; // rig meters at full coverage
uniform float strand_density = 300.0; // strands per rig meter
uniform float fur_stiff = 0.5; // 0 = hangs fully along the comb, 1 = straight out
uniform vec3 comb = vec3(0.0, -0.45, 1.0);
uniform vec3 crown = vec3(0.0, 1.7, 0.0);
uniform float comb_radial = 0.0; // 1 = hair falls away from the crown point
uniform float use_hair_color = 0.0;
uniform float tip_light = 0.25;
uniform float clumping = 0.3;
uniform sampler2D strand_tex : filter_linear_mipmap, repeat_enable;

varying vec3 v_rest;
varying vec3 v_rnormal;
varying float v_fur;
varying float v_occ;

void vertex() {
	v_rest = CUSTOM0.xyz;
	v_rnormal = CUSTOM1.xyz;
	v_occ = CUSTOM1.w;
	v_fur = CUSTOM2.x;
	float m = CUSTOM2.x;
	vec3 radial = normalize(CUSTOM0.xyz - crown + vec3(0.0, 0.0, 0.002));
	vec3 c = normalize(mix(normalize(comb), radial + vec3(0.0, -0.6, 0.15), comb_radial));
	vec3 n = normalize(NORMAL);
	vec3 ct = c - n * dot(c, n);
	float L = fur_len * m;
	float s = shell;
	VERTEX += n * L * s * mix(0.35, 1.0, fur_stiff) + ct * L * s * s * (1.0 - fur_stiff) * 1.6;
}

void fragment() {
	if (v_fur < 0.04) {
		discard;
	}
	vec3 rn = normalize(v_rnormal);
	vec3 an = abs(rn);
	vec3 p = v_rest * strand_density / 64.0;
	vec2 uv = an.x > an.y && an.x > an.z ? p.zy : (an.y > an.z ? p.xz : p.xy);
	// clumps: neighbouring strands bend together, which reads as locks of hair / tufts of fur
	vec2 cl = vec2(vnoise(v_rest * 18.0), vnoise(v_rest * 18.0 + 5.0)) - 0.5;
	uv += cl * clumping * 0.06 * shell;
	vec4 st = texture(strand_tex, uv);
	// shorter coverage near the coverage edge so the coat thins out instead of ending in a wall
	float reach = st.r * smoothstep(0.04, 0.5, v_fur);
	if (reach < shell + 0.02) {
		discard;
	}
	vec3 rp = v_rest / body_scale;
	vec3 base = mix(coat_color(rp, rn), hair_color, use_hair_color);
	base *= 0.85 + 0.3 * st.g;
	vec3 col = base * mix(0.45, 1.0 + tip_light, shell);
	float occ = clamp(v_occ, 0.0, 1.0);
	col *= mix(1.0, 0.55, occ * (1.0 - shell));
	ALBEDO = mix(col, vec3(1.0, 0.15, 0.1), hurt_flash * 0.5) + vec3(0.25, 0.35, 0.6) * select_flash;
	ROUGHNESS = mix(0.7, 0.55, use_hair_color);
	SPECULAR = mix(0.25, 0.45, use_hair_color);
	AO = mix(0.45, 1.0, shell);
	AO_LIGHT_AFFECT = 0.4;
	BACKLIGHT = base * 0.35 * shell;
	if (corruption > 0.0) {
		EMISSION = corruption_emission(rp, TIME) * 0.5;
	}
}
