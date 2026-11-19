class_name Genome
extends RefCounted
## Génome : liste ordonnée de gènes typés. Seule chose transmise d'une
## génération à l'autre.

const FORMAT := "crealife-genome"
const VERSION := 2
const STARTER_PATH := "res://data/genomes/souche_depart.json"

var genes: Array[Gene] = []
var genome_name := ""


static func load_file(path: String) -> Genome:
	var res := load(path) as JSON
	if res == null:
		push_error("Génome introuvable : " + path)
		return null
	return from_dict(res.data)


static func starter() -> Genome:
	return load_file(STARTER_PATH)


static func from_dict(d: Dictionary) -> Genome:
	if str(d.get("format", "")) != FORMAT:
		push_error("Ce fichier n'est pas un génome CreaLife.")
		return null
	var g := Genome.new()
	g.genome_name = str(d.get("name", ""))
	for gd in d.get("genes", []):
		var gene := Gene.from_dict(gd)
		if gene != null:
			g.genes.append(gene)
	return g


func to_dict() -> Dictionary:
	var list := []
	for gene in genes:
		list.append(gene.to_dict())
	return {"format": FORMAT, "version": VERSION, "name": genome_name, "genes": list}


func copy() -> Genome:
	var g := Genome.new()
	g.genome_name = genome_name
	for gene in genes:
		g.genes.append(gene.copy())
	return g


func expressed(stage: int, sex: int) -> Array[Gene]:
	var out: Array[Gene] = []
	for gene in genes:
		if gene.is_expressed(stage, sex):
			out.append(gene)
	return out


## Premier gène d'un type dont le paramètre key vaut value (ex. apparence du corps).
func find(type: int, key: String, value: String) -> Gene:
	for gene in genes:
		if gene.type == type and str(gene.params.get(key, "")) == value:
			return gene
	return null


func max_id() -> int:
	var m := 0
	for gene in genes:
		m = maxi(m, gene.id)
	return m


## Mutations sur place : paramètres, et rares erreurs de copie (duplication, perte).
func mutate(rng: RandomNumberGenerator, rate: float) -> void:
	var out: Array[Gene] = []
	var next_id := max_id() + 1
	for gene in genes:
		if gene.can_delete and rng.randf() < rate * 0.02:
			continue                                          # gène perdu
		gene.mutate(rng, rate)
		out.append(gene)
		if gene.can_duplicate and rng.randf() < rate * 0.05:
			var twin := gene.copy()                           # gène dupliqué
			twin.id = next_id
			next_id += 1
			out.append(twin)
	genes = out


## Croisement : gènes alignés par identifiant, pris par blocs chez l'un ou l'autre parent.
## Apparence : chaque trait vient de l'un ou l'autre parent, ou d'un mélange
## des deux (les teintes se mélangent sur le cercle des couleurs).
static func _blend_appearance(child: Gene, a: Gene, b: Gene, rng: RandomNumberGenerator) -> void:
	for key in Gene.ranges_for(Gene.Type.APPEARANCE):
		if not a.params.has(key) or not b.params.has(key):
			continue
		var va := float(a.params[key])
		var vb := float(b.params[key])
		var r := rng.randf()
		if r < 0.3:
			child.params[key] = va
		elif r < 0.6:
			child.params[key] = vb
		else:
			var t := rng.randf_range(0.25, 0.75)
			if key in ["hue", "hue2", "hue3", "glow"]:
				var d := fposmod(vb - va + 0.5, 1.0) - 0.5     # plus court chemin sur le cercle
				child.params[key] = fposmod(va + d * t, 1.0)
			else:
				child.params[key] = lerpf(va, vb, t)


## Sensibilité à l'herbe à chat (gène « gout ») : un allèle de chaque parent,
## comme pour le pelage (mendélien, sensibilité dominante).
static func _cross_catnip(child: Gene, a: Gene, b: Gene, rng: RandomNumberGenerator) -> void:
	var pa := "herbe1" if rng.randf() < 0.5 else "herbe2"
	var pb := "herbe1" if rng.randf() < 0.5 else "herbe2"
	child.params.herbe1 = float(a.params.get(pa, 1.0))
	child.params.herbe2 = float(b.params.get(pb, 0.0))


static func cross(a: Genome, b: Genome, rng: RandomNumberGenerator, mutation_rate: float = 0.02, crossover: float = 0.1) -> Genome:
	var by_id_b := {}
	for gene in b.genes:
		by_id_b[gene.id] = gene
	var by_id_a := {}
	for gene in a.genes:
		by_id_a[gene.id] = gene
	var child := Genome.new()
	child.genome_name = a.genome_name
	var from_a := rng.randf() < 0.5
	for gene in a.genes:
		if rng.randf() < crossover:
			from_a = not from_a
		# même numéro mais autre gène (génomes de versions différentes) : on garde a
		var same: bool = by_id_b.has(gene.id) and by_id_b[gene.id].type == gene.type \
			and str(by_id_b[gene.id].params.get("part", by_id_b[gene.id].params.get("lobe", ""))) \
				== str(gene.params.get("part", gene.params.get("lobe", "")))
		var pick: Gene = gene if from_a or not same else by_id_b[gene.id]
		var copy := pick.copy()
		if gene.type == Gene.Type.APPEARANCE and same:
			if str(gene.params.get("part", "")) == "pelage":
				CatCoat.cross(copy, gene, by_id_b[gene.id], rng)     # a = mère, b = père
			else:
				_blend_appearance(copy, gene, by_id_b[gene.id], rng)
		elif gene.type == Gene.Type.LOBE and same and str(gene.params.get("lobe", "")) == "gout":
			_cross_catnip(copy, gene, by_id_b[gene.id], rng)
		child.genes.append(copy)
	for gene in b.genes:                                     # gènes propres au parent b
		if not by_id_a.has(gene.id) and rng.randf() < 0.5:
			child.genes.append(gene.copy())
	child.mutate(rng, mutation_rate)
	return child
