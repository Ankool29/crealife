class_name Hud
extends CanvasLayer
## Interface tactile : état de la créature en haut à gauche, panneau chimie
## (optionnel) à droite, gros boutons en bas.

signal caress_pressed
signal scold_pressed
signal fruit_pressed
signal speed_pressed
signal follow_pressed
signal new_creature_pressed

const MARGIN := 40  # marge pour l'encoche / les bords arrondis
const BAR_LABELS: Array[String] = ["Faim", "Soif", "Fatigue", "Ennui", "Santé"]
const BAR_COLORS: Array[Color] = [
	Color(0.9, 0.55, 0.2), Color(0.3, 0.65, 0.95), Color(0.45, 0.55, 0.95),
	Color(0.75, 0.45, 0.85), Color(0.35, 0.8, 0.4),
]

var _name_label: Label
var _action_label: Label
var _event_label: Label
var _bars: Array[ProgressBar] = []
var _speed_button: Button
var _follow_button: Button
var _new_button: Button
var _chem_panel: PanelContainer
var _chem_label: Label


func _ready() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var theme := Theme.new()
	theme.default_font_size = 26
	root.theme = theme
	add_child(root)

	# --- Panneau d'état ---
	var panel := _panel()
	panel.position = Vector2(MARGIN, 20)
	root.add_child(panel)
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(box)
	_name_label = Label.new()
	_name_label.add_theme_font_size_override("font_size", 30)
	box.add_child(_name_label)
	for i in BAR_LABELS.size():
		var row := HBoxContainer.new()
		var l := Label.new()
		l.text = BAR_LABELS[i]
		l.custom_minimum_size = Vector2(120, 0)
		row.add_child(l)
		var bar := ProgressBar.new()
		bar.max_value = 1.0
		bar.step = 0.001
		bar.show_percentage = false
		bar.custom_minimum_size = Vector2(240, 22)
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

	# --- Panneau chimie (masqué par défaut) ---
	_chem_panel = _panel()
	_chem_panel.visible = false
	_chem_panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE, 20)
	_chem_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	root.add_child(_chem_panel)
	_chem_label = Label.new()
	_chem_label.add_theme_font_size_override("font_size", 18)
	_chem_label.custom_minimum_size = Vector2(330, 0)
	_chem_panel.add_child(_chem_label)

	# --- Message (haut, centré) ---
	_event_label = Label.new()
	_event_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_event_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_event_label.position.y = 24
	_event_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_event_label.add_theme_font_size_override("font_size", 22)
	root.add_child(_event_label)

	# --- Boutons ---
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 14)
	root.add_child(buttons)
	_new_button = _add_button(buttons, "Nouvelle créature", new_creature_pressed)
	_new_button.visible = false
	_add_button(buttons, "Caresser", caress_pressed)
	_add_button(buttons, "Gronder", scold_pressed)
	_add_button(buttons, "Fruit", fruit_pressed)
	var chem_button := Button.new()
	chem_button.text = "Chimie"
	chem_button.custom_minimum_size = Vector2(140, 90)
	chem_button.focus_mode = Control.FOCUS_NONE
	chem_button.pressed.connect(func() -> void: _chem_panel.visible = not _chem_panel.visible)
	buttons.add_child(chem_button)
	_speed_button = _add_button(buttons, "x1", speed_pressed)
	_follow_button = _add_button(buttons, "Suivre", follow_pressed)
	buttons.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT, Control.PRESET_MODE_MINSIZE, MARGIN)
	buttons.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	buttons.grow_vertical = Control.GROW_DIRECTION_BEGIN


func _panel() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.15, 0.2, 0.7)
	style.set_corner_radius_all(14)
	style.set_content_margin_all(16)
	panel.add_theme_stylebox_override("panel", style)
	return panel


func _add_button(parent: Control, text: String, sig: Signal) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(140, 90)
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(func() -> void: sig.emit())
	parent.add_child(b)
	return b


func update_from(c: CreatureSim, sim_speed: float, following: bool) -> void:
	var sex_mark := "♀" if c.sex == Gene.Sex.FEMALE else "♂"
	_name_label.text = "%s %s  ·  %s  ·  %s" % [c.creature_name, sex_mark, Lifecycle.STAGE_LABELS[c.stage], c.format_age()]
	var chem := c.biochem.conc
	var values := [chem[Chemicals.id_of("Faim")], chem[Chemicals.id_of("Soif")],
		chem[Chemicals.id_of("Fatigue")], chem[Chemicals.id_of("Ennui")], c.heart_health()]
	for i in _bars.size():
		_bars[i].value = values[i]
	_action_label.text = Brain.ACTION_LABELS[c.get_action()] if c.alive else "Morte"
	_event_label.text = c.last_event
	_speed_button.text = "x%d" % int(sim_speed)
	_follow_button.modulate = Color.WHITE if following else Color(1, 1, 1, 0.5)
	_new_button.visible = not c.alive
	if _chem_panel.visible:
		_chem_label.text = _chem_text(c)


## Liste des substances présentes et santé des organes.
func _chem_text(c: CreatureSim) -> String:
	var lines := PackedStringArray()
	for i in range(1, Chemicals.MAX):
		var v := c.biochem.conc[i]
		if v >= 0.005:
			lines.append("%s  %d %%" % [Chemicals.name_of(i), roundi(v * 100.0)])
	lines.append("")
	for o in c.biochem.organs.slice(1):
		lines.append("%s : santé %d %%" % [o.organ_name, roundi(o.health * 100.0)])
	return "\n".join(lines)
