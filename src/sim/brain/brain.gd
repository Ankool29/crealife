class_name Brain
extends RefCounted
## Cerveau à lobes (phase 2).
##
##   Pulsions (12) ─┐
##   Vision (1 par catégorie) ─> Attention : quelle catégorie d'objet l'intéresse
##   Situation (4) ─┘
##        └─> Combinaison : neurones « concepts » (pulsion × objet regardé, objet seul,
##            situations), reliés à chaque verbe par une connexion
##              └─> Décision : le verbe le plus activé est exécuté
##
## Chaque connexion a un poids à court terme (modifié par récompense et punition)
## et un poids à long terme qui le suit lentement (plus vite pendant le sommeil).
## Les instincts génétiques pré-câblent des associations avant la naissance.
##
## Langage (phase 4) : un nom entendu attire l'attention vers l'objet nommé ;
## chaque verbe entendu active un concept « on m'a dit de… », relié de façon
## innée au verbe correspondant (gène « obey »). Ces liens apprennent comme
## les autres : obéir et être caressée renforce l'obéissance.

enum Verb { RIEN, APPROCHER, FUIR, EXAMINER, PRENDRE, LACHER, MANGER, POUSSER, TIRER, FRAPPER, PARLER, DORMIR, EXPLORER, ACCOUPLER }
const VERB_COUNT := 14
const VERB_KEYS: Array[String] = ["rien", "approcher", "fuir", "examiner", "prendre", "lacher", "manger", "pousser", "tirer", "frapper", "parler", "dormir", "explorer", "accoupler"]
const VERB_LABELS: Array[String] = ["Se repose", "S'approche", "Fuit", "Examine", "Prend", "Lâche", "Mange", "Pousse", "Tire", "Frappe", "Parle", "Dort", "Explore", "S'accouple"]
const DRIVE_NAMES: Array[String] = ["Faim", "Soif", "Fatigue", "Sommeil", "Douleur", "Peur", "Ennui", "Solitude", "Surpopulation", "Froid", "Chaud", "Désir"]
const SITUATION_LABELS: Array[String] = ["tient un objet", "objet tout proche", "vient d'être caressée", "seule"]
const DRIVE_COUNT := 12
const SITUATION_COUNT := 4
const RELAX_PERIOD := 1.0
const CONTEXT_LEARNING := 0.05   # les poids se rapprochent du long terme une fois par seconde

## Verbes qui portent sur un objet regardé.
const OBJECT_VERBS: Array[int] = [Verb.APPROCHER, Verb.FUIR, Verb.EXAMINER, Verb.PRENDRE, Verb.MANGER, Verb.POUSSER, Verb.TIRER, Verb.FRAPPER, Verb.PARLER, Verb.ACCOUPLER]

# --- Activité des lobes (lisible par les outils d'observation) ---
var drives := PackedFloat32Array()
var vision := PackedFloat32Array()
var situation := PackedFloat32Array()
var attention := -1                      # catégorie regardée, -1 = aucune
var concepts := PackedFloat32Array()
var decision := PackedFloat32Array()     # score de chaque verbe au dernier choix
var verb: int = Verb.RIEN

# --- Connexions ---
var attn_w := PackedFloat32Array()       # pulsion × catégorie
var attn_bias := PackedFloat32Array()
var stw := PackedFloat32Array()          # concept × verbe, court terme
var ltw := PackedFloat32Array()          # concept × verbe, long terme
var verb_bias := PackedFloat32Array()

var _cats: int
var _concept_count: int
var _attn_noise := 0.1
var _dec_noise := 0.1
var _attn_lr := 0.3
var _lr := 0.3
var _ltw_rate := 0.0005
var _stw_relax := 0.002
var _relax_timer := 0.0
var _heard_base := 0
var lang: Language = null
## Plasticité selon l'âge (voir Lifecycle.learning_factor), fixée par le corps.
var plasticity := 1.0
var ageing := 0.5

# Trace de la dernière décision (ce que le renforcement va modifier)
var _elig := PackedFloat32Array()
var _elig_drives := PackedFloat32Array()
var _elig_cat := -1


