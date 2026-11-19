class_name CatGarden
extends RefCounted
## Le chat et le jardin : herbe à chat, plante toxique, jeu avec les papillons.
## (fonctions statiques sur un chat « me », appelées par CreatureSim)
##
## - Herbe à chat : un chat adulte sensible qui la renifle ou la mâche est
##   grisé un moment (plus d'ennui, envie de jouer, petite récompense), puis
##   s'en lasse. Sensibilité héréditaire (gène « gout », allèles herbe1 et
##   herbe2, sensible dominant) : environ un chat sur trois est insensible.
## - Lys : le manger rend malade (toxines, douleur). La punition porte sur ce
##   qui l'a poussé à le manger (pulsion + plante -> manger) et il en garde un
##   dégoût : il ne mange plus de lys tant que le souvenir dure.
## - Papillons : les espiègles et les chasseurs les poursuivent pour jouer ;
##   touchés, ils s'envolent (ils ne se mangent pas).

const Verb = Brain.Verb
const CATNIP_RESISTANT_ALLELE := 0.58   # fréquence de l'allèle insensible
const CATNIP_TIME := 90.0               # grisée pendant 1 min 30
const CATNIP_REST := 1500.0             # puis 25 min sans effet
const AVERSION_FADE := 1.0 / 14400.0    # un dégoût s'efface en ~4 h
const AVERSION_MIN := 0.3               # au-dessous, elle a oublié
const TOXIN_PUNISH := 1.5


## Sensible à l'herbe à chat : au moins un allèle sensible (dominant).
static func sensitive(p: Dictionary) -> bool:
	return float(p.get("herbe1", 1.0)) >= 0.5 or float(p.get("herbe2", 0.0)) >= 0.5


## Génotype lisible : S = sensible (dominant), i = insensible.
static func genotype_text(p: Dictionary) -> String:
	var a := "S" if float(p.get("herbe1", 1.0)) >= 0.5 else "i"
	var b := "S" if float(p.get("herbe2", 0.0)) >= 0.5 else "i"
	if a == "i" and b == "S":
		return "S/i"
	return "%s/%s" % [a, b]


static func tick(me: CreatureSim, dt: float) -> void:
	if me.catnip_left > 0.0:
		me.catnip_left = maxf(0.0, me.catnip_left - dt)
		me.biochem.add(me._chem["Ennui"], -0.004 * dt)       # grisée : l'ennui s'envole
	if me.catnip_rest > 0.0:
		me.catnip_rest = maxf(0.0, me.catnip_rest - dt)
	if not me.aversion.is_empty():
		for k in me.aversion.keys():
			me.aversion[k] = float(me.aversion[k]) - AVERSION_FADE * dt
			if me.aversion[k] <= 0.0:
				me.aversion.erase(k)


static func averse(me: CreatureSim, type_name: String) -> bool:
	return float(me.aversion.get(type_name, 0.0)) >= AVERSION_MIN


## Peut-elle viser cet objet pour le manger ? (pas un papillon, pas une plante
## qui l'a rendue malade)
static func edible_for(me: CreatureSim, o: WorldObject) -> bool:
	if ObjectCatalog.types[o.type_name].get("prey", {}).get("butterfly", false):
		return false
	return not averse(me, o.type_name)


## Effet d'une plante adulte (après les substances du catalogue).
static func plant_effect(me: CreatureSim, o: WorldObject, v: int, world: WorldSim) -> void:
	var info: Dictionary = ObjectCatalog.types[o.type_name].plant
	if v == Verb.MANGER:
		me.eaten[o.type_name] = me.eaten.get(o.type_name, 0) + 1
	if info.get("catnip", false) and v in [Verb.EXAMINER, Verb.MANGER]:
		catnip(me, world)
	if float(info.get("toxic", 0.0)) > 0.0 and v == Verb.MANGER:
		poison(me, world, o.type_name, float(info.toxic))
	if v == Verb.MANGER:
		Garden.bite(world, o)


