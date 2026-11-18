class_name CreatureView
extends Node2D
## Affiche un chat avec les sprites rendus en 3D : l'animation suit le verbe
## en cours, le pelage vient des gènes (CatCoat, shader cat.gdshader).

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
var _mat := ShaderMaterial.new()
var _t := 0.0
var _bubble_style := StyleBoxFlat.new()
## Noms, bulles et icônes : au-dessus de la nuit pour rester lisibles.
var _labels := Node2D.new()


func _ready() -> void:
	SpriteLibrary.ensure()
	_bubble_style.set_corner_radius_all(14)
	_labels.z_index = 60
	_labels.z_as_relative = false
	_labels.draw.connect(func() -> void: _draw_labels(_labels))
	add_child(_labels)
	_mat.shader = preload("res://src/view/shaders/cat.gdshader")
	_sprite.material = _mat
	_sprite.centered = false
	_sprite.offset = -SpriteLibrary.cat_anchor
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST     # pixel art net
	add_child(_sprite)


func _process(delta: float) -> void:
	if creature == null:
		return
	_t += delta
	var c := creature
	position = Vector2(c.x, -absf(sin(_t * 5.0)) * 70.0 * c.body_size() if c.bounce_left > 0.0 else 0.0)
	position = position.round()
	var anim := _animation()
	var count := SpriteLibrary.cat_frame_count(anim)
	var fps := WALK_FPS if anim == "marche" else (1.2 if anim == "assis" else 2.0)
	var f := int(_t * fps) % count
	_sprite.texture = SpriteLibrary.cat_texture(anim, f)
	_mat.set_shader_parameter("mask1", SpriteLibrary.cat_texture(anim, f, "_m1"))
	_mat.set_shader_parameter("mask2", SpriteLibrary.cat_texture(anim, f, "_m2"))
	var s := SpriteLibrary.cat_display_scale(c.body_size())
	var wide: float = round(s * lerpf(0.94, 1.08, c.corpulence) * 2.0) / 2.0   # corpulence : svelte à trapu
	_sprite.scale = Vector2(wide * c.facing, s)       # retourné quand il regarde à gauche
	_set_coat(_mat, c)
	_labels.queue_redraw()


func _set_coat(m: ShaderMaterial, c: CreatureSim) -> void:
	var coat := c.coat
	if coat.is_empty():
		return
	m.set_shader_parameter("col_e", coat.col_e)
	m.set_shader_parameter("col_r", coat.col_r)
	m.set_shader_parameter("orange", coat.orange)
	m.set_shader_parameter("agouti", coat.agouti)
	m.set_shader_parameter("pattern", coat.pattern)
	m.set_shader_parameter("silver", coat.silver)
	m.set_shader_parameter("contrast", coat.contrast)
	m.set_shader_parameter("points", coat.points)
	# siamois : extrémités plus foncées au froid ; les chatons naissent pâles
	var cold := clampf(0.55 + (20.0 - c.felt_temp) / 30.0, 0.35, 1.0)
	var age_f: float = [0.2, 0.6, 0.9, 1.0, 1.0][c.stage]
	m.set_shader_parameter("point_strength", cold * age_f)
	m.set_shader_parameter("white", coat.white)
	m.set_shader_parameter("eye_color", coat.eye)
	m.set_shader_parameter("desaturate", 0.0 if c.alive else 0.6)


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
	# au repos : assis quand il est fatigué, et de temps en temps
	if c.level("Fatigue") > 0.25 or int(c.age / 45.0) % 3 == 0:
		return "assis"
	return "repos"


## Point central du corps en coordonnées monde (pour savoir si on la touche).
func body_center() -> Vector2:
	return position + SpriteLibrary.cat_body_center * SpriteLibrary.cat_display_scale(creature.body_size())


