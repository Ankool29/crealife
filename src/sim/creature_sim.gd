class_name CreatureSim
extends RefCounted
## Une créature : génome, biochimie, cerveau et corps. Aucun affichage ici.
## Le corps perçoit le monde, le cerveau choisit (objet, verbe), le corps
## exécute ; les effets viennent de l'objet visé (data/objects.json).

const Verb = Brain.Verb
const VISION_RANGE := 700.0
const REACH := 30.0
## Le chat agit avec la gueule (et les pattes avant) : en pixels devant son centre.
const MOUTH := 105.0
const HOLD_H := 70.0
const AFTER_ACTION := 1.5        # pause après une action, le temps que la récompense arrive
const MIN_FATIGUE_TO_SLEEP := 0.2
const DRIVE_REWARD_GAIN := 3.0   # baisse d'une pulsion -> récompense
const ACTIVITY: Array[float] = [0.1, 0.5, 0.8, 0.2, 0.3, 0.1, 0.3, 0.5, 0.5, 0.6, 0.2, 0.0, 0.5, 0.4]
const COMPANY_RANGE := 400.0     # au-delà, elle se sent seule
const GESTATION := 1500.0        # 25 min de jeu avant la mise bas
## Allaitement : un bébé tète quand il est collé à sa mère (jusqu'au sevrage,
## c'est-à-dire au stade enfant). La mère a plus faim pendant qu'elle allaite.
const NURSE_RANGE := 140.0
const NURSE_RATE := 0.03         # faim et soif du bébé en moins par seconde
const NURSE_COST := 0.004        # faim de la mère en plus, par bébé qui tète
const MATING_DESIRE := 0.3       # désir minimal du partenaire pour accepter
const MATING_REST := 2400.0      # après un accouplement : 40 min sans désir
const REFUSED_PAUSE := 240.0     # après un refus : elle n'insiste pas tout de suite
const CARE_TIMEOUT := 60.0

var uid := 0
var creature_name: String
var generation := 1
var mother := ""
var father := ""
var genome: Genome
var sex: int
var biochem: Biochemistry
var brain: Brain
var language: Language

var x: float
var facing := 1.0
var age := 0.0
var stage: int = Lifecycle.Stage.BABY
var alive := true
var death_cause := ""
var is_moving := false
var held: WorldObject = null
## Ce que la créature vise : un WorldObject ou une autre CreatureSim.
var target: Object = null
## Gestation (femelle) : temps écoulé, -1 si elle n'attend pas d'œuf.
var pregnant_time := -1.0
var litter_size := 0             # chatons attendus
var nursing := 0.0               # > 0 : en train d'allaiter, ou de téter (affichage)
var _father_genome: Genome = null
var _father_name := ""
## Instant où l'action en cours a produit son effet (pour l'animation).
var acted := false
var meals := 0
var naps := 0
## Repas par type d'objet (statistiques et tests).
var eaten := {}
var last_event := ""

# Apparence (gène Apparence « corps »), valeurs dans [0, 1]
var hue := 0.5
var hue2 := 0.6
var saturation := 0.7
var brightness := 0.7
var glow := 0.47
var glow_power := 0.5
## Silhouette : variantes de queue et d'antennes (0, 1, 2), corpulence [0, 1].
var tail := 1
var antennae := 1
var corpulence := 0.5
## Motifs : intensité des taches, rayures, plaques ; teinte et clarté du motif.
var motif := Vector3.ZERO
var hue3 := 0.1
var light3 := 0.5
var _size_gene := 0.5
var _speed := 100.0

var _chem := {}          # nom -> numéro des substances utilisées par le corps
var _drive_loci := PackedInt32Array()
var _l_meta: int
var _l_act: int
var _l_dort: int
var _l_ennui: int
var _l_speed: int
var _l_seul: int

var _action_time := 0.0
var _done := false
var _goal_x := 0.0
var _prev_drives := PackedFloat32Array()
var _instinct_timer := 0.0
var _mate_rest := 0.0
var _screen_time := 0.0
## Goûts (gène « gout ») : plaisir que donne chaque aliment, et instinct de chasse.
var taste := {"patee": 0.7, "croquettes": 0.5, "proie": 0.6}
## Caractère (gène « caractere ») : sociabilité (câlins, besoin de compagnie),
## audace (peur), agressivité (bagarres), énergie (fatigue, vitesse).
var sociable := 0.5
var boldness := 0.5
var aggressive := 0.3
var energy := 0.5
## Relations : uid d'un autre chat -> affinité (-1 rival ... +1 ami).
var affinity := {}
var _caress_recent := 0.0          # câlins rapprochés : les indépendants s'en lassent
var _threat_uid := -1              # le chat qui lui fait peur
var hunting := 0.5
var catches := 0
var _last_pleasure := 0.0         # plaisir du dernier repas (tests, affichage)           # temps qu'elle compte encore passer devant l'écran
var _refused := 0.0
## Soins aux petits : instinct parental (gène) et tâche en cours
## {kind : "nourrir" ou "parler", child, food, time}.
var care_instinct := 0.0
var _care := {}
## Pelage (génétique du chat) : ce que l'on voit, voir CatCoat.phenotype.
var coat := {}
## Tempérament (gène) : curiosité (apprend plus à l'écran, aime le regarder)
## et espièglerie (s'ennuie plus vite, s'amuse plus avec les jouets).
var curiosity := 0.5
var playfulness := 0.5
## Saut sur le trampoline : temps restant (pour l'affichage).
var bounce_left := 0.0
## Température ressentie (°C) et zone actuelle, pour l'interface.
var felt_temp := 18.0
var _l_cold: int
var _l_hot: int
var _l_night: int
var _l_rain: int
const HUDDLE_RANGE := 150.0


func _init(p_name: String, p_genome: Genome, p_x: float, p_sex: int) -> void:
	creature_name = p_name
	genome = p_genome
	sex = p_sex
	x = p_x
	_goal_x = p_x
	biochem = Biochemistry.new()
	for n in ["Faim", "Peur", "Adrénaline", "Soif", "Fatigue", "Ennui", "Douleur", "Eau", "Glucose", "Toxines", "Récompense", "Punition",
			"Solitude", "Désir", "Hormone sexuelle", "Froid", "Chaud"]:
		_chem[n] = Chemicals.id_of(n)
	var l := biochem.loci
	_l_meta = l.id_of("corps.metabolisme")
	_l_act = l.id_of("corps.activite")
	_l_dort = l.id_of("corps.dort")
	_l_ennui = l.id_of("corps.ennui")
	_l_speed = l.id_of("corps.vitesse_bonus")
	_l_seul = l.id_of("corps.seul")
	_l_cold = l.id_of("corps.froid_ext")
	_l_hot = l.id_of("corps.chaud_ext")
	_l_night = l.id_of("corps.nuit")
	_l_rain = l.id_of("corps.pluie")
	for d in Brain.DRIVE_NAMES:
		_drive_loci.append(l.id_of("pulsion." + d))
	_prev_drives.resize(Brain.DRIVE_COUNT)
	ensure_cat_genes(genome, null, false)
	_express(true)
	language = Language.new(genome.expressed(stage, sex), hash(p_name))
	brain = Brain.new(genome.expressed(stage, sex), language)
	_apply_age_learning()


