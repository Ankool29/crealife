class_name WorldObject
extends RefCounted
## Un objet du monde (fruit, balle, machine...). Son comportement est décrit
## par son type dans le catalogue.

var id: int
var type_name: String
var category: int
var x: float
var h := 0.0          # hauteur au-dessus du sol
var vx := 0.0
var vy := 0.0
var holder: Object = null   # créature qui le porte
var cooldown := 0.0
var dead := false           # proie attrapée (elle ne bouge plus, on peut la manger)
var flee := 0.0             # proie effrayée : elle fuit encore quelques secondes


func _init(p_id: int, p_type: String, p_x: float, p_h: float = 0.0) -> void:
	id = p_id
	type_name = p_type
	category = ObjectCatalog.category_of(p_type)
	x = p_x
	h = p_h


func on_ground() -> bool:
	return h <= 0.0 and holder == null


## Proie encore vivante (souris, oiseau) et libre.
func prey_alive() -> bool:
	return not dead and holder == null and ObjectCatalog.types[type_name].has("prey")
