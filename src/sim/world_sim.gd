class_name WorldSim
extends RefCounted
## Le monde : un sol en vue de côté, des arbres à fruits, des buissons à baies,
## un distributeur de graines, des jouets, les créatures et leurs œufs.
## Aucune dépendance à l'affichage.
##
## La maison en coupe, de gauche à droite : chambre | cuisine | salle de jeux |
## salle d'apprentissage, puis le jardin. Climat : jour et nuit, saisons,
## météo, température (la maison est tempérée et éclairée).

const GRAVITY := 900.0
const MAX_POPULATION := 14       # chats vivants + chatons attendus
const HATCH_TIME := 600.0        # 10 min de jeu avant l'éclosion
const CORPSE_TIME := 180.0       # le corps reste 3 min puis disparaît
const SYLLABLES: Array[String] = ["ka", "lo", "mi", "ny", "ta", "vi", "ru", "se", "pa", "lu", "ze", "no",
	"bi", "ra", "ke", "yo", "ma", "ti", "sha", "el", "or", "un", "ix", "an"]

## Scénarios : "normal" (le jeu), "graines" (aucun fruit, des graines au sol),
## "vide" (aucune nourriture) — les deux derniers servent aux tests.
var scenario := "normal"
var width := 3000.0
## Zones de gauche à droite : {key, label, x0, x1, indoor}.
var zones: Array[Dictionary] = []
var climate := Climate.new()
var adoption := Adoption.new()
## Écran d'apprentissage : ce qu'il montre (mode 0 noms, 1 verbes, 2 besoins).
var screen := {"mode": 0, "index": 0, "timer": 0.0}
const SCREEN_PERIOD := 6.0
const SCREEN_MODES: Array[String] = ["noms", "verbes", "besoins"]
const SCREEN_RANGE := 600.0
const SCREEN_PASSIVE := 0.4     # part retenue sans regarder l'écran
const SCREEN_NOUNS: Array[String] = ["pâtée", "croquettes", "proie", "eau", "jouet", "machine", "créature"]
const MUSIC_RANGE := 450.0
const GARDEN_W := 2000.0
const FEEDER_PERIOD := 45.0       # le distributeur remet des croquettes (jusqu'à 3) toutes les ~45 s
const PATEE_MAX := 3
const PATEE_REFILL := 600.0       # largeur du décor pixel art à la densité des pièces
const BASKET_X := 340.0          # corbeille de fruits, depuis le bord gauche de la cuisine
## Pièces de la maison : clé, nom affiché, largeur (celle de leur décor).
const HOUSE: Array = [
	["chambre", "Chambre", 1400.0],
	["cuisine", "Cuisine", 1536.0],
	["jeux", "Salle de jeux", 1800.0],
	["salle", "Salle d'apprentissage", 1400.0],
	["entree", "Entrée", 1200.0],
]
## Anciennes sauvegardes (version 2) : salle | jardin | loisirs.
const V2_ZONES := {"salle": [0.0, 1800.0], "jardin": [1800.0, 4800.0], "loisirs": [4800.0, 7200.0]}
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
var _seed_timer := 5.0
var _feeder_timer := 3.0
var _prey_timer := 60.0
var _patee_timer := 0.0
## Pâtée que le joueur peut donner (se reconstitue avec le temps).
var patee_stock := 3
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
		zones = [{"key": "jardin", "label": "Jardin", "x0": 0.0, "x1": width, "indoor": false}]
		if scenario == "graines":
			add_object("eau", 600.0)
	else:
		_setup_zones()
		var g := garden_x()
		add_object("balle", g + 1300.0)
		_add_zone_objects()
		for i in 2:
			add_object("croquettes", machine_x + 60.0 + i * 25.0, 0.0)
	add_founders(founders)


func _setup_zones() -> void:
	zones = []
	var x := 0.0
	for r in HOUSE:
		zones.append({"key": r[0], "label": r[1], "x0": x, "x1": x + float(r[2]), "indoor": true})
		x += float(r[2])
	zones.append({"key": "jardin", "label": "Jardin", "x0": x, "x1": x + GARDEN_W, "indoor": false})
	width = x + GARDEN_W
	trees = PackedFloat32Array([x + 980.0])                # le pommier du décor
	bushes = PackedFloat32Array()         # plus de baies dans le jeu (les tests en ajoutent)
	machine_x = zone("cuisine").x0 + 1000.0     # le distributeur de croquettes