## L'âge règle la vitesse d'apprentissage (mots et habitudes) et l'oubli.
func _apply_age_learning() -> void:
	if brain == null:
		return
	brain.plasticity = Lifecycle.learning_factor(stage, brain.ageing)
	language.plasticity = brain.plasticity
	language.forgetting = stage == Lifecycle.Stage.OLD


## Ajoute les gènes de chat à un génome qui n'en a pas (créature d'une
## ancienne version) ; random = nouveau pelage tiré au hasard (fondateurs).
static func ensure_cat_genes(g: Genome, rng: RandomNumberGenerator, random: bool) -> void:
	var r := rng
	if r == null:
		r = RandomNumberGenerator.new()
		r.seed = hash(JSON.stringify(g.to_dict()))
	var starter := Genome.starter()
	for part in ["pelage", "morpho"]:
		var gene := g.find(Gene.Type.APPEARANCE, "part", part)
		if gene == null:
			gene = starter.find(Gene.Type.APPEARANCE, "part", part).copy()
			g.genes.append(gene)
			random = true if rng == null else random
		if random:
			gene.params = CatCoat.random_alleles(r) if part == "pelage" else CatCoat.random_morpho(r)
	var taste_gene := g.find(Gene.Type.LOBE, "lobe", "gout")
	if taste_gene == null:
		taste_gene = starter.find(Gene.Type.LOBE, "lobe", "gout").copy()
		g.genes.append(taste_gene)
		random = true
	if random:
		for k in ["patee", "croquettes", "proie", "chasse"]:
			taste_gene.params[k] = clampf(float(taste_gene.params[k]) + r.randf_range(-0.35, 0.35), 0.0, 1.0)
	var char_gene := g.find(Gene.Type.LOBE, "lobe", "caractere")
	var char_new := char_gene == null
	if char_new:
		char_gene = starter.find(Gene.Type.LOBE, "lobe", "caractere").copy()
		g.genes.append(char_gene)
	if random or char_new:
		for k in ["sociable", "audace", "energie"]:
			char_gene.params[k] = clampf(r.randfn(0.5, 0.2), 0.0, 1.0)
		char_gene.params.agressivite = clampf(r.randfn(0.3, 0.2), 0.0, 1.0)


## Exprime les gènes du stade actuel (naissance, puis à chaque changement de stade).
func _express(first_time: bool) -> void:
	biochem.configure(genome.expressed(stage, sex), first_time)
	var look := genome.find(Gene.Type.APPEARANCE, "part", "corps")
	if look:
		hue = float(look.params.get("hue", 0.5))
		hue2 = float(look.params.get("hue2", 0.6))
		saturation = float(look.params.get("saturation", 0.7))
		brightness = float(look.params.get("brightness", 0.7))
		glow = float(look.params.get("glow", 0.47))
		_size_gene = float(look.params.get("size", 0.5))
		_speed = lerpf(60.0, 150.0, float(look.params.get("speed", 0.5)))
		glow_power = float(look.params.get("glow_power", 0.5))
	care_instinct = 0.0
	for g in genome.expressed(stage, sex):
		if g.type == Gene.Type.LOBE and str(g.params.get("lobe", "")) == "parental":
			care_instinct = float(g.params.get("care", 0.6))
		if g.type == Gene.Type.LOBE and str(g.params.get("lobe", "")) == "temperament":
			curiosity = float(g.params.get("curiosity", 0.5))
		if g.type == Gene.Type.LOBE and g.params.get("lobe", "") == "gout":
			for k in taste:
				taste[k] = float(g.params.get(k, taste[k]))
			hunting = float(g.params.get("chasse", 0.5))
		if g.type == Gene.Type.LOBE and g.params.get("lobe", "") == "caractere":
			sociable = float(g.params.get("sociable", 0.5))
			boldness = float(g.params.get("audace", 0.5))
			aggressive = float(g.params.get("agressivite", 0.3))
			energy = float(g.params.get("energie", 0.5))
			playfulness = float(g.params.get("playfulness", 0.5))
	var pel := genome.find(Gene.Type.APPEARANCE, "part", "pelage")
	var mor := genome.find(Gene.Type.APPEARANCE, "part", "morpho")
	if pel and mor:
		coat = CatCoat.phenotype(pel.params, mor.params, sex)
		var c: Color = coat.col_r if coat.orange == 1 else coat.col_e
		hue = c.h
	var shape := genome.find(Gene.Type.APPEARANCE, "part", "silhouette")
	if shape:
		tail = clampi(int(float(shape.params.get("tail", 0.5)) * 3.0), 0, 2)
		antennae = clampi(int(float(shape.params.get("antennae", 0.5)) * 3.0), 0, 2)
		corpulence = float(shape.params.get("corpulence", 0.5))
	var pat := genome.find(Gene.Type.APPEARANCE, "part", "motif")
	if pat:
		var p := pat.params
		motif = Vector3(float(p.get("spots", 0)), float(p.get("stripes", 0)), float(p.get("patches", 0)))
		hue3 = float(p.get("hue3", 0.1))
		light3 = float(p.get("light3", 0.5))


func get_verb() -> int:
	return brain.verb


## Vrai pendant le court instant qui suit une action sur un objet (animation).
func is_acting() -> bool:
	return alive and _done and brain.verb != Verb.DORMIR


func is_asleep() -> bool:
	return alive and brain.verb == Verb.DORMIR


## Palette de couleurs tirée des gènes : [sombre, principale, claire].
func palette() -> Array[Color]:
	var s := lerpf(0.55, 1.0, saturation)
	var v := lerpf(0.75, 1.0, brightness)
	return [
		Color.from_hsv(fposmod(hue + 0.04, 1.0), minf(1.0, s + 0.1), v * 0.3),
		Color.from_hsv(hue, s, v),
		Color.from_hsv(hue2, s * 0.6, minf(1.0, v * 1.1 + 0.1)),
	]


## Couleur du motif (teinte propre, plus claire ou plus sombre que le corps).
func motif_color() -> Color:
	return Color.from_hsv(hue3, lerpf(0.5, 1.0, saturation), lerpf(0.25, 1.0, light3))


## Intensité visible de chaque motif : sous 0,2 le motif reste invisible
## (gène « dormant », qu'une mutation ou un croisement peut réveiller).
func motif_strength() -> Vector3:
	return Vector3(smoothstep(0.2, 0.55, motif.x), smoothstep(0.2, 0.55, motif.y), smoothstep(0.2, 0.55, motif.z))


## Taille affichée : gène de taille × stade de vie.
func body_size() -> float:
	return lerpf(0.8, 1.25, _size_gene) * Lifecycle.STAGE_SIZE[stage]


func level(chem_name: String) -> float:
	return biochem.conc[_chem[chem_name]]


func heart_health() -> float:
	var h := biochem.organ("Coeur")
	return h.health if h else 1.0


## Ce que fait la créature, en mots (« Mange : graine »).
func action_text() -> String:
	if not alive:
		return "Morte"
	if not _care.is_empty():
		return ("Nourrit : " if _care.kind == "nourrir" else "S'occupe de : ") + _care.child.creature_name
	var t := Brain.VERB_LABELS[brain.verb]
	if target != null and brain.verb in Brain.OBJECT_VERBS:
		t += " : " + (target.creature_name if target is CreatureSim else ObjectCatalog.label_of(target.type_name))
	return t


