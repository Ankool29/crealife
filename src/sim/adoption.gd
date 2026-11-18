class_name Adoption
extends RefCounted
## Demandes d'adoption : des familles cherchent un chat qui corresponde à
## quelques critères (pelage, sexe, âge, tempérament, mots connus). Le joueur
## choisit qui leur confier ; plus le chat correspond, plus la réputation de
## la chatterie monte. C'est aussi ce qui libère de la place dans la maison.

const MAX_OPEN := 3
const FIRST_DELAY := 300.0                 # première demande après 5 min
const PERIOD := [1200.0, 2400.0]           # puis toutes les 20 à 40 min
const LIFETIME := 2.0 * 3600.0             # une demande attend 2 h avant d'être retirée
const MIN_LEFT := 2                        # on garde toujours au moins deux chats

const FAMILIES: Array[String] = ["la famille Martin", "Léa et Hugo", "Mme Bernard", "la famille Petit",
	"M. Durand", "Chloé", "la famille Moreau", "Inès et Karim", "M. et Mme Lefèvre", "Jules", "Mme Roux",
	"la famille Garnier", "Sarah", "Théo et Manon", "M. Fontaine", "la famille Chevalier"]
const REASONS: Array[String] = ["pour leurs enfants", "pour tenir compagnie à leur grand-mère",
	"pour leur appartement en ville", "pour leur ferme", "après le départ de leur vieux chat",
	"pour leur premier chat", "pour leur maison avec jardin", "pour leur boutique"]

var requests: Array = []                   # demandes ouvertes
var reputation := 0
var adopted := 0
var _next_at := FIRST_DELAY
var _next_id := 1


func tick(world: WorldSim) -> void:
	for r in requests.duplicate():
		if world.time > float(r.expires):
			requests.erase(r)
			world.last_event = "%s n'a pas trouvé son chat et a cherché ailleurs." % cap(r.family)
	if world.time >= _next_at:
		_next_at = world.time + world.rng.randf_range(PERIOD[0], PERIOD[1])
		if requests.size() < MAX_OPEN:
			var r := _new_request(world)
			if not r.is_empty():
				requests.append(r)
				world.last_event = "Nouvelle demande d'adoption : %s cherche %s." % [r.family, describe(r)]


## Chats qu'on peut confier : sevrés (au moins enfants), vivants, pas en gestation.
static func adoptable(world: WorldSim) -> Array:
	return world.creatures.filter(func(c): return c.alive and c.stage >= Lifecycle.Stage.CHILD and c.pregnant_time < 0.0)


func can_adopt(world: WorldSim) -> bool:
	return world.alive_count() > MIN_LEFT


## Part des critères remplis par ce chat (0 à 1).
static func score(r: Dictionary, c: CreatureSim) -> float:
	var ok := 0
	for k in r.criteria:
		if meets(k, c):
			ok += 1
	return float(ok) / float(maxi(1, r.criteria.size()))


## Confie le chat à la famille. Rend le message à afficher.
func adopt(world: WorldSim, r: Dictionary, c: CreatureSim) -> String:
	var s := score(r, c)
	var gain := int(round(10.0 * s)) + (5 if s >= 0.999 else 0)
	reputation += gain
	adopted += 1
	requests.erase(r)
	for h in world.history:
		if h.uid == c.uid:
			h.alive = false
			h.cause = "adopté par %s" % r.family
			h.age = c.age
	world.creatures.erase(c)
	for other in world.creatures:
		if other.target == c:
			other.target = null
	if c.held:
		c.drop_held()
	var verdict := "ravie" if s >= 0.999 else ("contente" if s >= 0.5 else "un peu déçue")
	world.last_event = "%s a adopté %s, %s (+%d réputation)." % [cap(r.family), c.creature_name,
		verdict + (" : il correspond à tout" if s >= 0.999 else ""), gain]
	return world.last_event


# ------------------------------------------------------------- critères --

## Un critère : {"kind": ..., "value": ...}. Les pelages se lisent dans le
## phénotype (CatCoat), le reste dans la créature.
static func meets(k: Dictionary, c: CreatureSim) -> bool:
	var coat: Dictionary = c.coat
	match str(k.kind):
		"sexe":
			return c.sex == int(k.value)
		"age":
			return c.stage <= Lifecycle.Stage.ADO if k.value == "jeune" else c.stage >= Lifecycle.Stage.ADULT
		"pelage":
			return coat_is(coat, str(k.value))
		"poil":
			return bool(coat.get("long_fur", false)) == (k.value == "long")
		"caractère":
			match str(k.value):
				"joueur": return c.playfulness > 0.6
				"calme": return c.playfulness < 0.4
				"curieux": return c.curiosity > 0.6
				"maternel": return c.care_instinct > 0.6
		"mots":
			return words_known(c) >= int(k.value)
	return false