func zone(key: String) -> Dictionary:
	for z in zones:
		if z.key == key:
			return z
	return {}


func _add_zone_objects() -> void:
	var k := zone("cuisine")
	add_object("distributeur", machine_x)
	add_object("eau", k.x0 + 1250.0)
	add_object("mare", zone("jardin").x0 + 1720.0)
	var s := zone("salle")
	add_object("ecran", (s.x0 + s.x1) * 0.5)
	var j: float = zone("jeux").x0
	add_object("trampoline", j + 450.0)
	add_object("boite_musique", j + 1350.0)
	add_object("balle", j + 900.0)
	add_object("balle", j + 1600.0)


## Position d'une sauvegarde version 2 dans la maison actuelle : même place
## relative dans la zone équivalente (les loisirs deviennent la salle de jeux).
func _from_v2(x: float) -> float:
	for k in V2_ZONES:
		var r: Array = V2_ZONES[k]
		if x < r[1] or k == "loisirs":
			var z := zone("jeux" if k == "loisirs" else k)
			var t := clampf((x - r[0]) / (r[1] - r[0]), 0.0, 1.0)
			return z.x0 + t * (z.x1 - z.x0)
	return x


## Début du jardin (0 dans les scénarios de test, qui n'ont que le jardin).
func garden_x() -> float:
	for z in zones:
		if z.key == "jardin":
			return z.x0
	return 0.0


func zone_at(x: float) -> Dictionary:
	for z in zones:
		if x < z.x1:
			return z
	return zones[-1]


func temperature_at(x: float) -> float:
	return Climate.INDOOR_TEMP if zone_at(x).indoor else climate.outdoor_temp(time)


## Lumière : la salle est éclairée, dehors on suit le soleil.
func light_at(x: float) -> float:
	return 1.0 if zone_at(x).indoor else climate.daylight(time)


func raining_at(x: float) -> bool:
	return climate.is_raining() and not zone_at(x).indoor


## Ce qu'affiche l'écran : [genre, index] ("nom", "verbe" ou "besoin").
func screen_item() -> Array:
	var kind: String = ["nom", "verbe", "besoin"][screen.mode]
	if kind == "nom":                  # seulement les choses qui existent dans le jeu
		var shown := SCREEN_NOUNS.map(func(n): return ObjectCatalog.categories.find(n))
		return [kind, shown[screen.index % shown.size()]]
	var n: int = [0, Language.VERB_WORDS.size() - 1, Language.DRIVE_WORDS.size()][screen.mode]
	var i: int = screen.index % n
	if kind == "verbe":
		i += 1                         # pas « rien »
	return [kind, i]


## Le joueur (ou une créature qui le pousse) change ce que montre l'écran.
func next_screen_mode() -> void:
	screen.mode = (screen.mode + 1) % SCREEN_MODES.size()
	screen.index = 0
	screen.timer = 0.0


func _tick_screen(dt: float) -> void:
	var scr := _first("ecran")
	if scr == null:
		return
	screen.timer += dt
	if screen.timer < SCREEN_PERIOD:
		return
	screen.timer = 0.0
	# Le mot qui vient d'être montré : celles qui regardaient l'écran l'apprennent
	# Celles qui le fixent apprennent pleinement ; les autres présentes dans la
	# pièce en retiennent un peu au passage (surtout les curieuses).
	var item := screen_item()
	for c in creatures:
		if c.alive and not c.is_asleep() and absf(c.x - scr.x) < SCREEN_RANGE:
			c.learn_from_screen(item[0], item[1], 1.0 if c.watches(scr) else SCREEN_PASSIVE)
	screen.index += 1


func _tick_music(dt: float) -> void:
	for o in objects:
		if o.type_name != "boite_musique" or o.cooldown <= 0.0:
			continue
		for c in creatures:
			if c.alive and absf(c.x - o.x) < MUSIC_RANGE:
				c.hear_music(dt)


func _first(type_name: String) -> WorldObject:
	for o in objects:
		if o.type_name == type_name:
			return o
	return null