func tick(dt: float, world: WorldSim, rng: RandomNumberGenerator) -> void:
	if not alive:
		return
	age += dt
	var st := Lifecycle.stage_at(age)
	if st != stage:
		stage = st
		_express(false)
		for g in genome.expressed(stage, sex):
			if g.type == Gene.Type.INSTINCT and g.stage == stage:   # instincts de ce nouvel âge
				for i in int(round(float(g.params.get("repeat", 1.0)))):
					brain.train_instinct(g.params, 1.0)
		_apply_age_learning()
		last_event = "%s est maintenant %s." % [creature_name, Lifecycle.STAGE_LABELS[stage].to_lower()]

	_perceive(world)
	language.tick(dt)
	_gestation(dt, world)
	nursing = maxf(0.0, nursing - dt)
	if sex == Gene.Sex.FEMALE and stage >= Lifecycle.Stage.ADULT:
		_nurse(dt, world)
	_action_time -= dt
	is_moving = false
	acted = false
	_regulate_desire(dt, world)
	if not _care.is_empty():
		_execute_care(dt, world)
	elif not _done:
		_execute(dt, world, rng)
	if held != null:
		held.x = x + facing * MOUTH * body_size()
		held.h = HOLD_H * body_size()

	var l := biochem.loci.values
	l[_l_meta] = 1.0
	l[_l_act] = ACTIVITY[brain.verb] * lerpf(1.5, 0.6, energy)     # les énergiques se fatiguent moins
	l[_l_dort] = 1.0 if brain.verb == Verb.DORMIR else 0.0
	l[_l_ennui] = 0.0 if brain.verb == Verb.EXPLORER else lerpf(0.5, 1.8, playfulness)
	l[_l_seul] = brain.situation[3] * lerpf(0.3, 1.8, sociable)    # les indépendants s'ennuient peu des autres
	_caress_recent = maxf(0.0, _caress_recent - dt / 30.0)
	if is_asleep():                    # dormir côte à côte rapproche
		for c in world.creatures:
			if c != self and c.alive and c.is_asleep() and absf(c.x - x) < 130.0:
				bond(c, 0.004 * dt)
	_fear_reflex(dt, world)
	_feel_climate(dt, world)
	biochem.step(dt, age)

	# Récompense naturelle : sentir un besoin diminuer est agréable, et c'est
	# ce besoin-là qui apprend. Caresses et punitions agissent sur tout.
	for d in Brain.DRIVE_COUNT:
		var now := biochem.loci.values[_drive_loci[d]]
		if now < _prev_drives[d] - 0.0001:
			brain.reinforce_drive(d, (_prev_drives[d] - now) * DRIVE_REWARD_GAIN)
		_prev_drives[d] = now
	brain.reinforce((level("Récompense") - level("Punition")) * dt)
	brain.relax(dt, is_asleep())
	if is_asleep():
		_replay_instincts(dt, rng)

	if not biochem.organ("Coeur").is_alive():
		_die()
		return
	if _action_time <= 0.0:
		_decide(world, rng)


## Climat ressenti : température de la zone, réchauffée par les créatures
## blotties tout près ; nuit (fatigue) ; pluie (elle boit un peu).
func _feel_climate(dt: float, world: WorldSim) -> void:
	var l := biochem.loci.values
	bounce_left = maxf(0.0, bounce_left - dt)
	if world.scenario != "normal":          # les scénarios de test n'ont pas de climat
		l[_l_cold] = 0.0
		l[_l_hot] = 0.0
		l[_l_night] = 0.0
		l[_l_rain] = 0.0
		felt_temp = 18.0
		return
	var t := world.temperature_at(x)
	var huddle := 0.0
	for c in world.creatures:
		if c != self and c.alive and absf(c.x - x) < HUDDLE_RANGE:
			huddle += 2.0
	t += minf(huddle, 5.0) + (1.5 if is_asleep() else 0.0)     # endormie, roulée en boule
	felt_temp = t
	l[_l_cold] = clampf((14.0 - t) / 16.0, 0.0, 1.0)
	l[_l_hot] = clampf((t - 27.0) / 10.0, 0.0, 1.0)
	l[_l_night] = 1.0 - world.light_at(x)
	l[_l_rain] = 1.0 if world.raining_at(x) else 0.0


## Regarde-t-elle l'écran ?
func watches(scr: WorldObject) -> bool:
	if _screen_time > 0.0 and absf(scr.x - x) < 300.0 and brain.verb in [Verb.RIEN, Verb.EXPLORER]:
		return true                  # elle est venue exprès devant l'écran
	return target == scr and (brain.attention == ObjectCatalog.categories.find("machine"))


## Le mot montré par l'écran : on l'apprend d'autant mieux qu'on est curieuse.
func learn_from_screen(kind: String, i: int, focus: float = 1.0) -> void:
	var before := language.knowledge(kind, i)
	language.learn(kind, i, 0.3 * focus * lerpf(0.3, 1.7, curiosity))
	if language.knowledge(kind, i) > before + 0.005:
		language.progress_text = "+ " + Language.word_of(kind, i)
		language.progress_left = Language.PROGRESS_TIME


## La boîte à musique joue près d'elle : l'ennui et la solitude baissent.
func hear_music(dt: float) -> void:
	if is_asleep():
		return
	biochem.add(_chem["Ennui"], -0.006 * dt * lerpf(0.6, 1.4, playfulness))
	biochem.add(_chem["Solitude"], -0.002 * dt)


## Remplit les lobes d'entrée : pulsions, vision, situation.
func _perceive(world: WorldSim) -> void:
	for d in Brain.DRIVE_COUNT:
		brain.drives[d] = clampf(biochem.loci.values[_drive_loci[d]], 0.0, 1.0)
	brain.vision.fill(0.0)
	for o in world.objects:
		var dist := absf(o.x - x) if o.holder != self else 0.0
		if dist < VISION_RANGE and (o.holder == null or o.holder == self) and o.category >= 0:
			brain.vision[o.category] = maxf(brain.vision[o.category], 1.0 - dist / VISION_RANGE)
	var nearest_other := INF
	for c in world.creatures:
		if c != self and c.alive:
			nearest_other = minf(nearest_other, absf(c.x - x))
	var cc := ObjectCatalog.categories.find("créature")
	if nearest_other < VISION_RANGE:
		brain.vision[cc] = 1.0 - nearest_other / VISION_RANGE
	brain.situation[0] = 1.0 if held != null else 0.0
	brain.situation[1] = 1.0 if target != null and absf(target.x - mouth_x()) < REACH * 2.0 else 0.0
	brain.situation[2] = clampf(level("Récompense"), 0.0, 1.0)
	brain.situation[3] = 0.0 if nearest_other < COMPANY_RANGE else 1.0


