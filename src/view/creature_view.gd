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

var _sprite := Sprite2D.new()
var _material := ShaderMaterial.new()
var _t := 0.0


func _ready() -> void:
	SpriteLibrary.ensure()
	_material.shader = preload("res://src/view/shaders/creature.gdshader")
	_sprite.material = _material
	_sprite.centered = false
	_sprite.offset = -SpriteLibrary.creature_anchor
	add_child(_sprite)


func _process(delta: float) -> void:
	if creature == null:
		return
	_t += delta
	var c := creature
	position = Vector2(c.x, 0.0)
	var anim := _animation()
	var frames: Array = SpriteLibrary.creature_frames[anim]
	var fps := WALK_FPS if anim == "marche" else 2.0
	_sprite.texture = frames[int(_t * fps) % frames.size()]
	var s := SpriteLibrary.creature_scale * c.body_size()
	_sprite.scale = Vector2(s * c.facing, s)     # retourné quand elle regarde à gauche
	var pal := c.palette()
	_material.set_shader_parameter("col_dark", pal[0])
	_material.set_shader_parameter("col_mid", pal[1])
	_material.set_shader_parameter("col_light", pal[2])
	_material.set_shader_parameter("glow_shift", c.glow - 0.47)   # rendu d'origine : turquoise
	_material.set_shader_parameter("desaturate", 0.0 if c.alive else 0.75)
	queue_redraw()


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
	if c.is_asleep():
		var zy := -150.0 - fmod(_t * 20.0, 30.0)
		draw_string(font, Vector2(40, zy) * sz, "z z", HORIZONTAL_ALIGNMENT_LEFT, -1, 32, Color(1, 1, 1, 0.9))
	if c.alive and c.get_verb() == Verb.PARLER and c.is_acting():
		draw_string(font, Vector2(20, -230) * sz, "?!", HORIZONTAL_ALIGNMENT_LEFT, -1, 34, Color(1, 1, 1, 0.95))
	var reward := c.level("Récompense")
	if reward > 0.05:
		_draw_heart(Vector2(0, -250) * sz, Color(0.95, 0.25, 0.4, minf(reward, 1.0)))
	var punish := c.level("Punition")
	if punish > 0.05:
		draw_string(font, Vector2(-8, -240) * sz, "!", HORIZONTAL_ALIGNMENT_LEFT, -1, 52, Color(0.95, 0.15, 0.1, minf(punish, 1.0)))


func _draw_heart(p: Vector2, col: Color) -> void:
	draw_circle(p + Vector2(-8, 0), 9.0, col)
	draw_circle(p + Vector2(8, 0), 9.0, col)
	draw_colored_polygon(PackedVector2Array([p + Vector2(-17, 3), p + Vector2(17, 3), p + Vector2(0, 22)]), col)
