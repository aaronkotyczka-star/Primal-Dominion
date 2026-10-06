// Shared by creature.gdshader (body) and fur.gdshader (shells): coat colours and patterns
// are evaluated in rest space, so body and fur always match and patterns never swim.

uniform vec3 color_main : source_color = vec3(0.35, 0.32, 0.25);
uniform vec3 color_belly : source_color = vec3(0.65, 0.6, 0.5);
uniform vec3 color_pattern : source_color = vec3(0.15, 0.13, 0.1);
uniform int pattern_type = 1; // 0 none, 1 stripes, 2 spots/rosettes, 3 saddle bands, 4 mottled
uniform float pattern_scale = 1.0;
uniform float pattern_strength = 0.7;
uniform vec3 hair_color : source_color = vec3(0.12, 0.08, 0.05);
uniform vec3 glow_color : source_color = vec3(1.0, 0.25, 0.05);
uniform float corruption = 0.0;
uniform float glow = 0.0;
uniform float hurt_flash = 0.0;
uniform float select_flash = 0.0;
uniform float body_scale = 1.0;
uniform float human_skin = 0.0;

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

float fbm3(vec3 p) {
	return vnoise(p) * 0.55 + vnoise(p * 2.13 + 3.1) * 0.3 + vnoise(p * 4.7 + 7.7) * 0.15;
}

// cellular noise (distance to nearest jittered point, 3D) for rosettes/spots
vec2 cell3(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	float d1 = 8.0;
	float d2 = 8.0;
	for (int z = -1; z <= 1; z++) {
		for (int y = -1; y <= 1; y++) {
			for (int x = -1; x <= 1; x++) {
				vec3 g = vec3(float(x), float(y), float(z));
				vec3 o = vec3(hash3(i + g), hash3(i + g + 19.1), hash3(i + g + 47.3));
				float d = length(g + o - f);
				if (d < d1) {
					d2 = d1;
					d1 = d;
				} else if (d < d2) {
					d2 = d;
				}
			}
		}
	}
	return vec2(d1, d2);
}

// coat colour at rest position rp (scaled to body size) with rest normal rn
vec3 coat_color(vec3 rp, vec3 rn) {
	float n1 = fbm3(rp * 3.0 * pattern_scale);
	float n2 = vnoise(rp * 9.0 * pattern_scale + 7.0);
	float dorsal = smoothstep(-0.15, 0.75, rn.y);
	float belly = smoothstep(0.05, -0.7, rn.y);
	float pat = 0.0;
	if (pattern_type == 1) {
		// tiger-like stripes: warped bands across the body, broken and tapering towards the belly
		float band = sin((rp.z * 6.5 + n1 * 3.2 + rp.y * 1.5) * pattern_scale) * 0.5 + 0.5;
		pat = smoothstep(0.62, 0.8, band + (n2 - 0.5) * 0.25) * smoothstep(-0.5, 0.5, rn.y);
	} else if (pattern_type == 2) {
		// rosettes / spots
		vec2 c = cell3(rp * 5.0 * pattern_scale + n1 * 0.6);
		float ring = smoothstep(0.32, 0.38, c.x) * (1.0 - smoothstep(0.5, 0.62, c.x));
		pat = max(ring, smoothstep(0.24, 0.16, c.x) * 0.7) * (0.35 + dorsal);
	} else if (pattern_type == 3) {
		// saddle bands over the back
		pat = smoothstep(0.5, 0.68, sin((rp.z * 2.6 + n1 * 1.4) * pattern_scale) * 0.5 + 0.5) * smoothstep(0.05, 0.9, rn.y);
	} else if (pattern_type == 4) {
		pat = smoothstep(0.42, 0.68, n1 * 0.65 + n2 * 0.35);
	}
	vec3 col = mix(color_main, color_pattern, clamp(pat * pattern_strength, 0.0, 1.0));
	// countershading, darker dorsal line, broad tonal variation
	col = mix(col, color_belly, belly * 0.85);
	col *= 1.0 - 0.14 * smoothstep(0.6, 0.98, rn.y) * (1.0 - human_skin);
	col *= 0.88 + 0.24 * fbm3(rp * 1.1 + 11.0);
	return col;
}

vec3 corruption_emission(vec3 rp, float t) {
	float v = 1.0 - abs(vnoise(rp * 4.0) * 2.0 - 1.0);
	float crack = smoothstep(0.93, 0.985, v) * corruption;
	return glow_color * crack * (2.0 + sin(t * 2.5 + rp.z * 3.0));
}