func _init(genes: Array[Gene], p_lang: Language = null) -> void:
	lang = p_lang
	_cats = ObjectCatalog.category_count()
	# Concepts : pulsion × (catégorie ou rien), puis objet seul, puis
	# situations, puis verbes entendus
	_heard_base = DRIVE_COUNT * (_cats + 1) + (_cats + 1) + SITUATION_COUNT
	_concept_count = _heard_base + VERB_COUNT
	drives.resize(DRIVE_COUNT)
	vision.resize(_cats)
	situation.resize(SITUATION_COUNT)
	concepts.resize(_concept_count)
	decision.resize(VERB_COUNT)
	attn_w.resize(DRIVE_COUNT * _cats)
	attn_bias.resize(_cats)
	stw.resize(_concept_count * VERB_COUNT)
	ltw.resize(_concept_count * VERB_COUNT)
	verb_bias.resize(VERB_COUNT)
	verb_bias[Verb.RIEN] = 0.05
	verb_bias[Verb.EXPLORER] = 0.08
	_elig.resize(_concept_count)
	_elig_drives.resize(DRIVE_COUNT)
	for g in genes:
		if g.type != Gene.Type.LOBE:
			continue
		var p := g.params
		match str(p.get("lobe", "")):
			"attention":
				_attn_noise = lerpf(0.03, 0.3, float(p.get("noise", 0.4)))
				_attn_lr = lerpf(0.1, 0.6, float(p.get("learning_rate", 0.5)))
			"decision":
				_dec_noise = lerpf(0.03, 0.3, float(p.get("noise", 0.4)))
				_lr = lerpf(0.1, 0.6, float(p.get("learning_rate", 0.5)))
				_ltw_rate = float(p.get("ltw_rate", 0.0005))
				_stw_relax = float(p.get("stw_relax", 0.002))
				ageing = float(p.get("ageing", 0.5))
	var obey := lang.obey if lang else 0.5
	for v in VERB_COUNT:
		var i := (_heard_base + v) * VERB_COUNT + v
		stw[i] = lerpf(0.5, 1.6, obey)
		ltw[i] = stw[i]
	for g in genes:
		if g.type == Gene.Type.INSTINCT:
			for i in int(round(float(g.params.get("repeat", 1.0)))):
				train_instinct(g.params, 1.0)


func category_count() -> int:
	return _cats


## Choisit d'abord un objet à regarder, puis un verbe.
## allowed : verbes possibles dans la situation (sans objet, pas de « manger »...).
func decide(rng: RandomNumberGenerator, allowed: Array[bool]) -> int:
	_choose_attention(rng)
	_compute_concepts()
	var best := Verb.RIEN
	var best_score := -INF
	for v in VERB_COUNT:
		var s := verb_bias[v]
		for k in _concept_count:
			var a := concepts[k]
			if a > 0.0:
				s += a * stw[k * VERB_COUNT + v]
		decision[v] = s
		if not allowed[v] or (attention < 0 and v in OBJECT_VERBS):
			continue
		s += rng.randfn(0.0, _dec_noise)
		if s > best_score:
			best_score = s
			best = v
	verb = best
	_elig = concepts.duplicate()
	_elig_drives = drives.duplicate()
	_elig_cat = attention
	return verb


func _choose_attention(rng: RandomNumberGenerator) -> void:
	attention = -1
	var best := 0.15 + rng.randfn(0.0, _attn_noise)    # « rien de particulier »
	for c in _cats:
		if vision[c] <= 0.0:
			continue
		var s := 0.3 * vision[c] + attn_bias[c] + rng.randfn(0.0, _attn_noise)
		if lang:
			s += 2.0 * lang.heard_noun[c] * lang.heard_strength()
			if lang.shown_left > 0.0 and lang.shown_category == c:
				s += 3.0       # on lui montre cet objet : elle le regarde
		for d in DRIVE_COUNT:
			var k := attn_w[d * _cats + c] * drives[d]
			# Faim ou soif pressante : la survie passe avant l'ennui ou la solitude
			if (d == _hunger or d == _thirst) and drives[d] > URGENT and k > 0.0:
				k *= 3.0
			s += k
		if s > best:
			best = s
			attention = c


const URGENT := 0.75
var _hunger := DRIVE_NAMES.find("Faim")
var _thirst := DRIVE_NAMES.find("Soif")


func _compute_concepts() -> void:
	concepts.fill(0.0)
	var slot := attention if attention >= 0 else _cats
	for d in DRIVE_COUNT:
		concepts[d * (_cats + 1) + slot] = drives[d]
	concepts[DRIVE_COUNT * (_cats + 1) + slot] = 1.0
	var base := DRIVE_COUNT * (_cats + 1) + _cats + 1
	for s in SITUATION_COUNT:
		concepts[base + s] = situation[s]
	if lang and lang.obeying():
		var f := lang.heard_strength()
		for v in VERB_COUNT:
			concepts[_heard_base + v] = lang.heard_verb[v] * f


## Oublie la trace de la dernière décision (rien ne sera renforcé).
func clear_trace() -> void:
	_elig.fill(0.0)
	_elig_drives.fill(0.0)
	_elig_cat = -1


