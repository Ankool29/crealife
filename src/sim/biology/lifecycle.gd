class_name Lifecycle
extends RefCounted
## Stades de vie. Durées pour une vie d'environ 10 h de jeu (décision D2).

enum Stage { BABY, CHILD, ADO, ADULT, OLD }
const STAGE_KEYS: Array[String] = ["bebe", "enfant", "ado", "adulte", "vieux"]
const STAGE_LABELS: Array[String] = ["Bébé", "Enfant", "Ado", "Adulte", "Vieux"]
## Début de chaque stade, en heures de jeu.
const STAGE_START_H: Array[float] = [0.0, 0.5, 1.5, 2.5, 8.0]
## Taille relative du corps selon le stade.
const STAGE_SIZE: Array[float] = [0.55, 0.75, 0.9, 1.0, 0.97]
## Plasticité du cerveau selon le stade : les jeunes apprennent vite, les
## adultes sont plus « têtus », les vieux apprennent lentement et oublient.
const STAGE_LEARNING: Array[float] = [1.5, 1.3, 1.0, 0.7, 0.4]


## Multiplicateur d'apprentissage à ce stade. ageing (gène, 0..1) règle
## l'écart à 1 : faible = l'esprit reste jeune longtemps, fort = mûrit vite.
static func learning_factor(stage: int, ageing: float) -> float:
	return maxf(0.1, 1.0 + (STAGE_LEARNING[stage] - 1.0) * lerpf(0.4, 1.6, ageing))


static func stage_at(age_s: float) -> int:
	var h := age_s / 3600.0
	var s := 0
	for i in STAGE_START_H.size():
		if h >= STAGE_START_H[i]:
			s = i
	return s
