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
	_test_full_life()
	_test_save_load()
	_test_save_safety()
	_test_generations()
	_test_language()
	_test_appearance_genes()
	_test_family_life()
	_test_litter()
	_test_adoption()
	_test_food()
	_test_character()
	_test_zones_and_climate()
	_test_cat_genetics()
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
	var croq := ObjectCatalog.categories.find("croquettes")
	var patee := ObjectCatalog.categories.find("pâtée")
	_check(b.weight("Faim", croq, Brain.Verb.MANGER) > 0.5, "instinct : manger des croquettes quand on a faim")
	_check(absf(b.weight("Faim", patee, Brain.Verb.MANGER)) < 0.01, "aucun savoir inné sur la pâtée")
	var rng := RandomNumberGenerator.new()
	rng.seed = 2
	b.drives.fill(0.0)
	b.drives[Brain.DRIVE_NAMES.find("Ennui")] = 0.8
	b.vision.fill(0.0)
	b.vision[ObjectCatalog.categories.find("eau")] = 1.0
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
	print("Critère phase 2 : découvrir seule une nourriture inconnue (pâtée) :")
	var w := WorldSim.new(21, "graines")
	var c := w.creatures[0]
	c.age = 1.0 * 3600.0               # sevrée : elle a vraiment faim entre deux repas
	_run(w, 3.0)
	var patee := ObjectCatalog.categories.find("pâtée")
	# la pâtée calme la faim et un peu la soif : elle peut l'apprendre par l'une ou l'autre
	var wgt := maxf(c.brain.weight("Faim", patee, Brain.Verb.MANGER), c.brain.weight("Soif", patee, Brain.Verb.MANGER))
	print("    pâtées mangées : %d, poids faim ou soif×pâtée→manger : %.2f, vivante : %s" % [c.eaten.get("patee", 0), wgt, c.alive])
	_check(c.alive, "elle survit 3 h avec uniquement de la pâtée")
	_check(c.eaten.get("patee", 0) >= 30, "elle mange régulièrement de la pâtée")
	_check(wgt > 0.5, "elle a appris : besoin + pâtée -> manger")


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


func _test_save_safety() -> void:
	print("Sauvegarde sûre :")
	var path := "user://test_sauvegarde.json"
	for ext in ["", ".bak", ".tmp", ".abimee"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path + ext))
	var w := WorldSim.new(3, "normal", 3)
	_run(w, 0.2)
	var text := JSON.stringify(w.to_dict())
	var per := text.length() / 1024.0 / w.creatures.size()
	print("    taille : %d Ko, %.0f Ko par chat" % [text.length() / 1024, per])
	_check(per < 40.0, "sauvegarde compacte (moins de 40 Ko par chat ; environ 100 avant)")
	_check(SaveStore.save_now(w, path), "écriture via un fichier temporaire")
	var r := SaveStore.load_world(path)
	_check(r[0] != null and r[1] == "" and r[0].alive_count() == w.alive_count(), "relecture normale")
	var c0: CreatureSim = w.creatures[0]
	var c1: CreatureSim = r[0].creatures[0]
	_check(absf(c0.brain.stw[5] - c1.brain.stw[5]) < 0.001, "les cerveaux reviennent à l'identique (à 0,001 près)")
	SaveStore.save_now(w, path)                      # la précédente devient la copie de secours
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text.substr(0, text.length() / 2))   # appli tuée en pleine écriture
	f.close()
	r = SaveStore.load_world(path)
	_check(r[0] != null and r[1].contains("secours"), "sauvegarde coupée : reprise depuis la copie de secours")
	for ext in [".bak", ".tmp"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path + ext))
	f = FileAccess.open(path, FileAccess.WRITE)
	f.store_string("{\"creatures\": []}")
	f.close()
	r = SaveStore.load_world(path)
	_check(r[0] == null and FileAccess.file_exists(path + ".abimee") and not FileAccess.file_exists(path),
		"illisible : mise de côté, jamais écrasée")
	var d: Dictionary = JSON.parse_string(text)
	d.creatures[0].erase("genome")
	_check(not SaveStore.valid(d), "une donnée manquante est détectée avant le chargement")
	for ext in ["", ".bak", ".tmp", ".abimee"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path + ext))


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
	var fruit := ObjectCatalog.categories.find("croquettes")
	_check(absf(a.brain.weight("Faim", fruit, Brain.Verb.MANGER) - b.brain.weight("Faim", fruit, Brain.Verb.MANGER)) < 0.001,
		"ce que le cerveau a appris est conservé")
	_check(absf(a.level("Glucose") - b.level("Glucose")) < 0.001, "la chimie est conservée")
	print("    taille de la sauvegarde : %d Ko" % (text.length() / 1024))