## Renforcement de la dernière décision : r > 0 récompense, r < 0 punition.
## Les concepts de pulsion apprennent pleinement ; les concepts de contexte
## (objet seul, situations), toujours actifs, apprennent beaucoup moins vite :
## sinon ils accaparent toutes les récompenses et la créature ne tient plus
## compte de ses besoins.
func reinforce(r: float) -> void:
	if r == 0.0:
		return
	var drive_part := DRIVE_COUNT * (_cats + 1)
	for k in _concept_count:
		var a := _elig[k]
		if a > 0.01:
			var i := k * VERB_COUNT + verb
			var rate := (_lr if k < drive_part or k >= _heard_base else _lr * CONTEXT_LEARNING) * plasticity
			stw[i] = clampf(stw[i] + rate * r * a, -3.0, 3.0)
	if _elig_cat >= 0:
		for d in DRIVE_COUNT:
			var i := d * _cats + _elig_cat
			attn_w[i] = clampf(attn_w[i] + _attn_lr * plasticity * r * _elig_drives[d], -3.0, 3.0)
		attn_bias[_elig_cat] = clampf(attn_bias[_elig_cat] + _attn_lr * plasticity * CONTEXT_LEARNING * r, -1.0, 1.0)


## Récompense naturelle ciblée : la pulsion d qui vient de baisser renforce
## uniquement ses propres concepts (et l'attention qu'elle porte à l'objet).
## Ainsi « manger quand on a faim » n'est pas crédité à l'ennui, et inversement.
func reinforce_drive(d: int, r: float) -> void:
	var slot := _elig_cat if _elig_cat >= 0 else _cats
	var k := d * (_cats + 1) + slot
	if _elig[k] > 0.01:
		var i := k * VERB_COUNT + verb
		stw[i] = clampf(stw[i] + _lr * plasticity * r, -3.0, 3.0)
	if _elig_cat >= 0:
		var j := d * _cats + _elig_cat
		attn_w[j] = clampf(attn_w[j] + _attn_lr * plasticity * r, -3.0, 3.0)


## Les poids à court terme reviennent vers le long terme (oubli) et le long
## terme suit lentement le court terme (consolidation, plus rapide en dormant).
func relax(dt: float, asleep: bool) -> void:
	_relax_timer += dt
	if _relax_timer < RELAX_PERIOD:
		return
	var t := _relax_timer
	_relax_timer = 0.0
	var a := minf(1.0, _stw_relax * t)
	var b := minf(1.0, _ltw_rate * t * (10.0 if asleep else 1.0))
	for i in stw.size():
		var s := stw[i]
		var l := ltw[i]
		if s == l:
			continue
		stw[i] = s + (l - s) * a
		ltw[i] = l + (s - l) * b


## Instinct : rejoue une situation décrite par un gène et applique sa récompense
## directement aux deux mémoires (court et long terme).
func train_instinct(p: Dictionary, strength: float) -> void:
	var d := DRIVE_NAMES.find(str(p.get("drive", "")))
	var v := VERB_KEYS.find(str(p.get("verb", "")))
	if d < 0 or v < 0:
		return
	var cat_name := str(p.get("category", ""))
	# anciennes souches (fruits, graines...) : la catégorie équivalente d'aujourd'hui
	if cat_name in ["fruit", "graine", "baie", "pierre"]:
		cat_name = "eau" if str(p.get("drive", "")) == "Soif" else "croquettes"
	var cat := ObjectCatalog.categories.find(cat_name) if cat_name != "" else -1
	var reward := float(p.get("reward", 1.0)) * strength
	var slot := cat if cat >= 0 else _cats
	var k := d * (_cats + 1) + slot
	var i := k * VERB_COUNT + v
	var w := _lr * reward
	stw[i] = clampf(stw[i] + w, -3.0, 3.0)
	ltw[i] = clampf(ltw[i] + w, -3.0, 3.0)
	if cat >= 0:
		var j := d * _cats + cat
		attn_w[j] = clampf(attn_w[j] + _attn_lr * reward, -3.0, 3.0)


## Poids actuel (court terme) d'un verbe pour une pulsion face à une catégorie.
func weight(drive_name: String, category: int, v: int) -> float:
	var d := DRIVE_NAMES.find(drive_name)
	var slot := category if category >= 0 else _cats
	return stw[(d * (_cats + 1) + slot) * VERB_COUNT + v]


## Force du lien « on m'a dit de v » -> v (tendance à obéir à ce verbe).
func obedience(v: int) -> float:
	return stw[(_heard_base + v) * VERB_COUNT + v]


## Mémoire du cerveau pour la sauvegarde.
func to_dict() -> Dictionary:
	return {"stw": Array(stw), "ltw": Array(ltw), "attn_w": Array(attn_w),
		"attn_bias": Array(attn_bias), "verb_bias": Array(verb_bias)}


func load_dict(d: Dictionary) -> void:
	for key in ["stw", "ltw", "attn_w", "attn_bias", "verb_bias"]:
		var src: Array = d.get(key, [])
		var dst: PackedFloat32Array = get(key)
		if src.size() == dst.size():
			set(key, PackedFloat32Array(src))
		elif key in ["stw", "ltw"] and src.size() < dst.size() and src.size() % VERB_COUNT == 0:
			# sauvegarde d'avant le langage : les nouveaux concepts sont à la fin,
			# on garde l'acquis et les liens innés des verbes entendus
			for i in src.size():
				dst[i] = float(src[i])
			set(key, dst)
		# sinon : cerveau d'une autre version, on garde l'inné
