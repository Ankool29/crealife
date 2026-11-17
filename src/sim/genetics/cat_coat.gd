class_name CatCoat
extends RefCounted
## Génétique du pelage du chat (mendélienne).
##
## Le gène d'apparence « pelage » porte deux allèles par locus (X1, X2), un
## venant de chaque parent. Valeurs : 0 = allèle dominant (ou sauvage), 1 ou
## 2 = allèles récessifs ou mutants, comme chez le vrai chat :
##   O  orange, lié à l'X : O1 vient de la mère, O2 du père (ignoré chez le
##      mâle, qui n'a qu'un X) ; femelle O/o = écaille de tortue
##   B  0 noir > 1 chocolat > 2 cannelle
##   D  1 = dilution (récessive) : bleu, lilas, faon, crème
##   A  1 = non-agouti (récessif) : couleur unie au lieu de tigrée
##   T  1 = tigré classique (récessif), sinon maquereau
##   Ti 1 = tiqueté (dominant), efface les rayures du corps
##   Sp 1 = moucheté (rayures cassées en taches)
##   C  1 = colourpoint siamois (récessif, sensible à la température)
##   W  1 = blanc dominant (yeux souvent bleus, risque de surdité)
##   S  1 = panachure blanche (1 copie : un peu, 2 copies : beaucoup)
##   I  1 = argenté (dominant) : fond blanc argent, « smoke » si uni
##   L  1 = poil long (récessif)
##   M  1 = queue courte type Manx (dominant)
## Le gène « morpho » porte les traits continus : forme de tête, yeux,
## intensité du roux, quantité de blanc, contraste des rayures.

const LOCI := {"O": 1, "B": 2, "D": 1, "A": 1, "T": 1, "Ti": 1, "Sp": 1, "C": 1, "W": 1, "S": 1, "I": 1, "L": 1, "M": 1}
## Fréquence de l'allèle « mutant » chez les fondateurs (chats de gouttière).
const FOUNDER_FREQ := {"O": 0.3, "B": 0.15, "D": 0.3, "A": 0.55, "T": 0.45, "Ti": 0.06, "Sp": 0.1, "C": 0.15,
	"W": 0.04, "S": 0.3, "I": 0.07, "L": 0.35, "M": 0.03}
const MORPHO_KEYS: Array[String] = ["head", "eye", "rufous", "white_grade", "contrast"]
const PATTERNS: Array[String] = ["maquereau", "classique", "moucheté", "tiqueté"]


## Allèles d'un fondateur, tirés selon les fréquences.
static func random_alleles(rng: RandomNumberGenerator) -> Dictionary:
	var p := {"part": "pelage"}
	for locus in LOCI:
		for k in ["1", "2"]:
			var v := 0
			if rng.randf() < FOUNDER_FREQ[locus]:
				v = 1 if LOCI[locus] == 1 else rng.randi_range(1, LOCI[locus])
			p[locus + k] = float(v)
	return p


static func random_morpho(rng: RandomNumberGenerator) -> Dictionary:
	var p := {"part": "morpho"}
	for k in MORPHO_KEYS:
		p[k] = rng.randf()
	p["head"] = clampf(rng.randfn(0.5, 0.2), 0.0, 1.0)    # surtout des têtes moyennes
	return p


## Hérédité : un allèle de chaque parent pour chaque locus. Pour O (lié à
## l'X), le petit reçoit un X de sa mère (O1) et l'X du père (son O1), que
## seules les femelles expriment.
static func cross(child: Gene, mother: Gene, father: Gene, rng: RandomNumberGenerator) -> void:
	for locus in LOCI:
		var m: float = mother.params.get(locus + ("1" if rng.randf() < 0.5 else "2"), 0.0)
		var f: float
		if locus == "O":
			m = mother.params.get("O1" if rng.randf() < 0.5 else "O2", 0.0)
			f = father.params.get("O1", 0.0)
		else:
			f = father.params.get(locus + ("1" if rng.randf() < 0.5 else "2"), 0.0)
		child.params[locus + "1"] = m
		child.params[locus + "2"] = f


## Mutation rare d'un allèle (changement de version du gène).
static func mutate(g: Gene, rng: RandomNumberGenerator, rate: float) -> bool:
	var changed := false
	for locus in LOCI:
		for k in ["1", "2"]:
			if rng.randf() < rate * g.mutability * 0.1:
				g.params[locus + k] = float(rng.randi_range(0, LOCI[locus]))
				changed = true
	return changed


static func _has(p: Dictionary, locus: String) -> int:
	return int(p.get(locus + "1", 0.0) >= 0.5) + int(p.get(locus + "2", 0.0) >= 0.5)


