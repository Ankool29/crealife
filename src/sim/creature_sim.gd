class_name CreatureSim
extends RefCounted
## Une créature : génome, biochimie, cerveau et corps. Aucun affichage ici.
## Le corps perçoit le monde, le cerveau choisit (objet, verbe), le corps
## exécute ; les effets viennent de l'objet visé (data/objects.json).

const Verb = Brain.Verb
const VISION_RANGE := 700.0
const REACH := 30.0
const AFTER_ACTION := 1.5        # pause après une action, le temps que la récompense arrive
const MIN_FATIGUE_TO_SLEEP := 0.2
const DRIVE_REWARD_GAIN := 3.0   # baisse d'une pulsion -> récompense
const ACTIVITY: Array[float] = [0.1, 0.5, 0.8, 0.2, 0.3, 0.1, 0.3, 0.5, 0.5, 0.6, 0.2, 0.0, 0.5, 0.4]

var creature_name: String
var genome: Genome
var sex: int
var biochem: Biochemistry
var brain: Brain

var x: float
var facing := 1.0
var age := 0.0
var stage: int = Lifecycle.Stage.BABY
var alive := true
var death_cause := ""
var is_moving := false
var held: WorldObject = null
var target: WorldObject = null
## Instant où l'action en cours a produit son effet (pour l'animation).
var acted := false
var meals := 0
var naps := 0
## Repas par type d'objet (statistiques et tests).
var eaten := {}
var last_event := ""

# Apparence (gène Apparence « corps »)
var hue := 0.5
var _size_gene := 0.5
var _speed := 100.0

var _chem := {}          # nom -> numéro des substances utilisées par le corps
var _drive_loci := PackedInt32Array()
var _l_meta: int
var _l_act: int
var _l_dort: int
var _l_ennui: int
var _l_speed: int

var _action_time := 0.0
var _done := false
var _goal_x := 0.0
var _prev_drives := PackedFloat32Array()
var _instinct_timer := 0.0


func _init(p_name: String, p_genome: Genome, p_x: float, p_sex: int) -> void:
	creature_name = p_name
	genome = p_genome
	sex = p_sex
	x = p_x
	_goal_x = p_x
	biochem = Biochemistry.new()
	for n in ["Faim", "Soif", "Fatigue", "Ennui", "Douleur", "Eau", "Glucose", "Toxines", "Récompense", "Punition"]:
		_chem[n] = Chemicals.id_of(n)
	var l := biochem.loci
	_l_meta = l.id_of("corps.metabolisme")
	_l_act = l.id_of("corps.activite")
	_l_dort = l.id_of("corps.dort")
	_l_ennui = l.id_of("corps.ennui")
	_l_speed = l.id_of("corps.vitesse_bonus")
	for d in Brain.DRIVE_NAMES:
		_drive_loci.append(l.id_of("pulsion." + d))
	_prev_drives.resize(Brain.DRIVE_COUNT)
	_express(true)
	brain = Brain.new(genome.expressed(stage, sex))


## Exprime les gènes du stade actuel (naissance, puis à chaque changement de stade).
func _express(first_time: bool) -> void:
	biochem.configure(genome.expressed(stage, sex), first_time)
	var look := genome.find(Gene.Type.APPEARANCE, "part", "corps")
	if look:
		hue = float(look.params.get("hue", 0.5))
		_size_gene = float(look.params.get("size", 0.5))
		_speed = lerpf(60.0, 150.0, float(look.params.get("speed", 0.5)))


func get_verb() -> int:
	return brain.verb


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
	var t := Brain.VERB_LABELS[brain.verb]
	if target != null and brain.verb in Brain.OBJECT_VERBS:
		t += " : " + ObjectCatalog.label_of(target.type_name)
	return t


func tick(dt: float, world: WorldSim, rng: RandomNumberGenerator) -> void:
	if not alive:
		return
	age += dt
	var st := Lifecycle.stage_at(age)
	if st != stage:
		stage = st
		_express(false)
		last_event = "%s est maintenant %s." % [creature_name, Lifecycle.STAGE_LABELS[stage].to_lower()]

	_perceive(world)
	_action_time -= dt
	is_moving = false
	acted = false
	if not _done:
		_execute(dt, world, rng)
	if held != null:
		held.x = x + facing * 22.0 * body_size()
		held.h = 30.0 * body_size()

	var l := biochem.loci.values
	l[_l_meta] = 1.0
	l[_l_act] = ACTIVITY[brain.verb]
	l[_l_dort] = 1.0 if brain.verb == Verb.DORMIR else 0.0
	l[_l_ennui] = 0.0 if brain.verb == Verb.EXPLORER else 1.0
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


