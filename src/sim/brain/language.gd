class_name Language
extends RefCounted
## Langage (phase 4).
##
## Trois vocabulaires : les noms (une catégorie d'objet chacun), les verbes
## (une action chacun) et les mots des besoins (une pulsion chacun). Pour chaque
## mot, la créature a une connaissance de 0 (inconnu) à 1 (maîtrisé).
##
## - Elle apprend un nom quand on le prononce pendant qu'elle regarde l'objet
##   (ou qu'il est tout près d'elle), un verbe quand on le prononce pendant
##   qu'elle fait l'action, un mot de besoin quand on le prononce pendant
##   qu'elle ressent fortement ce besoin.
## - Elle comprend les ordres à proportion de ce qu'elle connaît des mots :
##   un nom entendu attire son attention vers l'objet, un verbe entendu active
##   un neurone « verbe entendu » relié à l'action (voir Brain). Obéir n'est
##   qu'une tendance, renforcée ou non par les caresses et les gronderies.
## - Elle dit ce qu'elle ressent et ce qu'elle fait, en déformant les mots
##   qu'elle connaît mal (au début, elle babille).
## - Entre créatures, parler transmet le vocabulaire.

const VERB_WORDS: Array[String] = ["rien", "approcher", "fuir", "examiner", "prendre", "lâcher", "manger",
	"pousser", "tirer", "frapper", "parler", "dormir", "explorer", "accoupler"]
const DRIVE_WORDS: Array[String] = ["faim", "soif", "fatigue", "sommeil", "douleur", "peur", "ennui",
	"solitude", "foule", "froid", "chaud", "désir"]
## Autres formes comprises (impératifs, synonymes). Clés sans accents.
const ALIASES := {
	"viens": "approcher", "approche": "approcher", "va": "approcher", "fuis": "fuir", "examine": "examiner",
	"regarde": "examiner", "prends": "prendre", "lache": "lâcher", "pose": "lâcher", "mange": "manger",
	"pousse": "pousser", "tire": "tirer", "frappe": "frapper", "tape": "frapper", "parle": "parler",
	"dors": "dormir", "explore": "explorer", "repose": "rien", "stop": "rien",
	"balle": "jouet", "ballon": "jouet", "distributeur": "machine", "caillou": "pierre", "fruits": "fruit",
	"amie": "créature", "ami": "créature", "copain": "créature", "copine": "créature",
}
const BABBLE: Array[String] = ["bi", "ba", "bou", "ga", "li", "mo", "nu", "pa", "da", "ti", "bo", "gu"]
const LETTERS := "aeioubdglmnpst"
const HEARD_TIME := 12.0      # durée pendant laquelle un ordre reste « en tête »
const SAY_TIME := 4.0
const SHOW_TIME := 15.0       # durée pendant laquelle elle regarde l'objet montré
const PROGRESS_TIME := 2.5

var nouns := PackedFloat32Array()     # une par catégorie d'objet
var verbs := PackedFloat32Array()     # une par verbe
var drive_words := PackedFloat32Array()

## Ordre en cours de compréhension : intensité (0..1) par catégorie et par verbe.
var heard_noun := PackedFloat32Array()
var heard_verb := PackedFloat32Array()
var _heard_left := 0.0

## Ce qu'elle dit en ce moment (bulle) et combien de temps encore.
var speech := ""
var speech_left := 0.0
## Mots entendus en dernier (affichage « a entendu : ... »).
var last_heard := ""
## Objet montré par le joueur : elle le regarde pendant SHOW_TIME.
var shown_category := -1
var shown_object: Object = null
var shown_left := 0.0
## Mots qui viennent de progresser (« + fruit ») et durée d'affichage.
var progress_text := ""
var progress_left := 0.0

var learning := 0.25
var talk := 0.5
var obey := 0.5
var seed := 0


func _init(genes: Array[Gene], p_seed: int) -> void:
	seed = p_seed
	nouns.resize(ObjectCatalog.category_count())
	verbs.resize(VERB_WORDS.size())
	drive_words.resize(DRIVE_WORDS.size())
	heard_noun.resize(nouns.size())
	heard_verb.resize(verbs.size())
	for g in genes:
		if g.type == Gene.Type.LOBE and str(g.params.get("lobe", "")) == "langage":
			learning = lerpf(0.08, 0.45, float(g.params.get("learning_rate", 0.5)))
			talk = float(g.params.get("talk", 0.5))
			obey = float(g.params.get("obey", 0.5))


