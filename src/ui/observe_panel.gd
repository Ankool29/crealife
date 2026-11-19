class_name ObservePanel
extends PanelContainer
## Outils d'observation (façon « Science Kit ») sur la créature sélectionnée :
## Chimie, Cerveau, Mots, Gènes, Famille. Lecture seule : rien n'est modifié.

const TABS: Array[String] = ["Chimie", "Cerveau", "Mots", "Gènes", "Famille"]
const FONT_SIZE := 18

var creature: CreatureSim
var world: WorldSim

var _tab := 0
var _tab_buttons: Array[Button] = []
var _chem_view := ChemView.new()
var _brain_view := BrainView.new()
var _text := RichTextLabel.new()
var _scroll := ScrollContainer.new()
var _refresh := 0.0


func _ready() -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.07, 0.1, 0.14, 0.92)
	style.set_corner_radius_all(16)
	style.set_content_margin_all(14)
	add_theme_stylebox_override("panel", style)
	var box := VBoxContainer.new()
	add_child(box)
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 8)
	box.add_child(bar)
	for i in TABS.size():
		var b := Button.new()
		b.text = TABS[i]
		b.custom_minimum_size = Vector2(104, 64)
		b.focus_mode = Control.FOCUS_NONE
		b.toggle_mode = true
		b.pressed.connect(_select_tab.bind(i))
		bar.add_child(b)
		_tab_buttons.append(b)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(spacer)
	var close := Button.new()
	close.text = "×"
	close.custom_minimum_size = Vector2(64, 64)
	close.focus_mode = Control.FOCUS_NONE
	close.pressed.connect(func() -> void: visible = false)
	bar.add_child(close)

	var content := Control.new()
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.clip_contents = true
	box.add_child(content)
	for v in [_chem_view, _brain_view, _scroll]:
		v.set_anchors_preset(Control.PRESET_FULL_RECT)
		content.add_child(v)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_text.bbcode_enabled = true
	_text.fit_content = true
	_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_text.add_theme_font_size_override("normal_font_size", FONT_SIZE)
	_text.add_theme_font_size_override("bold_font_size", FONT_SIZE + 2)
	_scroll.add_child(_text)
	_select_tab(0)


func _select_tab(i: int) -> void:
	_tab = i
	for k in _tab_buttons.size():
		_tab_buttons[k].button_pressed = k == i
	_chem_view.visible = i == 0
	_brain_view.visible = i == 1
	_scroll.visible = i >= 2
	_refresh = 0.0
	_update_text()


func _process(delta: float) -> void:
	if not visible or creature == null:
		return
	_chem_view.creature = creature
	_brain_view.creature = creature
	_chem_view.queue_redraw()
	_brain_view.queue_redraw()
	_refresh -= delta
	if _refresh <= 0.0:
		_refresh = 1.0
		_update_text()


func _update_text() -> void:
	if creature == null or world == null:
		return
	if _tab == 2:
		_text.text = _words_text(creature)
	elif _tab == 3:
		_text.text = _genes_text(creature)
	elif _tab == 4:
		_text.text = _family_text()


