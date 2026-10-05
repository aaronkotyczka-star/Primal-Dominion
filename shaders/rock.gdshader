shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley;

uniform sampler2DArray albedo_arr : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2DArray normal_arr : filter_linear_mipmap, repeat_enable;
uniform float layer = 2.0;
uniform float moss_layer = 0.0;
uniform float moss_amount = 0.35;
uniform vec3 tint : source_color = vec3(1.0);
uniform vec3 vein_color : source_color = vec3(0.0);
uniform float vein_amount = 0.0;
uniform float emissive = 0.0;

varying vec3 w_pos;
varying vec3 w_nrm;

void vertex() {
	w_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	w_nrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

vec4 tri(sampler2DArray t, vec3 p, vec3 n, float l) {
	vec3 w = pow(abs(n), vec3(4.0));
	w /= (w.x + w.y + w.z);
	return texture(t, vec3(p.zy, l)) * w.x + texture(t, vec3(p.xz, l)) * w.y + texture(t, vec3(p.xy, l)) * w.z;
}

void fragment() {
	vec3 p = w_pos / 5.0;
	vec4 a = tri(albedo_arr, p, w_nrm, layer);
	vec4 nm = tri(normal_arr, p, w_nrm, layer);
	vec3 col = a.rgb * tint;
	float moss = smoothstep(0.55, 0.85, w_nrm.y) * moss_amount;
	if (moss > 0.0) {
		vec4 m = tri(albedo_arr, w_pos / 3.0, w_nrm, moss_layer);
		col = mix(col, m.rgb, moss);
	}
	float veins = 0.0;
	if (vein_amount > 0.0) {
		veins = smoothstep(0.62, 0.7, a.a) * vein_amount;
		col = mix(col, vein_color, veins);
	}
	ALBEDO = col;
	ROUGHNESS = mix(nm.b, 0.3, veins);
	METALLIC = veins * 0.6;
	EMISSION = vein_color * veins * emissive;
}
