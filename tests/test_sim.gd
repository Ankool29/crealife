extends SceneTree
## Tests de la simulation, sans affichage.
## Lancer : godot --headless --script res://tests/test_sim.gd

const STEP := 0.2
var _failures := 0


func _init() -> void:
	_test_genome_file()
	_test_cross_and_mutation()
	_test_stage_expression()
	_test_learning()
	_test_starvation()
	_test_full_life()
	print("RÉSULTAT : %s" % ("OK" if _failures == 0 else "%d échec(s)" % _failures))
	quit(_failures)


func _check(cond: bool, msg: String) -> void:
	if cond:
		print("  ok    ", msg)
	else:
		print("  ÉCHEC ", msg)
		_failures += 1


func _test_genome_file() -> void:
	print("Génome :")
	var g := Genome.starter()
	_check(g != null and g.genes.size() > 50, "la souche de départ se charge (%d gènes)" % (g.genes.size() if g else 0))
	var again := Genome.from_dict(JSON.parse_string(JSON.stringify(g.to_dict())))
	_check(again.genes.size() == g.genes.size() and JSON.stringify(again.to_dict()) == JSON.stringify(g.to_dict()),
		"sauvegarde puis rechargement à l'identique")
	var d := g.to_dict()
	d.genes.append({"id": 999, "type": "gene_du_futur", "p": {}})
	_check(Genome.from_dict(d).genes.size() == g.genes.size(), "un type de gène inconnu est ignoré")


func _test_cross_and_mutation() -> void:
	print("Hérédité :")
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var a := Genome.starter()
	var b := Genome.starter()
	a.find(Gene.Type.APPEARANCE, "part", "corps").params.hue = 0.1
	b.find(Gene.Type.APPEARANCE, "part", "corps").params.hue = 0.9
	var hues := {}
	for i in 40:
		var child := Genome.cross(a, b, rng, 0.0)
		hues[snappedf(child.find(Gene.Type.APPEARANCE, "part", "corps").params.hue, 0.1)] = true
	_check(hues.has(0.1) and hues.has(0.9), "les enfants héritent de l'un ou l'autre parent")
	var m := Genome.starter()
	m.mutate(rng, 1.0)
	var ok := true
	for gene in m.genes:
		var ranges := Gene.ranges_for(gene.type)
		for k in ranges:
			if gene.params.has(k):
				var v := float(gene.params[k])
				ok = ok and v >= ranges[k][0] and v <= ranges[k][1]
	_check(ok, "les mutations restent dans les plages autorisées")
	var small := Genome.starter()
	var fat_gain := 0.0
	for gene in small.genes:
		if gene.type == Gene.Type.EMITTER and gene.params.chem == "Fatigue" and gene.params.source == "corps.activite":
			gene.mutate(rng, 1.0)
			fat_gain = float(gene.params.gain)
	_check(fat_gain > 0.0001 and fat_gain < 0.0004, "un petit gain mute en proportion (%.5f)" % fat_gain)
	var vital := 0
	for gene in m.genes:
		if gene.type == Gene.Type.ORGAN:
			vital += 1
	_check(vital == 6, "les organes ne sont jamais perdus par mutation")


func _test_stage_expression() -> void:
	print("Expression selon l'âge :")
	var hs := Chemicals.id_of("Hormone sexuelle")
	var c := CreatureSim.new("Test", Genome.starter(), 100.0, Gene.Sex.FEMALE)
	var emitters_baby := c.biochem._esrc.size()
	c.stage = Lifecycle.Stage.ADULT
	c._express(false)
	var emitters_adult := c.biochem._esrc.size()
	_check(emitters_adult > emitters_baby, "de nouveaux gènes s'activent à l'âge adulte (%d -> %d émetteurs)" % [emitters_baby, emitters_adult])
	c._express(false)
	_check(c.biochem._esrc.size() == emitters_adult, "réexprimer ne duplique pas les gènes")
	c.biochem.loci.set_value("corps.metabolisme", 1.0)
	for i in 600:
		c.biochem.step(STEP, 3.0 * 3600.0)
	_check(c.biochem.conc[hs] > 0.05, "l'hormone sexuelle apparaît chez l'adulte")


func _test_learning() -> void:
	print("Apprentissage :")
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var brain := Brain.new()
	var drives := PackedFloat32Array([0.1, 0.1, 0.9])
	brain.decide(drives, rng, [true, true, false, true, true] as Array[bool])
	var action := brain.current_action
	var before := brain.score(action, drives)
	brain.reinforce(-1.0)
	_check(brain.score(action, drives) < before, "une punition rend l'action moins probable")
	brain.reinforce(2.0)
	_check(brain.score(action, drives) > before, "une récompense rend l'action plus probable")


func _test_starvation() -> void:
	print("Famine (aucun fruit) :")
	var w := WorldSim.new(5)
	w.foods.clear()
	w.trees = PackedFloat32Array()   # plus aucun fruit ne tombe
	var c := w.creatures[0]
	var t := 0.0
	while c.alive and t < 4.0 * 3600.0:
		w.tick(STEP)
		t += STEP
	print("    %s" % c.last_event)
	_check(not c.alive and c.death_cause in ["de faim", "de soif"], "sans nourriture, elle meurt de faim ou de soif")
	_check(t > 0.3 * 3600.0, "elle tient un moment sur ses réserves")


func _test_full_life() -> void:
	print("Vie complète, sans joueur :")
	var w := WorldSim.new(42)
	var c := w.creatures[0]
	var t := 0.0
	var start := Time.get_ticks_msec()
	var health_3h := 0.0
	var stages := {}
	var hunger_sum := 0.0
	var n := 0
	while c.alive and t < 14.0 * 3600.0:
		w.tick(STEP)
		t += STEP
		stages[c.stage] = true
		hunger_sum += c.drives()[0]
		n += 1
		if health_3h == 0.0 and t >= 3.0 * 3600.0:
			health_3h = c.heart_health()
	var ms := Time.get_ticks_msec() - start
	print("    %s Repas : %d, siestes : %d, faim moyenne : %.2f, coeur à 3 h : %.2f" % [c.last_event, c.meals, c.naps, hunger_sum / n, health_3h])
	print("    %d pas simulés en %d ms (%.1f µs par pas)" % [n, ms, 1000.0 * ms / n])
	_check(health_3h > 0.8, "en bonne santé à 3 h sans aide du joueur")
	_check(stages.size() == 5, "elle traverse les 5 stades de vie")
	_check(not c.alive and c.death_cause == "de vieillesse", "elle meurt de vieillesse")
	_check(t > 9.0 * 3600.0 and t < 11.5 * 3600.0, "durée de vie autour de 10 h")
