class_name Brain
extends RefCounted
## Cerveau provisoire (phase 1), remplacé par le cerveau à lobes en phase 2.
## Score(action) = biais + somme(poids × pulsion) + bruit (curiosité).
## Une récompense renforce le lien entre ce que la créature ressentait
## au moment du choix et l'action choisie ; une punition l'affaiblit.

enum Action { IDLE, WANDER, EAT, SLEEP, PLAY }
const ACTION_COUNT := 5
const ACTION_LABELS: Array[String] = ["Se repose", "Se promène", "Cherche à manger", "Dort", "Joue"]
const ACTION_NOUNS: Array[String] = ["se reposer", "se promener", "manger", "dormir", "jouer"]

## Pulsions lues par ce cerveau : faim (ou soif), fatigue, ennui.
const DRIVE_COUNT := 3

## Poids à plat : index = action * DRIVE_COUNT + pulsion.
var weights := PackedFloat32Array()
var biases := PackedFloat32Array([0.15, 0.1, 0.0, -0.1, 0.0])
var current_action: int = Action.IDLE

var _snapshot := PackedFloat32Array([0.0, 0.0, 0.0])
var _noise: float
var _learning_rate: float


## Réglages lus dans le gène Lobe « decision » (valeurs dans [0, 1]).
func _init(noise_gene: float = 0.5, learning_gene: float = 0.5) -> void:
	_noise = lerpf(0.05, 0.3, noise_gene)
	_learning_rate = lerpf(0.1, 0.5, learning_gene)
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
	return weights[action * DRIVE_COUNT + drive]


func score(action: int, drives: PackedFloat32Array) -> float:
	var s := biases[action]
	for d in DRIVE_COUNT:
		s += get_weight(action, d) * drives[d]
	return s


## allowed[a] == false : action impossible pour l'instant (pas de fruit, pas faim...).
func decide(drives: PackedFloat32Array, rng: RandomNumberGenerator, allowed: Array[bool]) -> int:
	var best := Action.IDLE
	var best_score := -INF
	for a in ACTION_COUNT:
		if not allowed[a]:
			continue
		var s := score(a, drives) + rng.randfn(0.0, _noise)
		if s > best_score:
			best_score = s
			best = a
	current_action = best
	_snapshot = drives.duplicate()
	return best


## reinforcement > 0 : récompense ; < 0 : punition. Agit sur l'action en cours.
## include_bias : le joueur modifie aussi le penchant général pour l'action,
## alors que la satisfaction naturelle ne renforce que le lien avec l'état ressenti.
func reinforce(reinforcement: float, include_bias: bool = true) -> void:
	var a := current_action
	for d in DRIVE_COUNT:
		var i := a * DRIVE_COUNT + d
		weights[i] = clampf(weights[i] + _learning_rate * reinforcement * (_snapshot[d] + 0.1), -2.0, 2.0)
	if include_bias:
		biases[a] = clampf(biases[a] + _learning_rate * reinforcement * 0.1, -1.0, 1.0)
