class_name Chemicals
extends RefCounted
## Catalogue des substances (data/chemicals.json) : numéro <-> nom.

const MAX := 64
const CATALOG_PATH := "res://data/chemicals.json"

static var _names := PackedStringArray()
static var _families := PackedStringArray()
static var _ids := {}


static func _ensure() -> void:
	if not _names.is_empty():
		return
	_names.resize(MAX)
	_families.resize(MAX)
	var res := load(CATALOG_PATH) as JSON
	for e in res.data:
		var i := int(e.id)
		_names[i] = str(e.name)
		_families[i] = str(e.family)
		_ids[str(e.name)] = i


## Numéro d'une substance, ou -1 si le nom est vide ou inconnu.
static func id_of(chem_name: String) -> int:
	_ensure()
	if chem_name == "":
		return -1
	if not _ids.has(chem_name):
		push_warning("Substance inconnue : " + chem_name)
		return -1
	return _ids[chem_name]


static func name_of(i: int) -> String:
	_ensure()
	return _names[i]


static func family_of(i: int) -> String:
	_ensure()
	return _families[i]
