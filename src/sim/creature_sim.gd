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
## Gestation (femelle) : temps écoulé, -1 si elle n'attend pas de petits.
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
## Corpulence [0, 1] : svelte à trapu (affichage).
var corpulence := 0.5
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
var _dest_x := -1.0                # pièce visée (voyage en cours), -1 si aucune
var _dest_until := 0.0
var _dest_sleep := false           # elle va se coucher dans la chambre
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
		_size_gene = float(look.params.get("size", 0.5))
		_speed = lerpf(60.0, 150.0, float(look.params.get("speed", 0.5)))
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
	var shape := genome.find(Gene.Type.APPEARANCE, "part", "silhouette")
	if shape:
		corpulence = float(shape.params.get("corpulence", 0.5))


func get_verb() -> int:
	return brain.verb


## Vrai pendant le court instant qui suit une action sur un objet (animation).
func is_acting() -> bool:
	return alive and _done and brain.verb != Verb.DORMIR


func is_asleep() -> bool:
	return alive and brain.verb == Verb.DORMIR


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
	_go_to_bed(world, rng)
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


func _try_mating(other: CreatureSim, world: WorldSim) -> void:
	CatFamily.try_mating(self, other, world)


func _regulate_desire(dt: float, world: WorldSim) -> void:
	CatFamily.regulate_desire(self, dt, world)


func is_parent_of(c: CreatureSim) -> bool:
	return c != self and (c.mother == creature_name or c.father == creature_name)


# ------------------------------------------------------- soins aux petits --

func _start_care(world: WorldSim, rng: RandomNumberGenerator) -> bool:
	return CatFamily.start_care(self, world, rng)


# ------------------------------------------------------------- caractère --

func frighten(amount: float, source: CreatureSim = null) -> void:
	CatCharacter.frighten(self, amount, source)


func bond(other: CreatureSim, amount: float) -> void:
	CatCharacter.bond(self, other, amount)


func affinity_with(other: CreatureSim) -> float:
	return CatCharacter.affinity_with(self, other)


func _fear_reflex(dt: float, world: WorldSim) -> void:
	CatCharacter.fear_reflex(self, dt, world)


func personality() -> Array[String]:
	return CatCharacter.personality(self)


func _survival_reflex(world: WorldSim) -> void:
	CatFood.survival_reflex(self, world)


func _food_cat() -> int:
	return ObjectCatalog.categories.find("croquettes")


func _food_near(world: WorldSim, around: float) -> WorldObject:
	return CatFood.food_near(self, world, around)


func _execute_care(dt: float, world: WorldSim) -> void:
	CatFamily.execute_care(self, dt, world)


func _end_care() -> void:
	CatFamily.end_care(self)


func _gestation(dt: float, world: WorldSim) -> void:
	CatFamily.gestation(self, dt, world)


func _nurse(dt: float, world: WorldSim) -> void:
	CatFamily.nurse(self, dt, world)


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


func _hunt(o: WorldObject, v: int, world: WorldSim) -> void:
	CatFood.hunt(self, o, v, world)


func _taste(food: String, hunger: float = 1.0) -> void:
	CatFood.taste(self, food, hunger)


func favorite_food() -> String:
	return CatFood.favorite_food(self)


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
	# Voyage en cours vers une autre pièce : on continue jusqu'à y arriver
	if _dest_x >= 0.0:
		if absf(_dest_x - x) < 200.0 or world.time > _dest_until:
			_dest_x = -1.0
			if world.time > _dest_until:
				_dest_sleep = false
		else:
			return clampf(x + signf(_dest_x - x) * minf(absf(_dest_x - x), 900.0), 60.0, world.width - 60.0)
	# Parfois, envie d'aller ailleurs : la pièce dépend de l'état et du caractère
	if stage != Lifecycle.Stage.BABY and rng.randf() < 0.3:
		var room := _wanted_room(world, rng)
		if not room.is_empty():
			_dest_x = rng.randf_range(float(room.x0) + 150.0, float(room.x1) - 150.0)
			_dest_until = world.time + 300.0
			return clampf(x + signf(_dest_x - x) * minf(absf(_dest_x - x), 900.0), 60.0, world.width - 60.0)
	var social := level("Solitude")
	if stage == Lifecycle.Stage.ADULT:
		social = maxf(social, level("Désir"))
	if rng.randf() < social * 0.5:
		var best: CreatureSim = null
		for c in world.creatures:
			if c != self and c.alive and (best == null or absf(c.x - x) < absf(best.x - x)):
				best = c
		if best != null and absf(best.x - x) > 300.0:
			return clampf(x + signf(best.x - x) * rng.randf_range(300.0, 600.0), 60.0, world.width - 60.0)
	return _random_goal(world, rng, 500.0)


