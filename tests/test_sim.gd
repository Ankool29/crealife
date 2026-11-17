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
	_test_save_load()
	_test_generations()
	_test_language()
	_test_appearance_genes()
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


func _test_save_load() -> void:
	print("Sauvegarde :")
	var w := WorldSim.new(9, "normal", 2)
	for i in 3000:
		w.tick(STEP)
	var text := JSON.stringify(w.to_dict())
	var w2 := WorldSim.from_dict(JSON.parse_string(text))
	var a := w.creatures[0]
	var b := w2.creatures[0]
	_check(w2.creatures.size() == w.creatures.size() and w2.objects.size() == w.objects.size(),
		"créatures et objets rechargés")
	_check(a.creature_name == b.creature_name and absf(a.age - b.age) < 0.01 and absf(a.hue - b.hue) < 0.0001,
		"identité, âge et couleurs conservés")
	var fruit := ObjectCatalog.categories.find("fruit")
	_check(absf(a.brain.weight("Faim", fruit, Brain.Verb.MANGER) - b.brain.weight("Faim", fruit, Brain.Verb.MANGER)) < 0.001,
		"ce que le cerveau a appris est conservé")
	_check(absf(a.level("Glucose") - b.level("Glucose")) < 0.001, "la chimie est conservée")
	print("    taille de la sauvegarde : %d Ko" % (text.length() / 1024))


func _test_generations() -> void:
	print("Critère phase 3 : trois générations viables :")
	var w := WorldSim.new(12, "normal", 2)
	for c in w.creatures:
		c.age = 2.5 * 3600.0          # les fondateurs commencent adultes
	var t := 0.0
	var max_pop := 0
	var start := Time.get_ticks_msec()
	while t < 10.0 * 3600.0:
		w.tick(STEP)
		t += STEP
		max_pop = maxi(max_pop, w.alive_count() + w._eggs.size())
		var max_gen := 0
		for h in w.history:
			max_gen = maxi(max_gen, int(h.generation))
		if max_gen >= 3 and t > 1.0 * 3600.0:
			var g3_alive := false
			for c in w.creatures:
				if c.generation >= 3 and c.alive and c.age > 1800.0:
					g3_alive = true
			if g3_alive:
				break
	var gens := {}
	for h in w.history:
		gens[int(h.generation)] = gens.get(int(h.generation), 0) + 1
	print("    après %s : créatures par génération %s, population max %d (%d s de calcul)" % [_hm(t), gens, max_pop, (Time.get_ticks_msec() - start) / 1000])
	_check(gens.get(2, 0) >= 1, "des enfants naissent")
	_check(gens.get(3, 0) >= 1, "une troisième génération naît")
	var g3_ok := false
	for c in w.creatures:
		if c.generation >= 3 and c.alive and c.age > 1800.0:
			g3_ok = true
	_check(g3_ok, "un membre de la 3e génération vit plus de 30 min")
	_check(max_pop <= WorldSim.MAX_POPULATION, "la population reste plafonnée à %d" % WorldSim.MAX_POPULATION)