func _decide(world: WorldSim, rng: RandomNumberGenerator) -> void:
	var allowed: Array[bool] = []
	allowed.resize(Brain.VERB_COUNT)
	allowed.fill(true)
	allowed[Verb.LACHER] = held != null
	allowed[Verb.DORMIR] = level("Fatigue") >= MIN_FATIGUE_TO_SLEEP
	allowed[Verb.ACCOUPLER] = stage == Lifecycle.Stage.ADULT and _refused <= 0.0 and _mate_rest <= 0.0
	if _start_care(world, rng):
		return
	var v := brain.decide(rng, allowed)
	if language.shown_left > 0.0 and brain.attention == language.shown_category \
			and language.shown_object != null and _shown_valid(world):
		target = language.shown_object
	elif brain.attention == ObjectCatalog.categories.find("créature"):
		target = _nearest_creature(world)
	else:
		target = _nearest(world, brain.attention) if brain.attention >= 0 else null
	if v in Brain.OBJECT_VERBS and target == null:
		brain.verb = Verb.RIEN
	_survival_reflex(world)
	_done = false
	_maybe_talk(rng)
	match brain.verb:
		Verb.RIEN:
			_action_time = rng.randf_range(2.0, 4.0)
		Verb.EXPLORER:
			_action_time = rng.randf_range(4.0, 8.0)
			_goal_x = _explore_goal(world, rng)
		Verb.DORMIR:
			_action_time = 400.0
		Verb.FUIR:
			_action_time = 6.0
			var from: float = target.x if target != null else x - facing
			_goal_x = clampf(x + signf(x - from + 0.01) * 300.0, 60.0, world.width - 60.0)
		_:
			_action_time = 20.0


## Le chat « en vue » : le plus proche, mais on va plus volontiers vers ses
## amis et on évite ses rivaux.
func _nearest_creature(world: WorldSim) -> CreatureSim:
	var best: CreatureSim = null
	var best_d := VISION_RANGE
	for c in world.creatures:
		if c == self or not c.alive or absf(c.x - x) >= VISION_RANGE:
			continue
		var d := absf(c.x - x) - affinity_with(c) * 250.0
		if d < best_d:
			best_d = d
			best = c
	return best


func _nearest(world: WorldSim, category: int) -> WorldObject:
	if held != null and held.category == category:
		return held
	var best: WorldObject = null
	var best_d := VISION_RANGE
	for o in world.objects:
		if o.category == category and o.holder == null:
			var d := absf(o.x - x)
			if d < best_d:
				best_d = d
				best = o
	return best


func _execute(dt: float, world: WorldSim, rng: RandomNumberGenerator) -> void:
	var v := brain.verb
	match v:
		Verb.RIEN:
			pass
		Verb.EXPLORER:
			biochem.add(_chem["Ennui"], -0.02 * dt)
			if _move_towards(_goal_x, dt):
				_goal_x = _explore_goal(world, rng)
		Verb.DORMIR:
			if world.zone_at(x).key == "chambre":     # dans les paniers : sommeil plus réparateur
				biochem.add(_chem["Fatigue"], -0.003 * dt)
			if level("Fatigue") <= 0.03 or level("Douleur") > 0.5:
				naps += 1
				_finish()
		Verb.FUIR:
			if _move_towards(_goal_x, dt * 1.4):
				_finish()
		Verb.LACHER:
			drop_held()
			_finish()
		_:
			if not _target_valid(world):
				_action_time = 0.0       # la cible a disparu : on change d'idée
				return
			if target != held and not _approach(target.x, dt):
				return                           # d'abord s'approcher de l'objet
			if v != Verb.APPROCHER:
				if target is CreatureSim:
					_act_on_creature(target, v, world)
				else:
					_act_on(target, v, world)
			_finish()


func _target_valid(world: WorldSim) -> bool:
	if target == null:
		return false
	if target is CreatureSim:
		return target.alive and target in world.creatures
	return target in world.objects


## Interactions avec une autre créature.
func _act_on_creature(other: CreatureSim, v: int, world: WorldSim) -> void:
	acted = true
	match v:
		Verb.PARLER:
			var w := language.favourite_word(world.rng)
			if w.is_empty():
				language.speech = "bibou"
				language.speech_left = Language.SAY_TIME
			else:
				language.say([w])
				if not other.coat.get("deaf", false):
					other.language.learn_from(w[0], w[1], language.knowledge(w[0], w[1]))
			biochem.add(_chem["Solitude"], -0.3)
			other.biochem.add(other._chem["Solitude"], -0.3)
			biochem.add(_chem["Ennui"], -0.05)
			bond(other, 0.06)
			other.bond(self, 0.06)
		Verb.EXAMINER:
			biochem.add(_chem["Solitude"], -0.05)
		Verb.FRAPPER:
			other.biochem.add(other._chem["Douleur"], 0.3)
			# seuls les bagarreurs y trouvent du plaisir ; les autres s'en veulent un peu
			biochem.add(_chem["Ennui"], -0.1 * aggressive)
			biochem.add(_chem["Punition"], 0.3 * (1.0 - aggressive))
			other.last_event = "%s a été frappée par %s." % [other.creature_name, creature_name]
			other.frighten(0.5, self)
			bond(other, -0.25)
			other.bond(self, -0.35)
		Verb.POUSSER:
			other.x = clampf(other.x + facing * 40.0, 60.0, world.width - 60.0)
			biochem.add(_chem["Ennui"], -0.05)
		Verb.ACCOUPLER:
			_try_mating(other, world)


## Accouplement : adultes de sexe opposé, partenaire consentant (désir
## suffisant), femelle pas déjà en gestation, population pas au maximum.
func _try_mating(other: CreatureSim, world: WorldSim) -> void:
	var female: CreatureSim = self if sex == Gene.Sex.FEMALE else other
	if other.sex == sex or other.stage != Lifecycle.Stage.ADULT or stage != Lifecycle.Stage.ADULT \
			or other.level("Désir") < MATING_DESIRE or other._mate_rest > 0.0 \
			or female.pregnant_time >= 0.0 or world.population_full():
		_refused = REFUSED_PAUSE        # refus : elle n'insiste pas
		return
	var male: CreatureSim = other if female == self else self
	for c in [self, other]:
		c.biochem.add(c._chem["Désir"], -0.8)
		c.bond(other if c == self else self, 0.1)
		c.biochem.conc[c._chem["Hormone sexuelle"]] = 0.0
		c._mate_rest = MATING_REST
	female.pregnant_time = 0.0
	female.litter_size = world.litter_size_for(female)
	female._father_genome = male.genome
	female._father_name = male.creature_name
	female.last_event = "%s et %s se sont accouplés  : %s attend des petits." % [creature_name, other.creature_name, female.creature_name]
	world.last_event = female.last_event


## Le désir est freiné : repos après un accouplement, pendant la gestation,
## quand elle a un bébé, et quand le monde est plein (surpopulation).
func _regulate_desire(dt: float, world: WorldSim) -> void:
	_mate_rest = maxf(0.0, _mate_rest - dt)
	_screen_time = maxf(0.0, _screen_time - dt)
	_refused = maxf(0.0, _refused - dt)
	if stage < Lifecycle.Stage.ADULT:
		return
	var calm := _mate_rest > 0.0 or pregnant_time >= 0.0 or world.population_full()
	if not calm:
		for c in world.creatures:
			if c.alive and c.stage == Lifecycle.Stage.BABY and is_parent_of(c):
				calm = true
				break
	if calm:
		var h: int = _chem["Hormone sexuelle"]
		biochem.conc[h] = minf(biochem.conc[h], 0.2)     # sous le seuil qui produit le désir


func is_parent_of(c: CreatureSim) -> bool:
	return c != self and (c.mother == creature_name or c.father == creature_name)


# ------------------------------------------------------- soins aux petits --