func _draw_labels(cv: CanvasItem) -> void:
	if creature == null:
		return
	var c := creature
	var sz := c.body_size()
	var font := ThemeDB.fallback_font
	# Nom au-dessus de la tête (et repère si sélectionnée)
	var head := SpriteLibrary.cat_head_top * SpriteLibrary.CAT_PIXEL      # haut de la tête (négatif)
	var top := head * sz - 18.0
	var name_col := Color(1, 1, 1, 0.95) if selected else Color(1, 1, 1, 0.55)
	cv.draw_string(font, Vector2(-100, top), c.creature_name, HORIZONTAL_ALIGNMENT_CENTER, 200, 20 if selected else 16, name_col)
	if selected:
		var p := Vector2(0, top - 34)
		cv.draw_colored_polygon(PackedVector2Array([p + Vector2(-11, -12), p + Vector2(11, -12), p + Vector2(0, 2)]), Color(1, 0.9, 0.3))
	if c.alive and c.pregnant_time >= 0.0:
		cv.draw_string(font, Vector2(-100, top + 22), "attend un œuf", HORIZONTAL_ALIGNMENT_CENTER, 200, 14, Color(1, 0.85, 0.9, 0.9))
	if c.is_asleep():
		var zy := head * 0.55 - fmod(_t * 20.0, 30.0)
		cv.draw_string(font, Vector2(c.facing * 60.0, zy) * sz, "z z", HORIZONTAL_ALIGNMENT_LEFT, -1, 32, Color(1, 1, 1, 0.9))
	if c.alive and c.get_verb() == Verb.PARLER and c.is_acting():
		cv.draw_string(font, Vector2(c.facing * 100.0, head * 1.05) * sz, "?!", HORIZONTAL_ALIGNMENT_LEFT, -1, 34, Color(1, 1, 1, 0.95))
	if c.alive and c.language.speech != "":
		_draw_bubble(cv, Vector2(0, top - (52 if selected else 22)), c.language.speech, font)
	var L := c.language
	if c.alive and L.progress_left > 0.0:
		var rise := (Language.PROGRESS_TIME - L.progress_left) * 25.0
		cv.draw_string(font, Vector2(70, top + 10 - rise), L.progress_text,     # à droite du nom
			HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Color(0.55, 1.0, 0.6, minf(1.0, L.progress_left)))
	if selected and c.alive and L.shown_left > 0.0 and L.shown_object != null:
		# flèche au-dessus de ce qu'on lui montre
		var o = L.shown_object
		var tip := Vector2(o.x - c.x, (-o.h - 60.0) if o is WorldObject else head * o.body_size() - 20.0)
		tip.y -= 8.0 * sin(_t * 6.0)
		var col := Color(1, 0.9, 0.3, minf(1.0, L.shown_left))
		cv.draw_colored_polygon(PackedVector2Array([tip, tip + Vector2(-16, -22), tip + Vector2(16, -22)]), col)
		cv.draw_rect(Rect2(tip + Vector2(-6, -48), Vector2(12, 28)), col)
	var reward := c.level("Récompense")
	if reward > 0.05:
		_draw_heart(cv, Vector2(0, head * 1.15) * sz, Color(0.95, 0.25, 0.4, minf(reward, 1.0)))
	var punish := c.level("Punition")
	if punish > 0.05:
		cv.draw_string(font, Vector2(-8, head * 1.1) * sz, "!", HORIZONTAL_ALIGNMENT_LEFT, -1, 52, Color(0.95, 0.15, 0.1, minf(punish, 1.0)))


## Bulle de paroles au-dessus de la tête.
func _draw_bubble(cv: CanvasItem, p: Vector2, text: String, font: Font) -> void:
	var size := 22
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x + 28.0
	var r := Rect2(p.x - w * 0.5, p.y - 40.0, w, 34.0)
	var a := clampf(creature.language.speech_left, 0.0, 1.0)
	_bubble_style.bg_color = Color(1, 1, 1, 0.92 * a)
	cv.draw_style_box(_bubble_style, r)
	cv.draw_colored_polygon(PackedVector2Array([Vector2(p.x - 8, r.end.y - 1), Vector2(p.x + 8, r.end.y - 1),
		Vector2(p.x, r.end.y + 12)]), _bubble_style.bg_color)
	cv.draw_string(font, Vector2(r.position.x, r.position.y + 25), text, HORIZONTAL_ALIGNMENT_CENTER, w, size, Color(0.1, 0.1, 0.15, a))


func _draw_heart(cv: CanvasItem, p: Vector2, col: Color) -> void:
	cv.draw_circle(p + Vector2(-8, 0), 9.0, col)
	cv.draw_circle(p + Vector2(8, 0), 9.0, col)
	cv.draw_colored_polygon(PackedVector2Array([p + Vector2(-17, 3), p + Vector2(17, 3), p + Vector2(0, 22)]), col)
