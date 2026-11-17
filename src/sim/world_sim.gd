class_name WorldSim
extends RefCounted
## Le monde : un sol en vue de côté, des arbres qui laissent tomber des fruits,
## et les créatures. Aucune dépendance à l'affichage.

const GRAVITY := 900.0
const MAX_FOOD := 12

var width := 3000.0
var rng := RandomNumberGenerator.new()
var creatures: Array[CreatureSim] = []
## Chaque fruit : { id, x, h (hauteur au-dessus du sol), vy }
var foods: Array[Dictionary] = []
var trees := PackedFloat32Array([450.0, 1350.0, 2350.0])
var time := 0.0

var _next_id := 1
var _spawn_timer := 3.0


func _init(seed_value: int = 0) -> void:
	if seed_value == 0:
		rng.randomize()
	else:
		rng.seed = seed_value
	creatures.append(CreatureSim.new("Nina", Genome.create_random(rng), width * 0.5))
	for i in 3:
		_spawn_fruit_from_tree()


func tick(dt: float) -> void:
	time += dt
	_spawn_timer -= dt
	if _spawn_timer <= 0.0:
		_spawn_timer = rng.randf_range(6.0, 12.0)
		_spawn_fruit_from_tree()

	for f in foods:
		if f.h > 0.0:
			f.vy += GRAVITY * dt
			f.h = maxf(0.0, f.h - f.vy * dt)

	for c in creatures:
		c.tick(dt, self, rng)


## Le joueur fait tomber un fruit du ciel.
func drop_food(at_x: float) -> void:
	_add_food(clampf(at_x, 20.0, width - 20.0), 420.0)


func has_food() -> bool:
	for f in foods:
		if f.h <= 0.0:
			return true
	return false


## Fruit posé au sol le plus proche, ou {} s'il n'y en a pas.
func nearest_food(from_x: float) -> Dictionary:
	var best: Dictionary = {}
	var best_d := INF
	for f in foods:
		if f.h > 0.0:
			continue
		var d := absf(f.x - from_x)
		if d < best_d:
			best_d = d
			best = f
	return best


func remove_food(id: int) -> void:
	for i in foods.size():
		if foods[i].id == id:
			foods.remove_at(i)
			return


func _spawn_fruit_from_tree() -> void:
	var tree_x := trees[rng.randi_range(0, trees.size() - 1)]
	_add_food(tree_x + rng.randf_range(-110.0, 110.0), rng.randf_range(180.0, 260.0))


func _add_food(at_x: float, height: float) -> void:
	if foods.size() >= MAX_FOOD:
		return
	foods.append({ "id": _next_id, "x": at_x, "h": height, "vy": 0.0 })
	_next_id += 1
