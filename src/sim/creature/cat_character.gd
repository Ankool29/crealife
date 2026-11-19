class_name CatCharacter
extends RefCounted
## Caractère : peur et fuite, querelles, amitiés et rivalités, portrait en mots.
## (fonctions statiques sur un chat « me », appelées par CreatureSim)

const Verb = Brain.Verb


## Quelque chose lui fait peur (un coup, un chat agressif...) : plus ou moins
## selon son audace.
static func frighten(me: CreatureSim, amount: float, source: CreatureSim = null) -> void:
	me.biochem.add(me._chem["Peur"], amount * lerpf(1.6, 0.3, me.boldness))
	if source != null:
		me._threat_uid = source.uid


## Affinité avec un autre chat : monte quand on se parle, se blottit, s'accouple ;
## baisse quand on se bat.
static func bond(me: CreatureSim, other: CreatureSim, amount: float) -> void:
	if other == null or other == me:
		return
	me.affinity[other.uid] = clampf(float(me.affinity.get(other.uid, 0.0)) + amount, -1.0, 1.0)


static func affinity_with(me: CreatureSim, other: CreatureSim) -> float:
	return float(me.affinity.get(other.uid, 0.0))


## Peur : un chat peureux s'enfuit loin de ce qui l'effraie (un rival
## agressif qui approche, le chat qui vient de le frapper). Les bagarreurs,
## eux, cherchent parfois querelle à un adulte de même sexe tout proche.
static func fear_reflex(me: CreatureSim, dt: float, world: WorldSim) -> void:
	if not me.alive or me.is_asleep() or me._care.size() > 0:
		return
	for c in world.creatures:
		if c == me or not c.alive or absf(c.x - me.x) > 260.0:
			continue
		if c.aggressive > 0.7 and me.affinity_with(c) < -0.3 and c.stage >= Lifecycle.Stage.ADULT:
			me.frighten(0.04 * dt, c)              # un rival menaçant tout près
	if me.level("Peur") > 0.55 and me.brain.verb != Verb.FUIR:
		var threat := world.find_uid(me._threat_uid)
		if threat != null and absf(threat.x - me.x) < 400.0:
			me.brain.force(ObjectCatalog.categories.find("créature"), Verb.FUIR)
			me.target = threat
			me._done = false
			me._action_time = 6.0
			me._goal_x = clampf(me.x + signf(me.x - threat.x + 0.01) * 350.0, 60.0, world.width - 60.0)
			me.last_event = "%s a peur de %s et s'enfuit." % [me.creature_name, threat.creature_name]
			me.language.speech = "!"
			me.language.speech_left = Language.SAY_TIME
	# querelle : rare, et seulement chez les bagarreurs
	if me.aggressive > 0.6 and me.stage == Lifecycle.Stage.ADULT and me.brain.verb in [Verb.RIEN, Verb.EXPLORER] \
			and world.rng.randf() < (me.aggressive - 0.6) * 0.02 * dt:
		for c in world.creatures:
			if c != me and c.alive and c.stage == Lifecycle.Stage.ADULT and c.sex == me.sex \
					and absf(c.x - me.x) < 200.0 and me.affinity_with(c) < 0.3:
				me.brain.force(ObjectCatalog.categories.find("créature"), Verb.FRAPPER)
				me.target = c
				me._done = false
				me._action_time = 8.0
				me.last_event = "%s cherche querelle à %s." % [me.creature_name, c.creature_name]
				me.language.speech = "fff !"          # il crache
				me.language.speech_left = Language.SAY_TIME
				break


## Quelques mots pour décrire son caractère (panneau, adoptions).
static func personality(me: CreatureSim) -> Array[String]:
	var f := me.sex == Gene.Sex.FEMALE
	var w: Array[String] = []
	if me.sociable > 0.65:
		w.append("câline" if f else "câlin")
	elif me.sociable < 0.35:
		w.append("indépendante" if f else "indépendant")
	if me.boldness < 0.35:
		w.append("peureuse" if f else "peureux")
	elif me.boldness > 0.7:
		w.append("audacieuse" if f else "audacieux")
	if me.aggressive > 0.6:
		w.append("bagarreuse" if f else "bagarreur")
	if me.energy > 0.7:
		w.append("énergique")
	elif me.energy < 0.3:
		w.append("dormeuse" if f else "dormeur")
	if me.playfulness > 0.7:
		w.append("joueuse" if f else "joueur")
	if me.curiosity > 0.7:
		w.append("curieuse" if f else "curieux")
	return w
