class_name CreatureSim
extends RefCounted
## Logique d'une créature, sans aucun affichage (testable seule).

const EAT_DISTANCE := 24.0
const MIN_HUNGER_TO_EAT := 0.2
const MIN_FATIGUE_TO_SLEEP := 0.3
const Action = Brain.Action
const Drive = Biochemistry.Drive

var creature_name: String
var genome: Genome
var chem: Biochemistry
var brain: Brain

var x: float
var facing := 1.0
var age := 0.0
var speed: float
var size: float
var is_moving := false
var meals := 0
var naps := 0
## Dernier message à afficher au joueur.
var last_event := ""

var _action_time := 0.0
var _target_x := 0.0
var _drives_at_choice := 0.0


func _init(p_name: String, p_genome: Genome, p_x: float) -> void:
	creature_name = p_name
	genome = p_genome
	chem = Biochemistry.new(genome)
	brain = Brain.new(genome)
	x = p_x
	_target_x = p_x
	speed = lerpf(60.0, 150.0, genome.get_gene("speed"))
	size = lerpf(0.8, 1.25, genome.get_gene("size"))


func get_action() -> int:
	return brain.current_action


func tick(dt: float, world: WorldSim, rng: RandomNumberGenerator) -> void:
	age += dt
	_action_time -= dt
	is_moving = false
	var activity := 0.2

	match brain.current_action:
		Action.IDLE:
			activity = 0.1
		Action.WANDER:
			activity = 0.5
			chem.add(Drive.BOREDOM, -0.02 * dt)
			if _move_towards(_target_x, dt):
				_target_x = _random_target(world, rng, 500.0)
		Action.EAT:
			activity = 0.5
			var food := world.nearest_food(x)
			if food.is_empty():
				_action_time = 0.0
			elif _move_towards(food.x, dt) or absf(food.x - x) < EAT_DISTANCE:
				world.remove_food(food.id)
				chem.add(Drive.HUNGER, -0.4)
				meals += 1
				_action_time = 0.0
		Action.SLEEP:
			activity = 0.0
			chem.add(Drive.FATIGUE, -0.05 * dt)
			if chem.get_level(Drive.FATIGUE) <= 0.02:
				naps += 1
				_action_time = 0.0
		Action.PLAY:
			activity = 0.8
			chem.add(Drive.BOREDOM, -0.05 * dt)
			if _move_towards(_target_x, dt * 1.3):
				_target_x = _random_target(world, rng, 150.0)

	chem.tick(dt, activity)
	if _action_time <= 0.0:
		_decide(world, rng)


## Le joueur caresse la créature : récompense l'action en cours.
func caress() -> void:
	brain.reinforce(1.0)
	chem.reward = 1.0
	chem.add(Drive.BOREDOM, -0.1)
	last_event = "%s a été caressée pendant qu'elle voulait %s." % [creature_name, Brain.ACTION_NOUNS[get_action()]]


## Le joueur gronde la créature : punit l'action en cours et l'interrompt.
func scold() -> void:
	brain.reinforce(-1.0)
	chem.punishment = 1.0
	last_event = "%s a été grondée pendant qu'elle voulait %s." % [creature_name, Brain.ACTION_NOUNS[get_action()]]
	_action_time = 0.0


func _decide(world: WorldSim, rng: RandomNumberGenerator) -> void:
	# Récompense naturelle : avoir fait baisser ses besoins, c'est agréable.
	var relief := _drives_at_choice - chem.total()
	if absf(relief) > 0.02:
		brain.reinforce(clampf(relief, -0.5, 0.5), false)

	var allowed: Array[bool] = [true, true, true, true, true]
	allowed[Action.EAT] = world.has_food() and chem.get_level(Drive.HUNGER) >= MIN_HUNGER_TO_EAT
	allowed[Action.SLEEP] = chem.get_level(Drive.FATIGUE) >= MIN_FATIGUE_TO_SLEEP
	var a := brain.decide(chem, rng, allowed)
	_drives_at_choice = chem.total()
	match a:
		Action.IDLE:
			_action_time = rng.randf_range(2.0, 4.0)
		Action.WANDER:
			_action_time = rng.randf_range(4.0, 8.0)
			_target_x = _random_target(world, rng, 500.0)
		Action.EAT:
			_action_time = 20.0
		Action.SLEEP:
			_action_time = 40.0
		Action.PLAY:
			_action_time = rng.randf_range(4.0, 6.0)
			_target_x = _random_target(world, rng, 150.0)


## Avance vers tx ; renvoie true une fois arrivée.
func _move_towards(tx: float, dt: float) -> bool:
	var dx := tx - x
	if absf(dx) < 4.0:
		return true
	facing = signf(dx)
	x = move_toward(x, tx, speed * dt)
	is_moving = true
	return false


func _random_target(world: WorldSim, rng: RandomNumberGenerator, radius: float) -> float:
	return clampf(x + rng.randf_range(-radius, radius), 60.0, world.width - 60.0)
