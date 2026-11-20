class_name CatRig
extends Node2D
## Prototype : un chat « en pièces détachées » animé par squelette.
##
## Les pièces (assets/chat_rig, outil tools/build_cat_rig.py) sont assemblées
## et animées dans une petite image basse résolution (SubViewport), affichée
## agrandie et nette : les pièces qui tournent restent en vrais pixels.
## Chaque pièce est coloriée par le même shader que les chats actuels.
## La queue est tracée (bande texturée sur une courbe) : sa longueur et sa
## forme peuvent varier (bobtail, Manx...) sans dessin.

var dir := "res://assets/chat_rig/"   # pièces (à choisir avant d'ajouter le nœud)
const VIEW := Vector2i(112, 84)       # image basse résolution
const FEET := Vector2(56, 80)         # sol, au milieu de l'image
const PIXEL := 3.0                    # agrandissement (comme les chats actuels)
const STRIDE := 14.0                  # pixels parcourus par pas complet

var anim := "repos"                   # repos, marche, assis
var mouth_open := false
var tail_length := 1.0                # 1 normale, 0.4 bobtail, 0 Manx
var _t := 0.0
var _walked := 0.0
var _blink := 0.0
var _next_blink := 2.0

var _vp: SubViewport
var _root: Node2D
var _parts := {}
var _tail: Line2D
var _meta := {}
var _materials: Array[ShaderMaterial] = []
var _coat := {}


func _ready() -> void:
	_meta = JSON.parse_string(FileAccess.get_file_as_string(dir + "rig.json")).parts
	_vp = SubViewport.new()
	_vp.size = VIEW
	_vp.transparent_bg = true
	_vp.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_vp)
	_root = Node2D.new()
	_root.position = FEET
	_vp.add_child(_root)
	var show := Sprite2D.new()
	show.texture = _vp.get_texture()
	show.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	show.scale = Vector2.ONE * PIXEL
	show.centered = false
	show.offset = -Vector2(FEET)
	add_child(show)
	_build()


## Pelage : mêmes réglages que le shader des chats actuels.
func set_coat(params: Dictionary) -> void:
	_coat = params
	for m in _materials:
		for k in params:
			m.set_shader_parameter(k, params[k])


func _part(name: String, parent: Node2D, z := 0, tint := 1.0) -> Sprite2D:
	var s := Sprite2D.new()
	s.texture = load(dir + name + ".png")
	s.centered = false
	s.offset = -Vector2(_meta[name].pivot[0], _meta[name].pivot[1])
	s.z_index = z
	s.z_as_relative = false
	s.material = _material(name, tint)
	parent.add_child(s)
	_parts[name + ("" if tint == 1.0 else "_loin")] = s
	return s


func _material(name: String, tint: float) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load("res://src/view/shaders/cat.gdshader")
	m.set_shader_parameter("mask1", load(dir + name + "_m1.png"))
	m.set_shader_parameter("mask2", load(dir + name + "_m2.png"))
	m.set_shader_parameter("tint", tint)
	_materials.append(m)
	return m


func _build() -> void:
	# pattes du côté opposé : derrière, plus sombres
	for side in [0.72, 1.0]:
		var z := -2 if side < 1.0 else 2
		for leg in ["avant", "arriere"]:
			var top := _part(leg + "_haut", _root, z, side)
			var low := _part(leg + "_bas", top, z, side)
			low.position = Vector2(0, _meta[leg + "_haut"].size[1] * 0.78 - _meta[leg + "_haut"].pivot[1])
	var tronc := _part("tronc", _root, 0)
	_tail = Line2D.new()
	_tail.texture = load(dir + "queue.png")
	_tail.texture_mode = Line2D.LINE_TEXTURE_STRETCH
	_tail.width = 5.0
	_tail.joint_mode = Line2D.LINE_JOINT_ROUND
	_tail.begin_cap_mode = Line2D.LINE_CAP_ROUND
	_tail.end_cap_mode = Line2D.LINE_CAP_ROUND
	_tail.z_index = -1
	_tail.z_as_relative = false
	_tail.material = _material("queue", 1.0)
	_root.add_child(_tail)
	var head := _part("tete", _root, 3)
	var mouth := _part("tete_miaule", head, 3)
	mouth.position = Vector2.ZERO
	mouth.visible = false
	var hw: float = _meta.tete.size[0]
	var hh: float = _meta.tete.size[1]
	var hp := Vector2(_meta.tete.pivot[0], _meta.tete.pivot[1])
	var far_ear := _part("oreille_loin", head, 1, 0.75)
	far_ear.position = Vector2(hw * 0.72, hh * 0.12) - hp
	var near_ear := _part("oreille_proche", head, 4)
	near_ear.position = Vector2(hw * 0.5, hh * 0.14) - hp
	for e in ["oeil", "oeil_ferme"]:
		var eye := _part(e, head, 5)
		eye.position = Vector2(hw * 0.74, hh * 0.42) - hp
	_parts.oeil_ferme.visible = false
	_pose(0.0, 0.0)


