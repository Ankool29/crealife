class_name WorldOverlay
extends Node2D
## Ce qui se dessine par-dessus le décor et les objets : le contenu de
## l'écran d'apprentissage, les notes de la boîte à musique, la nuit, la
## pluie, la neige et le sol enneigé (zones extérieures seulement).

const NOUN_SPRITES := {"fruit": "fruit", "graine": "graine", "baie": "baie", "jouet": "balle",
	"machine": "distributeur_on", "pierre": "pierre", "œuf": "oeuf"}
const VERB_ANIM := {"approcher": "marche", "fuir": "marche", "explorer": "marche", "examiner": "examiner",
	"prendre": "prendre", "lâcher": "prendre", "manger": "manger", "pousser": "pousser", "tirer": "pousser",
	"frapper": "frapper", "parler": "parler", "dormir": "dormir", "accoupler": "parler"}
const PANE_CENTER := Vector2(0, -150)     # centre de la dalle de l'écran, au-dessus de son pied
const PANE_SIZE := Vector2(126, 86)
const NIGHT := Color(0.03, 0.05, 0.16)
const EDGE := 140.0                       # fondu entre la salle éclairée et la nuit dehors

var view: WorldView
var _t := 0.0


func _ready() -> void:
	z_index = 40
	SpriteLibrary.ensure()


func _process(delta: float) -> void:
	_t += delta


func _draw() -> void:
	var w := view.world if view else null
	if w == null:
		return
	var font := ThemeDB.fallback_font
	for o in w.objects:
		if o.type_name == "ecran":
			_draw_screen(w, o, font)
		elif o.type_name == "boite_musique" and o.cooldown > 0.0:
			_draw_notes(o, font)
	if w.scenario == "normal" and view.camera:
		_draw_climate(w)


func _draw_screen(w: WorldSim, o: WorldObject, font: Font) -> void:
	var c := Vector2(o.x, -o.h) + PANE_CENTER
	var item := w.screen_item()
	var kind: String = item[0]
	var i: int = item[1]
	var word := Language.word_of(kind, i)
	var area := Rect2(c - PANE_SIZE * 0.5, PANE_SIZE)
	draw_string(font, area.position + Vector2(6, 14), WorldSim.SCREEN_MODES[w.screen.mode], HORIZONTAL_ALIGNMENT_LEFT, -1, 11,
		Color(0.6, 1.0, 0.85, 0.7))
	var pic := Rect2(c + Vector2(-30, -36), Vector2(60, 52))
	var tex: Texture2D = null
	if kind == "nom":
		var cat: String = ObjectCatalog.categories[i]
		if cat == "créature":
			tex = SpriteLibrary.creature_frames["repos"][0]
		elif NOUN_SPRITES.has(cat):
			tex = SpriteLibrary.objects[NOUN_SPRITES[cat]].texture
	elif kind == "verbe":
		var frames: Array = SpriteLibrary.creature_frames.get(VERB_ANIM.get(Language.VERB_WORDS[i], "repos"), [])
		if not frames.is_empty():
			tex = frames[int(_t * 3.0) % frames.size()]
	if tex:
		draw_texture_rect(tex, pic, false, Color(0.75, 1.0, 0.9) if kind == "verbe" else Color.WHITE)
	elif kind == "besoin":
		var col := Color.from_hsv(float(i) / Language.DRIVE_WORDS.size(), 0.6, 1.0)
		draw_circle(pic.get_center(), 20.0, col)
		draw_string(font, pic.get_center() + Vector2(-20, 7), "!", HORIZONTAL_ALIGNMENT_CENTER, 40, 22, Color(0.1, 0.1, 0.15))
	draw_string(font, Vector2(area.position.x, area.end.y - 8), word, HORIZONTAL_ALIGNMENT_CENTER, PANE_SIZE.x, 18, Color.WHITE)


func _draw_notes(o: WorldObject, font: Font) -> void:
	for k in 3:
		var p := fmod(_t * 0.6 + k / 3.0, 1.0)
		var pos := Vector2(o.x + 10.0 + sin(_t * 2.0 + k) * 18.0 + k * 12.0, -o.h - 70.0 - p * 90.0)
		draw_string(font, pos, "♪" if k % 2 == 0 else "♫", HORIZONTAL_ALIGNMENT_LEFT, -1, 30,
			Color(1.0, 0.95, 0.6, 1.0 - p))


func _draw_climate(w: WorldSim) -> void:
	var half := view.get_viewport_rect().size * 0.5 / view.camera.zoom
	var left := view.camera.position.x - half.x - 50.0
	var right := view.camera.position.x + half.x + 50.0
	var top := -900.0
	var bottom := 260.0
	var dark := (1.0 - w.climate.daylight(w.time)) * 0.62
	var cloudy := 0.0 if w.climate.weather == 0 else (0.08 if w.climate.weather == 1 else 0.16)
	var winter := w.climate.season(w.time) == 3 and w.climate.outdoor_temp(w.time) < 3.0
	for z in w.zones:
		if z.indoor:
			continue
		var x0: float = maxf(z.x0, left)
		var x1: float = minf(z.x1, right)
		if x1 <= x0:
			continue
		# Sol enneigé en hiver
		if winter:
			draw_rect(Rect2(x0, -5.0, x1 - x0, 7.0), Color(0.95, 0.97, 1.0, 0.85))
			draw_rect(Rect2(x0, top, x1 - x0, bottom - top), Color(0.85, 0.9, 1.0, 0.12))
		# Ciel couvert puis nuit
		if cloudy > 0.0:
			draw_rect(Rect2(x0, top, x1 - x0, bottom - top), Color(0.45, 0.48, 0.55, cloudy))
		if dark > 0.01:
			var col := Color(NIGHT, dark)
			draw_rect(Rect2(x0, top, x1 - x0, bottom - top), col)
			# fondu du côté d'une zone éclairée (la salle)
			for other in w.zones:
				if other.indoor and absf(other.x1 - z.x0) < 1.0:
					var transparent := Color(NIGHT, 0.0)
					draw_polygon(PackedVector2Array([Vector2(z.x0 - EDGE, top), Vector2(z.x0, top),
						Vector2(z.x0, bottom), Vector2(z.x0 - EDGE, bottom)]),
						PackedColorArray([transparent, col, col, transparent]))
		# Précipitations
		if w.climate.is_raining():
			_draw_precipitation(x0, x1, w.climate.is_snowing(w.time))


func _draw_precipitation(x0: float, x1: float, snow: bool) -> void:
	var n := int((x1 - x0) / 9.0)
	var height := 640.0           # du haut du ciel jusqu'au sol
	for k in n:
		var seed := float(k) * 12.9898
		var x := x0 + fposmod(seed * 37.0 + (_t * (25.0 if snow else 60.0)), x1 - x0)
		var speed := (90.0 if snow else 900.0) * (0.8 + 0.4 * fposmod(seed, 1.0))
		var y := fposmod(seed * 53.0 + _t * speed, height) - height
		if snow:
			x += sin(_t * 1.5 + seed) * 12.0
			draw_circle(Vector2(x, y), 3.0, Color(1, 1, 1, 0.85))
		else:
			draw_line(Vector2(x, y), Vector2(x - 4.0, y + 22.0), Color(0.75, 0.82, 0.95, 0.55), 2.0)