## Un parent qui n'a pas lui-même de besoin pressant s'occupe parfois d'un
## petit (bébé ou enfant) : il lui apporte à manger s'il a faim ou soif, ou
## va lui parler s'il s'ennuie ou se sent seul (il lui apprend ses mots).
func _start_care(world: WorldSim, rng: RandomNumberGenerator) -> bool:
	if care_instinct <= 0.05 or stage < Lifecycle.Stage.ADULT or held != null and held.category != _food_cat():
		return false
	if level("Faim") > 0.6 or level("Soif") > 0.6 or level("Fatigue") > 0.7:
		return false
	var best: CreatureSim = null
	var best_need := 0.0
	var kind := ""
	for c in world.creatures:
		if not c.alive or c.stage > Lifecycle.Stage.CHILD or not is_parent_of(c) or c.is_asleep():
			continue
		if absf(c.x - x) > VISION_RANGE * 1.5:
			continue
		var hunger := maxf(c.level("Faim"), c.level("Soif"))
		var social := maxf(c.level("Solitude"), c.level("Ennui"))
		if hunger > 0.3 and c.stage == Lifecycle.Stage.BABY and c.mother == creature_name and hunger + 0.3 > best_need:
			best_need = hunger + 0.3           # la mère va allaiter : prioritaire
			best = c
			kind = "allaiter"
		elif hunger > 0.45 and hunger > best_need:
			best_need = hunger
			best = c
			kind = "nourrir"
		elif social > 0.5 and social * 0.8 > best_need:
			best_need = social * 0.8
			best = c
			kind = "parler"
	if best == null or rng.randf() > care_instinct * (0.4 + best_need) and kind != "allaiter":
		return false
	if kind == "allaiter":
		_care = {"kind": kind, "child": best, "food": null, "time": 0.0}
		brain.verb = Verb.APPROCHER
		brain.clear_trace()
		target = best
		_done = false
		_action_time = CARE_TIMEOUT
		return true
	var food: WorldObject = held if held != null else null
	if kind == "nourrir" and food == null:
		food = _food_near(world, best.x)
		if food == null:
			return false
	_care = {"kind": kind, "child": best, "food": food, "time": 0.0}
	brain.verb = Verb.PRENDRE if kind == "nourrir" and held == null else (Verb.APPROCHER if kind == "nourrir" else Verb.PARLER)
	brain.clear_trace()        # ce n'est pas une décision apprise : rien à renforcer
	target = food if held == null and food != null else best
	_done = false
	_action_time = CARE_TIMEOUT
	return true


# ------------------------------------------------------------- caractère --

## Quelque chose lui fait peur (un coup, un chat agressif...) : plus ou moins
## selon son audace.
func frighten(amount: float, source: CreatureSim = null) -> void:
	biochem.add(_chem["Peur"], amount * lerpf(1.6, 0.3, boldness))
	if source != null:
		_threat_uid = source.uid


## Affinité avec un autre chat : monte quand on se parle, se blottit, s'accouple ;
## baisse quand on se bat.
func bond(other: CreatureSim, amount: float) -> void:
	if other == null or other == self:
		return
	affinity[other.uid] = clampf(float(affinity.get(other.uid, 0.0)) + amount, -1.0, 1.0)


func affinity_with(other: CreatureSim) -> float:
	return float(affinity.get(other.uid, 0.0))


## Peur : un chat peureux s'enfuit loin de ce qui l'effraie (un rival
## agressif qui approche, le chat qui vient de le frapper). Les bagarreurs,
## eux, cherchent parfois querelle à un adulte de même sexe tout proche.
func _fear_reflex(dt: float, world: WorldSim) -> void:
	if not alive or is_asleep() or _care.size() > 0:
		return
	for c in world.creatures:
		if c == self or not c.alive or absf(c.x - x) > 260.0:
			continue
		if c.aggressive > 0.7 and affinity_with(c) < -0.3 and c.stage >= Lifecycle.Stage.ADULT:
			frighten(0.04 * dt, c)              # un rival menaçant tout près
	if level("Peur") > 0.55 and brain.verb != Verb.FUIR:
		var threat := world.find_uid(_threat_uid)
		if threat != null and absf(threat.x - x) < 400.0:
			brain.force(ObjectCatalog.categories.find("créature"), Verb.FUIR)
			target = threat
			_done = false
			_action_time = 6.0
			_goal_x = clampf(x + signf(x - threat.x + 0.01) * 350.0, 60.0, world.width - 60.0)
			last_event = "%s a peur de %s et s'enfuit." % [creature_name, threat.creature_name]
			language.speech = "!"
			language.speech_left = Language.SAY_TIME
	# querelle : rare, et seulement chez les bagarreurs
	if aggressive > 0.6 and stage == Lifecycle.Stage.ADULT and brain.verb in [Verb.RIEN, Verb.EXPLORER] \
			and world.rng.randf() < (aggressive - 0.6) * 0.02 * dt:
		for c in world.creatures:
			if c != self and c.alive and c.stage == Lifecycle.Stage.ADULT and c.sex == sex \
					and absf(c.x - x) < 200.0 and affinity_with(c) < 0.3:
				brain.force(ObjectCatalog.categories.find("créature"), Verb.FRAPPER)
				target = c
				_done = false
				_action_time = 8.0
				last_event = "%s cherche querelle à %s." % [creature_name, c.creature_name]
				language.speech = "fff !"          # il crache
				language.speech_left = Language.SAY_TIME
				break


## Quelques mots pour décrire son caractère (panneau, adoptions).
func personality() -> Array[String]:
	var f := sex == Gene.Sex.FEMALE
	var w: Array[String] = []
	if sociable > 0.65:
		w.append("câline" if f else "câlin")
	elif sociable < 0.35:
		w.append("indépendante" if f else "indépendant")
	if boldness < 0.35:
		w.append("peureuse" if f else "peureux")
	elif boldness > 0.7:
		w.append("audacieuse" if f else "audacieux")
	if aggressive > 0.6:
		w.append("bagarreuse" if f else "bagarreur")
	if energy > 0.7:
		w.append("énergique")
	elif energy < 0.3:
		w.append("dormeuse" if f else "dormeur")
	if playfulness > 0.7:
		w.append("joueuse" if f else "joueur")
	if curiosity > 0.7:
		w.append("curieuse" if f else "curieux")
	return w


## Réflexe de survie : affamée devant de la nourriture, ou assoiffée devant
## de l'eau, elle mange ou boit, quoi que son cerveau ait appris d'autre.
func _survival_reflex(world: WorldSim) -> void:
	var cats := ObjectCatalog.categories
	# épuisée (et ni affamée ni assoiffée) : elle s'endort où elle est
	if level("Fatigue") > 0.85 and level("Faim") < 0.6 and level("Soif") < 0.5 and brain.verb != Verb.DORMIR:
		brain.force(-1, Verb.DORMIR)
		target = null
		return
	var want := ""
	if level("Soif") > 0.6 and level("Soif") >= level("Faim"):
		want = "soif"
	elif level("Faim") > 0.7:
		want = "faim"
	elif level("Soif") > 0.6:
		want = "soif"
	if want == "":
		return
	var best: WorldObject = null
	for o in world.objects:
		if o.holder != null or absf(o.x - x) > VISION_RANGE * 0.7:
			continue
		var ok := false
		if want == "faim":
			ok = o.type_name in ["croquettes", "patee"] or o.dead
		else:
			ok = o.category == cats.find("eau")
		if ok and (best == null or absf(o.x - x) < absf(best.x - x)):
			best = o
	if best == null:
		# rien en vue : elle part chercher (vers le distributeur ou l'eau qu'elle connaît)
		if brain.verb != Verb.EXPLORER and brain.verb != Verb.DORMIR:
			brain.force(-1, Verb.EXPLORER)
			target = null
			_goal_x = _explore_goal(world, world.rng)
		return
	brain.force(best.category, Verb.MANGER)     # le cerveau en tirera la leçon
	target = best