## Ce que l'on voit : couleurs, motif, blanc, poil, queue, yeux, nom.
static func phenotype(pelage: Dictionary, morpho: Dictionary, sex: int) -> Dictionary:
	var ph := {}
	var female := sex == Gene.Sex.FEMALE
	var o := int(pelage.get("O1", 0.0) >= 0.5) + (int(pelage.get("O2", 0.0) >= 0.5) if female else 0)
	ph.orange = 0 if o == 0 else (2 if female and o == 1 else 1)     # 0 non, 1 roux, 2 écaille
	var b := int(min(pelage.get("B1", 0.0), pelage.get("B2", 0.0)))
	var dilute := _has(pelage, "D") == 2
	ph.dilute = dilute
	var rufous := float(morpho.get("rufous", 0.5))
	var eu: Array[Color] = [Color(0.08, 0.07, 0.065), Color(0.3, 0.17, 0.1), Color(0.5, 0.3, 0.16)]
	var eu_dil: Array[Color] = [Color(0.45, 0.48, 0.53), Color(0.66, 0.6, 0.6), Color(0.72, 0.6, 0.5)]
	ph.col_e = eu_dil[b] if dilute else eu[b]
	ph.b = b
	ph.col_r = Color(0.94, 0.8, 0.6).lerp(Color(0.97, 0.72, 0.5), rufous) if dilute \
		else Color(0.85, 0.5, 0.2).lerp(Color(0.8, 0.33, 0.08), rufous)
	ph.agouti = _has(pelage, "A") < 2
	ph.silver = _has(pelage, "I") > 0
	var ticked := _has(pelage, "Ti") > 0
	var pattern := 3 if ticked else (1 if _has(pelage, "T") == 2 else (2 if _has(pelage, "Sp") > 0 else 0))
	ph.pattern = pattern
	ph.points = _has(pelage, "C") == 2
	ph.white_dom = _has(pelage, "W") > 0
	var s := _has(pelage, "S")
	var grade := float(morpho.get("white_grade", 0.5))
	ph.white = 1.0 if ph.white_dom else [0.0, 0.12 + 0.3 * grade, 0.5 + 0.38 * grade][s]
	ph.long_fur = _has(pelage, "L") == 2
	ph.manx = _has(pelage, "M") > 0
	ph.head = clampi(int(float(morpho.get("head", 0.5)) * 3.0), 0, 2)
	ph.contrast = lerpf(0.6, 1.0, float(morpho.get("contrast", 0.5)))
	# Yeux : bleus chez les siamois ; chez les blancs, souvent bleus ou vairons
	var e := float(morpho.get("eye", 0.5))
	var normal := Color(0.85, 0.5, 0.1).lerp(Color(0.85, 0.75, 0.15), clampf(e * 2.0, 0.0, 1.0)) \
		.lerp(Color(0.35, 0.75, 0.3), clampf(e * 2.0 - 1.0, 0.0, 1.0))
	var blue := Color(0.35, 0.6, 0.95)
	ph.eye = normal
	ph.eye_far = normal
	ph.deaf = false
	if ph.points:
		ph.eye = blue
		ph.eye_far = blue
	elif ph.white_dom and e < 0.35:
		ph.eye = blue
		ph.eye_far = blue if e < 0.2 else normal          # vairon : un œil bleu
		ph.deaf = e < 0.2                                 # blanc aux yeux bleus : sourd
	ph.name = _name(ph)
	return ph


static func _name(ph: Dictionary) -> String:
	if ph.white_dom:
		var eyes := "aux yeux bleus" if ph.eye == ph.eye_far and ph.eye.b > 0.8 else ("vairon" if ph.eye != ph.eye_far else "")
		return ("blanc " + eyes).strip_edges() + (", poil long" if ph.long_fur else "")
	var e_names := ["noir", "chocolat", "cannelle"]
	var e_dil := ["bleu", "lilas", "faon"]
	var base: String
	var b: int = ph.b
	var e_name: String = e_dil[b] if ph.dilute else e_names[b]
	var r_name := "crème" if ph.dilute else "roux"
	match ph.orange:
		1: base = r_name
		2: base = ("calico" + (" dilué" if ph.dilute else "")) if ph.white >= 0.3 \
			else ("écaille de tortue" + (" bleue et crème" if ph.dilute else ""))
		_: base = e_name
	var tabby: bool = ph.orange == 1 or ph.agouti
	var t := ""
	if tabby:
		t = " tigré " + PATTERNS[ph.pattern]
		if ph.silver:
			t += " argenté"
	elif ph.silver:
		t = " smoke"
	if tabby and ph.orange == 0 and not ph.dilute and ph.b == 0:
		base = "brun"                     # un noir tigré s'appelle « brun tigré »
	var name: String = base + t
	if ph.points:
		name = "colourpoint " + name
	if ph.orange != 2 or ph.white < 0.3:
		if ph.white >= 0.8:
			name += ", van"
		elif ph.white >= 0.5:
			name += ", arlequin"
		elif ph.white >= 0.1:
			name += " et blanc"
	if ph.long_fur:
		name += ", poil long"
	if ph.manx:
		name += ", queue courte"
	return name
