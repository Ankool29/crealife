class_name Garden
extends RefCounted
## Écosystème du jardin : plantes qui poussent et fanent avec les saisons,
## papillons des beaux jours, population de souris qui se reproduit.
## (appelé par WorldSim, seulement dans le jeu normal)
##
## - Plantes : une graine tombe de temps en temps (moins en hiver), germe
##   (pousse) puis devient plante. L'hiver, pousses et plantes fanent ; elles
##   repoussent au printemps. Trois sortes : plante ordinaire, herbe à chat
##   (grise certains chats) et lys (toxique). Au plus MAX_PLANTS.
## - Papillons : le jour, par beau temps, hors de l'hiver ; ils volettent
##   surtout près des fleurs et s'envolent quand un chat les touche.
## - Souris : elles se reproduisent lentement jusqu'à un plafond ; la chasse
##   les fait diminuer ; s'il n'en reste presque plus, une arrive parfois
##   d'ailleurs.

enum { SEED, SPROUT, PLANT, WILTED }
const STAGE_LABELS: Array[String] = ["graine", "pousse", "plante", "fanée"]
const MAX_PLANTS := 10
const SPECIES := {"plante": 0.5, "herbe_chat": 0.25, "lys": 0.25}
const SEED_EVERY := [240.0, 540.0]     # une graine toutes les 4 à 9 min (×2,5 en hiver)
const GERMINATE := [120.0, 600.0]      # graine -> pousse : 2 à 10 min
const GROW := [900.0, 2400.0]          # pousse -> plante : 15 à 40 min
const REGROW := [60.0, 600.0]          # fanée -> pousse, au retour du printemps
const WILT_TIME := 400.0               # l'hiver venu, une plante fane en ~7 min en moyenne
const MAX_BUTTERFLIES := 4
const MAX_MICE := 8
const MOUSE_BIRTH_EVERY := [150.0, 300.0]
const CORPSE_TIME := 600.0             # une proie attrapée et pas mangée disparaît
const STEP := 1.0                      # le jardin n'est mis à jour qu'une fois par seconde

var _acc := 0.0
var _seed_timer := 60.0
var _butterfly_timer := 20.0
var _mouse_timer := 200.0


func tick(world: WorldSim, dt: float) -> void:
	_acc += dt
	if _acc < STEP:
		return
	var t := _acc
	_acc = 0.0
	var g := world.zone("jardin")
	if g.is_empty():
		return
	_tick_plants(world, g, t)
	_tick_butterflies(world, g, t)
	_tick_mice(world, g, t)


static func is_winter(world: WorldSim) -> bool:
	return world.climate.season(world.time) == 3


# ------------------------------------------------------------ plantes --

func plants(world: WorldSim) -> Array[WorldObject]:
	var out: Array[WorldObject] = []
	for o in world.objects:
		if o.is_plant():
			out.append(o)
	return out


func _tick_plants(world: WorldSim, g: Dictionary, t: float) -> void:
	var rng := world.rng
	var winter := is_winter(world)
	var list := plants(world)
	_seed_timer -= t
	if _seed_timer <= 0.0:
		_seed_timer = rng.randf_range(SEED_EVERY[0], SEED_EVERY[1]) * (2.5 if winter else 1.0)
		if list.size() < MAX_PLANTS:
			var x := _free_spot(world, g, list)
			if x >= 0.0:
				sow(world, _pick_species(rng), x)
	for o in list:
		match o.growth:
			SEED:
				if not winter:            # l'hiver, la graine attend le printemps
					o.timer -= t
					if o.timer <= 0.0:
						o.growth = SPROUT
						o.timer = rng.randf_range(GROW[0], GROW[1])
			SPROUT, PLANT:
				if winter:
					if rng.randf() < t / WILT_TIME:
						o.growth = WILTED
						o.timer = rng.randf_range(REGROW[0], REGROW[1])
				elif o.growth == SPROUT:
					o.timer -= t
					if o.timer <= 0.0:
						o.growth = PLANT
						o.bites = 0
			WILTED:
				if not winter:            # le printemps revient : elle repart du pied
					o.timer -= t
					if o.timer <= 0.0:
						o.growth = SPROUT
						o.bites = 0
						o.timer = rng.randf_range(GROW[0], GROW[1]) * 0.5


## Sème une graine (elle tombe du ciel et germera plus tard).
func sow(world: WorldSim, species: String, x: float) -> WorldObject:
	var o := world.add_object(species, x, 160.0)
	o.growth = SEED
	o.timer = world.rng.randf_range(GERMINATE[0], GERMINATE[1])
	return o


func _pick_species(rng: RandomNumberGenerator) -> String:
	var r := rng.randf()
	for k in SPECIES:
		r -= SPECIES[k]
		if r <= 0.0:
			return k
	return "plante"


## Une place libre au jardin (loin des autres plantes et de la mare), ou -1.
func _free_spot(world: WorldSim, g: Dictionary, list: Array[WorldObject]) -> float:
	var mare := world._first("mare")
	for attempt in 8:
		var x := world.rng.randf_range(float(g.x0) + 150.0, float(g.x1) - 120.0)
		var ok := mare == null or absf(mare.x - x) > 220.0
		for o in list:
			if absf(o.x - x) < 90.0:
				ok = false
		if ok:
			return x
	return -1.0


