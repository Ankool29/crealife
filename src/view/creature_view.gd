class_name CreatureView
extends Node2D
## Dessine une créature à partir de son état de simulation (formes procédurales,
## aucune image nécessaire pour l'instant).

const Action = Brain.Action

var creature: CreatureSim
var _t := 0.0


func _process(delta: float) -> void:
	if creature == null:
		return
	_t += delta
	var hop := 0.0
	if creature.alive and creature.get_action() == Action.PLAY:
		hop = -absf(sin(_t * 7.0)) * 35.0
	position = Vector2(creature.x, hop)
	queue_redraw()


## Point central du corps en coordonnées monde (pour savoir si on la touche).
func body_center() -> Vector2:
	return position + Vector2(0, -45.0 * creature.body_size())


func _draw() -> void:
	if creature == null:
		return
	var c := creature
	var sz := c.body_size()
	var col := Color.from_hsv(c.hue, 0.55, 0.92)
	if not c.alive:
		col = col.lerp(Color(0.55, 0.55, 0.55), 0.7)   # morte : couleurs éteintes
	var dark := col.darkened(0.25)
	var sleeping := c.alive and c.get_action() == Action.SLEEP
	# Morte : couchée sur le flanc
	var rot := -PI / 2.0 * c.facing if not c.alive else 0.0
	var base := Vector2(0, -14 * sz) if not c.alive else Vector2.ZERO

	draw_set_transform(base, rot, Vector2(c.facing * sz, sz))

	# Pattes (animées en marche)
	var swing := sin(_t * 12.0) * 10.0 if c.is_moving else 0.0
	draw_line(Vector2(-14, -22), Vector2(-14 + swing, 0), dark, 7.0)
	draw_line(Vector2(14, -22), Vector2(14 - swing, 0), dark, 7.0)
	# Queue
	draw_line(Vector2(-34, -38), Vector2(-52, -52 + sin(_t * 4.0) * 6.0), dark, 6.0)
	# Corps (ellipse via une transformation locale)
	draw_set_transform(base + (Vector2(0, -40) * sz).rotated(rot), rot, Vector2(c.facing * sz * 1.5, sz))
	draw_circle(Vector2.ZERO, 24.0, col)
	draw_set_transform(base, rot, Vector2(c.facing * sz, sz))
	# Tête
	var head := Vector2(36, -66)
	if sleeping:
		head = Vector2(36, -48)
	draw_circle(head, 20.0, col)
	draw_colored_polygon(PackedVector2Array([head + Vector2(-10, -14), head + Vector2(-6, -38), head + Vector2(2, -16)]), dark)
	# Œil
	if sleeping or not c.alive:
		draw_line(head + Vector2(2, -4), head + Vector2(13, -4), Color(0.1, 0.1, 0.1), 3.0)
	else:
		draw_circle(head + Vector2(7, -5), 6.0, Color.WHITE)
		draw_circle(head + Vector2(9, -5), 3.0, Color(0.1, 0.1, 0.1))
	# Bouche
	draw_line(head + Vector2(10, 8), head + Vector2(17, 6), Color(0.25, 0.1, 0.1), 2.0)

	# Indicateurs (dessinés sans miroir)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	var font := ThemeDB.fallback_font
	if sleeping:
		var zy := -100.0 - fmod(_t * 20.0, 30.0)
		draw_string(font, Vector2(30, zy) * sz, "z z", HORIZONTAL_ALIGNMENT_LEFT, -1, 30, Color(1, 1, 1, 0.9))
	if c.reward_level() > 0.05:
		_draw_heart(Vector2(0, -120) * sz, Color(0.95, 0.25, 0.4, c.reward_level()))
	if c.punishment_level() > 0.05:
		draw_string(font, Vector2(-8, -110) * sz, "!", HORIZONTAL_ALIGNMENT_LEFT, -1, 48, Color(0.9, 0.1, 0.1, c.punishment_level()))


func _draw_heart(p: Vector2, col: Color) -> void:
	draw_circle(p + Vector2(-8, 0), 9.0, col)
	draw_circle(p + Vector2(8, 0), 9.0, col)
	draw_colored_polygon(PackedVector2Array([p + Vector2(-17, 3), p + Vector2(17, 3), p + Vector2(0, 22)]), col)
