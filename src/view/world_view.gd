class_name WorldView
extends Node2D
## Décor rendu en 3D et sprites des objets, synchronisés avec la simulation.
## Un décor par zone (pièces de la maison, jardin), la couche lointaine
## répétée en miroir, la nuit, la pluie et la neige, l'écran d'apprentissage
## et la musique.

const DECOR_DIR := "res://assets/decor/"
const FAR_PARALLAX := 0.4          # la couche lointaine se déplace à 40 % de la caméra
## Décors pixel art (tools/build_decor_pixel.py) : prioritaires quand ils existent.
const PX_DECOR := {"cuisine": "px_cuisine.png", "chambre": "px_chambre.png", "jeux": "px_jeux.png",
	"salle": "px_salle.png", "entree": "px_entree.png", "jardin": "px_jardin.png"}
## Écran peint dans le décor de la salle (fractions de l'image).
const PX_SCREEN := Rect2(655.0 / 1774.0, 165.0 / 887.0, 495.0 / 1774.0, 285.0 / 887.0)
const FLOOR_DEPTH := 50.0          # les chats marchent un peu en avant du fond du plancher

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
## Zone de l'écran d'apprentissage dans le monde, si le décor le dessine.
var screen_rect := Rect2()


func _ready() -> void:
	var far_tex: Texture2D = load(DECOR_DIR + "px_lointain.png")
	for i in 3:                     # centre, puis copies en miroir de chaque côté
		var s := Sprite2D.new()
		s.centered = false
		s.texture = far_tex
		s.flip_h = i != 1
		s.z_index = -20
		s.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		add_child(s)
		_far.append(s)
	_near_layer.z_index = -10
	add_child(_near_layer)
	add_child(_objects_layer)
	_overlay.view = self
	add_child(_overlay)


func _build_zones() -> void:
	_zones_built = true
	screen_rect = Rect2()
	for c in _near_layer.get_children():
		c.queue_free()
	var px_meta := {}
	var f := FileAccess.open(DECOR_DIR + "px_decors.json", FileAccess.READ)
	if f:
		px_meta = JSON.parse_string(f.get_as_text())
	for z in world.zones:
		var s := Sprite2D.new()
		s.centered = false
		var px: String = PX_DECOR.get(z.key, "")
		if px_meta.has(z.key) and ResourceLoader.exists(DECOR_DIR + px):     # (les scénarios de test n'en ont pas)
			s.texture = load(DECOR_DIR + px)
			s.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			var room_w: float = z.x1 - z.x0
			s.scale = Vector2.ONE * room_w / float(s.texture.get_width())
			s.position = Vector2(z.x0, -FLOOR_DEPTH - float(px_meta[z.key].floor) * s.scale.y)
			if z.key == "salle":
				var img := Vector2(s.texture.get_width(), s.texture.get_height()) * s.scale
				screen_rect = Rect2(s.position + PX_SCREEN.position * img, PX_SCREEN.size * img)
			var under := ColorRect.new()          # fondations sous le plancher
			under.color = Color(0.17, 0.1, 0.07) if z.indoor else Color(0.36, 0.24, 0.13)
			under.position = Vector2(z.x0, s.position.y + s.texture.get_height() * s.scale.y)
			under.size = Vector2(room_w, 600.0)
			_near_layer.add_child(under)
			_near_layer.add_child(s)
		else:
			s.free()


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
			_far[i].position = Vector2(x + (i - 1) * far_w, -float(_far[1].texture.get_height()))
	var seen := {}
	for o in world.objects:
		seen[o.id] = true
		var s: Sprite2D = _sprites.get(o.id)
		if s == null:
			s = Sprite2D.new()
			_objects_layer.add_child(s)
			_sprites[o.id] = s
		var sprite_name := o.type_name
		if o.is_plant() and o.growth != Garden.PLANT and o.growth != Garden.WILTED:
			sprite_name = "graine" if o.growth == Garden.SEED else "pousse"
		if o.type_name == "distributeur":
			sprite_name = "distributeur_on" if o.cooldown <= 0.0 else "distributeur_off"
		if ObjectCatalog.types[o.type_name].get("invisible", false):     # la mare est dans le décor
			s.visible = false
			continue
		SpriteLibrary.setup_object_sprite(s, sprite_name)
		s.visible = not (o.type_name == "ecran" and screen_rect.has_area())
		if o.type_name in ["souris", "oiseau"]:       # tournée vers où elle va ; attrapée : sur le dos
			if absf(o.vx) > 1.0:
				s.flip_h = o.vx > 0.0
			s.flip_v = o.dead
		# plante fanée : brunie ; papillon : il bat des ailes
		s.modulate = Color(0.75, 0.55, 0.35) if o.is_plant() and o.growth == Garden.WILTED else Color.WHITE
		if o.type_name == "papillon":
			if absf(o.vx) > 1.0:
				s.flip_h = o.vx > 0.0
			s.scale.y *= 0.6 + 0.4 * absf(sin(world.time * 9.0 + o.id))
		s.position = Vector2(o.x, -o.h)
		s.z_index = 5 if o.holder != null else 0
	for id in _sprites.keys():
		if not seen.has(id):
			_sprites[id].queue_free()
			_sprites.erase(id)
	_overlay.queue_redraw()