func _words_text(c: CreatureSim) -> String:
	var L := c.language
	var t := "[b]%s connaît %d mots[/b]" % [c.creature_name, L.vocabulary_size()]
	t += "   [color=#9fb3c8]%s : apprend ×%.1f%s[/color]" % [Lifecycle.STAGE_LABELS[c.stage], L.plasticity,
		", oublie les mots inutilisés" if L.forgetting else ""]
	if L.last_heard != "":
		t += "   [color=#9fb3c8]a entendu : « %s »[/color]" % L.last_heard
	t += "\n[color=#9fb3c8]Dites un nom quand elle regarde l'objet, un verbe pendant qu'elle fait l'action, "
	t += "un besoin quand elle le ressent. Caressez-la quand elle obéit.[/color]\n"
	for group in [["Noms", "nom", ObjectCatalog.categories.size()], ["Verbes", "verbe", Language.VERB_WORDS.size()],
			["Besoins", "besoin", Language.DRIVE_WORDS.size()]]:
		var lines := ""
		for i in group[2]:
			if group[1] == "verbe" and i == 0:
				continue
			var k := L.knowledge(group[1], i)
			if k < 0.02:
				continue
			var filled := int(round(k * 10.0))
			var bar := "[color=#7fd6c2]%s[/color][color=#3a4652]%s[/color]" % ["█".repeat(filled), "█".repeat(10 - filled)]
			var line := "%s  %s  dit « %s »" % [bar, Language.word_of(group[1], i), L.pronounce(group[1], i)]
			if group[1] == "verbe":
				line += "  [color=#9fb3c8]obéissance %.1f[/color]" % c.brain.obedience(i)
			lines += line + "\n"
		t += "\n[b]%s[/b]\n%s" % [group[0], lines if lines != "" else "[color=#6b7785]aucun pour l'instant[/color]\n"]
	return t


func _genes_text(c: CreatureSim) -> String:
	var counts := {}
	for g in c.genome.genes:
		counts[g.type] = counts.get(g.type, 0) + 1
	var parts := PackedStringArray()
	for t in counts:
		parts.append("%s %d" % [Gene.TYPE_LABELS[t], counts[t]])
	var t := "[b]%s : %d gènes[/b]   (génération %d" % [c.creature_name, c.genome.genes.size(), c.generation]
	if c.mother != "":
		t += ", mère %s, père %s" % [c.mother, c.father]
	t += ")\n[color=#9fb3c8]%s[/color]\n" % " · ".join(parts)
	if not c.coat.is_empty():
		t += "[b]Pelage : %s[/b]%s\n" % [c.coat.name, "  [color=#ff9f80](sourd)[/color]" if c.coat.deaf else ""]
	t += "\n"
	for g in c.genome.genes:
		var active := g.is_expressed(c.stage, c.sex)
		var line := "[color=#7fd6c2]%s[/color]  %s" % [Gene.TYPE_LABELS[g.type], _gene_summary(g)]
		if g.stage > 0:
			line += "  [color=#9fb3c8](dès : %s)[/color]" % Lifecycle.STAGE_LABELS[g.stage].to_lower()
		if not active:
			line = "[color=#6b7785]" + line + "[/color]"
		t += line + "\n"
	return t