## Sommeil : fatiguée (sans être épuisée), elle va se coucher dans la chambre
## plutôt que de dormir n'importe où ; arrivée, elle s'endort.
func _go_to_bed(world: WorldSim, rng: RandomNumberGenerator) -> void:
	var bed := world.zone("chambre")
	if bed.is_empty() or stage == Lifecycle.Stage.BABY:
		return
	var in_bed: bool = world.zone_at(x).get("key", "") == "chambre"
	if _dest_sleep and in_bed and level("Fatigue") > MIN_FATIGUE_TO_SLEEP and brain.verb != Verb.DORMIR:
		_dest_sleep = false
		_dest_x = -1.0
		brain.force(-1, Verb.DORMIR)
		target = null
		return
	if brain.verb == Verb.DORMIR and not in_bed and level("Fatigue") < 0.85 \
			and absf((bed.x0 + bed.x1) * 0.5 - x) < 6000.0:
		_dest_sleep = true
		_dest_x = rng.randf_range(float(bed.x0) + 200.0, float(bed.x1) - 200.0)
		_dest_until = world.time + 300.0
		brain.force(-1, Verb.EXPLORER)
		target = null
		_goal_x = clampf(x + signf(_dest_x - x) * minf(absf(_dest_x - x), 900.0), 60.0, world.width - 60.0)


## La pièce où elle a envie d'aller : la chambre quand elle est fatiguée ou
## la nuit, le jardin pour les chasseuses et les énergiques (de jour, par beau
## temps), la salle de jeux pour les espiègles, la salle d'apprentissage pour
## les curieuses, la cuisine quand elle a faim. Tirage pondéré ; si c'est la
## pièce où elle est déjà, elle y reste.
func _wanted_room(world: WorldSim, rng: RandomNumberGenerator) -> Dictionary:
	var here: String = world.zone_at(x).get("key", "")
	var g := world.zone("jardin")
	var day := world.light_at(float(g.get("x0", 0.0)) + 100.0) > 0.5 if not g.is_empty() else true
	var nice := day and not world.raining_at(float(g.get("x0", 0.0)) + 100.0)
	var scores := {
		"chambre": level("Fatigue") * 2.5 + (0.6 if not day else 0.0),
		"jardin": 0.2 + hunting * 0.6 + energy * 0.4 + (0.4 if nice else -0.4),
		"jeux": 0.2 + playfulness * 0.8 + level("Ennui") * 0.5,
		"salle": 0.1 + curiosity * 0.6,
		"cuisine": 0.1 + level("Faim") * 1.5,
		"entree": 0.05,
	}
	var total := 0.0
	for k in scores:
		scores[k] = 0.0 if world.zone(k).is_empty() else pow(maxf(scores[k], 0.02), 2.0)
		total += scores[k]
	if total <= 0.0:
		return {}
	var r := rng.randf() * total
	for k in scores:
		r -= scores[k]
		if r <= 0.0:
			return {} if k == here else world.zone(k)     # la pièce où elle est déjà : elle y reste
	return {}


func _sees_food() -> bool:
	return CatFood.sees_food(self)


func _random_goal(world: WorldSim, rng: RandomNumberGenerator, radius: float) -> float:
	return clampf(x + rng.randf_range(-radius, radius), 60.0, world.width - 60.0)
