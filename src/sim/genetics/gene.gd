class_name Gene
extends RefCounted
## Un gène : un en-tête commun et des paramètres propres à son type.
## Les références (substances, organes, loci) sont des noms lisibles ;
## seuls les paramètres numériques mutent.

enum Type { SUBSTANCE, REACTION, EMITTER, RECEPTOR, ORGAN, LOBE, TRACT, INSTINCT, APPEARANCE }
const TYPE_KEYS: Array[String] = ["substance", "reaction", "emetteur", "recepteur", "organe", "lobe", "faisceau", "instinct", "apparence"]
const TYPE_LABELS: Array[String] = ["Substance", "Réaction", "Émetteur", "Récepteur", "Organe", "Lobe", "Faisceau", "Instinct", "Apparence"]

enum Sex { BOTH, MALE, FEMALE }
const SEX_KEYS: Array[String] = ["tous", "male", "femelle"]

## Paramètres dont la valeur peut être minuscule : ils mutent en proportion.
const RELATIVE_KEYS: Array[String] = ["half_life", "rate", "gain", "repair", "longevity_h", "ltw_rate", "stw_relax"]

var type: int = Type.SUBSTANCE
var id: int = 0
var stage: int = Lifecycle.Stage.BABY
var sex: int = Sex.BOTH
var mutability := 1.0
var can_duplicate := true
var can_delete := true
var silent := false
var params: Dictionary = {}


## Plages autorisées des paramètres numériques, par type (bornes des mutations).
static func ranges_for(t: int) -> Dictionary:
	match t:
		Type.SUBSTANCE: return {"half_life": [0.0, 36000.0], "initial": [0.0, 1.0]}
		Type.REACTION: return {"rate": [0.0, 2.0], "lo": [0.0, 1.0], "hi": [0.0, 1.0]}
		Type.EMITTER: return {"threshold": [0.0, 1.0], "gain": [-1.0, 1.0]}
		Type.RECEPTOR: return {"threshold": [0.0, 1.0], "gain": [0.0, 10.0]}
		Type.ORGAN: return {"longevity_h": [0.5, 40.0], "repair": [0.0, 0.01], "health": [0.0, 1.0]}
		Type.LOBE: return {"noise": [0.0, 1.0], "learning_rate": [0.0, 1.0], "ltw_rate": [0.0, 0.05], "stw_relax": [0.0, 0.05],
				"talk": [0.0, 1.0], "obey": [0.0, 1.0], "ageing": [0.0, 1.0], "care": [0.0, 1.0]}
		Type.INSTINCT: return {"reward": [-2.0, 2.0], "repeat": [0.0, 20.0]}
		Type.APPEARANCE: return {"hue": [0.0, 1.0], "hue2": [0.0, 1.0], "saturation": [0.0, 1.0],
				"brightness": [0.0, 1.0], "glow": [0.0, 1.0], "glow_power": [0.0, 1.0], "size": [0.0, 1.0],
				"speed": [0.0, 1.0], "tail": [0.0, 1.0], "antennae": [0.0, 1.0], "corpulence": [0.0, 1.0],
				"spots": [0.0, 1.0], "stripes": [0.0, 1.0], "patches": [0.0, 1.0], "hue3": [0.0, 1.0], "light3": [0.0, 1.0]}
	return {}


func is_expressed(stage_now: int, sex_now: int) -> bool:
	return not silent and stage <= stage_now and (sex == Sex.BOTH or sex == sex_now)


func copy() -> Gene:
	var g := Gene.new()
	g.type = type
	g.id = id
	g.stage = stage
	g.sex = sex
	g.mutability = mutability
	g.can_duplicate = can_duplicate
	g.can_delete = can_delete
	g.silent = silent
	g.params = params.duplicate(true)
	return g


## Mutation des paramètres numériques. rate = probabilité par paramètre.
func mutate(rng: RandomNumberGenerator, rate: float) -> bool:
	var changed := false
	var ranges := ranges_for(type)
	for key in ranges:
		if not params.has(key) or rng.randf() >= rate * mutability:
			continue
		var lo: float = ranges[key][0]
		var hi: float = ranges[key][1]
		var v := float(params[key])
		if key in RELATIVE_KEYS:
			v *= exp(rng.randfn(0.0, 0.2))           # taux et gains : mutation relative (±20 %)
		else:
			v += rng.randfn(0.0, 0.08 * (hi - lo))   # seuils, teintes... : mutation absolue
		params[key] = clampf(v, lo, hi)
		changed = true
	return changed


func to_dict() -> Dictionary:
	return {
		"id": id, "type": TYPE_KEYS[type], "stage": Lifecycle.STAGE_KEYS[stage],
		"sex": SEX_KEYS[sex], "mut": mutability, "dup": can_duplicate,
		"del": can_delete, "silent": silent, "p": params.duplicate(true),
	}


## Renvoie null pour un type inconnu (génome d'une version future) : il est ignoré.
static func from_dict(d: Dictionary) -> Gene:
	var t := TYPE_KEYS.find(str(d.get("type", "")))
	if t < 0:
		return null
	var g := Gene.new()
	g.type = t
	g.id = int(d.get("id", 0))
	g.stage = maxi(0, Lifecycle.STAGE_KEYS.find(str(d.get("stage", "bebe"))))
	g.sex = maxi(0, SEX_KEYS.find(str(d.get("sex", "tous"))))
	g.mutability = float(d.get("mut", 1.0))
	g.can_duplicate = bool(d.get("dup", true))
	g.can_delete = bool(d.get("del", true))
	g.silent = bool(d.get("silent", false))
	g.params = (d.get("p", {}) as Dictionary).duplicate(true)
	return g
