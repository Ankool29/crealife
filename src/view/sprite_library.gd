class_name SpriteLibrary
extends RefCounted
## Charge une seule fois les sprites rendus avec Blender (dossier assets/)
## et leurs points d'ancrage (le sol).

const CREATURE_DIR := "res://assets/creature/"
const OBJECTS_DIR := "res://assets/objects/"
## Échelle du monde : 1 unité Blender = 120 pixels de jeu.
const WORLD_PX_PER_UNIT := 120.0

static var creature_frames := {}        # animation -> Array[Texture2D]
static var creature_anchor := Vector2.ZERO
static var creature_scale := 1.0        # pixels de sprite -> pixels du monde
static var objects := {}                # nom -> {texture, anchor, scale}
static var _loaded := false


static func ensure() -> void:
	if _loaded:
		return
	_loaded = true
	var m: Dictionary = (load(CREATURE_DIR + "creature.json") as JSON).data
	creature_anchor = Vector2(m.anchor[0], m.anchor[1])
	creature_scale = WORLD_PX_PER_UNIT / float(m.px_per_unit)
	for anim in m.animations:
		var frames: Array[Texture2D] = []
		for f in m.animations[anim]:
			frames.append(load(CREATURE_DIR + f))
		creature_frames[anim] = frames
	var o: Dictionary = (load(OBJECTS_DIR + "objects.json") as JSON).data
	for name in o:
		objects[name] = {
			"texture": load(OBJECTS_DIR + name + ".png"),
			"anchor": Vector2(o[name].anchor[0], o[name].anchor[1]),
			"scale": float(o[name].scale),
		}


## Place un Sprite2D pour que son point d'ancrage tombe sur l'origine du nœud.
static func setup_object_sprite(sprite: Sprite2D, sprite_name: String) -> void:
	ensure()
	var info: Dictionary = objects[sprite_name]
	sprite.texture = info.texture
	sprite.centered = false
	sprite.scale = Vector2.ONE * info.scale
	sprite.offset = -info.anchor
