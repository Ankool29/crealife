class_name WorldSim
extends RefCounted
## Le monde : un sol en vue de côté, des arbres à fruits, des buissons à baies,
## un distributeur de graines, des jouets, les créatures et leurs œufs.
## Aucune dépendance à l'affichage.

const GRAVITY := 900.0
const MAX_POPULATION := 10       # créatures vivantes + œufs (décision D4)
const HATCH_TIME := 600.0        # 10 min de jeu avant l'éclosion
const CORPSE_TIME := 180.0       # le corps reste 3 min puis disparaît
const SYLLABLES: Array[String] = ["ka", "lo", "mi", "ny", "ta", "vi", "ru", "se", "pa", "lu", "ze", "no",
	"bi", "ra", "ke", "yo", "ma", "ti", "sha", "el", "or", "un", "ix", "an"]

## Scénarios : "normal" (le jeu), "graines" (aucun fruit, des graines au sol),
## "vide" (aucune nourriture) — les deux derniers servent aux tests.
var scenario := "normal"
var width := 3000.0
var rng := RandomNumberGenerator.new()
var creatures: Array[CreatureSim] = []
var objects: Array[WorldObject] = []
var trees := PackedFloat32Array([450.0, 1350.0, 2350.0])
var bushes := PackedFloat32Array([900.0, 2000.0])
var machine_x := 1750.0
var time := 0.0
## Toutes les créatures ayant existé : arbre généalogique.
var history: Array[Dictionary] = []
## Dernier événement marquant (naissance, accouplement...), pour l'interface.
var last_event := ""

var _next_id := 1
var _next_uid := 1
var _eggs := {}                  # id d'œuf -> {genome, mother, father, generation, hatch_at}
var _fruit_timer := 3.0
var _berry_timer := 10.0
var _seed_timer := 5.0
var _used_names := {}


func _init(seed_value: int = 0, p_scenario: String = "normal", founders: int = 1) -> void:
	scenario = p_scenario
	if seed_value == 0:
		rng.randomize()
	else:
		rng.seed = seed_value
	if scenario != "normal":
		trees = PackedFloat32Array()
		bushes = PackedFloat32Array()
	else:
		add_object("distributeur", machine_x)
		add_object("balle", 1150.0)
		add_object("pierre", 600.0)
		add_object("pierre", 2600.0)
		for i in 3:
			_spawn_fruit()
		_spawn_berry()
	add_founders(founders)


## Fondateurs : souche de départ légèrement mutée, couleurs au hasard,
## sexes alternés pour qu'un couple soit possible.
func add_founders(count: int) -> void:
	var first_sex := Gene.Sex.MALE if rng.randf() < 0.5 else Gene.Sex.FEMALE
	for i in count:
		var g := Genome.starter()
		g.mutate(rng, 0.05)
		var look := g.find(Gene.Type.APPEARANCE, "part", "corps")
		if look:
			for k in ["hue", "hue2", "saturation", "brightness", "glow", "size", "speed"]:
				look.params[k] = rng.randf()
		var sex := first_sex if i % 2 == 0 else (Gene.Sex.FEMALE if first_sex == Gene.Sex.MALE else Gene.Sex.MALE)
		_add_creature(g, width * 0.5 + (i - (count - 1) * 0.5) * 200.0, sex, 1, "", "")


func _add_creature(g: Genome, at_x: float, sex: int, generation: int, mother: String, father: String) -> CreatureSim:
	var c := CreatureSim.new(new_name(), g, at_x, sex)
	c.uid = _next_uid
	_next_uid += 1
	c.generation = generation
	c.mother = mother
	c.father = father
	creatures.append(c)
	history.append({"uid": c.uid, "name": c.creature_name, "sex": sex, "generation": generation,
		"mother": mother, "father": father, "born_at": time, "alive": true, "cause": "", "age": 0.0,
		"hue": c.hue})
	return c


## Nom unique fait de deux ou trois syllabes.
func new_name() -> String:
	for attempt in 50:
		var n := ""
		for i in rng.randi_range(2, 3):
			n += SYLLABLES[rng.randi_range(0, SYLLABLES.size() - 1)]
		n = n.capitalize()
		if not _used_names.has(n):
			_used_names[n] = true
			return n
	return "Créature %d" % _next_uid


func alive_count() -> int:
	var n := 0
	for c in creatures:
		if c.alive:
			n += 1
	return n


## Vivantes + œufs + gestations en cours : on ne conçoit plus au-delà du maximum.
func population_full() -> bool:
	var pregnant := 0
	for c in creatures:
		if c.alive and c.pregnant_time >= 0.0:
			pregnant += 1
	return alive_count() + _eggs.size() + pregnant >= MAX_POPULATION


func lay_egg(at_x: float, g: Genome, mother: String, father: String, generation: int) -> void:
	var egg := add_object("oeuf", at_x, 20.0)
	_eggs[egg.id] = {"genome": g, "mother": mother, "father": father, "generation": generation,
		"hatch_at": time + HATCH_TIME}


func egg_info(o: WorldObject) -> Dictionary:
	return _eggs.get(o.id, {})


func tick(dt: float) -> void:
	time += dt
	_spawners(dt)
	for o in objects:
		_physics(o, dt)
	for c in creatures:
		var was_alive := c.alive
		c.tick(dt, self, rng)
		if was_alive and not c.alive:
			_record_death(c)
			last_event = c.last_event
	_hatch_eggs()
	_remove_corpses()