## Fondateurs : souche de départ légèrement mutée, couleurs au hasard,
## sexes alternés pour qu'un couple soit possible.
func add_founders(count: int) -> void:
	var first_sex := Gene.Sex.MALE if rng.randf() < 0.5 else Gene.Sex.FEMALE
	for i in count:
		var g := Genome.starter()
		g.mutate(rng, 0.05)
		var look := g.find(Gene.Type.APPEARANCE, "part", "corps")
		if look:
			for k in ["hue", "hue2", "saturation", "brightness", "glow", "glow_power", "size", "speed"]:
				look.params[k] = rng.randf()
		CreatureSim.ensure_cat_genes(g, rng, true)
		var temper := g.find(Gene.Type.LOBE, "lobe", "temperament")
		if temper:     # des caractères variés dès les fondateurs
			temper.params.curiosity = rng.randf()
			temper.params.playfulness = rng.randf()
		var shape := g.find(Gene.Type.APPEARANCE, "part", "silhouette")
		if shape:
			for k in ["tail", "antennae", "corpulence"]:
				shape.params[k] = rng.randf()
		var motif := g.find(Gene.Type.APPEARANCE, "part", "motif")
		if motif:      # environ un fondateur sur deux porte un motif
			for k in ["spots", "stripes", "patches"]:
				motif.params[k] = rng.randf_range(0.3, 1.0) if rng.randf() < 0.2 else 0.0
			motif.params.hue3 = rng.randf()
			motif.params.light3 = rng.randf()
		var sex := first_sex if i % 2 == 0 else (Gene.Sex.FEMALE if first_sex == Gene.Sex.MALE else Gene.Sex.MALE)
		# les nouveaux arrivent dans la cuisine, près des gamelles (dans les tests : au milieu)
		var k := zone("cuisine")
		var mid: float = (k.x0 + k.x1) * 0.5 if not k.is_empty() else width * 0.5
		_add_creature(g, mid + (i - (count - 1) * 0.5) * 200.0, sex, 1, "", "")


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
		"hue": c.hue, "coat": c.coat.get("name", "")})
	return c


## Le joueur parle à une créature ; celles qui sont proches entendent aussi.
const HEARING_RANGE := 500.0

func say(text: String, to: CreatureSim) -> Array:
	var found := []
	for c in creatures:
		if not c.alive:
			continue
		if c == to:
			found = c.hear(text, 1.0)
		elif absf(c.x - to.x) < HEARING_RANGE:
			c.hear(text, 0.5 * (1.0 - absf(c.x - to.x) / HEARING_RANGE))
	return found


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
			pregnant += maxi(1, c.litter_size)
	return alive_count() + _eggs.size() + pregnant >= MAX_POPULATION


## Taille de la portée : souvent 3 ou 4, parfois 1-2 ou 5 ; les jeunes et
## vieilles mères en ont moins, et on ne dépasse pas la population maximale.
func litter_size_for(mother: CreatureSim) -> int:
	var n: int = [1, 2, 2, 3, 3, 3, 4, 4, 4, 5][rng.randi_range(0, 9)]
	if mother.age > 7.0 * 3600.0:
		n = maxi(1, n - 1)
	var room := MAX_POPULATION - alive_count() - _eggs.size()
	for c in creatures:
		if c.alive and c.pregnant_time >= 0.0 and c != mother:
			room -= maxi(1, c.litter_size)
	return clampi(n, 1, maxi(1, room))


func find_creature(n: String) -> CreatureSim:
	if n == "":
		return null
	for c in creatures:
		if c.creature_name == n:
			return c
	return null


## Mise bas : le chaton naît aux pieds de sa mère.
func give_birth(at_x: float, g: Genome, mother: String, father: String, generation: int) -> CreatureSim:
	var baby := _add_creature(g, at_x, _baby_sex(), generation, mother, father)
	last_event = "%s a mis bas : naissance de %s (génération %d), enfant de %s et %s." % [mother, baby.creature_name,
		baby.generation, mother, father]
	return baby


## Anciennes sauvegardes seulement : les chats ne pondent plus.
func lay_egg(at_x: float, g: Genome, mother: String, father: String, generation: int) -> void:
	var egg := add_object("oeuf", at_x, 20.0)
	_eggs[egg.id] = {"genome": g, "mother": mother, "father": father, "generation": generation,
		"hatch_at": time + HATCH_TIME}


func egg_info(o: WorldObject) -> Dictionary:
	return _eggs.get(o.id, {})


