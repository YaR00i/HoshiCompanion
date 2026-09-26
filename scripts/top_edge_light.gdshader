shader_type canvas_item;
render_mode unshaded, blend_mix;

uniform sampler2D avatar_texture : source_color, filter_linear, repeat_disable;
uniform vec3 edge_color : source_color = vec3(1.0, 0.92, 0.98);
uniform float edge_strength = 0.16;
uniform float edge_width = 0.4;
uniform vec3 outline_color : source_color = vec3(0.20, 0.16, 0.27);
uniform float outline_strength = 0.45;
uniform float outline_width = 0.35;

void fragment() {
	vec2 pixel = 1.0 / vec2(textureSize(avatar_texture, 0));
	float reach = mix(1.0, 3.2, clamp(edge_width, 0.0, 1.0));
	float center = texture(avatar_texture, UV).a;
	float above = texture(avatar_texture, UV - vec2(0.0, pixel.y * reach)).a;
	float below = texture(avatar_texture, UV + vec2(0.0, pixel.y * reach)).a;
	// The upper silhouette is the one-pixel transition from transparent
	// space to Hoshi's own alpha. This also follows alpha-cut hair strands.
	float inner_edge = max(center - above, 0.0);
	float outer_edge = max(below - center, 0.0);
	float strength = clamp(edge_strength * 3.5, 0.0, 1.0);
	float top_alpha = clamp((inner_edge * 0.82 + outer_edge * 0.28) * strength, 0.0, 1.0);
	float radius = mix(0.75, 2.5, clamp(outline_width, 0.0, 1.0));
	vec2 dx = vec2(pixel.x * radius, 0.0);
	vec2 dy = vec2(0.0, pixel.y * radius);
	vec2 diagonal = pixel * radius * 0.7071;
	float around = 0.0;
	around = max(around, texture(avatar_texture, UV + dx).a);
	around = max(around, texture(avatar_texture, UV - dx).a);
	around = max(around, texture(avatar_texture, UV + dy).a);
	around = max(around, texture(avatar_texture, UV - dy).a);
	around = max(around, texture(avatar_texture, UV + diagonal).a);
	around = max(around, texture(avatar_texture, UV - diagonal).a);
	around = max(around, texture(avatar_texture, UV + vec2(diagonal.x, -diagonal.y)).a);
	around = max(around, texture(avatar_texture, UV + vec2(-diagonal.x, diagonal.y)).a);
	float outline_alpha = clamp((around - center) * outline_strength, 0.0, 1.0);
	float combined_alpha = outline_alpha + top_alpha * (1.0 - outline_alpha);
	vec3 combined_color = (outline_color * outline_alpha * (1.0 - top_alpha) + edge_color * top_alpha) / max(combined_alpha, 0.0001);
	COLOR = vec4(combined_color, combined_alpha);
}
