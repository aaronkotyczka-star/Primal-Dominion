shader_type sky;
render_mode use_quarter_res_pass;

uniform vec3 zenith_day : source_color = vec3(0.22, 0.36, 0.55);
uniform vec3 horizon_day : source_color = vec3(0.62, 0.66, 0.66);
uniform vec3 zenith_night : source_color = vec3(0.01, 0.015, 0.03);
uniform vec3 horizon_night : source_color = vec3(0.04, 0.05, 0.07);
uniform vec3 sunset_color : source_color = vec3(0.95, 0.45, 0.2);
uniform vec3 storm_tint : source_color = vec3(0.45, 0.08, 0.06);
uniform float cloud_cover = 0.35;
uniform float cloud_dark = 0.0;
uniform float demon_storm = 0.0;
uniform float day_factor = 1.0;
uniform vec3 moon_dir = vec3(0.0, 0.5, -0.8);

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 5; i++) {
		v += noise(p) * a;
		p *= 2.03;
		a *= 0.5;
	}
	return v;
}

void sky() {
	vec3 d = EYEDIR;
	float h = clamp(d.y, -1.0, 1.0);
	vec3 sun = LIGHT0_DIRECTION;
	float sun_up = sun.y;
	vec3 zen = mix(zenith_night, zenith_day, day_factor);
	vec3 hor = mix(horizon_night, horizon_day, day_factor);
	float sunset = (1.0 - smoothstep(0.0, 0.35, abs(sun_up))) * day_factor;
	float toward_sun = max(dot(normalize(vec3(d.x, 0.0, d.z)), normalize(vec3(sun.x, 0.0, sun.z))), 0.0);
	hor = mix(hor, sunset_color, sunset * pow(toward_sun, 3.0) * 0.8);
	vec3 col = mix(hor, zen, pow(smoothstep(-0.05, 0.6, h), 0.6));
	if (h < 0.0) {
		col = mix(hor, hor * 0.4, smoothstep(0.0, -0.3, h));
	}
	// sun disk + glow
	float sd = max(dot(d, sun), 0.0);
	col += LIGHT0_COLOR * LIGHT0_ENERGY * (pow(sd, 900.0) * 30.0 + pow(sd, 12.0) * 0.25) * step(-0.05, sun_up);
	// moon + stars at night
	float night = 1.0 - day_factor;
	float md = max(dot(d, normalize(moon_dir)), 0.0);
	col += vec3(0.75, 0.8, 0.9) * (smoothstep(0.9994, 0.9997, md) * 1.6 + pow(md, 60.0) * 0.06) * night;
	if (h > 0.0 && !AT_QUARTER_RES_PASS) {
		vec2 sp = d.xz / (d.y + 0.3) * 160.0;
		float st = step(0.9965, hash(floor(sp))) * (0.5 + 0.5 * sin(TIME * 2.0 + hash(floor(sp) + 3.0) * 30.0));
		col += vec3(st) * night * 0.9 * (1.0 - cloud_cover);
	}
	// clouds (2D layer projected)
	if (h > 0.0) {
		vec2 cp = d.xz / (d.y + 0.15) * 1.6 + TIME * vec2(0.004, 0.002);
		float c = fbm(cp * 1.4);
		float cov = smoothstep(1.0 - cloud_cover - 0.25, 1.0 - cloud_cover + 0.35, c);
		vec3 ccol = mix(vec3(0.95, 0.94, 0.92) * (0.35 + 0.65 * day_factor), vec3(0.25, 0.26, 0.28) * (0.3 + 0.7 * day_factor), cloud_dark);
		ccol += sunset_color * sunset * 0.35;
		ccol = mix(ccol, storm_tint * 0.8, demon_storm * 0.7);
		col = mix(col, ccol, cov * smoothstep(0.0, 0.15, h));
	}
	col = mix(col, col * 0.4 + storm_tint * 0.6, demon_storm * 0.6);
	COLOR = col;
}