func tick(dt: float) -> void:
	time += dt
	climate.tick(dt, rng, time)
	if scenario == "normal":
		adoption.tick(self)
	_spawners(dt)
	_tick_screen(dt)
	_tick_music(dt)
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
		var sex := _baby_sex()
		var baby := _add_creature(e.genome, o.x, sex, e.generation, e.mother, e.father)
		_eggs.erase(o.id)
		remove_object(o)
		last_event = "Naissance de %s (génération %d), enfant de %s et %s." % [baby.creature_name, baby.generation, e.mother, e.father]


## Sexe d'un nouveau-né : une chance sur deux, corrigée vers le sexe
## minoritaire chez les vivants (évite les lignées sans couple possible).
func _baby_sex() -> int:
	var males := 0
	var females := 0
	for c in creatures:
		if c.alive and c.stage < Lifecycle.Stage.OLD:
			if c.sex == Gene.Sex.FEMALE:
				females += 1
			else:
				males += 1
	var p_female := 0.5
	if males + females > 0:
		p_female = clampf(0.5 + 0.35 * float(males - females) / float(males + females), 0.15, 0.85)
	return Gene.Sex.FEMALE if rng.randf() < p_female else Gene.Sex.MALE


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
	# Distributeurs automatiques : quelques croquettes dès que la gamelle se vide
	_feeder_timer -= dt
	if _feeder_timer <= 0.0:
		_feeder_timer = rng.randf_range(FEEDER_PERIOD * 0.8, FEEDER_PERIOD * 1.2)
		for o in objects.duplicate():
			if o.type_name == "distributeur" and _food_around(o.x, 300.0) < 3:
				add_object("croquettes", o.x + rng.randf_range(50.0, 90.0), 0.0)
	# Pâtée du joueur : une portion revient toutes les 10 min
	if patee_stock < PATEE_MAX:
		_patee_timer -= dt
		if _patee_timer <= 0.0:
			_patee_timer = PATEE_REFILL
			patee_stock += 1
	if scenario == "normal":
		_tick_prey_spawn(dt)
	if scenario == "graines":       # test : de la pâtée tombe, sans instinct pour elle
		_seed_timer -= dt
		if _seed_timer <= 0.0:
			_seed_timer = rng.randf_range(6.0, 12.0)
			if count_of("patee") < 10:
				add_object("patee", rng.randf_range(100.0, width - 100.0), 300.0)
	if scenario == "vide":
		return
	for o in objects:
		if o.prey_alive():
			_move_prey(o, dt)


func _food_around(at_x: float, r: float) -> int:
	var n := 0
	for o in objects:
		if o.holder == null and o.type_name in ["croquettes", "patee"] and absf(o.x - at_x) < r:
			n += 1
	return n


# ------------------------------------------------------------- proies --

## Des souris et des oiseaux viennent au jardin (moins l'hiver).
func _tick_prey_spawn(dt: float) -> void:
	_prey_timer -= dt
	if _prey_timer > 0.0:
		return
	var winter := climate.season(time) == 3
	_prey_timer = rng.randf_range(90.0, 180.0) * (2.0 if winter else 1.0)
	var g := zone("jardin")
	if g.is_empty():
		return
	var x := rng.randf_range(float(g.x0) + 150.0, float(g.x1) - 100.0)
	if _live_prey("souris") < 3 and rng.randf() < 0.6:
		add_object("souris", x, 0.0)
	elif _live_prey("oiseau") < 2 and not winter:
		add_object("oiseau", x, 260.0)          # il se pose


func _live_prey(type_name: String) -> int:
	var n := 0
	for o in objects:
		if o.type_name == type_name and o.prey_alive():
			n += 1
	return n