func _test_generations() -> void:
	print("Critère phase 3 : trois générations viables :")
	# Les rencontres dépendent du hasard (la maison est grande) : jusqu'à 3 mondes
	for seed_v in [12, 13, 14]:
		if _one_lineage(seed_v, seed_v == 14):
			return


## Fait vivre un couple 10 h ; vrai si une 3e génération dure. Les vérifications
## ne sont faites que sur la dernière tentative, ou dès qu'elle réussit.
func _one_lineage(seed_v: int, last: bool) -> bool:
	var w := WorldSim.new(seed_v, "normal", 2)
	for c in w.creatures:
		c.age = 2.5 * 3600.0          # les fondateurs commencent adultes
	var t := 0.0
	var max_pop := 0
	var start := Time.get_ticks_msec()
	var g3_ok := false
	while t < 10.0 * 3600.0:
		w.tick(STEP)
		t += STEP
		max_pop = maxi(max_pop, w.alive_count() + w._eggs.size())
		if t > 1.0 * 3600.0 and int(t / STEP) % 50 == 0:
			for c in w.creatures:
				if c.generation >= 3 and c.alive and c.age > 1800.0:
					g3_ok = true
			if g3_ok:
				break
	var gens := {}
	for h in w.history:
		gens[int(h.generation)] = gens.get(int(h.generation), 0) + 1
	print("    monde %d, après %s : créatures par génération %s, population max %d (%d s de calcul)" % [seed_v, _hm(t), gens, max_pop, (Time.get_ticks_msec() - start) / 1000])
	if not g3_ok and not last:
		return false
	_check(gens.get(2, 0) >= 1, "des enfants naissent")
	_check(gens.get(3, 0) >= 1, "une troisième génération naît")
	_check(g3_ok, "un membre de la 3e génération vit plus de 30 min")
	_check(max_pop <= WorldSim.MAX_POPULATION, "la population reste plafonnée à %d" % WorldSim.MAX_POPULATION)
	return true


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
	_check(c.language.nouns[ObjectCatalog.categories.find("pâtée")] < 0.05, "elle n'apprend pas les mots qu'on ne lui dit pas")

	# 2. Obéir à un ordre (même monde, avec et sans ordres)
	var pushes := [0, 0]
	for run in 6:        # 3 mondes, sans puis avec ordres
		var ordered := run % 2 == 1
		var w2 := WorldSim.new(43 + run / 2, "vide")
		var c2 := w2.creatures[0]
		c2.energy = 0.5                      # caractère neutre : seul l'ordre change
		c2.sociable = 0.5
		c2.language.verbs[Brain.Verb.POUSSER] = 1.0
		c2.language.nouns[jouet] = 1.0
		w2.add_object("balle", c2.x + 150.0)
		w2.add_object("eau", c2.x - 150.0)
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
		pushes[1 if ordered else 0] += n
	print("    balle poussée en 3 × 20 min : %d fois sans ordre, %d fois avec l'ordre « pousse la balle »" % pushes)
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


