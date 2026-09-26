shader_type spatial;
render_mode unshaded, cull_disabled, fog_disabled;

uniform sampler2D base_texture : source_color, filter_linear_mipmap, repeat_enable;
uniform vec4 base_factor = vec4(1.0);
uniform vec3 shade_factor = vec3(1.0);
uniform float shade_shift = -0.3;
uniform float shade_toony = 0.8;
uniform float shade_blend = 0.72;
uniform float extra_shade = 0.1;
uniform float alpha_cutoff = 0.5;
uniform vec3 light_position_world = vec3(-1.2, 2.2, 2.4);
uniform float rim_strength = 0.06;
uniform float shadow_strength = 1.0;
uniform vec3 shadow_tint : source_color = vec3(1.0);

void fragment() {
	vec4 texel = texture(base_texture, UV);
	vec3 lit = texel.rgb * base_factor.rgb;
	vec3 authored_shade = texel.rgb * shade_factor;
	vec3 shade = mix(lit, authored_shade, shade_blend) * (1.0 - extra_shade);
	vec3 normal = normalize(NORMAL);
	vec3 light_view = (VIEW_MATRIX * vec4(light_position_world, 1.0)).xyz;
	vec3 light_direction = normalize(light_view - VERTEX);
	float diffuse = clamp(dot(normal, light_direction) * 0.5 + 0.5 + shade_shift * 0.18, 0.0, 1.0);
	// Inspired by the reference's Shader-to-RGB/Snap ramp. Feathering keeps
	// the small desktop avatar from showing harsh striped bands.
	float feather = mix(0.055, 0.012, clamp(shade_toony, 0.0, 1.0));
	float band = 0.0;
	for (int i = 1; i < 6; i++) {
		band += smoothstep(float(i) / 6.0 - feather, float(i) / 6.0 + feather, diffuse);
	}
	band /= 5.0;
	float rim = pow(1.0 - clamp(dot(normal, normalize(VIEW)), 0.0, 1.0), 3.0);
	vec3 tinted_shade = shade * mix(vec3(1.0), shadow_tint, 0.7);
	vec3 surface_color = mix(lit, tinted_shade, clamp((1.0 - band) * shadow_strength, 0.0, 1.0));
	surface_color += lit * rim * rim_strength;
	ALBEDO = surface_color;
	ALPHA = texel.a * base_factor.a;
	ALPHA_SCISSOR_THRESHOLD = alpha_cutoff;
}