func _food_cat() -> int:
	return ObjectCatalog.categories.find("croquettes")


func _food_near(world: WorldSim, around: float) -> WorldObject:
	var best: WorldObject = null
	var best_d := VISION_RANGE * 2.0
	for o in world.objects:
		if o.holder == null and (o.type_name in ["croquettes", "patee"] or o.dead) and absf(o.x - around) < best_d:
			best_d = absf(o.x - around)
			best = o
	return best


func _execute_care(dt: float, world: WorldSim) -> void:
	var child: CreatureSim = _care.child
	_care.time += dt
	if _care.time > CARE_TIMEOUT or not child.alive or not child in world.creatures:
		_end_care()
		return
	if _care.kind == "allaiter":
		if not _approach(child.x, dt, NURSE_RANGE * 0.5):
			return
		brain.verb = Verb.RIEN           # elle se couche et le laisse téter
		if maxf(child.level("Faim"), child.level("Soif")) < 0.05 or level("Faim") > 0.8:
			last_event = "%s a allaité %s." % [creature_name, child.creature_name]
			_end_care()
		return
	if _care.kind == "nourrir":
		var food: WorldObject = _care.food
		if held == null:
			if food == null or not food in world.objects or food.holder != null:
				_end_care()
				return
			if not _approach(food.x, dt):
				return
			held = food                      # il ramasse la nourriture
			food.holder = self
			food.vx = 0.0
			acted = true
			brain.verb = Verb.APPROCHER
			target = child
			return
		if not _approach(child.x, dt, REACH * 1.5):
			return
		drop_held()                          # posée devant le petit
		acted = true
		brain.verb = Verb.LACHER
		biochem.add(_chem["Récompense"], 0.3)
		last_event = "%s apporte à manger à %s." % [creature_name, child.creature_name]
		_end_care()
	else:
		if not _approach(child.x, dt, REACH * 1.5):
			return
		brain.verb = Verb.PARLER
		_act_on_creature(child, Verb.PARLER, world)
		child.biochem.add(child._chem["Ennui"], -0.2)
		biochem.add(_chem["Récompense"], 0.2)
		last_event = "%s parle à son petit %s." % [creature_name, child.creature_name]
		_end_care()


func _end_care() -> void:
	_care = {}
	_finish()


## Gestation : au bout du temps voulu, la chatte met bas un chaton.
func _gestation(dt: float, world: WorldSim) -> void:
	if pregnant_time < 0.0:
		return
	pregnant_time += dt
	if pregnant_time >= GESTATION:
		pregnant_time = -1.0
		var names: Array[String] = []
		var n := maxi(1, litter_size)
		for i in n:                      # chaque chaton a son propre mélange
			var child := Genome.cross(genome, _father_genome, world.rng, 0.03)
			var at := clampf(x + (i - (n - 1) * 0.5) * 45.0, 60.0, world.width - 60.0)
			names.append(world.give_birth(at, child, creature_name, _father_name, maxi(generation, 1) + 1).creature_name)
		var gen := maxi(generation, 1) + 1
		if n == 1:
			world.last_event = "%s a mis bas : naissance de %s (génération %d)." % [creature_name, names[0], gen]
		else:
			world.last_event = "%s a mis bas %d chatons : %s (génération %d)." % [creature_name, n, ", ".join(names), gen]
		last_event = world.last_event
		litter_size = 0
		_father_genome = null


## Les bébés collés à leur mère tètent, éveillés ou endormis.
func _nurse(dt: float, world: WorldSim) -> void:
	var fed := 0
	for c in world.creatures:
		if not c.alive or c.stage != Lifecycle.Stage.BABY or c.mother != creature_name:
			continue
		if absf(c.x - x) > NURSE_RANGE or maxf(c.level("Faim"), c.level("Soif")) < 0.1:
			continue
		c.biochem.add(c._chem["Faim"], -NURSE_RATE * dt)
		c.biochem.add(c._chem["Soif"], -NURSE_RATE * dt)
		c.biochem.add(c._chem["Solitude"], -0.01 * dt)
		c.nursing = 0.5
		fed += 1
	if fed > 0:
		nursing = 0.5
		biochem.add(_chem["Faim"], NURSE_COST * fed * dt)
		biochem.add(_chem["Solitude"], -0.005 * dt)


## Elle dit parfois ce qu'elle ressent, ou ce qu'elle va faire.
func _maybe_talk(rng: RandomNumberGenerator) -> void:
	if language.speech_left > 0.0 or is_asleep() or stage == Lifecycle.Stage.BABY and rng.randf() < 0.5:
		return
	if rng.randf() > 0.08 + 0.25 * language.talk:
		return
	var strongest := -1
	var best := 0.45
	for d in Brain.DRIVE_COUNT:
		if brain.drives[d] > best:
			best = brain.drives[d]
			strongest = d
	if strongest >= 0 and rng.randf() < 0.6:
		language.say([["besoin", strongest]])
	elif brain.verb in Brain.OBJECT_VERBS and brain.attention >= 0:
		language.say([["verbe", brain.verb], ["nom", brain.attention]])


## Le joueur lui montre un objet ou une créature : elle se tourne vers lui
## et le regarde un moment (le temps de lui en dire le nom).
func show_thing(obj: Object) -> void:
	if not alive or is_asleep() or obj == self:
		return
	var cat: int = ObjectCatalog.categories.find("créature") if obj is CreatureSim else obj.category
	if cat < 0:
		return
	language.show(obj, cat)
	facing = signf(obj.x - x) if absf(obj.x - x) > 1.0 else facing
	_action_time = minf(_action_time, 0.3)
	last_event = "Vous montrez %s à %s." % [
		obj.creature_name if obj is CreatureSim else ObjectCatalog.label_of(obj.type_name).to_lower(), creature_name]


func _shown_valid(world: WorldSim) -> bool:
	var o := language.shown_object
	if o is CreatureSim:
		return o.alive and o in world.creatures
	return o in world.objects and o.holder == null


## Le joueur (ou une autre créature) lui parle. closeness : 1 si c'est à elle
## qu'on s'adresse, moins pour celles qui entendent de loin.
func hear(text: String, closeness: float) -> Array:
	if not alive or is_asleep():
		return []
	if coat.get("deaf", false):
		last_event = "%s est sourde : elle n'entend pas les mots (elle peut lire l'écran)." % creature_name
		return []
	var found := language.hear(text, brain, closeness)
	if closeness >= 1.0 and not found.is_empty():
		var understood := false
		for w in found:
			if language.knowledge(w[0], w[1]) > 0.3:
				understood = true
		# un ordre compris interrompt doucement ce qu'elle fait
		if understood and language.obeying() and brain.verb != Verb.DORMIR:
			_action_time = minf(_action_time, 0.5)
		last_event = "%s a entendu « %s »." % [creature_name, text.strip_edges()]
	return found