func _test_litter() -> void:
	print("Portées et allaitement :")
	var w := WorldSim.new(31, "normal", 2)
	var mum: CreatureSim = null
	var dad: CreatureSim = null
	for c in w.creatures:
		c.age = 3.0 * 3600.0
		if c.sex == Gene.Sex.FEMALE:
			mum = c
		else:
			dad = c
	if mum == null or dad == null:
		_check(false, "un couple pour le test")
		return
	mum.pregnant_time = CreatureSim.GESTATION - 1.0
	mum.litter_size = 3
	mum._father_genome = dad.genome
	mum._father_name = dad.creature_name
	_run(w, 0.001)
	var kits: Array = w.creatures.filter(func(c): return c.mother == mum.creature_name)
	_check(kits.size() == 3, "elle met bas 3 chatons à la fois")
	var coats := {}
	for k in kits:
		coats[k.coat.get("name", "") + str(k.body_size())] = true
	_check(coats.size() >= 2, "les chatons ne sont pas des copies")
	var nursed := 0.0
	var hunger := 0.0
	var near := 0.0
	var n := 0
	var t := 0.0
	while t < 1500.0:
		w.tick(STEP)
		t += STEP
		if mum.nursing > 0.0:
			nursed += STEP
		for k in kits:
			if k.alive:
				hunger += k.level("Faim")
				near += 1.0 if absf(k.x - mum.x) < 300.0 else 0.0
				n += 1
	print("    25 min : allaitement %d s, faim moyenne des chatons %.2f, près de la mère %d %%" % [nursed, hunger / n, 100.0 * near / n])
	_check(kits.all(func(k): return k.alive), "les chatons survivent")
	_check(nursed > 60.0, "la mère allaite")
	_check(near / n > 0.5, "les bébés restent près de leur mère")


func _test_adoption() -> void:
	print("Demandes d'adoption :")
	var w := WorldSim.new(41, "normal", 4)
	for c in w.creatures:
		c.age = 3.0 * 3600.0
	_run(w, 0.75)
	_check(not w.adoption.requests.is_empty(), "une famille demande un chat")
	var r: Dictionary = w.adoption.requests[0]
	print("    " + str(r.family) + " cherche " + Adoption.describe(r))
	var pool := Adoption.adoptable(w)
	pool.sort_custom(func(a, b): return Adoption.score(r, a) > Adoption.score(r, b))
	var best: CreatureSim = pool[0]
	var before := w.alive_count()
	var saved := WorldSim.from_dict(JSON.parse_string(JSON.stringify(w.to_dict())))
	_check(saved.adoption.requests.size() == w.adoption.requests.size(), "les demandes sont sauvegardées")
	w.adoption.adopt(w, r, best)
	_check(w.alive_count() == before - 1 and not best in w.creatures, "le chat adopté quitte la maison")
	_check(w.adoption.reputation > 0, "la réputation monte (%d)" % w.adoption.reputation)
	var h: Array = w.history.filter(func(x): return x.uid == best.uid)
	_check(h.size() == 1 and str(h[0].cause).begins_with("adopté"), "l'arbre garde la trace de l'adoption")
	var white := {"kind": "pelage", "value": "blanc"}
	var cw := w.creatures[0]
	cw.coat["white"] = 1.0
	_check(Adoption.meets(white, cw), "un chat blanc correspond au critère « tout blanc »")


func _test_food() -> void:
	print("Nourriture de chat :")
	var w := WorldSim.new(77, "normal", 3)
	for c in w.creatures:
		c.age = 3.0 * 3600.0
	_run(w, 1.0)
	var croq := 0
	for c in w.creatures:
		croq += c.eaten.get("croquettes", 0)
	_check(croq >= 10, "le distributeur nourrit la maison (%d croquettes en 1 h)" % croq)
	_check(w.creatures.all(func(c): return c.alive), "tout le monde est en vie")
	# pâtée : stock limité qui revient
	var stock := w.patee_stock
	w.drop_patee(w.creatures[0].x)
	_check(w.patee_stock == stock - 1 and w.count_of("patee") >= 1, "le joueur donne de la pâtée (stock %d)" % w.patee_stock)
	w.patee_stock = 0
	_check(not w.drop_patee(100.0), "plus de pâtée quand le stock est vide")
	# chasse : une bonne chasseuse attrape une souris et la mange
	var hunter := w.creatures[0]
	hunter.hunting = 1.0
	var caught := 0
	for i in 40:
		var m := w.add_object("souris", hunter.x + 60.0)
		hunter._act_on(m, Brain.Verb.FRAPPER, w)
		if m.dead:
			caught += 1
		w.remove_object(m)
	_check(caught >= 25, "une bonne chasseuse attrape souvent (%d/40)" % caught)
	var lazy := w.creatures[1]
	lazy.hunting = 0.0
	var caught2 := 0
	for i in 40:
		var m := w.add_object("souris", lazy.x + 60.0)
		lazy._act_on(m, Brain.Verb.FRAPPER, w)
		if m.dead:
			caught2 += 1
		w.remove_object(m)
	_check(caught2 < caught, "une piètre chasseuse rate plus souvent (%d/40)" % caught2)
	var prey := w.add_object("souris", hunter.x + 60.0)
	prey.dead = true
	var before: int = hunter.eaten.get("souris", 0)
	hunter._act_on(prey, Brain.Verb.MANGER, w)
	_check(not prey in w.objects and hunter.eaten.get("souris", 0) == before + 1, "une souris attrapée se mange")
	# goûts : la préférence vient du plaisir pris
	hunter.taste = {"patee": 0.95, "croquettes": 0.1, "proie": 0.2}
	hunter.eaten["patee"] = 1
	_check(hunter.favorite_food() == "patee", "elle préfère ce qu'elle aime le plus parmi ce qu'elle a goûté")
	hunter._taste("patee")
	var r_patee := hunter._last_pleasure
	hunter._taste("croquettes")
	_check(r_patee > hunter._last_pleasure * 3.0, "la pâtée lui fait bien plus plaisir que les croquettes")


