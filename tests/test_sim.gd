extends SceneTree
## Tests de la simulation, sans affichage.
## Lancer : godot --headless --script res://tests/test_sim.gd

const STEP := 0.2
var _failures := 0


func _init() -> void:
	_test_genome_file()
	_test_cross_and_mutation()
	_test_stage_expression()
	_test_instincts_and_reinforcement()
	_test_starvation()
	_test_learns_seeds()
	_test_avoids_berries()
	_test_full_life()
	print("RÉSULTAT : %s" % ("OK" if _failures == 0 else "%d échec(s)" % _failures))
	quit(_failures)


func _check(cond: bool, msg: String) -> void:
	if cond:
		print("  ok    ", msg)
	else:
		print("  ÉCHEC ", msg)
		_failures += 1


func _run(w: WorldSim, hours: float) -> float:
	var c := w.creatures[0]
	var t := 0.0
	while c.alive and t < hours * 3600.0:
		w.tick(STEP)
		t += STEP
	return t


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


func _test_instincts_and_reinforcement() -> void:
	print("Cerveau :")
	var c := CreatureSim.new("Test", Genome.starter(), 100.0, Gene.Sex.FEMALE)
	var b := c.brain
	var fruit := ObjectCatalog.categories.find("fruit")
	var graine := ObjectCatalog.categories.find("graine")
	_check(b.weight("Faim", fruit, Brain.Verb.MANGER) > 0.5, "instinct : manger un fruit quand on a faim")
	_check(absf(b.weight("Faim", graine, Brain.Verb.MANGER)) < 0.01, "aucun savoir inné sur les graines")
	var rng := RandomNumberGenerator.new()
	rng.seed = 2
	b.drives.fill(0.0)
	b.drives[Brain.DRIVE_NAMES.find("Ennui")] = 0.8
	b.vision.fill(0.0)
	b.vision[ObjectCatalog.categories.find("pierre")] = 1.0
	var allowed: Array[bool] = []
	allowed.resize(Brain.VERB_COUNT)
	allowed.fill(true)
	b.decide(rng, allowed)
	var v := b.verb
	var cat := b.attention
	var before := b.weight("Ennui", cat, v)
	b.reinforce(-1.0)
	_check(b.weight("Ennui", cat, v) < before, "une punition affaiblit la connexion utilisée")
	var after_punish := b.weight("Ennui", cat, v)
	for i in 3000:
		b.relax(1.0, false)
	_check(b.weight("Ennui", cat, v) > after_punish, "le court terme revient vers le long terme (oubli)")


func _test_starvation() -> void:
	print("Famine (aucune nourriture) :")
	var w := WorldSim.new(5, "vide")
	_run(w, 4.0)
	var c := w.creatures[0]
	print("    %s" % c.last_event)
	_check(not c.alive and c.death_cause in ["de faim", "de soif"], "sans nourriture, elle meurt de faim ou de soif")


func _test_learns_seeds() -> void:
	print("Critère phase 2 : découvrir seule une nourriture inconnue (graines) :")
	var w := WorldSim.new(21, "graines")
	var c := w.creatures[0]
	_run(w, 3.0)
	var graine := ObjectCatalog.categories.find("graine")
	var wgt := c.brain.weight("Faim", graine, Brain.Verb.MANGER)
	print("    graines mangées : %d, poids faim×graine→manger : %.2f, vivante : %s" % [c.eaten.get("graine", 0), wgt, c.alive])
	_check(c.alive, "elle survit 3 h avec uniquement des graines")
	_check(c.eaten.get("graine", 0) >= 30, "elle mange régulièrement des graines")
	_check(wgt > 0.5, "elle a appris : faim + graine -> manger")


func _test_avoids_berries() -> void:
	print("Apprendre à éviter les baies toxiques :")
	var w := WorldSim.new(8)
	var c := w.creatures[0]
	_run(w, 3.0)
	var baie := ObjectCatalog.categories.find("baie")
	var wgt := c.brain.weight("Faim", baie, Brain.Verb.MANGER)
	print("    repas : %s, poids faim×baie→manger : %.2f" % [c.eaten, wgt])
	_check(c.alive, "elle est vivante à 3 h")
	_check(c.eaten.get("baie", 0) < c.eaten.get("fruit", 0) / 5, "elle mange bien moins de baies que de fruits")


func _test_full_life() -> void:
	print("Vie complète, sans joueur :")
	var w := WorldSim.new(42)
	var c := w.creatures[0]
	var start := Time.get_ticks_msec()
	var t := 0.0
	var stages := {}
	var health_3h := 0.0
	var n := 0
	while c.alive and t < 14.0 * 3600.0:
		w.tick(STEP)
		t += STEP
		n += 1
		stages[c.stage] = true
		if health_3h == 0.0 and t >= 3.0 * 3600.0:
			health_3h = c.heart_health()
	var ms := Time.get_ticks_msec() - start
	print("    %s Repas : %s, siestes : %d, coeur à 3 h : %.2f" % [c.last_event, c.eaten, c.naps, health_3h])
	print("    %d pas simulés en %d ms (%.1f µs par pas)" % [n, ms, 1000.0 * ms / n])
	_check(health_3h > 0.8, "en bonne santé à 3 h sans aide du joueur")
	_check(stages.size() == 5, "elle traverse les 5 stades de vie")
	_check(not c.alive and c.death_cause == "de vieillesse", "elle meurt de vieillesse")
	_check(t > 9.0 * 3600.0 and t < 11.5 * 3600.0, "durée de vie autour de 10 h")
