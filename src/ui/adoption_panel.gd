class_name AdoptionPanel
extends Control
## Fenêtre des demandes d'adoption : chaque famille, ses critères, et les
## chats de la maison qui y correspondent le mieux (✓ critère rempli, ✗ non).
## Toucher un chat demande confirmation, puis il part dans sa famille.

var world: WorldSim
var _list: VBoxContainer
var _header: Label
var _confirm: PanelContainer
var _confirm_label: Label
var _pending: Array = []            # [demande, chat] en attente de confirmation
var _refresh := 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var panel := _panel()
	panel.anchor_left = 0.08
	panel.anchor_right = 0.92
	panel.anchor_top = 0.04
	panel.anchor_bottom = 0.96
	panel.offset_left = 0
	panel.offset_right = 0
	panel.offset_top = 0
	panel.offset_bottom = 0
	add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)
	var top := HBoxContainer.new()
	box.add_child(top)
	_header = Label.new()
	_header.add_theme_font_size_override("font_size", 28)
	_header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(_header)
	var close := Button.new()
	close.text = "Fermer"
	close.focus_mode = Control.FOCUS_NONE
	close.custom_minimum_size = Vector2(140, 64)
	close.pressed.connect(func() -> void: visible = false)
	top.add_child(close)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 14)
	scroll.add_child(_list)

	# confirmation
	_confirm = _panel()
	_confirm.set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_MINSIZE)
	_confirm.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_confirm.grow_vertical = Control.GROW_DIRECTION_BOTH
	_confirm.visible = false
	add_child(_confirm)
	var cb := VBoxContainer.new()
	cb.add_theme_constant_override("separation", 16)
	_confirm.add_child(cb)
	_confirm_label = Label.new()
	cb.add_child(_confirm_label)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END
	row.add_theme_constant_override("separation", 16)
	cb.add_child(row)
	for pair in [["Annuler", func() -> void: _confirm.visible = false],
			["Confier", func() -> void:
				_confirm.visible = false
				if _pending.size() == 2 and world and _pending[0] in world.adoption.requests:
					world.adoption.adopt(world, _pending[0], _pending[1])
				_rebuild()]]:
		var b := Button.new()
		b.text = pair[0]
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(200, 80)
		b.pressed.connect(pair[1])
		row.add_child(b)
	visibility_changed.connect(func() -> void: if visible: _rebuild())


func _process(delta: float) -> void:
	if not visible or _confirm.visible:
		return
	_refresh -= delta
	if _refresh <= 0.0:
		_rebuild()


func _rebuild() -> void:
	_refresh = 2.0
	if world == null:
		return
	var a := world.adoption
	_header.text = "Adoptions  ·  réputation %d  ·  %d chat%s placé%s" % [a.reputation, a.adopted,
		"s" if a.adopted > 1 else "", "s" if a.adopted > 1 else ""]
	for ch in _list.get_children():
		ch.queue_free()
	if a.requests.is_empty():
		var l := Label.new()
		l.text = "Aucune demande pour le moment. Les familles se manifestent de temps en temps."
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_list.add_child(l)
		return
	var pool := Adoption.adoptable(world)
	for r in a.requests:
		var card := _panel(Color(0.18, 0.24, 0.3, 0.9))
		_list.add_child(card)
		var cbox := VBoxContainer.new()
		card.add_child(cbox)
		var t := Label.new()
		var left := int((float(r.expires) - world.time) / 60.0)
		t.text = "%s, %s  (encore %d h %02d)" % [Adoption.cap(str(r.family)), r.reason, left / 60, left % 60]
		t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		t.add_theme_font_size_override("font_size", 22)
		cbox.add_child(t)
		var want := Label.new()
		want.text = "Cherche " + Adoption.describe(r) + "."
		want.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		want.modulate = Color(0.95, 0.9, 0.7)
		cbox.add_child(want)
		if not a.can_adopt(world):
			var no := Label.new()
			no.text = "Il faut garder au moins %d chats." % Adoption.MIN_LEFT
			cbox.add_child(no)
			continue
		var ranked := pool.duplicate()
		ranked.sort_custom(func(x, y): return Adoption.score(r, x) > Adoption.score(r, y))
		var flow := HFlowContainer.new()
		flow.add_theme_constant_override("h_separation", 10)
		flow.add_theme_constant_override("v_separation", 10)
		cbox.add_child(flow)
		for c in ranked.slice(0, 6):
			var marks := ""
			for k in r.criteria:
				marks += "✓" if Adoption.meets(k, c) else "✗"
			var b := Button.new()
			b.text = "%s %s  %s" % [c.creature_name, "♀" if c.sex == Gene.Sex.FEMALE else "♂", marks]
			b.focus_mode = Control.FOCUS_NONE
			b.custom_minimum_size = Vector2(0, 64)
			if Adoption.score(r, c) >= 0.999:
				b.modulate = Color(0.75, 1.0, 0.75)
			b.pressed.connect(_ask.bind(r, c))
			flow.add_child(b)


func _ask(r: Dictionary, c: CreatureSim) -> void:
	_pending = [r, c]
	var lines: Array[String] = []
	for k in r.criteria:
		lines.append(("✓ " if Adoption.meets(k, c) else "✗ ") + Adoption.label(k))
	_confirm_label.text = "Confier %s (%s, %s) à %s ?\n%s\nIl quittera la maison pour de bon." % [c.creature_name,
		c.coat.get("name", ""), Lifecycle.STAGE_LABELS[c.stage].to_lower(), r.family, "\n".join(lines)]
	_confirm.visible = true


func _panel(col: Color = Color(0.1, 0.15, 0.2, 0.95)) -> PanelContainer:
	var p := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = col
	style.set_corner_radius_all(14)
	style.set_content_margin_all(16)
	p.add_theme_stylebox_override("panel", style)
	return p
