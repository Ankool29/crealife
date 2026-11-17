class_name Hud
extends CanvasLayer
## Interface tactile : état de la créature en haut à gauche, gros boutons en bas.

signal caress_pressed
signal scold_pressed
signal fruit_pressed
signal speed_pressed
signal follow_pressed

const MARGIN := 40  # marge pour l'encoche / les bords arrondis
const BAR_COLORS: Array[Color] = [Color(0.9, 0.55, 0.2), Color(0.45, 0.55, 0.95), Color(0.75, 0.45, 0.85)]

var _name_label: Label
var _action_label: Label
var _event_label: Label
var _bars: Array[ProgressBar] = []
var _speed_button: Button
var _follow_button: Button


func _ready() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var theme := Theme.new()
	theme.default_font_size = 26
	root.theme = theme
	add_child(root)

	# --- Panneau d'état ---
	var panel := PanelContainer.new()
	panel.position = Vector2(MARGIN, 20)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.15, 0.2, 0.7)
	style.set_corner_radius_all(14)
	style.set_content_margin_all(16)
	panel.add_theme_stylebox_override("panel", style)
	root.add_child(panel)
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(box)

	_name_label = Label.new()
	_name_label.add_theme_font_size_override("font_size", 32)
	box.add_child(_name_label)
	for label_text in Biochemistry.DRIVE_LABELS:
		var row := HBoxContainer.new()
		var l := Label.new()
		l.text = label_text
		l.custom_minimum_size = Vector2(120, 0)
		row.add_child(l)
		var bar := ProgressBar.new()
		bar.max_value = 1.0
		bar.step = 0.001
		bar.show_percentage = false
		bar.custom_minimum_size = Vector2(260, 24)
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var fill := StyleBoxFlat.new()
		fill.bg_color = BAR_COLORS[_bars.size()]
		fill.set_corner_radius_all(6)
		bar.add_theme_stylebox_override("fill", fill)
		row.add_child(bar)
		box.add_child(row)
		_bars.append(bar)
	_action_label = Label.new()
	box.add_child(_action_label)

	# --- Message d'apprentissage (haut, centré) ---
	_event_label = Label.new()
	_event_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_event_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_event_label.position.y = 24
	_event_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_event_label.add_theme_font_size_override("font_size", 22)
	root.add_child(_event_label)

	# --- Boutons ---
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 16)
	root.add_child(buttons)
	_add_button(buttons, "Caresser", caress_pressed)
	_add_button(buttons, "Gronder", scold_pressed)
	_add_button(buttons, "Fruit", fruit_pressed)
	_speed_button = _add_button(buttons, "x1", speed_pressed)
	_follow_button = _add_button(buttons, "Suivre", follow_pressed)
	buttons.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT, Control.PRESET_MODE_MINSIZE, MARGIN)
	buttons.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	buttons.grow_vertical = Control.GROW_DIRECTION_BEGIN


func _add_button(parent: Control, text: String, sig: Signal) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(150, 90)
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(func() -> void: sig.emit())
	parent.add_child(b)
	return b


func update_from(c: CreatureSim, sim_speed: float, following: bool) -> void:
	_name_label.text = "%s  -  %d min" % [c.creature_name, int(c.age / 60.0)]
	for i in _bars.size():
		_bars[i].value = c.chem.get_level(i)
	_action_label.text = Brain.ACTION_LABELS[c.get_action()]
	_event_label.text = c.last_event
	_speed_button.text = "x%d" % int(sim_speed)
	_follow_button.modulate = Color.WHITE if following else Color(1, 1, 1, 0.5)