static func coat_is(coat: Dictionary, v: String) -> bool:
	var white: float = coat.get("white", 0.0)
	var orange: int = coat.get("orange", 0)
	match v:
		"blanc": return white >= 0.999
		"noir": return orange == 0 and not coat.get("agouti", false) and not coat.get("dilute", false) \
				and not coat.get("points", false) and coat.get("b", 0) == 0 and white < 0.5
		"roux": return orange == 1 and white < 0.5
		"écaille": return orange == 2
		"tigré": return coat.get("agouti", false) and white < 0.5 and not coat.get("points", false)
		"gris": return coat.get("dilute", false) and orange == 0 and white < 0.5
		"siamois": return coat.get("points", false)
		"bicolore": return white > 0.1 and white < 0.999
	return false


static func words_known(c: CreatureSim) -> int:
	var n := 0
	for v in c.language.nouns:
		if v > 0.5:
			n += 1
	for v in c.language.verbs:
		if v > 0.5:
			n += 1
	return n


static func label(k: Dictionary) -> String:
	match str(k.kind):
		"sexe": return "une femelle" if int(k.value) == Gene.Sex.FEMALE else "un mâle"
		"age": return "jeune" if k.value == "jeune" else "adulte"
		"pelage":
			return {"blanc": "tout blanc", "noir": "noir", "roux": "roux", "écaille": "écaille de tortue ou calico",
				"tigré": "tigré", "gris": "gris (bleu)", "siamois": "colourpoint (siamois)",
				"bicolore": "avec du blanc"}.get(k.value, str(k.value))
		"poil": return "à poil long" if k.value == "long" else "à poil court"
		"caractère":
			return {"joueur": "joueur", "calme": "calme", "curieux": "curieux", "maternel": "affectueux"}.get(k.value, "")
		"mots": return "qui connaît au moins %d mots" % int(k.value)
	return ""


static func describe(r: Dictionary) -> String:
	var head := "un chat"
	var parts: Array[String] = []
	for k in r.criteria:
		if k.kind == "sexe":
			head = "une chatte" if int(k.value) == Gene.Sex.FEMALE else "un chat mâle"
		else:
			parts.append(label(k))
	return head + (" " + ", ".join(parts) if not parts.is_empty() else "")


## Majuscule au début seulement (« Théo et Manon », pas « Théo Et Manon »).
static func cap(t: String) -> String:
	return t.substr(0, 1).to_upper() + t.substr(1)


## Les critères partent souvent d'un chat de la maison (la demande est alors
## faisable), parfois d'un tirage libre (il faudra peut-être l'élever).
func _new_request(world: WorldSim) -> Dictionary:
	var rng := world.rng
	var pool := adoptable(world)
	var model: CreatureSim = pool[rng.randi_range(0, pool.size() - 1)] if not pool.is_empty() and rng.randf() < 0.7 else null
	var options: Array = []
	var coats := ["blanc", "noir", "roux", "écaille", "tigré", "gris", "siamois", "bicolore"]
	if model:
		for v in coats:
			if coat_is(model.coat, v):
				options.append({"kind": "pelage", "value": v})
		options.append({"kind": "poil", "value": "long" if model.coat.get("long_fur", false) else "court"})
		options.append({"kind": "sexe", "value": model.sex})
		options.append({"kind": "age", "value": "jeune" if model.stage <= Lifecycle.Stage.ADO else "adulte"})
		for v in ["joueur", "calme", "curieux", "maternel"]:
			if meets({"kind": "caractère", "value": v}, model):
				options.append({"kind": "caractère", "value": v})
		var w := words_known(model)
		if w >= 2:
			options.append({"kind": "mots", "value": mini(w, 2 + rng.randi_range(0, 3))})
	else:
		options = [{"kind": "pelage", "value": coats[rng.randi_range(0, coats.size() - 1)]},
			{"kind": "poil", "value": ["long", "court"][rng.randi_range(0, 1)]},
			{"kind": "sexe", "value": [Gene.Sex.FEMALE, Gene.Sex.MALE][rng.randi_range(0, 1)]},
			{"kind": "caractère", "value": ["joueur", "calme", "curieux", "maternel"][rng.randi_range(0, 3)]},
			{"kind": "mots", "value": rng.randi_range(2, 5)}]
	options.shuffle()
	var picked: Array = []
	var kinds := {}
	var want := rng.randi_range(2, 3)
	for o in options:
		if kinds.has(o.kind):
			continue
		kinds[o.kind] = true
		picked.append(o)
		if picked.size() >= want:
			break
	if picked.is_empty():
		return {}
	var r := {"id": _next_id, "family": FAMILIES[rng.randi_range(0, FAMILIES.size() - 1)],
		"reason": REASONS[rng.randi_range(0, REASONS.size() - 1)], "criteria": picked,
		"created": world.time, "expires": world.time + LIFETIME}
	_next_id += 1
	return r


func to_dict() -> Dictionary:
	return {"requests": requests, "reputation": reputation, "adopted": adopted, "next_at": _next_at, "next_id": _next_id}


func load_dict(d: Dictionary) -> void:
	requests = d.get("requests", [])
	for r in requests:                     # JSON : les nombres reviennent en float
		r.id = int(r.id)
		for k in r.criteria:
			if k.kind in ["sexe", "mots"]:
				k.value = int(k.value)
	reputation = int(d.get("reputation", 0))
	adopted = int(d.get("adopted", 0))
	_next_at = float(d.get("next_at", FIRST_DELAY))
	_next_id = int(d.get("next_id", 1))
