class_name WorldView
extends Node2D
## Décor rendu en 3D (deux couches, la lointaine défile plus lentement)
## et sprites des objets, synchronisés avec la simulation.

const DECOR_DIR := "res://assets/decor/"
const DECOR_TOP := -560.0          # haut des images de décor, en pixels de jeu
const FAR_PARALLAX := 0.4          # la couche lointaine se déplace à 40 % de la caméra

var world: WorldSim
var camera: Camera2D

var _far := Sprite2D.new()
var _near := Sprite2D.new()
var _sprites := {}                 # id d'objet -> Sprite2D
var _objects_layer := Node2D.new()


func _ready() -> void:
	for s in [_far, _near]:
		s.centered = false
		add_child(s)
	_far.texture = load(DECOR_DIR + "decor_lointain.png")
	_near.texture = load(DECOR_DIR + "decor_proche.png")
	_far.z_index = -20
	_near.z_index = -10
	_near.position = Vector2(0, DECOR_TOP)
	add_child(_objects_layer)


func _process(_delta: float) -> void:
	if world == null:
		return
	if camera:
		# Couche lointaine : centrée quand la caméra est au milieu du monde
		var far_w := float(_far.texture.get_width())
		var half := world.width * 0.5
		_far.position = Vector2(half - far_w * 0.5 + (camera.position.x - half) * (1.0 - FAR_PARALLAX), DECOR_TOP)
	var seen := {}
	for o in world.objects:
		seen[o.id] = true
		var s: Sprite2D = _sprites.get(o.id)
		if s == null:
			s = Sprite2D.new()
			_objects_layer.add_child(s)
			_sprites[o.id] = s
		var sprite_name := o.type_name
		if o.type_name == "distributeur":
			sprite_name = "distributeur_on" if o.cooldown <= 0.0 else "distributeur_off"
		SpriteLibrary.setup_object_sprite(s, sprite_name)
		s.position = Vector2(o.x, -o.h)
		s.z_index = 5 if o.holder != null else 0
	for id in _sprites.keys():
		if not seen.has(id):
			_sprites[id].queue_free()
			_sprites.erase(id)
