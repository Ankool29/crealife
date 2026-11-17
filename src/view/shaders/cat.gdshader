shader_type canvas_item;
// Pelage génétique du chat. Le sprite est rendu en gris (relief et lumière) ;
// deux masques indiquent où sont les rayures, les extrémités, l'ordre du blanc
// et les plaques d'écaille. Les couleurs viennent des gènes (CatCoat).

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
	float mx = max(c.r, max(c.g, c.b));
	float mn = min(c.r, min(c.g, c.b));
	float sat = mx > 0.0 ? (mx - mn) / mx : 0.0;

	bool red = orange == 1 || (orange == 2 && m2.b > 0.5);
	vec3 pig = red ? col_r : col_e;
	vec3 col = pig;
	if (red || agouti) {
		// fond aux poils bandés (agouti) : plus clair et chaud, ou argenté
		vec3 bg = silver ? vec3(0.86, 0.87, 0.9) : (red ? mix(pig, vec3(1.0, 0.9, 0.75), 0.45)
			: mix(pig, vec3(0.72, 0.58, 0.4), 0.62));
		float p = pattern == 0 ? m1.r : (pattern == 1 ? max(m1.g, m1.r * 0.4) : (pattern == 2 ? m1.b : 0.0));
		if (pattern == 3) {
			bg = mix(bg, pig, 0.35);                   // tiqueté : poils bandés partout
			p = m1.r * m2.r * 0.8;                     // rayures seulement aux pattes et à la queue
		}
		col = mix(bg, pig, clamp(p * contrast, 0.0, 1.0));
	} else if (silver) {
		col = mix(pig, vec3(0.9), 0.22);               // smoke : racines claires
	}
	if (points) {
		vec3 pale = mix(vec3(0.96, 0.93, 0.86), col, 0.1);
		col = mix(pale, col, clamp(m2.r * point_strength, 0.0, 1.0));
	}
	// panachure blanche : les zones dont l'« ordre » est sous le seuil blanchissent
	float w = 1.0 - smoothstep(white - 0.04, white + 0.04, m2.g);
	if (white >= 0.999) w = 1.0;
	col = mix(col, vec3(0.97, 0.96, 0.93), w);
	// relief et lumière du rendu 3D
	vec3 rgb = col * (0.28 + 1.05 * lum) + vec3(smoothstep(0.82, 1.0, lum) * 0.25);
	// yeux (pixels colorés du rendu) : couleur des gènes
	float eye = smoothstep(0.3, 0.5, sat);
	rgb = mix(rgb, eye_color * (0.5 + 1.2 * lum), eye);
	float grey = dot(rgb, vec3(0.299, 0.587, 0.114));
	rgb = mix(rgb, vec3(grey) * 0.85, desaturate);
	COLOR = vec4(rgb, c.a) * COLOR;
}