## Une souris trottine et file quand un chat approche ; un oiseau sautille et
## s'envole parfois quand on s'approche trop. Elles restent au jardin.
func _move_prey(o: WorldObject, dt: float) -> void:
	if o.h > 0.0:
		return
	var info: Dictionary = ObjectCatalog.types[o.type_name].get("prey", {})
	var g := zone("jardin")
	var x0: float = g.get("x0", 0.0) + 60.0
	var x1: float = g.get("x1", width) - 60.0
	var near: CreatureSim = null
	for c in creatures:
		if c.alive and (near == null or absf(c.x - o.x) < absf(near.x - o.x)):
			near = c
	var d := absf(near.x - o.x) if near else 1e9
	o.flee = maxf(0.0, o.flee - dt)
	if info.get("flies", false):
		if d < 170.0 and rng.randf() < dt * (3.0 if o.flee > 0.0 else 0.8):
			remove_object(o)                       # envolé
			return
	var flee_r: float = info.get("flee", 0.0)
	if near and (d < flee_r or o.flee > 0.0) and not info.get("flies", false):
		o.x += signf(o.x - near.x) * 170.0 * dt
	else:
		if rng.randf() < dt * 0.4:
			o.vx = rng.randf_range(-1.0, 1.0) * float(info.get("speed", 40.0))
		o.x += o.vx * dt
	if o.x < x0 or o.x > x1:
		o.x = clampf(o.x, x0, x1)
		o.vx = -o.vx


## Le joueur donne de la pâtée (stock limité, qui se reconstitue).
func drop_patee(at_x: float) -> bool:
	if patee_stock <= 0:
		last_event = "Plus de pâtée pour le moment (une portion revient toutes les 10 min)."
		return false
	patee_stock -= 1
	add_object("patee", at_x, 120.0)
	return true


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


# ------------------------------------------------------------- sauvegarde --

func to_dict() -> Dictionary:
	var objs := []
	for o in objects:
		# Un objet tenu est sauvegardé posé au sol, aux pieds de la créature.
		var od := {"id": o.id, "type": o.type_name, "x": o.x, "h": 0.0 if o.holder else o.h, "cooldown": o.cooldown,
			"dead": o.dead}
		if _eggs.has(o.id):
			var e: Dictionary = _eggs[o.id]
			od["egg"] = {"genome": e.genome.to_dict(), "mother": e.mother, "father": e.father,
				"generation": e.generation, "hatch_in": e.hatch_at - time}
		objs.append(od)
	var cs := []
	for c in creatures:
		cs.append(c.to_dict())
	return {"version": 4, "time": time, "climate": climate.to_dict(), "screen": screen, "next_id": _next_id, "next_uid": _next_uid,
		"names": _used_names.keys(), "objects": objs, "creatures": cs, "history": history,
		"adoption": adoption.to_dict()}


static func from_dict(d: Dictionary) -> WorldSim:
	ObjectCatalog.ensure()
	var w := WorldSim.new(0, "normal", 0)
	w.objects.clear()
	w.time = float(d.time)
	w.climate.load_dict(d.get("climate", {}))
	w.adoption.load_dict(d.get("adoption", {}))
	var scr: Dictionary = d.get("screen", {})
	w.screen = {"mode": int(scr.get("mode", 0)), "index": int(scr.get("index", 0)), "timer": float(scr.get("timer", 0.0))}
	# v1 : le jardin seul (0 à 3000) ; v2 : salle | jardin | loisirs ; v3 : la maison
	var version := int(d.get("version", 1))
	var place := func(x: float) -> float:
		if version == 1:
			return w.garden_x() + x
		if version == 2:
			return w._from_v2(x)
		return x
	var fixed := ["distributeur", "ecran", "trampoline", "boite_musique", "eau", "mare"]
	w._next_id = int(d.next_id)
	w._next_uid = int(d.next_uid)
	for n in d.names:
		w._used_names[n] = true
	var old_objects := version < 4
	if old_objects:          # les meubles changent de place : on les recrée
		w._add_zone_objects()
	for od in d.objects:
		if old_objects and str(od.type) in fixed:
			continue
		if not ObjectCatalog.types.has(str(od.type)):      # retirés du jeu (fruits, graines...)
			continue
		var o := WorldObject.new(int(od.id), str(od.type), place.call(float(od.x)), float(od.h))
		o.cooldown = float(od.cooldown)
		o.dead = bool(od.get("dead", false))
		w.objects.append(o)
		if od.has("egg"):
			var e: Dictionary = od.egg
			w._eggs[o.id] = {"genome": Genome.from_dict(e.genome), "mother": e.mother, "father": e.father,
				"generation": int(e.generation), "hatch_at": w.time + float(e.hatch_in)}
	for cd in d.creatures:
		var c := CreatureSim.from_dict(cd)
		c.x = place.call(c.x)
		if not c.alive:
			c.set_meta("died_at", w.time)
		w.creatures.append(c)
	for h in d.history:
		w.history.append(h)
	return w
