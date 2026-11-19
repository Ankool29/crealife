class_name CatFamily
extends RefCounted
## Famille : désir et accouplement, gestation et mise bas, allaitement,
## soins des parents aux petits.
## (fonctions statiques sur un chat « me », appelées par CreatureSim)

const Verb = Brain.Verb


## Accouplement : adultes de sexe opposé, partenaire consentant (désir
## suffisant), femelle pas déjà en gestation, population pas au maximum.
static func try_mating(me: CreatureSim, other: CreatureSim, world: WorldSim) -> void:
	var female: CreatureSim = me if me.sex == Gene.Sex.FEMALE else other
	if other.sex == me.sex or other.stage != Lifecycle.Stage.ADULT or me.stage != Lifecycle.Stage.ADULT \
			or other.level("Désir") < CreatureSim.MATING_DESIRE or other._mate_rest > 0.0 \
			or female.pregnant_time >= 0.0 or world.population_full():
		me._refused = CreatureSim.REFUSED_PAUSE        # refus : elle n'insiste pas
		return
	var male: CreatureSim = other if female == me else me
	for c in [me, other]:
		c.biochem.add(c._chem["Désir"], -0.8)
		c.bond(other if c == me else me, 0.1)
		c.biochem.conc[c._chem["Hormone sexuelle"]] = 0.0
		c._mate_rest = CreatureSim.MATING_REST
	female.pregnant_time = 0.0
	female.litter_size = world.litter_size_for(female)
	female._father_genome = male.genome
	female._father_name = male.creature_name
	female.last_event = "%s et %s se sont accouplés  : %s attend des petits." % [me.creature_name, other.creature_name, female.creature_name]
	world.last_event = female.last_event


## Le désir est freiné : repos après un accouplement, pendant la gestation,
## quand elle a un bébé, et quand le monde est plein (surpopulation).
static func regulate_desire(me: CreatureSim, dt: float, world: WorldSim) -> void:
	me._mate_rest = maxf(0.0, me._mate_rest - dt)
	me._screen_time = maxf(0.0, me._screen_time - dt)
	me._refused = maxf(0.0, me._refused - dt)
	if me.stage < Lifecycle.Stage.ADULT:
		return
	var calm := me._mate_rest > 0.0 or me.pregnant_time >= 0.0 or world.population_full()
	if not calm:
		for c in world.creatures:
			if c.alive and c.stage == Lifecycle.Stage.BABY and me.is_parent_of(c):
				calm = true
				break
	if calm:
		var h: int = me._chem["Hormone sexuelle"]
		me.biochem.conc[h] = minf(me.biochem.conc[h], 0.2)     # sous le seuil qui produit le désir


## Un parent qui n'a pas lui-même de besoin pressant s'occupe parfois d'un
## petit (bébé ou enfant) : il lui apporte à manger s'il a faim ou soif, ou
## va lui parler s'il s'ennuie ou se sent seul (il lui apprend ses mots).
static func start_care(me: CreatureSim, world: WorldSim, rng: RandomNumberGenerator) -> bool:
	if me.care_instinct <= 0.05 or me.stage < Lifecycle.Stage.ADULT or me.held != null and me.held.category != me._food_cat():
		return false
	if me.level("Faim") > 0.6 or me.level("Soif") > 0.6 or me.level("Fatigue") > 0.7:
		return false
	var best: CreatureSim = null
	var best_need := 0.0
	var kind := ""
	for c in world.creatures:
		if not c.alive or c.stage > Lifecycle.Stage.CHILD or not me.is_parent_of(c) or c.is_asleep():
			continue
		if absf(c.x - me.x) > CreatureSim.VISION_RANGE * 1.5:
			continue
		var hunger := maxf(c.level("Faim"), c.level("Soif"))
		var social := maxf(c.level("Solitude"), c.level("Ennui"))
		if hunger > 0.3 and c.stage == Lifecycle.Stage.BABY and c.mother == me.creature_name and hunger + 0.3 > best_need:
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
	if best == null or rng.randf() > me.care_instinct * (0.4 + best_need) and kind != "allaiter":
		return false
	if kind == "allaiter":
		me._care = {"kind": kind, "child": best, "food": null, "time": 0.0}
		me.brain.verb = Verb.APPROCHER
		me.brain.clear_trace()
		me.target = best
		me._done = false
		me._action_time = CreatureSim.CARE_TIMEOUT
		return true
	var food: WorldObject = me.held if me.held != null else null
	if kind == "nourrir" and food == null:
		food = me._food_near(world, best.x)
		if food == null:
			return false
	me._care = {"kind": kind, "child": best, "food": food, "time": 0.0}
	me.brain.verb = Verb.PRENDRE if kind == "nourrir" and me.held == null else (Verb.APPROCHER if kind == "nourrir" else Verb.PARLER)
	me.brain.clear_trace()        # ce n'est pas une décision apprise : rien à renforcer
	me.target = food if me.held == null and food != null else best
	me._done = false
	me._action_time = CreatureSim.CARE_TIMEOUT
	return true