## L'objet répond au verbe : substances, consommation, coup de pied, apparition.
func _act_on(o: WorldObject, v: int, world: WorldSim) -> void:
	acted = true
	if v == Verb.PRENDRE:
		if held == null and ObjectCatalog.can_carry(o.type_name):
			held = o
			o.holder = self
			o.vx = 0.0
		return
	var r := ObjectCatalog.response(o.type_name, Brain.VERB_KEYS[v])
	var hunger_before := level("Faim")
	if r.get("prey", false) and not o.dead:
		_hunt(o, v, world)
		return
	for chem_name in r.get("chems", {}):
		var amount := float(r.chems[chem_name])
		if chem_name == "Ennui" and amount < 0.0:
			if o.category == ObjectCatalog.categories.find("jouet"):
				amount *= lerpf(0.8, 1.3, playfulness)       # les espiègles s'amusent plus
			elif r.get("curious", false):
				amount *= lerpf(0.4, 1.8, curiosity)         # les curieuses aiment l'écran
		biochem.add(Chemicals.id_of(chem_name), amount)
	if r.has("bounce"):
		bounce_left = float(r.bounce)
	if r.has("music"):
		o.cooldown = float(r.music)
		world.last_event = "%s fait jouer la boîte à musique." % creature_name
	if r.get("next_screen", false):
		world.next_screen_mode()
	if r.get("curious", false) and o.type_name == "ecran":
		var item := world.screen_item()
		learn_from_screen(item[0], item[1])
	if r.has("kick"):
		if o == held:
			drop_held()
		o.vx = facing * float(r.kick)
		o.vy = -150.0
		o.h = 1.0
	if r.has("spawn") and o.cooldown <= 0.0:
		world.add_object(str(r.spawn), o.x + facing * 40.0, 60.0)
		o.cooldown = float(r.get("cooldown", 10.0))
	if r.get("consume", false):
		if o == held:
			held = null
		world.remove_object(o)
		target = null
		meals += 1
		eaten[o.type_name] = eaten.get(o.type_name, 0) + 1
		_taste(str(ObjectCatalog.types[o.type_name].get("food", "")), hunger_before)


## Tente d'attraper une proie vivante : réussite selon l'instinct de chasse
## (un oiseau est plus dur qu'une souris). Attraper est un plaisir en soi.
func _hunt(o: WorldObject, v: int, world: WorldSim) -> void:
	var info: Dictionary = ObjectCatalog.types[o.type_name].prey
	var p := (0.15 + 0.6 * hunting) * float(info.get("catch", 1.0))
	if v == Verb.MANGER:
		p *= 0.5                     # se jeter dessus la gueule ouverte : moins efficace
	if v == Verb.FRAPPER:
		p *= 1.3                     # le coup de patte
	if world.rng.randf() < p:
		o.dead = true
		o.vx = 0.0
		catches += 1
		biochem.add(_chem["Récompense"], 0.3 + 0.6 * hunting)
		biochem.add(_chem["Ennui"], -0.3)
		last_event = "%s a attrapé %s !" % [creature_name, "une souris" if o.type_name == "souris" else "un oiseau"]
		world.last_event = last_event
	else:
		o.flee = 3.0
		biochem.add(_chem["Ennui"], -0.05 * hunting)


## Le goût : plus un aliment est aimé, plus il fait plaisir (récompense en
## plus de la faim calmée). Le cerveau apprend ainsi ses préférences ; un
## aliment peu aimé reste mangé quand on a faim (pas de punition : sinon un
## chat pourrait se laisser mourir devant sa gamelle).
func _taste(food: String, hunger: float = 1.0) -> void:
	# le plaisir dépend de l'appétit : manger sans faim n'apporte presque rien
	# (sinon le cerveau apprend à manger sans arrêt, par gourmandise)
	# Le plaisir renforce « faim -> manger cet aliment » (et lui seul : pas de
	# grignotage par ennui). Moins de plaisir sans appétit.
	if taste.has(food):
		var r := float(taste[food]) * 0.5 * clampf(hunger * 1.5, 0.25, 1.0)
		brain.reinforce_drive(Brain.DRIVE_NAMES.find("Faim"), r)
		_last_pleasure = r


## L'aliment préféré parmi ceux qu'elle a déjà goûtés ("" si aucun).
func favorite_food() -> String:
	var best := ""
	var types := {"patee": ["patee"], "croquettes": ["croquettes"], "proie": ["souris", "oiseau"]}
	for f in taste:
		var tried := 0
		for t in types[f]:
			tried += eaten.get(t, 0)
		if tried > 0 and (best == "" or taste[f] > taste[best]):
			best = f
	return best


func _finish() -> void:
	if language.obeying() and language.heard_verb[brain.verb] > 0.0:
		language.clear_order()
	_done = true
	_action_time = AFTER_ACTION


func drop_held() -> void:
	if held != null:
		held.holder = null
		held.h = 30.0
		held = null


## Le joueur caresse la créature : récompense ce qu'elle vient de faire.
func caress() -> void:
	if not alive:
		return
	# un indépendant qu'on câline trop souvent finit par donner un coup de patte
	_caress_recent += 1.0
	if sociable < 0.35 and _caress_recent > 1.5 + sociable * 4.0:
		biochem.add(_chem["Punition"], 0.2)
		last_event = "%s vous donne un coup de patte : trop de câlins pour ce chat indépendant." % creature_name
		return
	biochem.add(_chem["Récompense"], lerpf(0.5, 1.4, sociable))
	biochem.add(_chem["Ennui"], -0.1)
	biochem.add(_chem["Peur"], -0.3)
	if sociable > 0.6:
		language.speech = "rrrr"           # il ronronne
		language.speech_left = Language.SAY_TIME
	last_event = "%s a été caressée pendant qu'elle : %s." % [creature_name, action_text().to_lower()]


## Le joueur gronde la créature : punit ce qu'elle vient de faire et l'interrompt.
func scold() -> void:
	if not alive:
		return
	biochem.add(_chem["Punition"], 1.0)
	biochem.add(_chem["Peur"], 0.3 * lerpf(1.5, 0.3, boldness))
	last_event = "%s a été grondée pendant qu'elle : %s." % [creature_name, action_text().to_lower()]
	_action_time = minf(_action_time, AFTER_ACTION)


## Pendant le sommeil, les instincts sont rejoués de temps en temps.
func _replay_instincts(dt: float, rng: RandomNumberGenerator) -> void:
	_instinct_timer += dt
	if _instinct_timer < 30.0:
		return
	_instinct_timer = 0.0
	var instincts := []
	for g in genome.expressed(stage, sex):
		if g.type == Gene.Type.INSTINCT:
			instincts.append(g)
	if not instincts.is_empty():
		brain.train_instinct(instincts[rng.randi_range(0, instincts.size() - 1)].params, 0.3)


func _die() -> void:
	alive = false
	is_moving = false
	drop_held()
	if age > biochem.organ("Coeur").longevity_s:
		death_cause = "de vieillesse"
	elif level("Glucose") < 0.05:
		death_cause = "de faim"
	elif level("Eau") < 0.05:
		death_cause = "de soif"
	elif level("Toxines") > 0.5:
		death_cause = "empoisonnée"
	else:
		death_cause = "d'épuisement"
	last_event = "%s est morte %s, à %s." % [creature_name, death_cause, format_age()]


