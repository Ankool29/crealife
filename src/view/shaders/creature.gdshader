shader_type canvas_item;
// Colorisation génétique. Le sprite est rendu en niveaux de gris : sa
// luminosité (relief, ombres, ventre clair, dos sombre) est convertie en
// couleurs à partir de trois teintes tirées des gènes. Les parties déjà
// colorées (yeux, antennes, taches lumineuses) restent telles quelles.

uniform vec3 col_dark : source_color = vec3(0.1, 0.05, 0.2);
uniform vec3 col_mid : source_color = vec3(0.2, 0.6, 0.6);
uniform vec3 col_light : source_color = vec3(0.8, 0.9, 0.8);
uniform float glow_shift = 0.0;     // rotation de teinte des parties lumineuses (en tours)
uniform float glow_power = 1.0;     // intensité des parties lumineuses
uniform float desaturate = 0.0;     // 1 = gris (créature morte)

vec3 rotate_hue(vec3 c, float turns) {
	float a = turns * 6.2831853;
	vec3 k = vec3(0.57735);
	return c * cos(a) + cross(k, c) * sin(a) + k * dot(k, c) * (1.0 - cos(a));
}

void fragment() {
	vec4 c = texture(TEXTURE, UV);
	float mx = max(c.r, max(c.g, c.b));
	float mn = min(c.r, min(c.g, c.b));
	float sat = mx > 0.0 ? (mx - mn) / mx : 0.0;
	float lum = dot(c.rgb, vec3(0.299, 0.587, 0.114));
	float l = clamp(lum * 1.7, 0.0, 1.0);
	vec3 tinted = l < 0.45 ? mix(col_dark, col_mid, l / 0.45) : mix(col_mid, col_light, (l - 0.45) / 0.55);
	// Reflets très clairs : on garde un peu de blanc pour l'aspect brillant
	tinted = mix(tinted, vec3(1.0), smoothstep(0.85, 1.0, lum) * 0.6);
	float k = 1.0 - smoothstep(0.18, 0.35, sat);
	vec3 glow = clamp(rotate_hue(c.rgb, glow_shift) * glow_power, 0.0, 1.0);
	vec3 rgb = mix(glow, tinted, k);
	float grey = dot(rgb, vec3(0.299, 0.587, 0.114));
	rgb = mix(rgb, vec3(grey) * 0.8, desaturate);
	COLOR = vec4(rgb, c.a) * COLOR;
}
