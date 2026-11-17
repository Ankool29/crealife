class_name SpriteLibrary
extends RefCounted
## Sprites rendus avec Blender (dossier assets/) et leurs points d'ancrage.
## Les chats sont chargés à la demande (corps, têtes, queues, poil court ou
## long, avec leurs masques de pelage) pour ne pas tout mettre en mémoire.

const CAT_DIR := "res://assets/chat/"
const OBJECTS_DIR := "res://assets/objects/"
## Échelle du monde : 1 unité Blender = 120 pixels de jeu.
const WORLD_PX_PER_UNIT := 120.0
## Les chats sont affichés un peu plus grands que nature par rapport au décor.
const CAT_SIZE := 1.25

static var cat := {}                     # manifeste chat.json
static var cat_anchor := Vector2.ZERO
static var cat_scale := 1.0              # pixels de sprite -> pixels du monde
static var cat_head_top := -130.0        # haut de la tête, en pixels de sprite (négatif)
static var cat_body_center := Vector2.ZERO
static var objects := {}                 # nom -> {texture, anchor, scale}
static var _cache := {}
static var _loaded := false


static func ensure() -> void:
	if _loaded:
		return
	_loaded = true
	cat = (load(CAT_DIR + "chat.json") as JSON).data
	cat_anchor = Vector2(cat.anchor[0], cat.anchor[1])
	cat_scale = WORLD_PX_PER_UNIT * CAT_SIZE / float(cat.px_per_unit)
	cat_head_top = float(cat.head_top)
	cat_body_center = Vector2(cat.body_center[0], cat.body_center[1])
	var o: Dictionary = (load(OBJECTS_DIR + "objects.json") as JSON).data
	for name in o:
		objects[name] = {
			"texture": load(OBJECTS_DIR + name + ".png"),
			"anchor": Vector2(o[name].anchor[0], o[name].anchor[1]),
			"scale": float(o[name].scale),
		}


static func cat_frame_count(anim: String) -> int:
	ensure()
	return (cat.animations[anim] as Array).size()


## Image d'une couche : anim, numéro d'image, couche (corps, tete0..2,
## queue0..1), poil ("c" ou "l"), suffixe ("" image, "_m1" ou "_m2" masques).
static func cat_texture(anim: String, f: int, layer: String, fur: String, suffix: String) -> Texture2D:
	ensure()
	var frames: Array = cat.animations[anim]
	var path: String = "%s%s_%s_%s%s.png" % [CAT_DIR, frames[f % frames.size()], layer, fur, suffix]
	if not _cache.has(path):
		_cache[path] = load(path)
	return _cache[path]


## Place un Sprite2D pour que son point d'ancrage tombe sur l'origine du nœud.
static func setup_object_sprite(sprite: Sprite2D, sprite_name: String) -> void:
	ensure()
	var info: Dictionary = objects[sprite_name]
	sprite.texture = info.texture
	sprite.centered = false
	sprite.scale = Vector2.ONE * info.scale
	sprite.offset = -info.anchor
