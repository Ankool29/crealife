shader_type canvas_item;
// Pelage génétique du chat en pixel art. Le sprite est dessiné en gris
// (ombres et lumières), avec les yeux en vert pur et le nez, les oreilles et
// la gueule en rose ; deux masques indiquent où sont les rayures, les
// extrémités, l'ordre du blanc et les plaques d'écaille. Les couleurs viennent
// des gènes (CatCoat).

uniform sampler2D mask1 : filter_linear;   // r maquereau, v classique, b moucheté
uniform sampler2D mask2 : filter_linear;   // r extrémités, v ordre du blanc, b plaques d'écaille
uniform vec3 col_e : source_color = vec3(0.08, 0.07, 0.065);   // eumélanine (noir, chocolat...)
uniform vec3 col_r : source_color = vec3(0.85, 0.45, 0.15);    // phaeomélanine (roux, crème)
uniform int orange = 0;          // 0 non, 1 roux, 2 écaille de tortue
uniform bool agouti = true;      // tigré visible sur l'eumélanine
uniform int pattern = 0;         // 0 maquereau, 1 classique, 2 moucheté, 3 tiqueté
uniform bool silver = false;
uniform float contrast = 0.8;
uniform bool points = false;
uniform float point_strength = 1.0;   // siamois : plus foncé au froid, pâle chez les chatons
uniform float white = 0.0;            // part de blanc (0 à 1)
uniform vec3 eye_color : source_color = vec3(0.4, 0.75, 0.3);
uniform float desaturate = 0.0;

void fragment() {
	vec4 c = texture(TEXTURE, UV);
	vec4 m1 = texture(mask1, UV);
	vec4 m2 = texture(mask2, UV);
	float lum = dot(c.rgb, vec3(0.299, 0.587, 0.114));
	bool eye = c.g > c.r + 0.15 && c.g > c.b + 0.15;
	bool pink = !eye && c.r > c.g + 0.1 && c.r > c.b + 0.02;

	bool red = orange == 1 || (orange == 2 && m2.b > 0.5);
	vec3 pig = red ? col_r : col_e;
	vec3 col = pig;
	if (red || agouti) {
		// fond aux poils bandés (agouti) : plus clair et chaud, ou argenté
		vec3 bg = silver ? vec3(0.86, 0.87, 0.9) : (red ? mix(pig, vec3(1.0, 0.9, 0.75), 0.45)
			: mix(pig, vec3(0.72, 0.58, 0.4), 0.62));
		float p = pattern == 0 ? m1.r : (pattern == 1 ? m1.g : (pattern == 2 ? m1.b : 0.0));
		if (pattern == 3) {
			bg = mix(bg, pig, 0.35);                   // tiqueté : poils bandés partout
			p = m1.r * step(0.4, m2.r);                // rayures seulement aux pattes et à la queue
		}
		col = mix(bg, pig, step(0.5, p) * contrast);
	} else if (silver) {
		col = mix(pig, vec3(0.9), 0.22);               // smoke : racines claires
	}
	if (points) {
		vec3 pale = mix(vec3(0.96, 0.92, 0.84), col, 0.1);
		col = mix(pale, col, clamp(m2.r * point_strength, 0.0, 1.0));
	}
	// panachure blanche : les zones dont l'« ordre » est sous le seuil blanchissent
	if (m2.g < white || white >= 0.999) col = vec3(0.97, 0.96, 0.93);
	// ombres et lumières du dessin d'origine
	vec3 rgb = col * clamp(lum / 0.72, 0.15, 1.35);
	if (lum < 0.2) rgb = col * 0.25 + vec3(0.03, 0.02, 0.03);     // contour : version sombre du pelage
	if (eye) rgb = eye_color * (0.45 + 0.9 * lum) + vec3(step(0.85, lum) * 0.4);
	if (pink) rgb = c.rgb;
	float grey = dot(rgb, vec3(0.299, 0.587, 0.114));
	rgb = mix(rgb, vec3(grey) * 0.85, desaturate);
	COLOR = vec4(rgb, c.a) * COLOR;
}