# ------------------------------------------------------------ mots ---------

static func normalize(w: String) -> String:
	w = w.strip_edges().to_lower()
	var from := ["é", "è", "ê", "ë", "à", "â", "î", "ï", "ô", "û", "ù", "ç", "œ"]
	var to := ["e", "e", "e", "e", "a", "a", "i", "i", "o", "u", "u", "c", "oe"]
	for i in from.size():
		w = w.replace(from[i], to[i])
	return w


## Analyse un mot : [genre, index] avec genre "nom", "verbe", "besoin" ou "".
static func classify(word: String) -> Array:
	var w := normalize(word)
	if ALIASES.has(w):
		w = normalize(ALIASES[w])
	for i in ObjectCatalog.categories.size():
		if normalize(ObjectCatalog.categories[i]) == w:
			return ["nom", i]
	for i in VERB_WORDS.size():
		if normalize(VERB_WORDS[i]) == w:
			return ["verbe", i]
	for i in DRIVE_WORDS.size():
		if normalize(DRIVE_WORDS[i]) == w:
			return ["besoin", i]
	if w.ends_with("s") and w.length() > 3:
		return classify(w.left(-1))
	return ["", -1]


static func word_of(kind: String, i: int) -> String:
	match kind:
		"nom": return ObjectCatalog.categories[i]
		"verbe": return VERB_WORDS[i]
		"besoin": return DRIVE_WORDS[i]
	return ""


func knowledge(kind: String, i: int) -> float:
	match kind:
		"nom": return nouns[i]
		"verbe": return verbs[i]
		"besoin": return drive_words[i]
	return 0.0


func _set_knowledge(kind: String, i: int, k: float) -> void:
	k = clampf(k, 0.0, 1.0)
	match kind:
		"nom": nouns[i] = k
		"verbe": verbs[i] = k
		"besoin": drive_words[i] = k


## Rapproche la connaissance d'un mot de 1 ; strength dans [0, 1].
func learn(kind: String, i: int, strength: float) -> void:
	var k := knowledge(kind, i)
	_set_knowledge(kind, i, k + learning * strength * (1.0 - k))


## Nombre de mots bien connus (connaissance > 0,6).
func vocabulary_size() -> int:
	var n := 0
	for arr in [nouns, verbs, drive_words]:
		for k in arr:
			if k > 0.6:
				n += 1
	return n


# ------------------------------------------------------------ entendre -----

## La créature entend une phrase. Renvoie les mots reconnus [[genre, index], ...].
## brain : pour savoir ce qu'elle regarde, fait et ressent (apprentissage).
## closeness : 1 pour la créature à qui l'on parle, moins pour les voisines.
func hear(text: String, brain: Brain, closeness: float) -> Array:
	var found := []
	var said := []
	for raw in text.replace(",", " ").replace("!", " ").replace("?", " ").replace(".", " ").split(" ", false):
		var c := classify(raw)
		if c[1] >= 0:
			found.append(c)
			said.append(raw.to_lower())
	last_heard = text.strip_edges()
	if found.is_empty():
		return found
	heard_noun.fill(0.0)
	heard_verb.fill(0.0)
	_heard_left = HEARD_TIME
	var gained: Array[String] = []
	for n in found.size():
		var c: Array = found[n]
		var i: int = c[1]
		var before := knowledge(c[0], i)
		match c[0]:
			"nom":
				# Apprendre : elle regarde l'objet (ou on le lui montre),
				# sinon un peu s'il est tout près d'elle.
				var look := 0.6 * brain.vision[i]
				if brain.attention == i or (shown_left > 0.0 and shown_category == i):
					look = 1.0
				learn("nom", i, look * closeness)
				heard_noun[i] = nouns[i] * closeness
			"verbe":
				if brain.verb == i:
					learn("verbe", i, closeness)
				heard_verb[i] = verbs[i] * closeness * lerpf(0.4, 1.0, obey)
			"besoin":
				if brain.drives[i] > 0.4:
					learn("besoin", i, brain.drives[i] * closeness)
		if knowledge(c[0], i) > before + 0.005:
			gained.append("+ " + said[n])
	if not gained.is_empty():
		progress_text = "  ".join(gained)
		progress_left = PROGRESS_TIME
	return found


