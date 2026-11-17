class_name CreatureView
extends Node2D
## Affiche une créature avec les sprites rendus en 3D : l'animation suit le
## verbe en cours, la teinte vient du gène d'apparence.

const Verb = Brain.Verb
const WALK_FPS := 10.0
const ACTION_ANIM := {
	Verb.MANGER: "manger", Verb.POUSSER: "pousser", Verb.TIRER: "pousser",
	Verb.FRAPPER: "frapper", Verb.PRENDRE: "prendre", Verb.LACHER: "prendre",
	Verb.EXAMINER: "examiner", Verb.PARLER: "parler",
}

var creature: CreatureSim:
	set(value):
		creature = value
		_t = 0.0

## Créature sélectionnée : un repère s'affiche au-dessus d'elle.
var selected := false

var _sprite := Sprite2D.new()
var _tail := Sprite2D.new()
var _antennae := Sprite2D.new()
var _material := ShaderMaterial.new()
var _t := 0.0
var _bubble_style := StyleBoxFlat.new()


func _ready() -> void:
	SpriteLibrary.ensure()
	_bubble_style.set_corner_radius_all(14)
	_material.shader = preload("res://src/view/shaders/creature.gdshader")
	# queue, corps puis antennes : chaque couche est déjà masquée là où le
	# corps la cache, l'ordre n'importe que pour les bords
	for s in [_tail, _sprite, _antennae]:
		s.material = _material
		s.centered = false
		s.offset = -SpriteLibrary.creature_anchor
		add_child(s)


func _process(delta: float) -> void:
	if creature == null:
		return
	_t += delta
	var c := creature
	position = Vector2(c.x, 0.0)
	var anim := _animation()
	var frames: Array = SpriteLibrary.creature_frames[anim]
	var fps := WALK_FPS if anim == "marche" else 2.0
	var f := int(_t * fps) % frames.size()
	_sprite.texture = frames[f]
	_tail.texture = _layer("queue", c.tail, anim, f)
	_antennae.texture = _layer("antennes", c.antennae, anim, f)
	var s := SpriteLibrary.creature_scale * c.body_size()
	var wide := lerpf(0.86, 1.18, c.corpulence)     # corpulence : fine à trapue
	for sp in [_tail, _sprite, _antennae]:
		sp.scale = Vector2(s * wide * c.facing, s)   # retourné quand elle regarde à gauche
	var pal := c.palette()
	_material.set_shader_parameter("col_dark", pal[0])
	_material.set_shader_parameter("col_mid", pal[1])
	_material.set_shader_parameter("col_light", pal[2])
	_material.set_shader_parameter("glow_shift", c.glow - 0.47)   # rendu d'origine : turquoise
	_material.set_shader_parameter("glow_power", lerpf(0.55, 1.6, c.glow_power))
	_material.set_shader_parameter("desaturate", 0.0 if c.alive else 0.75)
	queue_redraw()


func _layer(kind: String, variant: int, anim: String, f: int) -> Texture2D:
	var layers: Array = SpriteLibrary.creature_layers[kind]
	if variant >= layers.size():
		return null
	var frames: Array = layers[variant][anim]
	return frames[f % frames.size()]


func _animation() -> String:
	var c := creature
	if not c.alive:
		return "mort"
	if c.is_asleep():
		return "dormir"
	if c.is_moving:
		return "marche"
	if c.is_acting() and ACTION_ANIM.has(c.get_verb()):
		return ACTION_ANIM[c.get_verb()]
	return "repos"


## Point central du corps en coordonnées monde (pour savoir si on la touche).
func body_center() -> Vector2:
	return position + Vector2(0, -95.0 * creature.body_size())


func _draw() -> void:
	if creature == null:
		return
	var c := creature
	var sz := c.body_size()
	var font := ThemeDB.fallback_font
	# Nom au-dessus de la tête (et repère si sélectionnée)
	var top := -215.0 * sz - 18.0
	var name_col := Color(1, 1, 1, 0.95) if selected else Color(1, 1, 1, 0.55)
	draw_string(font, Vector2(-100, top), c.creature_name, HORIZONTAL_ALIGNMENT_CENTER, 200, 20 if selected else 16, name_col)
	if selected:
		var p := Vector2(0, top - 34)
		draw_colored_polygon(PackedVector2Array([p + Vector2(-11, -12), p + Vector2(11, -12), p + Vector2(0, 2)]), Color(1, 0.9, 0.3))
	if c.alive and c.pregnant_time >= 0.0:
		draw_string(font, Vector2(-100, top + 22), "attend un œuf", HORIZONTAL_ALIGNMENT_CENTER, 200, 14, Color(1, 0.85, 0.9, 0.9))
	if c.is_asleep():
		var zy := -150.0 - fmod(_t * 20.0, 30.0)
		draw_string(font, Vector2(40, zy) * sz, "z z", HORIZONTAL_ALIGNMENT_LEFT, -1, 32, Color(1, 1, 1, 0.9))
	if c.alive and c.get_verb() == Verb.PARLER and c.is_acting():
		draw_string(font, Vector2(20, -230) * sz, "?!", HORIZONTAL_ALIGNMENT_LEFT, -1, 34, Color(1, 1, 1, 0.95))
	if c.alive and c.language.speech != "":
		_draw_bubble(Vector2(0, top - (52 if selected else 22)), c.language.speech, font)
	var reward := c.level("Récompense")
	if reward > 0.05:
		_draw_heart(Vector2(0, -250) * sz, Color(0.95, 0.25, 0.4, minf(reward, 1.0)))
	var punish := c.level("Punition")
	if punish > 0.05:
		draw_string(font, Vector2(-8, -240) * sz, "!", HORIZONTAL_ALIGNMENT_LEFT, -1, 52, Color(0.95, 0.15, 0.1, minf(punish, 1.0)))


## Bulle de paroles au-dessus de la tête.
func _draw_bubble(p: Vector2, text: String, font: Font) -> void:
	var size := 22
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x + 28.0
	var r := Rect2(p.x - w * 0.5, p.y - 40.0, w, 34.0)
	var a := clampf(creature.language.speech_left, 0.0, 1.0)
	_bubble_style.bg_color = Color(1, 1, 1, 0.92 * a)
	draw_style_box(_bubble_style, r)
	draw_colored_polygon(PackedVector2Array([Vector2(p.x - 8, r.end.y - 1), Vector2(p.x + 8, r.end.y - 1),
		Vector2(p.x, r.end.y + 12)]), _bubble_style.bg_color)
	draw_string(font, Vector2(r.position.x, r.position.y + 25), text, HORIZONTAL_ALIGNMENT_CENTER, w, size, Color(0.1, 0.1, 0.15, a))


func _draw_heart(p: Vector2, col: Color) -> void:
	draw_circle(p + Vector2(-8, 0), 9.0, col)
	draw_circle(p + Vector2(8, 0), 9.0, col)
	draw_colored_polygon(PackedVector2Array([p + Vector2(-17, 3), p + Vector2(17, 3), p + Vector2(0, 22)]), col)
