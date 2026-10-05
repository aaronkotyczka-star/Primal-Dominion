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

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

const float ROT_C = 0.6;
const float ROT_S = 0.8;

// one layer: anti-tiling (second rotated sample blended by noise), distance macro sample, triplanar on slopes
void layer_sample(int i, vec2 xz, vec3 wp, vec3 n, float tri_w, float var_n, float far_mix, out vec4 al, out vec4 nm) {
	float fl = float(i);
	float ts = tile_scales[i];
	vec2 uv = xz / ts;
	vec2 uv2 = vec2(ROT_C * uv.x - ROT_S * uv.y, ROT_S * uv.x + ROT_C * uv.y) * 0.77 + vec2(0.37, 0.61);
	vec4 a1 = texture(albedo_arr, vec3(uv, fl));
	vec4 n1 = texture(normal_arr, vec3(uv, fl));
	if (var_n > 0.02 && var_n < 0.98) {
		vec4 a2 = texture(albedo_arr, vec3(uv2, fl));
		vec4 n2 = texture(normal_arr, vec3(uv2, fl));
		vec2 d = n2.xy * 2.0 - 1.0;
		d = vec2(ROT_C * d.x + ROT_S * d.y, -ROT_S * d.x + ROT_C * d.y);
		n2.xy = d * 0.5 + 0.5;
		al = mix(a1, a2, var_n);
		nm = mix(n1, n2, var_n);
	} else if (var_n >= 0.98) {
		al = texture(albedo_arr, vec3(uv2, fl));
		nm = texture(normal_arr, vec3(uv2, fl));
		vec2 d = nm.xy * 2.0 - 1.0;
		nm.xy = vec2(ROT_C * d.x + ROT_S * d.y, -ROT_S * d.x + ROT_C * d.y) * 0.5 + 0.5;
	} else {
		al = a1;
		nm = n1;
	}
	if (tri_w > 0.01) {
		vec2 suv = (abs(n.x) > abs(n.z) ? wp.zy : wp.xy) / ts;
		vec4 as = texture(albedo_arr, vec3(suv, fl));
		vec4 ns = texture(normal_arr, vec3(suv, fl));
		al = mix(al, as, tri_w);
		nm = mix(nm, ns, tri_w);
	}
	if (far_mix > 0.01) {
		vec3 af = texture(albedo_arr, vec3(xz / (ts * 5.3), fl)).rgb;
		al.rgb = mix(al.rgb, af, far_mix * 0.55);
	}
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
	vec4 al[8];
	vec4 nl[8];
	float hw[8];
	float maxv = 0.0;
	float var_n = smoothstep(0.3, 0.7, vnoise(xz * 0.07) * 0.65 + vnoise(xz * 0.23 + 7.0) * 0.35);
	float tri_w = smoothstep(0.3, 0.55, slope);
	for (int i = 0; i < 8; i++) {
		if (w[i] < 0.01) {
			hw[i] = -1.0;
			continue;
		}
		vec4 la;
		vec4 ln;
		layer_sample(i, xz, w_pos, w_nrm, tri_w, var_n, far_mix, la, ln);
		al[i] = la;
		nl[i] = ln;
		hw[i] = w[i] + nl[i].a * 0.5;
		maxv = max(maxv, hw[i]);
	}
	float total = 0.0;
	for (int i = 0; i < 8; i++) {
		if (hw[i] < 0.0) continue;
		float bw = max(hw[i] - maxv + 0.22, 0.0);
		if (bw <= 0.0) continue;
		vec4 nm = nl[i];
		col += al[i].rgb * bw;
		nrm += vec3(nm.xy * 2.0 - 1.0, 0.0) * bw;
		rough += nm.b * bw;
		if (i == 7) {
			emis += smoothstep(0.12, 0.45, al[i].r - al[i].b) * bw;
		}
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
	vec2 nxy = nrm.xy * (1.0 - far_mix * 0.5) * 1.15;
	NORMAL_MAP = vec3(clamp(nxy, vec2(-0.9), vec2(0.9)) * 0.5 + 0.5, 1.0);
	NORMAL_MAP_DEPTH = 1.0;
	EMISSION = corrupt_glow * emis * (0.6 + 0.4 * sin(TIME * 1.7 + xz.x * 0.3)) * 0.8;
}