func _test_character() -> void:
	print("Caractères :")
	var w := WorldSim.new(83, "vide", 2)
	var a := w.creatures[0]
	var b := w.creatures[1]
	for c in w.creatures:
		c.age = 3.0 * 3600.0
	# peur : un coup effraie bien plus un peureux qu'un audacieux
	a.boldness = 0.05
	b.boldness = 0.95
	var pid := Chemicals.id_of("Peur")
	a.biochem.conc[pid] = 0.0
	b.biochem.conc[pid] = 0.0
	a.frighten(0.4)
	b.frighten(0.4)
	_check(a.level("Peur") > 3.0 * b.level("Peur"), "un coup effraie plus un peureux (%.2f) qu'un audacieux (%.2f)" % [a.level("Peur"), b.level("Peur")])
	# un peureux frappé s'enfuit loin de son agresseur
	a.x = 1500.0
	b.x = 1560.0
	b._act_on_creature(a, Brain.Verb.FRAPPER, w)
	a.biochem.conc[pid] = 0.8
	var fled := false
	var far := 0.0
	for i in 150:
		w.tick(STEP)
		fled = fled or a.brain.verb == Brain.Verb.FUIR
		far = maxf(far, absf(a.x - b.x))
	_check(fled and far > 200.0, "un chat effrayé s'enfuit loin de celui qui l'a frappé (%d px)" % int(far))
	_check(a.affinity_with(b) < 0.0 and b.affinity_with(a) < 0.0, "les coups font des rivaux")
	# amitié : se parler rapproche
	var w2 := WorldSim.new(84, "vide", 2)
	var c := w2.creatures[0]
	var d := w2.creatures[1]
	for i in 10:
		c._act_on_creature(d, Brain.Verb.PARLER, w2)
	_check(c.affinity_with(d) > 0.3, "se parler crée une amitié (%.2f)" % c.affinity_with(d))
	# indépendant : trop de câlins, coup de patte ; câlin : il ronronne
	c.sociable = 0.1
	var swat := false
	for i in 6:
		c.caress()
		swat = swat or c.last_event.contains("coup de patte")
	_check(swat, "un chat indépendant se lasse des câlins")
	d.sociable = 0.9
	d.caress()
	_check(d.language.speech == "rrrr", "un chat câlin ronronne")
	_check("câline" in d.personality() or "câlin" in d.personality(), "son caractère s'affiche (%s)" % ", ".join(d.personality()))
	# sociabilité : les indépendants se sentent moins seuls
	var lonely := [0.0, 0.0]
	for run in 2:
		var w3 := WorldSim.new(85, "vide", 1)
		var e := w3.creatures[0]
		e.sociable = 0.9 if run == 1 else 0.1
		e.biochem.conc[Chemicals.id_of("Solitude")] = 0.0
		for i in 1500:
			w3.tick(STEP)
		lonely[run] = e.level("Solitude")
	_check(lonely[1] > lonely[0] * 2.0, "seuls, les sociables souffrent plus de solitude (%.2f contre %.2f)" % [lonely[1], lonely[0]])
	# bagarreur : il cherche querelle à un adulte de même sexe
	var w4 := WorldSim.new(86, "vide", 2)
	var f := w4.creatures[0]
	var g := w4.creatures[1]
	g.sex = f.sex
	for e in w4.creatures:
		e.age = 3.0 * 3600.0
		e.x = 1500.0 + (100.0 if e == g else 0.0)
	f.aggressive = 1.0
	var quarrel := false
	for i in 9000:
		w4.tick(STEP)
		g.x = f.x + 100.0
		quarrel = quarrel or g.affinity_with(f) < 0.0           # il s'est pris un coup
		if quarrel:
			break
	_check(quarrel, "un bagarreur cherche querelle")