func _hatch_eggs() -> void:
	for o in objects.duplicate():
		if o.type_name != "oeuf" or not _eggs.has(o.id):
			continue
		var e: Dictionary = _eggs[o.id]
		if time < e.hatch_at:
			continue
		if o.holder != null:
			o.holder.drop_held()
		var sex := Gene.Sex.MALE if rng.randf() < 0.5 else Gene.Sex.FEMALE
		var baby := _add_creature(e.genome, o.x, sex, e.generation, e.mother, e.father)
		_eggs.erase(o.id)
		remove_object(o)
		last_event = "Naissance de %s (génération %d), enfant de %s et %s." % [baby.creature_name, baby.generation, e.mother, e.father]


func _record_death(c: CreatureSim) -> void:
	for h in history:
		if h.uid == c.uid:
			h.alive = false
			h.cause = c.death_cause
			h.age = c.age
	c.set_meta("died_at", time)


func _remove_corpses() -> void:
	for c in creatures.duplicate():
		if not c.alive and time - float(c.get_meta("died_at", time)) > CORPSE_TIME and creatures.size() > 1:
			creatures.erase(c)
			for other in creatures:
				if other.target == c:
					other.target = null


## Plus aucune créature vivante ni œuf : le joueur peut relancer une lignée.
func is_extinct() -> bool:
	return alive_count() == 0 and _eggs.is_empty()


func restart_lineage() -> void:
	creatures.clear()
	add_founders(2)
	last_event = "Deux nouvelles créatures arrivent."


func _spawners(dt: float) -> void:
	_fruit_timer -= dt
	if _fruit_timer <= 0.0:
		_fruit_timer = rng.randf_range(6.0, 12.0) / maxf(1.0, alive_count() * 0.6)
		_spawn_fruit()
	_berry_timer -= dt
	if _berry_timer <= 0.0:
		_berry_timer = rng.randf_range(15.0, 25.0)
		_spawn_berry()
	if scenario == "graines":
		_seed_timer -= dt
		if _seed_timer <= 0.0:
			_seed_timer = rng.randf_range(6.0, 12.0)
			if count_of("graine") < 10:
				add_object("graine", rng.randf_range(100.0, width - 100.0), 300.0)


func _physics(o: WorldObject, dt: float) -> void:
	if o.cooldown > 0.0:
		o.cooldown -= dt
	if o.holder != null:
		return
	if o.h > 0.0 or o.vy != 0.0:
		o.vy += GRAVITY * dt
		o.h -= o.vy * dt
		if o.h <= 0.0:
			o.h = 0.0
			o.vy = -o.vy * 0.3 if absf(o.vy) > 120.0 else 0.0
	if o.vx != 0.0:
		o.x += o.vx * dt
		o.vx = move_toward(o.vx, 0.0, 300.0 * dt)
		if o.x < 20.0 or o.x > width - 20.0:
			o.x = clampf(o.x, 20.0, width - 20.0)
			o.vx = -o.vx * 0.5


func add_object(type_name: String, at_x: float, at_h: float = 0.0) -> WorldObject:
	var o := WorldObject.new(_next_id, type_name, clampf(at_x, 20.0, width - 20.0), at_h)
	_next_id += 1
	objects.append(o)
	return o


func remove_object(o: WorldObject) -> void:
	objects.erase(o)


func count_of(type_name: String) -> int:
	var n := 0
	for o in objects:
		if o.type_name == type_name:
			n += 1
	return n


## Le joueur fait tomber un fruit du ciel.
func drop_food(at_x: float) -> void:
	add_object("fruit", at_x, 420.0)


func _spawn_fruit() -> void:
	if trees.is_empty() or count_of("fruit") >= 6 + 2 * alive_count():
		return
	var tree_x := trees[rng.randi_range(0, trees.size() - 1)]
	add_object("fruit", tree_x + rng.randf_range(-110.0, 110.0), rng.randf_range(180.0, 260.0))


func _spawn_berry() -> void:
	if bushes.is_empty() or count_of("baie") >= 6:
		return
	var bx := bushes[rng.randi_range(0, bushes.size() - 1)]
	add_object("baie", bx + rng.randf_range(-60.0, 60.0), 40.0)


# ------------------------------------------------------------- sauvegarde --

func to_dict() -> Dictionary:
	var objs := []
	for o in objects:
		# Un objet tenu est sauvegardé posé au sol, aux pieds de la créature.
		var od := {"id": o.id, "type": o.type_name, "x": o.x, "h": 0.0 if o.holder else o.h, "cooldown": o.cooldown}
		if _eggs.has(o.id):
			var e: Dictionary = _eggs[o.id]
			od["egg"] = {"genome": e.genome.to_dict(), "mother": e.mother, "father": e.father,
				"generation": e.generation, "hatch_in": e.hatch_at - time}
		objs.append(od)
	var cs := []
	for c in creatures:
		cs.append(c.to_dict())
	return {"version": 1, "time": time, "next_id": _next_id, "next_uid": _next_uid,
		"names": _used_names.keys(), "objects": objs, "creatures": cs, "history": history}


static func from_dict(d: Dictionary) -> WorldSim:
	var w := WorldSim.new(0, "normal", 0)
	w.objects.clear()
	w.time = float(d.time)
	w._next_id = int(d.next_id)
	w._next_uid = int(d.next_uid)
	for n in d.names:
		w._used_names[n] = true
	for od in d.objects:
		var o := WorldObject.new(int(od.id), str(od.type), float(od.x), float(od.h))
		o.cooldown = float(od.cooldown)
		w.objects.append(o)
		if od.has("egg"):
			var e: Dictionary = od.egg
			w._eggs[o.id] = {"genome": Genome.from_dict(e.genome), "mother": e.mother, "father": e.father,
				"generation": int(e.generation), "hatch_at": w.time + float(e.hatch_in)}
	for cd in d.creatures:
		var c := CreatureSim.from_dict(cd)
		if not c.alive:
			c.set_meta("died_at", w.time)
		w.creatures.append(c)
	for h in d.history:
		w.history.append(h)
	return w
