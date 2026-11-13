shader_type canvas_item;
uniform bool locker = false;
uniform bool portrait = false;

void fragment() {
	float opacity;
	if (locker) {
		opacity = portrait
			? smoothstep(0.26, 0.55, UV.y) * 0.94
			: smoothstep(0.32, 0.50, UV.x) * 0.96;
	} else {
		opacity = portrait
			? smoothstep(0.34, 0.7, UV.y) * 0.94
			: (1.0 - smoothstep(0.15, 0.57, UV.x)) * 0.92;
		opacity = max(opacity, smoothstep(0.8, 1.0, UV.y) * 0.65);
	}
	COLOR = vec4(0.025, 0.047, 0.09, opacity);
}
