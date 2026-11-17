extends SceneTree
## Tests de la simulation, sans affichage.
## Lancer : godot --headless --script res://tests/test_sim.gd

var _failures := 0


func _init() -> void:
	_test_survival()
	_test_genome_cross()
	_test_learning()
	print("RÉSULTAT : %s" % ("OK" if _failures == 0 else "%d échec(s)" % _failures))
	quit(_failures)


func _check(cond: bool, msg: String) -> void:
	if cond:
		print("  ok   ", msg)
	else:
		print("  ÉCHEC ", msg)
		_failures += 1


func _test_survival() -> void:
	print("Survie sur 30 minutes simulées :")
	var w := WorldSim.new(42)
	var c := w.creatures[0]
	var counts := PackedInt32Array([0, 0, 0, 0, 0])
	var hunger_sum := 0.0
	var ticks := 30 * 60 * 10
	for i in ticks:
		w.tick(0.1)
		counts[c.get_action()] += 1
		hunger_sum += c.chem.get_level(Biochemistry.Drive.HUNGER)
	print("    repas=%d siestes=%d faim moyenne=%.2f temps par action=%s" % [c.meals, c.naps, hunger_sum / ticks, counts])
	_check(c.meals > 5, "la créature mange régulièrement")
	_check(c.naps > 2, "la créature dort régulièrement")
	_check(hunger_sum / ticks < 0.7, "la faim reste sous contrôle")
	_check(c.x >= 0.0 and c.x <= w.width, "la créature reste dans le monde")


func _test_genome_cross() -> void:
	print("Génétique :")
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var a := Genome.create_random(rng)
	var b := Genome.create_random(rng)
	var child := Genome.cross(a, b, rng)
	var ok := true
	for n in Genome.GENE_NAMES:
		var v := child.get_gene(n)
		ok = ok and v >= 0.0 and v <= 1.0
	_check(ok, "les gènes de l'enfant restent dans [0, 1]")
	var copy := Genome.from_dict(child.to_dict())
	_check(copy.get_gene("hue") == child.get_gene("hue"), "sauvegarde / chargement du génome")


func _test_learning() -> void:
	print("Apprentissage :")
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var g := Genome.create_random(rng)
	var chem := Biochemistry.new(g)
	var brain := Brain.new(g)
	chem.levels = PackedFloat32Array([0.1, 0.1, 0.9])
	brain.decide(chem, rng, [true, true, false, true, true] as Array[bool])
	var action := brain.current_action
	var before := brain.score(action, chem)
	brain.reinforce(-1.0)
	_check(brain.score(action, chem) < before, "une punition rend l'action moins probable")
	brain.reinforce(2.0)
	_check(brain.score(action, chem) > before, "une récompense rend l'action plus probable")