func _gene_summary(g: Gene) -> String:
	var p := g.params
	match g.type:
		Gene.Type.SUBSTANCE:
			return "%s, demi-vie %s" % [p.chem, "stable" if float(p.half_life) <= 0.0 else "%d s" % int(p.half_life)]
		Gene.Type.REACTION:
			var right := str(p.c) if str(p.c) != "" else "rien"
			return "%s → %s  (vitesse %.3f, %s)" % [p.a, right, float(p.rate), p.organ]
		Gene.Type.EMITTER:
			return "%s → %s  (gain %.4f)" % [str(p.source).replace("chem:", ""), p.chem, float(p.gain)]
		Gene.Type.RECEPTOR:
			return "%s → %s  (gain %.3f)" % [p.chem, p.locus, float(p.gain)]
		Gene.Type.ORGAN:
			return "%s, longévité %.1f h" % [p.organ, float(p.longevity_h)]
		Gene.Type.LOBE:
			if str(p.lobe) == "temperament":
				return "tempérament : curiosité %.2f, espièglerie %.2f" % [float(p.get("curiosity", 0)), float(p.get("playfulness", 0))]
			if str(p.lobe) == "gout":
				return "goûts : pâtée %.2f, croquettes %.2f, proies %.2f ; instinct de chasse %.2f" % [
					float(p.get("patee", 0)), float(p.get("croquettes", 0)), float(p.get("proie", 0)), float(p.get("chasse", 0))]
			if str(p.lobe) == "parental":
				return "instinct parental %.2f (nourrir et parler à ses petits)" % float(p.get("care", 0))
			if str(p.lobe) == "langage":
				return "lobe langage, apprentissage %.2f, bavardage %.2f, obéissance %.2f" % [
					float(p.get("learning_rate", 0)), float(p.get("talk", 0)), float(p.get("obey", 0))]
			var txt := "lobe %s, curiosité %.2f, apprentissage %.2f" % [p.lobe, float(p.get("noise", 0)), float(p.learning_rate)]
			if p.has("ageing"):
				txt += ", maturation %.2f" % float(p.ageing)
			return txt
		Gene.Type.INSTINCT:
			var cat := str(p.category) if str(p.category) != "" else "rien"
			return "%s + %s → %s  (%+.1f)" % [p.drive, cat, p.verb, float(p.reward)]
		Gene.Type.APPEARANCE:
			if str(p.get("part", "")) == "pelage":
				var pairs := PackedStringArray()
				for locus in CatCoat.LOCI:
					pairs.append("%s %d/%d" % [locus, int(p.get(locus + "1", 0)), int(p.get(locus + "2", 0))])
				return "pelage (allèles, 0 = sauvage) : " + "  ".join(pairs)
			if str(p.get("part", "")) == "morpho":
				return "morphologie : tête %.2f (en coin → ronde), yeux %.2f, roux %.2f, blanc %.2f, contraste %.2f" % [
					float(p.get("head", 0)), float(p.get("eye", 0)), float(p.get("rufous", 0)),
					float(p.get("white_grade", 0)), float(p.get("contrast", 0))]
			if str(p.get("part", "")) == "motif":
				var names := PackedStringArray()
				for pair in [["taches", "spots"], ["rayures", "stripes"], ["plaques", "patches"]]:
					var v := float(p.get(pair[1], 0))
					names.append("%s %.2f%s" % [pair[0], v, "" if v >= 0.2 else " (dormant)"])
				return "motif : %s, teinte %.2f" % [", ".join(names), float(p.get("hue3", 0))]
			if str(p.get("part", "")) == "silhouette":
				return "queue %s, antennes %s, corpulence %.2f" % [
					["courte", "longue", "massue"][clampi(int(float(p.get("tail", 0.5)) * 3.0), 0, 2)],
					["courtes", "longues", "ramifiées"][clampi(int(float(p.get("antennae", 0.5)) * 3.0), 0, 2)],
					float(p.get("corpulence", 0.5))]
			return "teinte %.2f, 2e teinte %.2f, saturation %.2f, lumière %.2f (force %.2f), taille %.2f, vitesse %.2f" % [
				float(p.get("hue", 0)), float(p.get("hue2", 0)), float(p.get("saturation", 0)),
				float(p.get("glow", 0)), float(p.get("glow_power", 0.5)), float(p.get("size", 0)), float(p.get("speed", 0))]
	return str(p)


func _family_text() -> String:
	var rows := world.history.duplicate()
	rows.sort_custom(func(a, b): return a.generation < b.generation or (a.generation == b.generation and a.born_at < b.born_at))
	var t := "[b]Famille : %d créatures, %d vivantes[/b]\n\n" % [rows.size(), world.alive_count()]
	var gen := 0
	for h in rows:
		if int(h.generation) != gen:
			gen = int(h.generation)
			t += "[b]Génération %d[/b]\n" % gen
		var sex := "♀" if int(h.sex) == Gene.Sex.FEMALE else "♂"
		var col := Color.from_hsv(float(h.get("hue", 0.5)), 0.7, 0.95).to_html(false)
		var line := "  [color=#%s]●[/color] %s %s" % [col, h.name, sex]
		if str(h.get("coat", "")) != "":
			line += " [color=#c8b89f](%s)[/color]" % h.coat
		if str(h.mother) != "":
			line += "  [color=#9fb3c8]de %s et %s[/color]" % [h.mother, h.father]
		if bool(h.alive):
			var c := _find(int(h.uid))
			line += "  — vivante" + (", %s" % c.format_age() if c else "")
			if c and c.pregnant_time >= 0.0:
				line += ", attend des petits"
		else:
			var m := int(float(h.age) / 60.0)
			line += "  — morte %s à %d h %02d" % [h.cause, m / 60, m % 60]
		if creature and int(h.uid) == creature.uid:
			line = "[b]" + line + "[/b]"
		t += line + "\n"
	return t


