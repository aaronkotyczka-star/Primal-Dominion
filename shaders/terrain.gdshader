shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler2D heightmap : filter_linear, repeat_disable;
uniform sampler2D splat0 : filter_linear, repeat_disable;
uniform sampler2D splat1 : filter_linear, repeat_disable;
uniform sampler2DArray albedo_arr : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2DArray normal_arr : filter_linear_mipmap_anisotropic, repeat_enable;
uniform float extent = 1024.0;
uniform float hm_size = 1025.0;
uniform float wetness = 0.0;
uniform float snow_cover = 0.0;
uniform float detail_dist = 160.0;
// per-layer tiling (meters per repeat)
const float tile_scales[8] = float[8](6.0, 5.0, 9.0, 6.0, 5.0, 7.0, 6.0, 6.0);
uniform vec4 layer_tint0 : source_color = vec4(1.0);
uniform vec3 corrupt_glow : source_color = vec3(1.0, 0.2, 0.05);

varying vec3 w_pos;
varying vec3 w_nrm;

vec2 hm_uv(vec2 xz) {
	return (xz + extent) / (2.0 * extent) * ((hm_size - 1.0) / hm_size) + 0.5 / hm_size;
}

float H(vec2 xz) {
	return textureLod(heightmap, hm_uv(xz), 0.0).r;
}

void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float skirt = UV2.x;
	float h = H(wp.xz);
	float e = 2.0 * extent / (hm_size - 1.0);
	float hx = H(wp.xz + vec2(e, 0.0)) - H(wp.xz - vec2(e, 0.0));
	float hz = H(wp.xz + vec2(0.0, e)) - H(wp.xz - vec2(0.0, e));
	vec3 n = normalize(vec3(-hx, 2.0 * e, -hz));
	VERTEX.y = h - skirt * 3.0;
	NORMAL = n;
	TANGENT = normalize(cross(vec3(0.0, 0.0, 1.0), n));
	BINORMAL = normalize(cross(n, TANGENT));
	w_pos = vec3(wp.x, VERTEX.y, wp.z);
	w_nrm = n;
}

vec4 tex_layer(int i, vec2 xz, float far_mix) {
	vec4 a = texture(albedo_arr, vec3(xz / tile_scales[i], float(i)));
	vec4 b = texture(albedo_arr, vec3(xz / (tile_scales[i] * 4.7), float(i)));
	return mix(a, b, far_mix * 0.6 + 0.2);
}

vec4 nrm_layer(int i, vec2 xz) {
	return texture(normal_arr, vec3(xz / tile_scales[i], float(i)));
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

void fragment() {
	vec2 xz = w_pos.xz;
	vec2 uv = hm_uv(xz);
	// break up splat edges with noise
	vec2 jit = vec2(vnoise(xz * 0.15), vnoise(xz * 0.15 + 13.0)) - 0.5;
	vec4 s0 = texture(splat0, uv + jit * 0.0015);
	vec4 s1 = texture(splat1, uv + jit * 0.0015);
	float w[8] = {s0.r, s0.g, s0.b, s0.a, s1.r, s1.g, s1.b, s1.a};
	float dist = length(VERTEX);
	float far_mix = smoothstep(20.0, 120.0, dist);
	float slope = 1.0 - w_nrm.y;
	// height-based blending
	vec3 col = vec3(0.0);
	vec3 nrm = vec3(0.0);
	float rough = 0.0;
	float emis = 0.0;
	float best = -1.0;
	vec4 al[8];
	float hw[8];
	float maxv = 0.0;
	for (int i = 0; i < 8; i++) {
		if (w[i] < 0.01) {
			hw[i] = -1.0;
			continue;
		}
		al[i] = tex_layer(i, xz, far_mix);
		hw[i] = w[i] + al[i].a * 0.5;
		maxv = max(maxv, hw[i]);
	}
	float total = 0.0;
	for (int i = 0; i < 8; i++) {
		if (hw[i] < 0.0) continue;
		float bw = max(hw[i] - maxv + 0.25, 0.0);
		if (bw <= 0.0) continue;
		vec4 nm = nrm_layer(i, xz);
		col += al[i].rgb * bw;
		nrm += vec3(nm.xy * 2.0 - 1.0, 0.0) * bw;
		rough += nm.b * bw;
		emis += nm.a * bw * (i == 7 ? 1.0 : 0.0);
		total += bw;
	}
	col /= max(total, 1e-4);
	nrm /= max(total, 1e-4);
	rough /= max(total, 1e-4);
	emis /= max(total, 1e-4);
	// macro variation
	float macro = vnoise(xz * 0.01) * 0.6 + vnoise(xz * 0.043) * 0.4;
	col *= 0.82 + 0.3 * macro;
	// wet shoreline & rain
	float shore = 1.0 - smoothstep(0.2, 1.8, w_pos.y);
	float wet = clamp(max(shore, wetness * 0.8), 0.0, 1.0);
	col *= mix(1.0, 0.55, wet);
	rough = mix(rough, 0.18, wet);
	// snow cover on flat surfaces (weather)
	float sn = snow_cover * smoothstep(0.75, 0.9, w_nrm.y);
	col = mix(col, vec3(0.88, 0.9, 0.95), sn);
	// underwater darkening
	col *= mix(1.0, 0.7, 1.0 - smoothstep(-6.0, 0.0, w_pos.y));
	ALBEDO = col;
	ROUGHNESS = clamp(rough, 0.05, 1.0);
	SPECULAR = 0.35;
	vec2 nxy = nrm.xy * (1.0 - far_mix * 0.6);
	NORMAL_MAP = vec3(clamp(nxy, vec2(-0.9), vec2(0.9)) * 0.5 + 0.5, 1.0);
	NORMAL_MAP_DEPTH = 1.0;
	EMISSION = corrupt_glow * emis * (0.6 + 0.4 * sin(TIME * 1.7 + xz.x * 0.3)) * 0.8;
}
