class_name WorldSim
extends RefCounted
## Le monde : un sol en vue de côté, des arbres à fruits, des buissons à baies,
## un distributeur de graines, des jouets et les créatures.
## Aucune dépendance à l'affichage.

const GRAVITY := 900.0
const NAMES: Array[String] = ["Nina", "Ylo", "Kesh", "Mira", "Tavi", "Oru", "Sena", "Pim", "Lysa", "Bao", "Ezra", "Noa"]

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

var _next_id := 1
var _fruit_timer := 3.0
var _berry_timer := 10.0
var _seed_timer := 5.0
var _name_index := 0


func _init(seed_value: int = 0, p_scenario: String = "normal") -> void:
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
	creatures.append(new_creature(width * 0.5))


## Nouvelle créature issue de la souche de départ, légèrement mutée,
## avec une apparence tirée au hasard.
func new_creature(at_x: float) -> CreatureSim:
	var g := Genome.starter()
	g.mutate(rng, 0.05)
	var look := g.find(Gene.Type.APPEARANCE, "part", "corps")
	if look:
		for k in ["hue", "size", "speed"]:
			look.params[k] = rng.randf()
	var creature_name := NAMES[_name_index % NAMES.size()]
	_name_index += 1
	var sex := Gene.Sex.MALE if rng.randf() < 0.5 else Gene.Sex.FEMALE
	return CreatureSim.new(creature_name, g, at_x, sex)


## Remplace la créature morte par une nouvelle.
func replace_dead() -> void:
	for i in creatures.size():
		if not creatures[i].alive:
			creatures[i].drop_held()
			creatures[i] = new_creature(creatures[i].x)


func tick(dt: float) -> void:
	time += dt
	_spawners(dt)
	for o in objects:
		_physics(o, dt)
	for c in creatures:
		c.tick(dt, self, rng)


func _spawners(dt: float) -> void:
	_fruit_timer -= dt
	if _fruit_timer <= 0.0:
		_fruit_timer = rng.randf_range(6.0, 12.0)
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
	if trees.is_empty() or count_of("fruit") >= 10:
		return
	var tree_x := trees[rng.randi_range(0, trees.size() - 1)]
	add_object("fruit", tree_x + rng.randf_range(-110.0, 110.0), rng.randf_range(180.0, 260.0))


func _spawn_berry() -> void:
	if bushes.is_empty() or count_of("baie") >= 6:
		return
	var bx := bushes[rng.randi_range(0, bushes.size() - 1)]
	add_object("baie", bx + rng.randf_range(-60.0, 60.0), 40.0)