static func catnip(me: CreatureSim, world: WorldSim) -> void:
	if me.stage < Lifecycle.Stage.ADULT:
		return                                   # les chatons n'y réagissent pas
	if not me.catnip_sensitive:
		me.last_event = "%s renifle l'herbe à chat : aucun effet sur elle." % me.creature_name
		return
	if me.catnip_left > 0.0 or me.catnip_rest > 0.0:
		return                                   # déjà grisée, ou lassée
	me.catnip_left = CATNIP_TIME
	me.catnip_rest = CATNIP_TIME + CATNIP_REST
	me.biochem.add(me._chem["Ennui"], -0.4)
	me.brain.reinforce_drive(Brain.DRIVE_NAMES.find("Ennui"), 0.4)    # petite récompense, liée à l'ennui
	me.language.speech = "mrraou !"
	me.language.speech_left = Language.SAY_TIME
	me.last_event = "%s se roule dans l'herbe à chat : la voilà toute joyeuse !" % me.creature_name
	world.last_event = me.last_event


## Plante toxique : malade (toxines, douleur), sans en mourir d'un coup.
static func poison(me: CreatureSim, world: WorldSim, type_name: String, dose: float) -> void:
	me.biochem.add(me._chem["Toxines"], dose)
	me.biochem.add(me._chem["Douleur"], 0.35)
	# la punition vise ce qui l'a poussée à manger cette plante
	me.brain.reinforce_drives(-TOXIN_PUNISH)
	me.aversion[type_name] = 1.0
	me.language.speech = "bleuh"
	me.language.speech_left = Language.SAY_TIME
	me.last_event = "%s a mangé du %s : elle est malade (elle s'en souviendra)." % [me.creature_name,
		ObjectCatalog.label_of(type_name)]
	world.last_event = me.last_event


## Envie de jouer : un papillon en vue tente les espiègles chasseuses ; une
## chatte grisée par l'herbe à chat joue avec ce qu'elle trouve. Ne passe pas
## avant la faim, la soif, la fatigue ou la peur.
static func play_reflex(me: CreatureSim, world: WorldSim, rng: RandomNumberGenerator) -> void:
	if me.stage == Lifecycle.Stage.BABY or not me._care.is_empty() \
			or me.brain.verb in [Verb.DORMIR, Verb.MANGER, Verb.ACCOUPLER, Verb.FUIR]:
		return
	if me.level("Faim") > 0.5 or me.level("Soif") > 0.5 or me.level("Fatigue") > 0.7 or me.level("Peur") > 0.3:
		return
	var high := me.catnip_left > 0.0
	var p := 0.45 * me.playfulness * me.hunting + (0.5 if high else 0.0)
	if rng.randf() >= p:
		return
	var best: WorldObject = null
	for o in world.objects:
		if o.type_name == "papillon" and absf(o.x - me.x) < 500.0 \
				and (best == null or absf(o.x - me.x) < absf(best.x - me.x)):
			best = o
	if best != null:
		me.brain.force(best.category, Verb.FRAPPER)
		me.target = best
		return
	if high:
		var toy := me._nearest(world, ObjectCatalog.categories.find("jouet"))
		if toy != null:
			me.brain.force(toy.category, Verb.POUSSER)
			me.target = toy


## Coup de patte vers un papillon : touché, il s'envole ; c'est l'ennui qui
## baisse (et le jeu qui s'apprend).
static func chase_butterfly(me: CreatureSim, o: WorldObject, v: int, world: WorldSim) -> void:
	var info: Dictionary = ObjectCatalog.types[o.type_name].prey
	var p := (0.15 + 0.6 * me.hunting) * float(info.get("catch", 0.4)) * (1.3 if v == Verb.FRAPPER else 1.0)
	if world.rng.randf() < p:
		o.flee = 5.0
		o.h = minf(o.h + 60.0, 260.0)
		me.butterflies += 1
		me.biochem.add(me._chem["Ennui"], -0.3 * lerpf(0.6, 1.4, me.playfulness))
		me.brain.reinforce_drive(Brain.DRIVE_NAMES.find("Ennui"), 0.2)
		me.last_event = "%s touche un papillon, qui s'envole !" % me.creature_name
	else:
		o.flee = 3.0
		me.biochem.add(me._chem["Ennui"], -0.05)