func _test_language() -> void:
	print("Critère phase 4 : le langage :")
	# 1. Apprendre un nom en regardant l'objet
	var w := WorldSim.new(41, "vide")
	var c := w.creatures[0]
	var jouet := ObjectCatalog.categories.find("jouet")
	_check(c.language.pronounce("nom", jouet) != "jouet", "au début elle babille (« %s »)" % c.language.pronounce("nom", jouet))
	var t := 0.0
	while t < 600.0:
		w.objects.filter(func(o): return o.type_name == "balle").map(func(o): o.x = c.x + 40.0)
		if w.objects.filter(func(o): return o.type_name == "balle").is_empty():
			w.add_object("balle", c.x + 40.0)
		if int(t / STEP) % 75 == 0:
			w.say("balle", c)
		w.tick(STEP)
		t += STEP
	print("    connaissance de « jouet » après 10 min de leçons : %.2f, dit « %s »" % [c.language.nouns[jouet], c.language.pronounce("nom", jouet)])
	_check(c.language.nouns[jouet] > 0.8, "elle apprend un nom en voyant l'objet")
	_check(c.language.pronounce("nom", jouet) == "jouet", "elle prononce correctement un mot bien appris")
	_check(c.language.nouns[ObjectCatalog.categories.find("fruit")] < 0.05, "elle n'apprend pas les mots qu'on ne lui dit pas")

	# 2. Obéir à un ordre (même monde, avec et sans ordres)
	var pushes := []
	for ordered in [false, true]:
		var w2 := WorldSim.new(43, "vide")
		var c2 := w2.creatures[0]
		c2.language.verbs[Brain.Verb.POUSSER] = 1.0
		c2.language.nouns[jouet] = 1.0
		w2.add_object("balle", c2.x + 150.0)
		w2.add_object("pierre", c2.x - 150.0)
		var n := 0
		t = 0.0
		while t < 1200.0:
			if int(t / STEP) % 150 == 0:
				for o in w2.objects:     # la balle reste à portée de vue
					if o.type_name == "balle" and o.holder == null:
						o.x = clampf(c2.x + 200.0, 100.0, w2.width - 100.0)
				if ordered:
					w2.say("pousse la balle", c2)
			w2.tick(STEP)
			t += STEP
			if c2.acted and c2.brain.verb == Brain.Verb.POUSSER and c2.target is WorldObject and c2.target.type_name == "balle":
				n += 1
		pushes.append(n)
	print("    balle poussée en 20 min : %d fois sans ordre, %d fois avec l'ordre « pousse la balle »" % pushes)
	_check(pushes[1] >= 2 * pushes[0] + 5, "elle obéit à un ordre qu'elle comprend")

	# 3. Transmission entre créatures
	var w3 := WorldSim.new(47, "vide", 2)
	var a := w3.creatures[0]
	var b := w3.creatures[1]
	a.language.nouns.fill(1.0)
	for i in 30:
		a._act_on_creature(b, Brain.Verb.PARLER, w3)
	var learnt := 0
	for k in b.language.nouns:
		if k > 0.3:
			learnt += 1
	print("    après 30 échanges, %s connaît %d noms appris de %s (dernière phrase : « %s »)" % [b.creature_name, learnt, a.creature_name, a.language.speech])
	_check(learnt >= 4, "les mots se transmettent en parlant")

	# 5. L'âge : les enfants apprennent plus vite que les adultes, les vieux oublient
	var gains := []
	for hours in [1.0, 4.0]:
		var w5 := WorldSim.new(51, "vide")
		var c5 := w5.creatures[0]
		c5.age = hours * 3600.0
		w5.tick(STEP)
		var b5 := w5.add_object("balle", c5.x + 30.0)
		c5.show_thing(b5)
		w5.say("balle", c5)
		gains.append(c5.language.nouns[jouet])
	print("    une leçon : enfant %.2f, adulte %.2f" % gains)
	_check(gains[0] > gains[1] * 1.4, "un enfant apprend plus vite qu'un adulte")
	var w6 := WorldSim.new(53, "vide")
	var c6 := w6.creatures[0]
	c6.age = 8.2 * 3600.0
	w6.tick(STEP)
	c6.language.nouns[jouet] = 1.0
	c6.language.nouns[0] = 1.0
	t = 0.0
	while t < 3600.0:
		if int(t / STEP) % 1500 == 0:
			c6.language.used("nom", 0)     # « fruit » est entretenu, « jouet » non
		c6.tick(STEP, w6, w6.rng)
		t += STEP
	print("    vieille, après 1 h : mot entretenu %.2f, mot oublié %.2f" % [c6.language.nouns[0], c6.language.nouns[jouet]])
	_check(c6.language.nouns[0] > 0.99 and c6.language.nouns[jouet] < 0.95, "les vieux oublient les mots qui ne servent plus")

	# 4. Sauvegarde
	var w4 := WorldSim.from_dict(JSON.parse_string(JSON.stringify(w3.to_dict())))
	_check(is_equal_approx(w4.creatures[1].language.nouns[jouet], b.language.nouns[jouet]), "le vocabulaire est sauvegardé")


func _test_appearance_genes() -> void:
	print("Silhouette génétique :")
	var w := WorldSim.new(5, "normal", 10)
	var tails := {}
	var ants := {}
	for c in w.creatures:
		tails[c.tail] = true
		ants[c.antennae] = true
	print("    variantes de queue : %s, d'antennes : %s" % [tails.keys(), ants.keys()])
	_check(tails.size() >= 2 and ants.size() >= 2, "les fondateurs ont des silhouettes variées")


func _hm(t: float) -> String:
	var m := int(t / 60.0)
	return "%d h %02d" % [m / 60, m % 60]
