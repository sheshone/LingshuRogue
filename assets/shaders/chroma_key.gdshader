shader_type canvas_item;

uniform vec3 key_color = vec3(1.0, 0.0, 1.0);
uniform float tolerance = 0.22;
uniform float softness = 0.08;

void fragment() {
	vec4 color = texture(TEXTURE, UV);
	float distance_to_key = distance(color.rgb, key_color);
	color.a *= smoothstep(tolerance, tolerance + softness, distance_to_key);
	COLOR = color;
}