func _test_family_life() -> void:
	print("Vie de famille :")
	# Mélange des couleurs : les enfants ne sont pas des copies d'un parent
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var a := Genome.starter()
	var b := Genome.starter()
	a.find(Gene.Type.APPEARANCE, "part", "corps").params.hue = 0.1
	b.find(Gene.Type.APPEARANCE, "part", "corps").params.hue = 0.3
	var mixed := 0
	for i in 40:
		var h := float(Genome.cross(a, b, rng, 0.0).find(Gene.Type.APPEARANCE, "part", "corps").params.hue)
		if h > 0.11 and h < 0.29:
			mixed += 1
	print("    teinte : %d enfants sur 40 ont une couleur intermédiaire" % mixed)
	_check(mixed >= 10, "les couleurs des parents se mélangent")
	a.find(Gene.Type.APPEARANCE, "part", "motif").params.spots = 0.9
	var spotted := 0
	for i in 40:
		if float(Genome.cross(a, b, rng, 0.0).find(Gene.Type.APPEARANCE, "part", "motif").params.spots) >= 0.2:
			spotted += 1
	print("    taches : %d enfants sur 40 en héritent d'un parent tacheté" % spotted)
	_check(spotted >= 15 and spotted <= 38, "les motifs se transmettent sans être systématiques")

	# Accouplements : un couple d'adultes ne fait pas que ça
	var w := WorldSim.new(61, "normal", 2)
	for c in w.creatures:
		c.age = 2.6 * 3600.0
	var tries := 0
	var mates := 0
	var t := 0.0
	var was_pregnant := false
	while t < 2.0 * 3600.0:
		w.tick(STEP)
		t += STEP
		for c in w.creatures:
			if c.generation == 1 and c.acted and c.brain.verb == Brain.Verb.ACCOUPLER:
				tries += 1
		var f := w.creatures[0] if w.creatures[0].sex == Gene.Sex.FEMALE else w.creatures[1]
		if f.pregnant_time >= 0.0 and not was_pregnant:
			mates += 1
		was_pregnant = f.pregnant_time >= 0.0
	print("    en 2 h d'âge adulte : %d tentatives, %d accouplements réussis" % [tries, mates])
	_check(mates >= 1 and mates <= 3, "ils s'accouplent, mais pas sans arrêt")
	_check(tries <= 40, "ils n'insistent pas en boucle")

	# Soins : un parent nourrit son petit affamé
	var w2 := WorldSim.new(67, "vide", 1)
	var mum := w2.creatures[0]
	mum.age = 3.0 * 3600.0
	w2.tick(STEP)
	var kid := w2.give_birth(mum.x + 300.0, Genome.starter(), mum.creature_name, "Papa", 2)
	kid.age = 0.6 * 3600.0              # sevré : on lui apporte à manger (un bébé, on l'allaite)
	var fed := false
	t = 0.0
	while t < 2400.0 and not fed:
		w2.tick(STEP)
		t += STEP
		for c in w2.creatures:
			if c != mum and c.alive:
				c.biochem.conc[Chemicals.id_of("Faim")] = maxf(c.level("Faim"), 0.7)
		if w2.count_of("croquettes") == 0:
			w2.add_object("croquettes", mum.x - 200.0)
		fed = mum.last_event.contains("apporte à manger")
	print("    %s : %s" % [mum.creature_name, mum.last_event])
	_check(fed, "un parent apporte à manger à son petit")


