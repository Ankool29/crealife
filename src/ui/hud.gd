class_name Hud
extends CanvasLayer
## Interface tactile : état de la créature sélectionnée en haut à gauche,
## gros boutons en bas, panneau d'observation à droite.

signal caress_pressed
signal scold_pressed
signal fruit_pressed
signal speed_pressed
signal follow_pressed
signal new_creature_pressed
signal next_creature_pressed
signal say_pressed(text: String)

const MARGIN := 40  # marge pour l'encoche / les bords arrondis
const BAR_LABELS: Array[String] = ["Faim", "Soif", "Fatigue", "Ennui", "Solitude", "Désir", "Santé"]
const BAR_COLORS: Array[Color] = [
	Color(0.9, 0.55, 0.2), Color(0.3, 0.65, 0.95), Color(0.45, 0.55, 0.95),
	Color(0.75, 0.45, 0.85), Color(0.6, 0.75, 0.8), Color(0.95, 0.45, 0.6), Color(0.35, 0.8, 0.4),
]

var observe: ObservePanel

var _name_label: Label
var _info_label: Label
var _action_label: Label
var _event_label: Label
var _bars: Array[ProgressBar] = []
var _speed_button: Button
var _follow_button: Button
var _new_button: Button
var _speech_panel: PanelContainer
var _speech_line: LineEdit

## Mots proposés sous forme de boutons (on peut aussi taper la phrase).
const CHIPS := [
	["fruit", "graine", "baie", "balle", "machine", "pierre", "créature", "œuf"],
	["viens", "mange", "pousse", "prends", "lâche", "examine", "tire", "frappe", "parle", "dors", "explore", "repose"],
	["faim", "soif", "fatigue", "ennui", "solitude", "douleur", "peur", "désir"],
]


func _ready() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var theme := Theme.new()
	theme.default_font_size = 24
	root.theme = theme
	add_child(root)

	# --- Panneau d'état ---
	var panel := _panel()
	panel.position = Vector2(MARGIN, 16)
	root.add_child(panel)
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 2)
	panel.add_child(box)
	_name_label = Label.new()
	_name_label.add_theme_font_size_override("font_size", 28)
	box.add_child(_name_label)
	_info_label = Label.new()
	_info_label.add_theme_font_size_override("font_size", 18)
	_info_label.modulate = Color(0.75, 0.82, 0.9)
	box.add_child(_info_label)
	for i in BAR_LABELS.size():
		var row := HBoxContainer.new()
		var l := Label.new()
		l.text = BAR_LABELS[i]
		l.add_theme_font_size_override("font_size", 20)
		l.custom_minimum_size = Vector2(110, 0)
		row.add_child(l)
		var bar := ProgressBar.new()
		bar.max_value = 1.0
		bar.step = 0.001
		bar.show_percentage = false
		bar.custom_minimum_size = Vector2(220, 18)
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var fill := StyleBoxFlat.new()
		fill.bg_color = BAR_COLORS[i]
		fill.set_corner_radius_all(6)
		bar.add_theme_stylebox_override("fill", fill)
		row.add_child(bar)
		box.add_child(row)
		_bars.append(bar)
	_action_label = Label.new()
	box.add_child(_action_label)

	# --- Message (haut, centré) ---
	_event_label = Label.new()
	_event_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_event_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_event_label.position.y = 20
	_event_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_event_label.add_theme_font_size_override("font_size", 21)
	_event_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_event_label.add_theme_constant_override("outline_size", 6)
	root.add_child(_event_label)

	# --- Panneau d'observation (masqué au départ) ---
	observe = ObservePanel.new()
	observe.visible = false
	observe.anchor_left = 0.36
	observe.anchor_right = 1.0
	observe.anchor_top = 0.0
	observe.anchor_bottom = 1.0
	observe.offset_left = 0
	observe.offset_right = -16
	observe.offset_top = 12
	observe.offset_bottom = -130
	root.add_child(observe)

	# --- Boutons ---
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 12)
	root.add_child(buttons)
	_new_button = _add_button(buttons, "Nouvelle lignée", new_creature_pressed)
	_new_button.visible = false
	_add_button(buttons, "Caresser", caress_pressed)
	_add_button(buttons, "Gronder", scold_pressed)
	_add_button(buttons, "Fruit", fruit_pressed)
	var talk := Button.new()
	talk.text = "Parler"
	talk.custom_minimum_size = Vector2(130, 90)
	talk.focus_mode = Control.FOCUS_NONE
	talk.pressed.connect(func() -> void:
		_speech_panel.visible = not _speech_panel.visible
		if not _speech_panel.visible:
			_speech_line.release_focus())
	buttons.add_child(talk)
	_add_button(buttons, "Suivante", next_creature_pressed)
	var obs := Button.new()
	obs.text = "Observer"
	obs.custom_minimum_size = Vector2(140, 90)
	obs.focus_mode = Control.FOCUS_NONE
	obs.pressed.connect(func() -> void: observe.visible = not observe.visible)
	buttons.add_child(obs)
	_speed_button = _add_button(buttons, "x1", speed_pressed)
	_follow_button = _add_button(buttons, "Suivre", follow_pressed)
	_build_speech_panel(root)
	buttons.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT, Control.PRESET_MODE_MINSIZE, MARGIN * 0.5)
	buttons.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	buttons.grow_vertical = Control.GROW_DIRECTION_BEGIN


