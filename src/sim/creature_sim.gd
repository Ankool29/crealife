class_name CreatureSim
extends RefCounted
## Une créature : génome, biochimie, cerveau et corps. Aucun affichage ici.

const EAT_DISTANCE := 24.0
const MIN_HUNGER_TO_EAT := 0.15
const MIN_FATIGUE_TO_SLEEP := 0.35
const Action = Brain.Action

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
var meals := 0
var naps := 0
## Dernier message à afficher au joueur.
var last_event := ""

# Apparence (gène Apparence « corps »)
var hue := 0.5
var _size_gene := 0.5
var _speed := 100.0

# Numéros des substances et loci utilisés directement par le corps
var _faim: int
var _soif: int
var _fatigue: int
var _ennui: int
var _glucides_e: int
var _proteines_e: int
var _eau: int
var _recompense: int
var _punition: int
var _glucose: int
var _toxines: int
var _l_meta: int
var _l_act: int
var _l_dort: int
var _l_ennui: int
var _l_speed: int

var _action_time := 0.0
var _target_x := 0.0
var _drives_at_choice := 0.0


func _init(p_name: String, p_genome: Genome, p_x: float, p_sex: int) -> void:
	creature_name = p_name
	genome = p_genome
	sex = p_sex
	x = p_x
	_target_x = p_x
	biochem = Biochemistry.new()
	_faim = Chemicals.id_of("Faim")
	_soif = Chemicals.id_of("Soif")
	_fatigue = Chemicals.id_of("Fatigue")
	_ennui = Chemicals.id_of("Ennui")
	_glucides_e = Chemicals.id_of("Glucides (estomac)")
	_proteines_e = Chemicals.id_of("Protéines (estomac)")
	_eau = Chemicals.id_of("Eau")
	_recompense = Chemicals.id_of("Récompense")
	_punition = Chemicals.id_of("Punition")
	_glucose = Chemicals.id_of("Glucose")
	_toxines = Chemicals.id_of("Toxines")
	var l := biochem.loci
	_l_meta = l.id_of("corps.metabolisme")
	_l_act = l.id_of("corps.activite")
	_l_dort = l.id_of("corps.dort")
	_l_ennui = l.id_of("corps.ennui")
	_l_speed = l.id_of("corps.vitesse_bonus")
	_express(true)
	var lobe := genome.find(Gene.Type.LOBE, "lobe", "decision")
	var noise := float(lobe.params.get("noise", 0.5)) if lobe else 0.5
	var learning := float(lobe.params.get("learning_rate", 0.5)) if lobe else 0.5
	brain = Brain.new(noise, learning)


## Exprime les gènes du stade actuel (naissance, puis à chaque changement de stade).
func _express(first_time: bool) -> void:
	biochem.configure(genome.expressed(stage, sex), first_time)
	var look := genome.find(Gene.Type.APPEARANCE, "part", "corps")
	if look:
		hue = float(look.params.get("hue", 0.5))
		_size_gene = float(look.params.get("size", 0.5))
		_speed = lerpf(60.0, 150.0, float(look.params.get("speed", 0.5)))


func get_action() -> int:
	return brain.current_action


## Taille affichée : gène de taille × stade de vie.
func body_size() -> float:
	return lerpf(0.8, 1.25, _size_gene) * Lifecycle.STAGE_SIZE[stage]


func drives() -> PackedFloat32Array:
	var c := biochem.conc
	return PackedFloat32Array([maxf(c[_faim], c[_soif]), c[_fatigue], c[_ennui]])


func heart_health() -> float:
	var h := biochem.organ("Coeur")
	return h.health if h else 1.0


func reward_level() -> float:
	return biochem.conc[_recompense]


func punishment_level() -> float:
	return biochem.conc[_punition]