func _test_zones_and_climate() -> void:
	print("Critère phase 5 : zones et climat :")
	var w := WorldSim.new(71, "normal", 2)
	_check(w.zones.size() == 6 and w.zones[2].key == "jeux" and w.zones[-1].key == "jardin", "la maison (5 pièces) puis le jardin")
	_check(w.zone_at(w.creatures[0].x).key == "cuisine", "les fondateurs arrivent dans la cuisine")
	for c in w.creatures:               # pour le froid : dehors
		c.x = w.garden_x() + 600.0
	# Hiver : froid dehors, doux dedans, peu de fruits
	w.time = 3.0 * Climate.SEASON + 0.2 * Climate.DAY
	var outside := w.temperature_at(w.garden_x() + 500.0)
	var inside := w.temperature_at(300.0)
	print("    en hiver : %.0f °C au jardin, %.0f °C dans la salle (%s)" % [outside, inside, w.climate.describe(w.time)])
	_check(outside < 8.0 and inside > 15.0, "l'hiver est froid dehors et doux dans la salle")
	var froid := 0.0
	var t := 0.0
	while t < 1800.0:
		w.tick(STEP)
		t += STEP
		froid = maxf(froid, w.creatures[0].level("Froid"))
		if t < 600.0:
			for c in w.creatures:       # on les garde dehors un moment
				c.x = maxf(c.x, w.garden_x() + 300.0)
	print("    froid ressenti au plus fort : %.2f, toutes vivantes : %s" % [froid, w.alive_count() == 2])
	_check(froid > 0.2, "elles ont froid en hiver")
	_check(w.alive_count() == 2, "elles survivent à une demi-heure d'hiver")

	# Écran : les curieuses apprennent plus vite que les autres
	var learnt := [0.0, 0.0]
	for run in 4:
		var curious := run % 2 == 1
		var w2 := WorldSim.new(80 + run / 2, "normal", 1)
		var c := w2.creatures[0]
		c.curiosity = 0.95 if curious else 0.05
		var scr := w2._first("ecran")
		c.x = scr.x + 120.0
		t = 0.0
		while t < 300.0:
			c.target = scr                  # elle regarde l'écran (comme si on le lui montrait)
			c.brain.attention = ObjectCatalog.categories.find("machine")
			w2._tick_screen(STEP)
			t += STEP
		var k := 0.0
		for v in c.language.nouns:
			k += v
		learnt[1 if curious else 0] += k
	print("    5 min devant l'écran : vocabulaire %.1f (peu curieuse) contre %.1f (curieuse)" % learnt)
	_check(learnt[0] > 0.5 and learnt[1] > learnt[0] * 1.8, "l'écran apprend des mots, mieux aux curieuses")

	# Loisirs : les espiègles jouent plus (même monde, tempérament différent)
	var plays := [0, 0]
	for run in 4:
		var playful := run % 2 == 1
		var w3 := WorldSim.new(90 + run / 2, "normal", 1)
		var c3 := w3.creatures[0]
		c3.playfulness = 0.95 if playful else 0.05
		c3.curiosity = 0.0                  # sans aller voir l'écran : seul l'espièglerie change
		c3.hunting = 0.0                    # ni chasse, ni autre trait qui change
		c3.energy = 0.5
		c3.sociable = 0.5
		c3.x = w3.zones[2].x0 + 500.0
		t = 0.0
		while t < 3600.0:
			w3.tick(STEP)
			t += STEP
			if c3.acted and c3.target is WorldObject and c3.target.category == ObjectCatalog.categories.find("jouet"):
				plays[1 if playful else 0] += 1
	print("    1 h aux loisirs : %d jeux (peu espiègle) contre %d (espiègle)" % plays)
	_check(plays[1] > plays[0], "les espiègles jouent plus")

	# Sauvegarde d'avant les zones : le jardin est décalé, les zones ajoutées
	var old := w.to_dict()
	old.version = 1
	for od in old.objects:
		od.x = float(od.x) - w.garden_x()
	old.objects = old.objects.filter(func(od): return od.type in ["distributeur", "balle"] and float(od.x) >= 0.0)
	for cd in old.creatures:
		cd.x = float(cd.x) - w.garden_x()
	var w4 := WorldSim.from_dict(JSON.parse_string(JSON.stringify(old)))
	_check(is_equal_approx(w4._first("distributeur").x, w.machine_x) and is_equal_approx(w4.creatures[0].x, w.creatures[0].x)
		and w4._first("ecran") != null and w4._first("trampoline") != null,
		"une ancienne sauvegarde s'ouvre avec les nouvelles zones")


func _cat(alleles: Dictionary) -> Genome:
	var g := Genome.starter()
	var p := g.find(Gene.Type.APPEARANCE, "part", "pelage").params
	for k in alleles:
		p[k] = float(alleles[k])
	return g


