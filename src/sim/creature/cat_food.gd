class_name CatFood
extends RefCounted
## Alimentation : goûts, chasse, réflexe de survie, recherche de nourriture.
## (fonctions statiques sur un chat « me », appelées par CreatureSim)

const Verb = Brain.Verb


## Réflexe de survie : affamée devant de la nourriture, ou assoiffée devant
## de l'eau, elle mange ou boit, quoi que son cerveau ait appris d'autre.
static func survival_reflex(me: CreatureSim, world: WorldSim) -> void:
	var cats := ObjectCatalog.categories
	# épuisée (et ni affamée ni assoiffée) : elle s'endort où elle est
	if me.level("Fatigue") > 0.85 and me.level("Faim") < 0.6 and me.level("Soif") < 0.5 and me.brain.verb != Verb.DORMIR:
		me.brain.force(-1, Verb.DORMIR)
		me.target = null
		return
	var want := ""
	if me.level("Soif") > 0.6 and me.level("Soif") >= me.level("Faim"):
		want = "soif"
	elif me.level("Faim") > 0.7:
		want = "faim"
	elif me.level("Soif") > 0.6:
		want = "soif"
	if want == "":
		return
	var best: WorldObject = null
	for o in world.objects:
		if o.holder != null or absf(o.x - me.x) > CreatureSim.VISION_RANGE * 0.7:
			continue
		var ok := false
		if want == "faim":
			ok = o.type_name in ["croquettes", "patee"] or o.dead
		else:
			ok = o.category == cats.find("eau")
		if ok and (best == null or absf(o.x - me.x) < absf(best.x - me.x)):
			best = o
	if best == null:
		# rien en vue : elle part chercher (vers le distributeur ou l'eau qu'elle connaît)
		if me.brain.verb != Verb.EXPLORER and me.brain.verb != Verb.DORMIR:
			me.brain.force(-1, Verb.EXPLORER)
			me.target = null
			me._goal_x = me._explore_goal(world, world.rng)
		return
	me.brain.force(best.category, Verb.MANGER)     # le cerveau en tirera la leçon
	me.target = best


static func food_near(me: CreatureSim, world: WorldSim, around: float) -> WorldObject:
	var best: WorldObject = null
	var best_d := CreatureSim.VISION_RANGE * 2.0
	for o in world.objects:
		if o.holder == null and (o.type_name in ["croquettes", "patee"] or o.dead) and absf(o.x - around) < best_d:
			best_d = absf(o.x - around)
			best = o
	return best


## Tente d'attraper une proie vivante : réussite selon l'instinct de chasse
## (un oiseau est plus dur qu'une souris). Attraper est un plaisir en soi.
static func hunt(me: CreatureSim, o: WorldObject, v: int, world: WorldSim) -> void:
	var info: Dictionary = ObjectCatalog.types[o.type_name].prey
	var p := (0.15 + 0.6 * me.hunting) * float(info.get("catch", 1.0))
	if v == Verb.MANGER:
		p *= 0.5                     # se jeter dessus la gueule ouverte : moins efficace
	if v == Verb.FRAPPER:
		p *= 1.3                     # le coup de patte
	if world.rng.randf() < p:
		o.dead = true
		o.vx = 0.0
		me.catches += 1
		me.biochem.add(me._chem["Récompense"], 0.3 + 0.6 * me.hunting)
		me.biochem.add(me._chem["Ennui"], -0.3)
		me.last_event = "%s a attrapé %s !" % [me.creature_name, "une souris" if o.type_name == "souris" else "un oiseau"]
		world.last_event = me.last_event
	else:
		o.flee = 3.0
		me.biochem.add(me._chem["Ennui"], -0.05 * me.hunting)


## Le goût : plus un aliment est aimé, plus il fait plaisir (récompense en
## plus de la faim calmée). Le cerveau apprend ainsi ses préférences ; un
## aliment peu aimé reste mangé quand on a faim (pas de punition : sinon un
## chat pourrait se laisser mourir devant sa gamelle).
static func taste(me: CreatureSim, food: String, hunger: float = 1.0) -> void:
	# le plaisir dépend de l'appétit : manger sans faim n'apporte presque rien
	# (sinon le cerveau apprend à manger sans arrêt, par gourmandise)
	# Le plaisir renforce « faim -> manger cet aliment » (et lui seul : pas de
	# grignotage par ennui). Moins de plaisir sans appétit.
	if me.taste.has(food):
		var r := float(me.taste[food]) * 0.5 * clampf(hunger * 1.5, 0.25, 1.0)
		me.brain.reinforce_drive(Brain.DRIVE_NAMES.find("Faim"), r)
		me._last_pleasure = r


## L'aliment préféré parmi ceux qu'elle a déjà goûtés ("" si aucun).
static func favorite_food(me: CreatureSim) -> String:
	var best := ""
	var types := {"patee": ["patee"], "croquettes": ["croquettes"], "proie": ["souris", "oiseau"]}
	for f in me.taste:
		var tried := 0
		for t in types[f]:
			tried += me.eaten.get(t, 0)
		if tried > 0 and (best == "" or me.taste[f] > me.taste[best]):
			best = f
	return best


static func sees_food(me: CreatureSim) -> bool:
	for n in ["pâtée", "croquettes"]:
		if me.brain.vision[ObjectCatalog.categories.find(n)] > 0.0:
			return true
	return false