static func execute_care(me: CreatureSim, dt: float, world: WorldSim) -> void:
	var child: CreatureSim = me._care.child
	me._care.time += dt
	if me._care.time > CreatureSim.CARE_TIMEOUT or not child.alive or not child in world.creatures:
		me._end_care()
		return
	if me._care.kind == "allaiter":
		if not me._approach(child.x, dt, CreatureSim.NURSE_RANGE * 0.5):
			return
		me.brain.verb = Verb.RIEN           # elle se couche et le laisse téter
		if maxf(child.level("Faim"), child.level("Soif")) < 0.05 or me.level("Faim") > 0.8:
			me.last_event = "%s a allaité %s." % [me.creature_name, child.creature_name]
			me._end_care()
		return
	if me._care.kind == "nourrir":
		var food: WorldObject = me._care.food
		if me.held == null:
			if food == null or not food in world.objects or food.holder != null:
				me._end_care()
				return
			if not me._approach(food.x, dt):
				return
			me.held = food                      # il ramasse la nourriture
			food.holder = me
			food.vx = 0.0
			me.acted = true
			me.brain.verb = Verb.APPROCHER
			me.target = child
			return
		if not me._approach(child.x, dt, CreatureSim.REACH * 1.5):
			return
		me.drop_held()                          # posée devant le petit
		me.acted = true
		me.brain.verb = Verb.LACHER
		me.biochem.add(me._chem["Récompense"], 0.3)
		me.last_event = "%s apporte à manger à %s." % [me.creature_name, child.creature_name]
		me._end_care()
	else:
		if not me._approach(child.x, dt, CreatureSim.REACH * 1.5):
			return
		me.brain.verb = Verb.PARLER
		me._act_on_creature(child, Verb.PARLER, world)
		child.biochem.add(child._chem["Ennui"], -0.2)
		me.biochem.add(me._chem["Récompense"], 0.2)
		me.last_event = "%s parle à son petit %s." % [me.creature_name, child.creature_name]
		me._end_care()


static func end_care(me: CreatureSim) -> void:
	me._care = {}
	me._finish()


## Gestation : au bout du temps voulu, la chatte met bas un chaton.
static func gestation(me: CreatureSim, dt: float, world: WorldSim) -> void:
	if me.pregnant_time < 0.0:
		return
	me.pregnant_time += dt
	if me.pregnant_time >= CreatureSim.GESTATION:
		me.pregnant_time = -1.0
		var names: Array[String] = []
		var n := maxi(1, me.litter_size)
		for i in n:                      # chaque chaton a son propre mélange
			var child := Genome.cross(me.genome, me._father_genome, world.rng, 0.03)
			var at := clampf(me.x + (i - (n - 1) * 0.5) * 45.0, 60.0, world.width - 60.0)
			names.append(world.give_birth(at, child, me.creature_name, me._father_name, maxi(me.generation, 1) + 1).creature_name)
		var gen := maxi(me.generation, 1) + 1
		if n == 1:
			world.last_event = "%s a mis bas : naissance de %s (génération %d)." % [me.creature_name, names[0], gen]
		else:
			world.last_event = "%s a mis bas %d chatons : %s (génération %d)." % [me.creature_name, n, ", ".join(names), gen]
		me.last_event = world.last_event
		me.litter_size = 0
		me._father_genome = null


## Les bébés collés à leur mère tètent, éveillés ou endormis.
static func nurse(me: CreatureSim, dt: float, world: WorldSim) -> void:
	var fed := 0
	for c in world.creatures:
		if not c.alive or c.stage != Lifecycle.Stage.BABY or c.mother != me.creature_name:
			continue
		if absf(c.x - me.x) > CreatureSim.NURSE_RANGE or maxf(c.level("Faim"), c.level("Soif")) < 0.1:
			continue
		c.biochem.add(c._chem["Faim"], -CreatureSim.NURSE_RATE * dt)
		c.biochem.add(c._chem["Soif"], -CreatureSim.NURSE_RATE * dt)
		c.biochem.add(c._chem["Solitude"], -0.01 * dt)
		c.nursing = 0.5
		fed += 1
	if fed > 0:
		me.nursing = 0.5
		me.biochem.add(me._chem["Faim"], CreatureSim.NURSE_COST * fed * dt)
		me.biochem.add(me._chem["Solitude"], -0.005 * dt)