## Remplit les lobes d'entrée : pulsions, vision, situation.
func _perceive(world: WorldSim) -> void:
	for d in Brain.DRIVE_COUNT:
		brain.drives[d] = clampf(biochem.loci.values[_drive_loci[d]], 0.0, 1.0)
	brain.vision.fill(0.0)
	for o in world.objects:
		var dist := absf(o.x - x) if o.holder != self else 0.0
		if dist < VISION_RANGE and (o.holder == null or o.holder == self) and o.category >= 0:
			brain.vision[o.category] = maxf(brain.vision[o.category], 1.0 - dist / VISION_RANGE)
	brain.situation[0] = 1.0 if held != null else 0.0
	brain.situation[1] = 1.0 if target != null and absf(target.x - x) < REACH * 2.0 else 0.0
	brain.situation[2] = clampf(level("Récompense"), 0.0, 1.0)
	brain.situation[3] = 1.0 if world.creatures.size() <= 1 else 0.0


func _decide(world: WorldSim, rng: RandomNumberGenerator) -> void:
	var allowed: Array[bool] = []
	allowed.resize(Brain.VERB_COUNT)
	allowed.fill(true)
	allowed[Verb.LACHER] = held != null
	allowed[Verb.DORMIR] = level("Fatigue") >= MIN_FATIGUE_TO_SLEEP
	allowed[Verb.ACCOUPLER] = false    # phase 3
	var v := brain.decide(rng, allowed)
	target = _nearest(world, brain.attention) if brain.attention >= 0 else null
	if v in Brain.OBJECT_VERBS and target == null:
		brain.verb = Verb.RIEN
	_done = false
	match brain.verb:
		Verb.RIEN:
			_action_time = rng.randf_range(2.0, 4.0)
		Verb.EXPLORER:
			_action_time = rng.randf_range(4.0, 8.0)
			_goal_x = _random_goal(world, rng, 500.0)
		Verb.DORMIR:
			_action_time = 400.0
		Verb.FUIR:
			_action_time = 6.0
			_goal_x = clampf(x + signf(x - target.x + 0.01) * 300.0, 60.0, world.width - 60.0)
		_:
			_action_time = 20.0


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
				_goal_x = _random_goal(world, rng, 500.0)
		Verb.DORMIR:
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
			if target == null or not (target in world.objects):
				_action_time = 0.0       # l'objet a disparu : on change d'idée
				return
			if target != held and absf(target.x - x) > REACH:
				_move_towards(target.x, dt)      # d'abord s'approcher de l'objet
				return
			if v != Verb.APPROCHER:
				_act_on(target, v, world)
			_finish()


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
	for chem_name in r.get("chems", {}):
		biochem.add(Chemicals.id_of(chem_name), float(r.chems[chem_name]))
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


func _finish() -> void:
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
	biochem.add(_chem["Récompense"], 1.0)
	biochem.add(_chem["Ennui"], -0.1)
	last_event = "%s a été caressée pendant qu'elle : %s." % [creature_name, action_text().to_lower()]


## Le joueur gronde la créature : punit ce qu'elle vient de faire et l'interrompt.
func scold() -> void:
	if not alive:
		return
	biochem.add(_chem["Punition"], 1.0)
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


func format_age() -> String:
	var m := int(age / 60.0)
	return "%d h %02d" % [m / 60, m % 60]


## Avance vers tx ; renvoie true une fois arrivée.
func _move_towards(tx: float, dt: float) -> bool:
	var dx := tx - x
	if absf(dx) < 4.0:
		return true
	facing = signf(dx)
	var speed := _speed * (1.0 + 0.5 * minf(biochem.loci.values[_l_speed], 1.0)) * Lifecycle.STAGE_SIZE[stage]
	x = move_toward(x, tx, speed * dt)
	is_moving = true
	return false


func _random_goal(world: WorldSim, rng: RandomNumberGenerator, radius: float) -> float:
	return clampf(x + rng.randf_range(-radius, radius), 60.0, world.width - 60.0)