## État complet pour la sauvegarde.
func to_dict() -> Dictionary:
	return {
		"uid": uid, "name": creature_name, "genome": genome.to_dict(), "sex": sex,
		"generation": generation, "mother": mother, "father": father,
		"x": x, "facing": facing, "age": age, "alive": alive, "death_cause": death_cause,
		"meals": meals, "naps": naps, "eaten": eaten, "catches": catches, "affinity": affinity,
		"pregnant_time": pregnant_time, "litter_size": litter_size, "father_genome": _father_genome.to_dict() if _father_genome else null,
		"father_name": _father_name, "mate_rest": _mate_rest,
		"biochem": biochem.to_dict(), "brain": brain.to_dict(), "language": language.to_dict(),
	}


static func from_dict(d: Dictionary) -> CreatureSim:
	var c := CreatureSim.new(str(d.name), Genome.from_dict(d.genome), float(d.x), int(d.sex))
	c.uid = int(d.uid)
	c.generation = int(d.generation)
	c.mother = str(d.mother)
	c.father = str(d.father)
	c.facing = float(d.facing)
	c.age = float(d.age)
	c.stage = Lifecycle.stage_at(c.age)
	c._express(false)
	c.alive = bool(d.alive)
	c.death_cause = str(d.death_cause)
	c.meals = int(d.meals)
	c.naps = int(d.naps)
	c.catches = int(d.get("catches", 0))
	for k in d.get("affinity", {}):
		c.affinity[int(k)] = float(d.affinity[k])
	c.eaten = d.eaten
	c.pregnant_time = float(d.pregnant_time)
	c.litter_size = int(d.get("litter_size", 1))
	if d.father_genome != null:
		c._father_genome = Genome.from_dict(d.father_genome)
	c._father_name = str(d.father_name)
	c._mate_rest = float(d.get("mate_rest", 0.0))
	c.biochem.load_dict(d.biochem)
	c._apply_age_learning()
	c.brain.load_dict(d.brain)
	c.language.load_dict(d.get("language", {}))
	return c


func format_age() -> String:
	var m := int(age / 60.0)
	return "%d h %02d" % [m / 60, m % 60]


## Position de la gueule (devant le chat, du côté où il regarde).
func mouth_x() -> float:
	return x + facing * MOUTH * body_size()


## S'approche jusqu'à avoir tx juste devant la gueule ; true une fois arrivée.
func _approach(tx: float, dt: float, tolerance: float = REACH) -> bool:
	var dir := signf(tx - x) if absf(tx - x) > 1.0 else facing
	var want := tx - dir * MOUTH * body_size()
	if absf(want - x) > tolerance:
		_move_towards(want, dt)
		if absf(tx - x) > 1.0:
			facing = signf(tx - x)              # toujours tournée vers ce qu'elle vise
		return false
	facing = dir
	return true


## Avance vers tx ; renvoie true une fois arrivée.
func _move_towards(tx: float, dt: float) -> bool:
	var dx := tx - x
	if absf(dx) < 4.0:
		return true
	facing = signf(dx)
	var speed := _speed * (1.0 + 0.5 * minf(biochem.loci.values[_l_speed], 1.0)) * Lifecycle.STAGE_SIZE[stage] \
		* lerpf(0.85, 1.15, energy)
	x = move_toward(x, tx, speed * dt)
	is_moving = true
	return false


## Exploration : au hasard, sauf quand elle se sent seule ou cherche un
## partenaire : elle part alors plutôt du côté où elle sent les autres
## (odorat et ouïe, au-delà de la vue), ce qui les regroupe dans la grande maison.
func _explore_goal(world: WorldSim, rng: RandomNumberGenerator) -> float:
	# Un bébé ne s'éloigne pas de sa mère : il la suit
	if stage == Lifecycle.Stage.BABY:
		var mum := world.find_creature(mother)
		if mum != null and mum.alive and absf(mum.x - x) > 120.0:
			return clampf(mum.x - signf(mum.x - x) * rng.randf_range(20.0, 80.0), 60.0, world.width - 60.0)
	# Une mère qui a des bébés ne s'en éloigne pas beaucoup
	if sex == Gene.Sex.FEMALE and level("Faim") < 0.5:
		var sum := 0.0
		var nb := 0
		for c in world.creatures:
			if c.alive and c.stage == Lifecycle.Stage.BABY and c.mother == creature_name:
				sum += c.x
				nb += 1
		if nb > 0:
			return clampf(sum / nb + rng.randf_range(-150.0, 150.0), 60.0, world.width - 60.0)
	# Affamée (ou assoiffée) sans rien en vue : elle se souvient où sont le
	# distributeur de croquettes et l'eau, et s'y dirige.
	var spots: Array[float] = []
	if level("Faim") > 0.35 and not _sees_food():
		for o in world.objects:
			if o.type_name == "distributeur":
				spots.append(o.x)
	elif level("Soif") > 0.35 and brain.vision[ObjectCatalog.categories.find("eau")] <= 0.0:
		for o in world.objects:
			if o.category == ObjectCatalog.categories.find("eau"):
				spots.append(o.x)
	if true:
		if not spots.is_empty():
			spots.sort_custom(func(a, b): return absf(a - x) < absf(b - x))
			if absf(spots[0] - x) > 250.0:
				return clampf(x + signf(spots[0] - x) * minf(absf(spots[0] - x), 800.0), 60.0, world.width - 60.0)
	# Les curieuses vont d'elles-mêmes s'installer devant l'écran un moment
	var scr := world._first("ecran")
	if scr and _screen_time > 0.0 and level("Faim") < 0.4:     # elle reste devant
		return clampf(scr.x + rng.randf_range(-150.0, 150.0), 60.0, world.width - 60.0)
	var needy := maxf(maxf(level("Faim"), level("Soif")), level("Fatigue")) > 0.3
	if scr and not needy and rng.randf() < curiosity * 0.15 and absf(scr.x - x) < 3000.0:
		_screen_time = rng.randf_range(30.0, 60.0) * lerpf(0.5, 1.5, curiosity)
		return clampf(scr.x + rng.randf_range(-150.0, 150.0), 60.0, world.width - 60.0)
	# Les espiègles, elles, filent vers la salle de jeux
	var jeux := world.zone("jeux")
	if not jeux.is_empty() and not needy and rng.randf() < playfulness * 0.15:
		var mid: float = (jeux.x0 + jeux.x1) * 0.5
		if absf(mid - x) < 3000.0 and world.zone_at(x).key != "jeux":
			return clampf(mid + rng.randf_range(-500.0, 500.0), 60.0, world.width - 60.0)
	var social := level("Solitude")
	if stage == Lifecycle.Stage.ADULT:
		social = maxf(social, level("Désir"))
	if rng.randf() < social:
		var best: CreatureSim = null
		for c in world.creatures:
			if c != self and c.alive and (best == null or absf(c.x - x) < absf(best.x - x)):
				best = c
		if best != null and absf(best.x - x) > 300.0:
			return clampf(x + signf(best.x - x) * rng.randf_range(300.0, 600.0), 60.0, world.width - 60.0)
	return _random_goal(world, rng, 500.0)


func _sees_food() -> bool:
	for n in ["pâtée", "croquettes"]:
		if brain.vision[ObjectCatalog.categories.find(n)] > 0.0:
			return true
	return false


func _random_goal(world: WorldSim, rng: RandomNumberGenerator, radius: float) -> float:
	return clampf(x + rng.randf_range(-radius, radius), 60.0, world.width - 60.0)
