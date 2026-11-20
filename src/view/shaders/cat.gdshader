shader_type canvas_item;
// Pelage génétique du chat en pixel art. Le sprite est dessiné en gris
// (ombres et lumières), avec les yeux en vert pur et le nez, les oreilles et
// la gueule en rose ; deux masques indiquent où sont les rayures, les
// extrémités, l'ordre du blanc et les plaques d'écaille. Les couleurs viennent
// des gènes (CatCoat).

uniform sampler2D mask1 : filter_nearest;  // r le long du dos (u), v du dos au ventre (v), b région
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
uniform float seed = 0.0;
uniform bool blink = false;
uniform float tint = 1.0;        // assombrit (pattes et oreille du côté opposé, pièces détachées)      // paupières fermées (clignement)        // propre à chaque chat : ses rayures sont uniques


float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x),
		mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

// Rayures du tigré, calculées sur le corps (u le long du dos, v du dos au
// ventre) et déformées par du bruit : ondulées, d'épaisseur inégale, uniques
// à chaque chat. 1 = poil foncé, 0 = fond clair.
float tabby(vec3 m, int pat) {
	float u = m.r;
	float v = m.g;
	int reg = int(m.b * 4.0);
	vec2 sd = vec2(seed * 17.31, seed * 5.13);
	float wob = vnoise(vec2(u * 4.0, v * 2.5) + sd) - 0.5;
	float wob2 = vnoise(vec2(u * 9.0, v * 5.0) + sd * 1.7) - 0.5;
	if (reg == 3) {                                  // pattes : bracelets
		float bars = step(0.35 + wob2 * 0.4, sin(TAU * (v * 3.0 + u * 2.0 + wob * 0.5)));
		return bars * step(v, 0.85) * step(0.12, v);
	}
	if (reg == 2) {                                  // queue : anneaux, bout foncé
		float rings = step(0.3 + wob2 * 0.3, sin(TAU * (u * 9.0 + wob * 0.4)));
		return max(rings, step(u, 0.06));
	}
	if (pat == 3) return 0.0;                        // tiqueté : corps et tête unis
	if (reg == 1) {                                  // tête : traits du front (le « M »), joue
		float front = step(0.7, sin(TAU * (u * 16.0 + wob * 0.6))) * step(v, 0.3);
		float cheek = step(abs(v - 0.58 - wob * 0.08), 0.03) * step(u, 0.85);
		return max(front, cheek);
	}
	float dorsal = step(v, 0.1 + wob2 * 0.08);       // raie du dos
	float dark = 0.0;
	if (pat == 1) {
		// classique (marbré) : cercles concentriques sur le flanc, tache au centre
		float d = length(vec2((u - 0.45) * 2.4, (v - 0.55) * 1.2)) + wob * 0.45 + wob2 * 0.15;
		dark = max(step(0.3, sin(TAU * d * 3.0)), step(d, 0.1));
		dark = max(dark, step(v, 0.25) * step(0.3, sin(TAU * (v * 9.0 + wob))));
	} else {
		// maquereau : rayures verticales fines, inclinées, qui se brisent vers le ventre
		float sv = sin(TAU * (u * 8.0 + v * 0.8 + wob * 1.3));
		dark = step(0.38 + wob2 * 0.6 + v * 0.35, sv);
		if (pat == 2)                                // moucheté : rayures brisées en taches
			dark *= step(0.45, vnoise(vec2(u * 16.0, v * 6.0) + sd * 2.3));
	}
	return max(dark, dorsal) * (1.0 - step(0.93, v) * 0.6);
}

void fragment() {
	vec4 c = texture(TEXTURE, UV);
	// coordonnées prises au centre du pixel du sprite : rayures nettes
	vec2 ts = 1.0 / TEXTURE_PIXEL_SIZE;
	vec4 m1 = texture(mask1, (floor(UV * ts) + 0.5) / ts);
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
		float p = tabby(m1.rgb, pattern);
		if (pattern == 3) {
			bg = mix(bg, pig, 0.35);                   // tiqueté : poils bandés partout
			p *= 0.6;                                  // rayures pâles, aux pattes et à la queue
		}
		col = mix(bg, pig, p * contrast);
	} else if (silver) {
		col = mix(pig, vec3(0.9), 0.22);               // smoke : racines claires
	}
	if (points) {
		vec3 pale = mix(vec3(0.96, 0.92, 0.84), col, 0.1);
		col = mix(pale, col, smoothstep(0.08, 0.6, m2.r) * point_strength);
	}
	// panachure blanche : les zones dont l'« ordre » est sous le seuil blanchissent
	if (m2.g < white || white >= 0.999) col = vec3(1.0, 0.99, 0.96);
	// ombres et lumières du dessin d'origine
	// (les pelages clairs, le blanc surtout, gardent des ombres plus douces :
	// sinon un chat blanc paraît gris)
	float shade = lum / 0.62;
	float soft = smoothstep(0.55, 0.95, max(col.r, max(col.g, col.b)));
	shade = 1.0 + (shade - 1.0) * mix(1.0, 0.4, soft);
	vec3 rgb = col * clamp(shade, 0.15, 1.3);
	if (lum < 0.2) rgb = col * 0.25 + vec3(0.03, 0.02, 0.03);     // contour : version sombre du pelage
	if (eye) rgb = blink ? col * 0.45 : eye_color * (0.45 + 0.9 * lum) + vec3(step(0.85, lum) * 0.4);
	if (pink) rgb = c.rgb;
	float grey = dot(rgb, vec3(0.299, 0.587, 0.114));
	rgb = mix(rgb, vec3(grey) * 0.85, desaturate);
	// (pas « * COLOR » : en Godot 4, COLOR contient déjà la texture, ce qui
	// assombrissait tout le pelage d'environ 40 %)
	COLOR = vec4(rgb * tint, c.a);
}
