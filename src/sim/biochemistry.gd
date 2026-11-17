class_name Biochemistry
extends RefCounted
## Chimie simplifiée : chaque pulsion est une concentration dans [0, 1].
## Plus elle est haute, plus la créature ressent le besoin.

enum Drive { HUNGER, FATIGUE, BOREDOM }
const DRIVE_COUNT := 3
const DRIVE_LABELS: Array[String] = ["Faim", "Fatigue", "Ennui"]

var levels := PackedFloat32Array([0.3, 0.2, 0.3])
## Signaux de renforcement visibles (cœur / colère), décroissent vite.
var reward := 0.0
var punishment := 0.0

var _hunger_rate: float
var _fatigue_rate: float
var _boredom_rate := 0.008


func _init(genome: Genome) -> void:
	# Valeurs par seconde de jeu.
	_hunger_rate = lerpf(0.004, 0.010, genome.get_gene("metabolism"))
	_fatigue_rate = lerpf(0.008, 0.003, genome.get_gene("stamina"))


func get_level(d: int) -> float:
	return levels[d]


func add(d: int, amount: float) -> void:
	levels[d] = clampf(levels[d] + amount, 0.0, 1.0)


func total() -> float:
	var s := 0.0
	for v in levels:
		s += v
	return s


## Évolution naturelle. activity : 0 = repos complet, 1 = gros effort.
func tick(dt: float, activity: float) -> void:
	add(Drive.HUNGER, _hunger_rate * dt * (0.6 + activity))
	add(Drive.FATIGUE, _fatigue_rate * dt * (0.2 + activity))
	add(Drive.BOREDOM, _boredom_rate * dt)
	reward = move_toward(reward, 0.0, dt * 0.5)
	punishment = move_toward(punishment, 0.0, dt * 0.5)
