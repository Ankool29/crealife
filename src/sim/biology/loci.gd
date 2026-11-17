class_name Loci
extends RefCounted
## Points d'attache nommés entre la chimie et le reste du corps
## (activité, sommeil, dégâts d'un organe...). Les émetteurs les lisent,
## les récepteurs les écrivent.

var values := PackedFloat32Array()
var _index := {}


func id_of(locus_name: String) -> int:
	if not _index.has(locus_name):
		_index[locus_name] = values.size()
		values.append(0.0)
	return _index[locus_name]


func get_value(locus_name: String) -> float:
	return values[id_of(locus_name)]


func set_value(locus_name: String, v: float) -> void:
	values[id_of(locus_name)] = v
