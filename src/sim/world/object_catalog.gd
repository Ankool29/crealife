class_name ObjectCatalog
extends RefCounted
## Catalogue des objets (data/objects.json) : catégories vues par le cerveau,
## et réponse de chaque type d'objet à chaque verbe.

const PATH := "res://data/objects.json"

static var categories := PackedStringArray()
static var types := {}
static var _loaded := false


static func ensure() -> void:
	if _loaded:
		return
	var data: Dictionary = (load(PATH) as JSON).data
	categories = PackedStringArray(data.categories)
	types = data.types
	_loaded = true


static func category_count() -> int:
	ensure()
	return categories.size()


static func category_of(type_name: String) -> int:
	ensure()
	return categories.find(str(types[type_name].category))


static func category_label(i: int) -> String:
	ensure()
	return categories[i]


static func label_of(type_name: String) -> String:
	ensure()
	return str(types[type_name].get("label", type_name))


static func can_carry(type_name: String) -> bool:
	ensure()
	return bool(types[type_name].get("carry", false))


## Réponse d'un type d'objet à un verbe (clé française), ou {} si rien ne se passe.
static func response(type_name: String, verb_key: String) -> Dictionary:
	ensure()
	return types[type_name].get("verbs", {}).get(verb_key, {})