## Un chat prend une bouchée : au bout de quelques-unes, la plante est mangée.
static func bite(world: WorldSim, o: WorldObject) -> void:
	o.bites += 1
	if o.bites >= int(ObjectCatalog.types[o.type_name].plant.get("bites", 3)):
		world.remove_object(o)


# ----------------------------------------------------------- papillons --

## Temps à papillons : de jour, sans pluie, hors de l'hiver, pas trop froid.
static func butterfly_weather(world: WorldSim, g: Dictionary) -> bool:
	var x := float(g.x0) + 100.0
	return not is_winter(world) and world.light_at(x) > 0.6 and not world.raining_at(x) \
		and world.temperature_at(x) >= 12.0


func _tick_butterflies(world: WorldSim, g: Dictionary, t: float) -> void:
	var rng := world.rng
	var nice := butterfly_weather(world, g)
	var flowers: Array[WorldObject] = []
	for o in world.objects:
		if o.is_plant() and o.is_grown() and ObjectCatalog.types[o.type_name].plant.get("flowers", false):
			flowers.append(o)
	var n := world.count_of("papillon")
	if not nice:
		for o in world.objects.duplicate():      # ils s'en vont peu à peu
			if o.type_name == "papillon" and rng.randf() < t / 20.0:
				world.remove_object(o)
		return
	_butterfly_timer -= t
	if _butterfly_timer > 0.0:
		return
	_butterfly_timer = rng.randf_range(40.0, 90.0)
	var room := mini(MAX_BUTTERFLIES, 1 + flowers.size() / 2)
	if n < room:
		var x := rng.randf_range(float(g.x0) + 150.0, float(g.x1) - 150.0)
		if not flowers.is_empty() and rng.randf() < 0.8:
			x = flowers[rng.randi_range(0, flowers.size() - 1)].x + rng.randf_range(-80.0, 80.0)
		var b := world.add_object("papillon", x, rng.randf_range(80.0, 180.0))
		b.vx = rng.randf_range(-30.0, 30.0)


## Un papillon volette : il vagabonde d'une fleur à l'autre, monte et descend,
## et s'écarte vite quand un chat s'approche (ou vient de le toucher).
static func move_butterfly(world: WorldSim, o: WorldObject, near: CreatureSim, dt: float) -> void:
	var rng := world.rng
	var g := world.zone("jardin")
	var x0: float = g.get("x0", 0.0) + 40.0
	var x1: float = g.get("x1", world.width) - 40.0
	var d := absf(near.x - o.x) if near else 1e9
	var info: Dictionary = ObjectCatalog.types[o.type_name].prey
	if near and (d < float(info.get("flee", 140.0)) or o.flee > 0.0):
		o.x += signf(o.x - near.x + 0.01) * 110.0 * dt
		o.h = minf(o.h + 70.0 * dt, 260.0)
	else:
		if rng.randf() < dt * 0.5:
			# vers une fleur proche, sinon au hasard
			var target := o.x + rng.randf_range(-200.0, 200.0)
			for p in world.objects:
				if p.is_plant() and p.is_grown() and absf(p.x - o.x) < 400.0 and rng.randf() < 0.5:
					target = p.x
					break
			o.vx = clampf((target - o.x) * 0.5, -60.0, 60.0)
		o.x += o.vx * dt
		o.h = clampf(o.h + rng.randf_range(-60.0, 60.0) * dt + (110.0 - o.h) * 0.2 * dt, 40.0, 240.0)
	if o.x < x0 or o.x > x1:
		o.x = clampf(o.x, x0, x1)
		o.vx = -o.vx


# --------------------------------------------------------------- souris --

## Souris vivantes au jardin.
static func mice(world: WorldSim) -> Array[WorldObject]:
	var out: Array[WorldObject] = []
	for o in world.objects:
		if o.type_name == "souris" and o.prey_alive():
			out.append(o)
	return out


func _tick_mice(world: WorldSim, g: Dictionary, t: float) -> void:
	var rng := world.rng
	# les proies attrapées mais pas mangées finissent par disparaître
	for o in world.objects.duplicate():
		if o.dead and o.holder == null:
			o.timer -= t
			if o.timer <= 0.0:
				world.remove_object(o)
	_mouse_timer -= t
	if _mouse_timer > 0.0:
		return
	_mouse_timer = rng.randf_range(MOUSE_BIRTH_EVERY[0], MOUSE_BIRTH_EVERY[1]) * (2.0 if is_winter(world) else 1.0)
	var list := mice(world)
	var n := list.size()
	if n >= 2:
		# croissance logistique : lente au début, nulle au plafond
		if rng.randf() < 0.25 * n * (1.0 - float(n) / MAX_MICE):
			var mum: WorldObject = list[rng.randi_range(0, n - 1)]
			world.add_object("souris", mum.x + rng.randf_range(-60.0, 60.0), 0.0)
	elif rng.randf() < 0.3:          # presque plus de souris : une arrive d'ailleurs
		world.add_object("souris", rng.randf_range(float(g.x0) + 150.0, float(g.x1) - 100.0), 0.0)


# ---------------------------------------------------------- sauvegarde --

func to_dict() -> Dictionary:
	return {"seed": _seed_timer, "butterfly": _butterfly_timer, "mouse": _mouse_timer}


func load_dict(d: Dictionary) -> void:
	_seed_timer = float(d.get("seed", 60.0))
	_butterfly_timer = float(d.get("butterfly", 20.0))
	_mouse_timer = float(d.get("mouse", 200.0))
