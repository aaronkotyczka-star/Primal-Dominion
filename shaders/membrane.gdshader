shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_burley;

varying vec3 v_rest;
varying flat float v_region;

uniform vec3 color_main : source_color = vec3(0.35, 0.28, 0.22);
uniform vec3 color_pattern : source_color = vec3(0.15, 0.1, 0.08);
uniform vec3 glow_color : source_color = vec3(1.0, 0.25, 0.05);
uniform float corruption = 0.0;
uniform float hurt_flash = 0.0;
uniform float select_flash = 0.0;

void vertex() {
	v_rest = CUSTOM0.xyz;
	v_region = CUSTOM0.w;
}

void fragment() {
	int reg = int(v_region + 0.5);
	vec2 uv = UV;
	vec3 col = color_main;
	float rough = 0.7;
	if (reg == 5) {
		// feathers: barbs along chord, separated tips at trailing edge
		float feather_idx = uv.x * 26.0;
		float f = fract(feather_idx);
		float shaft = smoothstep(0.08, 0.0, abs(f - 0.5) - 0.01);
		float tip = 1.0 - smoothstep(0.82, 1.0, uv.y + abs(f - 0.5) * 0.35);
		if (tip < 0.5) {
			discard;
		}
		float barbs = sin((uv.y * 140.0 + f * 9.0)) * 0.5 + 0.5;
		col = mix(color_main, color_pattern, smoothstep(0.5, 1.0, uv.y) * 0.6);
		col *= 0.8 + barbs * 0.15 + shaft * 0.2;
		rough = 0.8;
	} else {
		// skin membrane with veins
		float vein = smoothstep(0.03, 0.0, abs(fract(uv.x * 7.0 + uv.y * 1.3) - 0.5) - 0.46);
		col = mix(color_main, color_pattern, vein * 0.5 + uv.y * 0.25);
		rough = 0.55;
	}
	float v = 1.0 - abs(fract(v_rest.x * 0.9 + v_rest.z * 0.7) * 2.0 - 1.0);
	EMISSION = glow_color * corruption * smoothstep(0.85, 0.98, v) * 2.0 + vec3(0.8, 0.1, 0.05) * hurt_flash * 0.3;
	ALBEDO = mix(col, vec3(1.0, 0.15, 0.1), hurt_flash * 0.5) + vec3(0.25, 0.35, 0.6) * select_flash;
	ROUGHNESS = rough;
	BACKLIGHT = col * 0.6;
}