func tick(dt: float, world: WorldSim, rng: RandomNumberGenerator) -> void:
	if not alive:
		return
	age += dt
	var st := Lifecycle.stage_at(age)
	if st != stage:
		stage = st
		_express(false)
		last_event = "%s est maintenant %s." % [creature_name, Lifecycle.STAGE_LABELS[stage].to_lower()]

	_action_time -= dt
	is_moving = false
	var activity := 0.2
	var asleep := false
	var playing := false

	match brain.current_action:
		Action.IDLE:
			activity = 0.1
		Action.WANDER:
			activity = 0.5
			playing = true
			biochem.add(_ennui, -0.02 * dt)
			if _move_towards(_target_x, dt):
				_target_x = _random_target(world, rng, 500.0)
		Action.EAT:
			activity = 0.5
			var food := world.nearest_food(x)
			if food.is_empty():
				_action_time = 0.0
			elif _move_towards(food.x, dt) or absf(food.x - x) < EAT_DISTANCE:
				world.remove_food(food.id)
				_eat_fruit()
				_action_time = 0.0
		Action.SLEEP:
			activity = 0.0
			asleep = true
			if biochem.conc[_fatigue] <= 0.03:
				naps += 1
				_action_time = 0.0
		Action.PLAY:
			activity = 0.8
			playing = true
			biochem.add(_ennui, -0.05 * dt)
			if _move_towards(_target_x, dt * 1.3):
				_target_x = _random_target(world, rng, 150.0)

	var l := biochem.loci.values
	l[_l_meta] = 1.0
	l[_l_act] = activity
	l[_l_dort] = 1.0 if asleep else 0.0
	l[_l_ennui] = 0.0 if playing else 1.0
	biochem.step(dt, age)

	if not biochem.organ("Coeur").is_alive():
		_die()
		return
	if _action_time <= 0.0:
		_decide(world, rng)


## Effet d'un fruit (sera porté par l'objet lui-même en phase 2).
func _eat_fruit() -> void:
	biochem.add(_glucides_e, 0.3)
	biochem.add(_proteines_e, 0.05)
	biochem.add(_eau, 0.25)
	biochem.add(_faim, -0.3)
	biochem.add(_soif, -0.3)
	meals += 1


## Le joueur caresse la créature : récompense l'action en cours.
func caress() -> void:
	if not alive:
		return
	brain.reinforce(1.0)
	biochem.conc[_recompense] = 1.0
	biochem.add(_ennui, -0.1)
	last_event = "%s a été caressée pendant qu'elle voulait %s." % [creature_name, Brain.ACTION_NOUNS[get_action()]]


## Le joueur gronde la créature : punit l'action en cours et l'interrompt.
func scold() -> void:
	if not alive:
		return
	brain.reinforce(-1.0)
	biochem.conc[_punition] = 1.0
	last_event = "%s a été grondée pendant qu'elle voulait %s." % [creature_name, Brain.ACTION_NOUNS[get_action()]]
	_action_time = 0.0


func _drive_total() -> float:
	var s := 0.0
	for v in drives():
		s += v
	return s


func _decide(world: WorldSim, rng: RandomNumberGenerator) -> void:
	# Récompense naturelle : avoir fait baisser ses besoins, c'est agréable.
	var relief := _drives_at_choice - _drive_total()
	if absf(relief) > 0.02:
		brain.reinforce(clampf(relief, -0.5, 0.5), false)

	var d := drives()
	var allowed: Array[bool] = [true, true, true, true, true]
	allowed[Action.EAT] = world.has_food() and d[0] >= MIN_HUNGER_TO_EAT
	allowed[Action.SLEEP] = d[1] >= MIN_FATIGUE_TO_SLEEP
	var a := brain.decide(d, rng, allowed)
	_drives_at_choice = _drive_total()
	match a:
		Action.IDLE:
			_action_time = rng.randf_range(2.0, 4.0)
		Action.WANDER:
			_action_time = rng.randf_range(4.0, 8.0)
			_target_x = _random_target(world, rng, 500.0)
		Action.EAT:
			_action_time = 25.0
		Action.SLEEP:
			_action_time = 400.0
		Action.PLAY:
			_action_time = rng.randf_range(4.0, 6.0)
			_target_x = _random_target(world, rng, 150.0)


func _die() -> void:
	alive = false
	is_moving = false
	var c := biochem.conc
	if age > biochem.organ("Coeur").longevity_s:
		death_cause = "de vieillesse"
	elif c[_glucose] < 0.05:
		death_cause = "de faim"
	elif c[_eau] < 0.05:
		death_cause = "de soif"
	elif c[_toxines] > 0.5:
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


func _random_target(world: WorldSim, rng: RandomNumberGenerator, radius: float) -> float:
	return clampf(x + rng.randf_range(-radius, radius), 60.0, world.width - 60.0)
