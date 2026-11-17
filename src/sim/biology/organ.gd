class_name Organ
extends RefCounted
## Organe : sa santé règle l'efficacité de tous les gènes qui lui sont rattachés.
## Il s'abîme (récepteurs, vieillesse) et se répare en consommant des protéines.

## Dégâts de vieillesse par seconde, une fois la longévité dépassée.
const AGEING_DAMAGE := 0.0005

var organ_name: String
var health := 1.0
var longevity_s := 36000.0
var repair_rate := 0.0005
var damage_locus := -1


func _init(p_name: String) -> void:
	organ_name = p_name


func configure(params: Dictionary, loci: Loci, first_time: bool) -> void:
	longevity_s = float(params.get("longevity_h", 10.0)) * 3600.0
	repair_rate = float(params.get("repair", 0.0005))
	if first_time:
		health = float(params.get("health", 1.0))
	damage_locus = loci.id_of("organe.%s.degats" % organ_name)


func is_alive() -> bool:
	return health > 0.0


func efficiency() -> float:
	return maxf(health, 0.0)


## Renvoie la quantité de protéines consommée pour la réparation.
func step(dt: float, age_s: float, damage: float, proteins: float) -> float:
	if health <= 0.0:
		return 0.0
	var old := age_s > longevity_s
	var dmg := damage + (AGEING_DAMAGE if old else 0.0)
	health -= dmg * dt
	var used := 0.0
	if not old and health < 1.0 and health > 0.0 and proteins > 0.02:
		var r := minf(repair_rate * dt, 1.0 - health)
		health += r
		used = r * 0.5
	health = clampf(health, 0.0, 1.0)
	return used