## Panneau « Parler » : une ligne de texte et des mots à toucher.
func _build_speech_panel(root: Control) -> void:
	_speech_panel = _panel()
	_speech_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_speech_panel.visible = false
	_speech_panel.anchor_left = 0.0
	_speech_panel.anchor_right = 0.62
	_speech_panel.anchor_top = 1.0
	_speech_panel.anchor_bottom = 1.0
	_speech_panel.offset_left = MARGIN
	_speech_panel.offset_bottom = -126
	_speech_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	root.add_child(_speech_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	_speech_panel.add_child(box)
	var row := HBoxContainer.new()
	box.add_child(row)
	_speech_line = LineEdit.new()
	_speech_line.placeholder_text = "ex. : mange la graine"
	_speech_line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_speech_line.custom_minimum_size = Vector2(0, 64)
	_speech_line.text_submitted.connect(func(_t: String) -> void: _send_speech())
	row.add_child(_speech_line)
	for pair in [["Effacer", func() -> void: _speech_line.text = ""], ["Dire", _send_speech]]:
		var b := Button.new()
		b.text = pair[0]
		b.custom_minimum_size = Vector2(110, 64)
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(pair[1])
		row.add_child(b)
	var colors := [Color(0.75, 0.95, 0.85), Color(1.0, 0.9, 0.7), Color(0.95, 0.8, 0.95)]
	for g in CHIPS.size():
		var flow := HFlowContainer.new()
		flow.add_theme_constant_override("h_separation", 6)
		flow.add_theme_constant_override("v_separation", 6)
		box.add_child(flow)
		for w in CHIPS[g]:
			var chip := Button.new()
			chip.text = w
			chip.focus_mode = Control.FOCUS_NONE
			chip.custom_minimum_size = Vector2(0, 52)
			chip.add_theme_font_size_override("font_size", 20)
			chip.modulate = colors[g]
			chip.pressed.connect(func() -> void:
				_speech_line.text = (_speech_line.text + " " + w).strip_edges())
			flow.add_child(chip)


func _send_speech() -> void:
	var t := _speech_line.text.strip_edges()
	if t != "":
		say_pressed.emit(t)
	_speech_line.text = ""
	_speech_line.release_focus()


func _panel() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.15, 0.2, 0.7)
	style.set_corner_radius_all(14)
	style.set_content_margin_all(14)
	panel.add_theme_stylebox_override("panel", style)
	return panel


func _add_button(parent: Control, text: String, sig: Signal) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(130, 90)
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(func() -> void: sig.emit())
	parent.add_child(b)
	return b


func update_from(c: CreatureSim, world: WorldSim, event_text: String, sim_speed: float, following: bool) -> void:
	observe.creature = c
	observe.world = world
	_event_label.text = event_text
	_speed_button.text = "x%d" % int(sim_speed)
	_follow_button.modulate = Color.WHITE if following else Color(1, 1, 1, 0.5)
	_new_button.visible = world.is_extinct()
	if c == null:
		return
	var sex_mark := "♀" if c.sex == Gene.Sex.FEMALE else "♂"
	_name_label.text = "%s %s  ·  %s  ·  %s" % [c.creature_name, sex_mark, Lifecycle.STAGE_LABELS[c.stage], c.format_age()]
	var info := "Génération %d" % c.generation
	if c.mother != "":
		info += " · enfant de %s et %s" % [c.mother, c.father]
	if c.pregnant_time >= 0.0:
		info += " · attend un œuf"
	info += " · %d vivantes" % world.alive_count()
	_info_label.text = info
	var values := [c.level("Faim"), c.level("Soif"), c.level("Fatigue"), c.level("Ennui"),
		c.level("Solitude"), c.level("Désir"), c.heart_health()]
	for i in _bars.size():
		_bars[i].value = values[i]
	_action_label.text = c.action_text()
