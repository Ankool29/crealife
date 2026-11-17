shader_type canvas_item;
// Teinte génétique : fait tourner la couleur autour de l'axe des gris
// (la luminosité et les reflets du rendu 3D sont conservés).

uniform float hue_shift = 0.0;      // en tours (0 à 1)
uniform float desaturate = 0.0;     // 1 = gris (créature morte)

void fragment() {
	vec4 c = texture(TEXTURE, UV);
	float a = hue_shift * 6.2831853;
	float cs = cos(a);
	float sn = sin(a);
	vec3 k = vec3(0.57735);
	vec3 rgb = c.rgb * cs + cross(k, c.rgb) * sn + k * dot(k, c.rgb) * (1.0 - cs);
	float grey = dot(rgb, vec3(0.299, 0.587, 0.114));
	rgb = mix(rgb, vec3(grey) * 0.8, desaturate);
	COLOR = vec4(rgb, c.a) * COLOR;
}