## Le joueur lui montre un objet (ou une autre créature).
func show(obj: Object, category: int) -> void:
	shown_object = obj
	shown_category = category
	shown_left = SHOW_TIME


func tick(dt: float) -> void:
	if _heard_left > 0.0:
		_heard_left -= dt
		if _heard_left <= 0.0:
			heard_noun.fill(0.0)
			heard_verb.fill(0.0)
	if shown_left > 0.0:
		shown_left -= dt
		if shown_left <= 0.0:
			shown_object = null
			shown_category = -1
	if progress_left > 0.0:
		progress_left -= dt
	if speech_left > 0.0:
		speech_left -= dt
		if speech_left <= 0.0:
			speech = ""


## L'ordre s'estompe : 1 juste après l'avoir entendu, 0 au bout de HEARD_TIME.
func heard_strength() -> float:
	return clampf(_heard_left / HEARD_TIME, 0.0, 1.0)


func obeying() -> bool:
	return _heard_left > 0.0


## L'ordre a été exécuté (ou contredit) : on l'oublie.
func clear_order() -> void:
	_heard_left = 0.0
	heard_noun.fill(0.0)
	heard_verb.fill(0.0)


# ------------------------------------------------------------ parler -------

## Prononciation d'un mot selon sa connaissance : babillage, mot écorché,
## puis mot juste. Les déformations sont propres à chaque créature et stables.
func pronounce(kind: String, i: int) -> String:
	var word := word_of(kind, i)
	var k := knowledge(kind, i)
	if k >= 0.9:
		return word
	var r := RandomNumberGenerator.new()
	r.seed = hash(word) ^ seed
	if k < 0.2:
		var n := maxi(1, word.length() / 3)
		var s := ""
		for j in n:
			s += BABBLE[r.randi_range(0, BABBLE.size() - 1)]
		return s
	var out := ""
	for ch in word:
		var roll := r.randf()
		var rep := LETTERS[r.randi_range(0, LETTERS.length() - 1)]
		out += rep if roll < (0.9 - k) * 0.8 else ch
	return out


func say(words: Array) -> void:
	var parts: Array[String] = []
	for w in words:
		parts.append(pronounce(w[0], w[1]))
	speech = " ".join(parts)
	if speech != "":
		speech += " !" if words.size() == 1 and words[0][0] == "besoin" else ""
		speech_left = SAY_TIME


## Mot le mieux connu, tiré au hasard parmi les mots connus (pour bavarder).
func favourite_word(rng: RandomNumberGenerator) -> Array:
	var pool := []
	var total := 0.0
	for kind in ["nom", "verbe", "besoin"]:
		var arr: PackedFloat32Array = nouns if kind == "nom" else (verbs if kind == "verbe" else drive_words)
		for i in arr.size():
			if arr[i] > 0.15 and not (kind == "verbe" and i == 0):
				pool.append([kind, i, arr[i]])
				total += arr[i]
	if pool.is_empty():
		return []
	var pick := rng.randf() * total
	for p in pool:
		pick -= p[2]
		if pick <= 0.0:
			return [p[0], p[1]]
	return [pool[-1][0], pool[-1][1]]


## Transmission : l'auditrice apprend le mot à proportion de ce que la
## locutrice en sait (on n'apprend pas un mot juste de quelqu'un qui babille).
func learn_from(kind: String, i: int, speaker_knowledge: float) -> void:
	var k := knowledge(kind, i)
	if speaker_knowledge > k:
		_set_knowledge(kind, i, k + learning * 0.5 * (speaker_knowledge - k))


func to_dict() -> Dictionary:
	return {"nouns": Array(nouns), "verbs": Array(verbs), "drives": Array(drive_words)}


func load_dict(d: Dictionary) -> void:
	nouns = _restore(d.get("nouns", []), nouns)
	verbs = _restore(d.get("verbs", []), verbs)
	drive_words = _restore(d.get("drives", []), drive_words)


static func _restore(src: Array, dst: PackedFloat32Array) -> PackedFloat32Array:
	for i in mini(src.size(), dst.size()):
		dst[i] = float(src[i])
	return dst