func _coat(g: Genome, sex: int) -> Dictionary:
	return CatCoat.phenotype(g.find(Gene.Type.APPEARANCE, "part", "pelage").params,
		g.find(Gene.Type.APPEARANCE, "part", "morpho").params, sex)


func _test_cat_genetics() -> void:
	print("Chats : génétique du pelage :")
	var rng := RandomNumberGenerator.new()
	rng.seed = 21
	# Mère écaille de tortue (O/o) × père noir (o) : fils roux ou noirs, filles écaille ou noires
	var mum := _cat({"O1": 1, "O2": 0})
	var dad := _cat({"O1": 0})
	_check(_coat(mum, Gene.Sex.FEMALE).orange == 2, "une femelle O/o est écaille de tortue (%s)" % _coat(mum, Gene.Sex.FEMALE).name)
	var sons_red := 0
	var daughters := {0: 0, 1: 0, 2: 0}
	for i in 200:
		var kid := Genome.cross(mum, dad, rng, 0.0)
		if _coat(kid, Gene.Sex.MALE).orange == 1:
			sons_red += 1
		daughters[_coat(kid, Gene.Sex.FEMALE).orange] += 1
	print("    mère écaille × père noir : %d fils roux sur 200 ; filles : %d noires, %d écaille, %d rousses" % [
		sons_red, daughters[0], daughters[2], daughters[1]])
	_check(sons_red > 70 and sons_red < 130 and daughters[1] == 0 and daughters[2] > 70, "le roux est lié au chromosome X")
	# Père roux × mère noire : toutes les filles écaille, aucun fils roux
	var red_dad := _cat({"O1": 1})
	var black_mum := _cat({"O1": 0, "O2": 0})
	var tortie := 0
	var red_sons := 0
	for i in 100:
		var kid := Genome.cross(black_mum, red_dad, rng, 0.0)
		tortie += int(_coat(kid, Gene.Sex.FEMALE).orange == 2)
		red_sons += int(_coat(kid, Gene.Sex.MALE).orange == 1)
	_check(tortie == 100 and red_sons == 0, "père roux × mère noire : filles écaille, fils noirs")
	# Récessifs cachés : deux noirs porteurs de dilution et de colourpoint
	var a := _cat({"D1": 1, "D2": 0, "C1": 1, "C2": 0, "A1": 1, "A2": 1})
	var b := _cat({"D1": 0, "D2": 1, "C1": 0, "C2": 1, "A1": 1, "A2": 1})
	var blue := 0
	var siamese := 0
	for i in 400:
		var kid := Genome.cross(a, b, rng, 0.0)
		var ph := _coat(kid, Gene.Sex.MALE)
		blue += int(ph.dilute)
		siamese += int(ph.points)
	print("    deux noirs porteurs : %d%% de bleus, %d%% de siamois (attendu ≈ 25 %%) ; parents : %s" % [
		blue * 100 / 400, siamese * 100 / 400, _coat(a, Gene.Sex.MALE).name])
	_check(_coat(a, Gene.Sex.MALE).name == "noir" and absi(blue - 100) < 35 and absi(siamese - 100) < 35,
		"les récessifs réapparaissent chez un quart des petits")
	# Blanc aux yeux bleus : sourd, n'apprend pas les mots entendus
	var white := _cat({"W1": 1})
	white.find(Gene.Type.APPEARANCE, "part", "morpho").params.eye = 0.1
	var w := WorldSim.new(3, "vide", 0)
	var deaf := CreatureSim.new("Neige", white, 500.0, Gene.Sex.FEMALE)
	w.creatures.append(deaf)
	_check(deaf.coat.deaf and deaf.hear("pâtée", 1.0).is_empty(), "un chat blanc aux yeux bleus est sourd (%s)" % deaf.coat.name)
	# Variété des fondateurs
	var w2 := WorldSim.new(9, "normal", 10)
	var names := {}
	for c in w2.creatures:
		names[c.coat.name] = true
	print("    10 fondateurs : %s" % ", ".join(names.keys()))
	_check(names.size() >= 6, "des pelages variés")


func _hm(t: float) -> String:
	var m := int(t / 60.0)
	return "%d h %02d" % [m / 60, m % 60]