func _find(uid: int) -> CreatureSim:
	for c in world.creatures:
		if c.uid == uid:
			return c
	return null


# --------------------------------------------------------------- chimie ----
class ChemView extends Control:
	var creature: CreatureSim
	const FAMILY_COLORS := {
		"énergie": Color(0.95, 0.7, 0.25), "digestion": Color(0.85, 0.55, 0.3), "déchets": Color(0.6, 0.5, 0.4),
		"hormone": Color(0.85, 0.45, 0.8), "pulsion": Color(0.4, 0.65, 1.0), "renforcement": Color(0.4, 0.9, 0.5),
		"immunité": Color(0.9, 0.35, 0.35),
	}

	func _draw() -> void:
		if creature == null:
			return
		var font := ThemeDB.fallback_font
		var cols := 3
		var col_w := size.x / cols
		var row_h := 27.0
		var items := []
		for i in range(1, Chemicals.MAX):
			if Chemicals.name_of(i) != "":
				items.append(i)
		var rows := int(ceil((items.size() + 7) / float(cols)))
		var k := 0
		for i in items:
			var x := (k / rows) * col_w
			var y := (k % rows) * row_h + 20.0
			var v := creature.biochem.conc[i]
			var col: Color = FAMILY_COLORS.get(Chemicals.family_of(i), Color.WHITE)
			draw_string(font, Vector2(x, y + 14), Chemicals.name_of(i), HORIZONTAL_ALIGNMENT_LEFT, col_w * 0.55, 15, Color(0.85, 0.9, 0.95))
			var bx := x + col_w * 0.56
			var bw := col_w * 0.38
			draw_rect(Rect2(bx, y + 3, bw, 13), Color(1, 1, 1, 0.08))
			draw_rect(Rect2(bx, y + 3, bw * clampf(v, 0.0, 1.0), 13), col)
			k += 1
		k += 1
		for o in creature.biochem.organs.slice(1):
			var x := (k / rows) * col_w
			var y := (k % rows) * row_h + 20.0
			draw_string(font, Vector2(x, y + 14), "♥ " + o.organ_name, HORIZONTAL_ALIGNMENT_LEFT, col_w * 0.55, 15, Color(1, 0.85, 0.85))
			var bx := x + col_w * 0.56
			var bw := col_w * 0.38
			draw_rect(Rect2(bx, y + 3, bw, 13), Color(1, 1, 1, 0.08))
			draw_rect(Rect2(bx, y + 3, bw * o.health, 13), Color(0.35, 0.85, 0.45).lerp(Color(0.9, 0.3, 0.3), 1.0 - o.health))
			k += 1


