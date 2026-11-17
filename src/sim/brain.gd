class_name Brain
extends RefCounted
## Cerveau minimal façon Creatures.
## Score(action) = biais + somme(poids × pulsion) + bruit (curiosité).
## Une récompense renforce le lien entre ce que la créature ressentait
## au moment du choix et l'action choisie ; une punition l'affaiblit.

enum Action { IDLE, WANDER, EAT, SLEEP, PLAY }
const ACTION_COUNT := 5
const ACTION_LABELS: Array[String] = ["Se repose", "Se promène", "Cherche à manger", "Dort", "Joue"]
const ACTION_NOUNS: Array[String] = ["se reposer", "se promener", "manger", "dormir", "jouer"]

## Poids à plat : index = action * DRIVE_COUNT + pulsion.
var weights := PackedFloat32Array()
var biases := PackedFloat32Array([0.15, 0.1, 0.0, -0.1, 0.0])
var current_action: int = Action.IDLE

var _snapshot := PackedFloat32Array([0.0, 0.0, 0.0])
var _noise: float
var _learning_rate: float


func _init(genome: Genome) -> void:
	_noise = lerpf(0.05, 0.3, genome.get_gene("curiosity"))
	_learning_rate = lerpf(0.1, 0.5, genome.get_gene("learning_rate"))
	# Instincts innés, volontairement modestes : l'éducation doit compter.
	#                           faim  fatigue ennui
	weights = PackedFloat32Array([
		0.0, 0.2, 0.0,     # IDLE
		0.0, -0.3, 0.6,    # WANDER
		0.9, 0.0, 0.0,     # EAT
		0.0, 0.9, 0.0,     # SLEEP
		-0.2, -0.4, 0.7,   # PLAY
	])


func get_weight(action: int, drive: int) -> float:
	return weights[action * Biochemistry.DRIVE_COUNT + drive]


func score(action: int, chem: Biochemistry) -> float:
	var s := biases[action]
	for d in Biochemistry.DRIVE_COUNT:
		s += get_weight(action, d) * chem.get_level(d)
	return s


## allowed[a] == false : action impossible pour l'instant (pas de fruit, pas faim...).
func decide(chem: Biochemistry, rng: RandomNumberGenerator, allowed: Array[bool]) -> int:
	var best := Action.IDLE
	var best_score := -INF
	for a in ACTION_COUNT:
		if not allowed[a]:
			continue
		var s := score(a, chem) + rng.randfn(0.0, _noise)
		if s > best_score:
			best_score = s
			best = a
	current_action = best
	_snapshot = chem.levels.duplicate()
	return best


## reinforcement > 0 : récompense ; < 0 : punition. Agit sur l'action en cours.
## include_bias : le joueur modifie aussi le penchant général pour l'action,
## alors que la satisfaction naturelle ne renforce que le lien avec l'état ressenti.
func reinforce(reinforcement: float, include_bias: bool = true) -> void:
	var a := current_action
	for d in Biochemistry.DRIVE_COUNT:
		var i := a * Biochemistry.DRIVE_COUNT + d
		weights[i] = clampf(weights[i] + _learning_rate * reinforcement * (_snapshot[d] + 0.1), -2.0, 2.0)
	if include_bias:
		biases[a] = clampf(biases[a] + _learning_rate * reinforcement * 0.1, -1.0, 1.0)
