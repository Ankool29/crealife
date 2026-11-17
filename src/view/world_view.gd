class_name WorldView
extends Node2D
## Décor rendu en 3D et sprites des objets, synchronisés avec la simulation.
## Phase 5 : un décor par zone (salle, jardin, loisirs), la couche lointaine
## répétée en miroir, la nuit, la pluie et la neige, l'écran d'apprentissage
## et la musique.

const DECOR_DIR := "res://assets/decor/"
const DECOR_TOP := -560.0          # haut des images de décor, en pixels de jeu
const FAR_PARALLAX := 0.4          # la couche lointaine se déplace à 40 % de la caméra
const ZONE_DECOR := {"salle": "decor_salle.png", "jardin": "decor_proche.png", "loisirs": "decor_loisirs.png"}

var world: WorldSim:
	set(value):
		world = value
		_zones_built = false
var camera: Camera2D

var _far: Array[Sprite2D] = []
var _near_layer := Node2D.new()
var _sprites := {}                 # id d'objet -> Sprite2D
var _objects_layer := Node2D.new()
var _overlay := WorldOverlay.new()
var _zones_built := false


func _ready() -> void:
	var far_tex: Texture2D = load(DECOR_DIR + "decor_lointain.png")
	for i in 3:                     # centre, puis copies en miroir de chaque côté
		var s := Sprite2D.new()
		s.centered = false
		s.texture = far_tex
		s.flip_h = i != 1
		s.z_index = -20
		add_child(s)
		_far.append(s)
	_near_layer.z_index = -10
	add_child(_near_layer)
	add_child(_objects_layer)
	_overlay.view = self
	add_child(_overlay)


func _build_zones() -> void:
	_zones_built = true
	for c in _near_layer.get_children():
		c.queue_free()
	for z in world.zones:
		var s := Sprite2D.new()
		s.centered = false
		s.texture = load(DECOR_DIR + ZONE_DECOR.get(z.key, "decor_proche.png"))
		s.position = Vector2(z.x0, DECOR_TOP)
		_near_layer.add_child(s)


func _process(_delta: float) -> void:
	if world == null:
		return
	if not _zones_built:
		_build_zones()
	if camera:
		# Couche lointaine : centrée quand la caméra est au milieu du monde
		var far_w := float(_far[1].texture.get_width())
		var half := world.width * 0.5
		var x := half - far_w * 0.5 + (camera.position.x - half) * (1.0 - FAR_PARALLAX)
		for i in 3:
			_far[i].position = Vector2(x + (i - 1) * far_w, DECOR_TOP)
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
	_overlay.queue_redraw()