func _process(delta: float) -> void:
	_t += delta
	_next_blink -= delta
	if _next_blink <= 0.0:
		_blink = 0.15
		_next_blink = randf_range(2.5, 6.0)
	_blink = maxf(0.0, _blink - delta)
	_parts.oeil.visible = _blink <= 0.0
	_parts.oeil_ferme.visible = _blink > 0.0
	_parts.tete_miaule.visible = mouth_open
	if anim == "marche":
		_walked += delta * 34.0
	_pose(_walked / STRIDE * TAU, _t)


## Place toutes les pièces pour la phase de marche (phi) et le temps (t).
func _pose(phi: float, t: float) -> void:
	var walking := anim == "marche"
	var tw: float = _meta.tronc.size[0]
	var th: float = _meta.tronc.size[1]
	var bob := roundf(sin(phi * 2.0) * 0.6) if walking else 0.0
	var breath := 1.0 + (0.025 * sin(t * 2.2) if not walking else 0.0)
	var tronc: Sprite2D = _parts.tronc
	# hauteur du tronc : posé sur les pattes avant tendues
	var up: Dictionary = _meta.avant_haut
	var low_m: Dictionary = _meta.avant_bas
	var leg_len: float = up.size[1] * 0.78 - up.pivot[1] + low_m.size[1] - low_m.pivot[1]
	tronc.position = Vector2(0, -leg_len - th * 0.55 + bob)
	tronc.scale = Vector2(1.0, breath)
	var shoulder := tronc.position + Vector2(tw * 0.28, th * 0.05)
	var hip := tronc.position + Vector2(-tw * 0.3, th * 0.02)
	# pattes : angles de la cuisse (haut) et du bas, phases opposées en diagonale
	var legs := {
		"avant": [shoulder, 0.0, 1.0], "arriere": [hip, PI, -1.0],
	}
	for leg in legs:
		var base: Vector2 = legs[leg][0]
		for side in ["", "_loin"]:
			var ph: float = phi + legs[leg][1] + (PI if side == "_loin" else 0.0)
			var top: Sprite2D = _parts[leg + "_haut" + side]
			var low: Sprite2D = top.get_child(0)
			top.position = base + (Vector2(-2, 0) if side == "_loin" else Vector2.ZERO)
			if walking:
				top.rotation = deg_to_rad(28.0 * sin(ph))
				low.rotation = deg_to_rad(legs[leg][2] * 30.0 * maxf(0.0, sin(ph + PI * 0.5)))
			else:
				top.rotation = 0.0
				low.rotation = 0.0
	# tête : légère oscillation, petits mouvements au repos
	var head: Sprite2D = _parts.tete
	head.position = tronc.position + Vector2(tw * 0.4, -th * 0.1) + Vector2(0, bob * 0.5)
	head.rotation = deg_to_rad(4.0 * sin(phi * 2.0) if walking else 5.0 * sin(t * 0.6) * sin(t * 0.23))
	# queue : courbe qui monte puis se recourbe, balancement
	var base_t := tronc.position + Vector2(-tw * 0.47, -th * 0.2)
	var pts := PackedVector2Array()
	var n := 8
	var length := 27.0 * tail_length
	var sway := sin(t * (3.0 if walking else 1.3)) * (0.25 if walking else 0.4)
	for i in n + 1:
		var k := float(i) / n
		# part en arrière et vers le haut, le bout se recourbe un peu
		var ang := deg_to_rad(-140.0 + 55.0 * k * k) + sway * k
		pts.append((base_t + Vector2(cos(ang), sin(ang)) * length * k).round())
	_tail.points = pts
	_tail.visible = tail_length > 0.05