# --------------------------------------------------------------- cerveau ----
class BrainView extends Control:
	var creature: CreatureSim
	const SHORT_DRIVES: Array[String] = ["Faim", "Soif", "Fatig.", "Somm.", "Doul.", "Peur", "Ennui", "Solit.", "Foule", "Froid", "Chaud", "Désir"]

	func _draw() -> void:
		if creature == null:
			return
		var b := creature.brain
		var font := ThemeDB.fallback_font
		var w := size.x
		var y := 22.0
		# Pulsions
		draw_string(font, Vector2(0, y), "Pulsions", HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color(0.7, 0.8, 0.9))
		y += 30.0
		var step := w / Brain.DRIVE_COUNT
		for d in Brain.DRIVE_COUNT:
			var cx := step * (d + 0.5)
			var a := b.drives[d]
			draw_circle(Vector2(cx, y), 14.0, Color(0.15, 0.2, 0.3))
			draw_circle(Vector2(cx, y), 3.0 + 11.0 * a, Color(0.4, 0.65, 1.0).lerp(Color(1.0, 0.45, 0.3), a))
			draw_string(font, Vector2(cx - step * 0.5, y + 34), SHORT_DRIVES[d], HORIZONTAL_ALIGNMENT_CENTER, step, 13, Color(0.8, 0.85, 0.9))
		y += 62.0
		# Vision et attention
		draw_string(font, Vector2(0, y), "Ce qu'elle voit  (cercle blanc : ce qui retient son attention)", HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color(0.7, 0.8, 0.9))
		y += 30.0
		var cats := b.category_count()
		var cstep := w / cats
		for c in cats:
			var cx := cstep * (c + 0.5)
			draw_circle(Vector2(cx, y), 14.0, Color(0.15, 0.2, 0.3))
			draw_circle(Vector2(cx, y), 3.0 + 11.0 * b.vision[c], Color(0.95, 0.8, 0.3))
			if c == b.attention:
				draw_arc(Vector2(cx, y), 19.0, 0, TAU, 32, Color.WHITE, 3.0)
			draw_string(font, Vector2(cx - cstep * 0.5, y + 34), ObjectCatalog.category_label(c), HORIZONTAL_ALIGNMENT_CENTER, cstep, 13, Color(0.8, 0.85, 0.9))
		y += 62.0
		# Décision
		draw_string(font, Vector2(0, y), "Décision  (envie de chaque verbe)", HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color(0.7, 0.8, 0.9))
		y += 12.0
		var vstep := w / Brain.VERB_COUNT
		var max_s := 0.01
		for v in Brain.VERB_COUNT:
			max_s = maxf(max_s, absf(b.decision[v]))
		for v in Brain.VERB_COUNT:
			var x := vstep * v
			var hgt := 60.0 * clampf(b.decision[v] / max_s, -1.0, 1.0)
			var col := Color(0.4, 0.9, 0.55) if v == b.verb else Color(0.45, 0.55, 0.7)
			if hgt >= 0.0:
				draw_rect(Rect2(x + 4, y + 60 - hgt, vstep - 8, hgt), col)
			else:
				draw_rect(Rect2(x + 4, y + 60, vstep - 8, -hgt * 0.3), Color(0.8, 0.4, 0.4))
			draw_string(font, Vector2(x, y + 80), Brain.VERB_KEYS[v], HORIZONTAL_ALIGNMENT_CENTER, vstep, 12, Color(1, 1, 1) if v == b.verb else Color(0.75, 0.8, 0.85))
		y += 108.0
		# Associations apprises
		draw_string(font, Vector2(0, y), "Ce qu'elle a appris (associations les plus fortes)", HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color(0.7, 0.8, 0.9))
		y += 8.0
		var best := []
		var slots := cats + 1
		for d in Brain.DRIVE_COUNT:
			for s in slots:
				for v in Brain.VERB_COUNT:
					var wgt := b.stw[(d * slots + s) * Brain.VERB_COUNT + v]
					if absf(wgt) > 0.3:
						best.append([absf(wgt), wgt, d, s, v])
		best.sort_custom(func(p, q): return p[0] > q[0])
		var col_w := w / 2.0
		for i in mini(10, best.size()):
			var e = best[i]
			var obj := "rien de particulier" if e[3] == cats else ObjectCatalog.category_label(e[3])
			var txt := "%s + %s → %s  (%+.1f)" % [Brain.DRIVE_NAMES[e[2]], obj, Brain.VERB_KEYS[e[4]], e[1]]
			var col := Color(0.55, 0.95, 0.6) if e[1] > 0 else Color(1.0, 0.55, 0.5)
			draw_string(font, Vector2((i % 2) * col_w, y + 22 + (i / 2) * 24), txt, HORIZONTAL_ALIGNMENT_LEFT, col_w - 10, 15, col)
