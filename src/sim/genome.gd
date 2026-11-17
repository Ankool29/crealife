class_name Genome
extends RefCounted
## Génome d'une créature : une liste de gènes numériques dans [0, 1].
## Les autres systèmes (chimie, cerveau, corps) « expriment » ces gènes.

const GENE_NAMES: Array[String] = [
	"hue",            # couleur du pelage
	"size",           # taille du corps
	"speed",          # vitesse de marche
	"metabolism",     # vitesse à laquelle la faim monte
	"stamina",        # résistance à la fatigue
	"curiosity",      # part d'imprévu dans les décisions
	"learning_rate",  # vitesse d'apprentissage
]

var genes: Dictionary = {}


static func create_random(rng: RandomNumberGenerator) -> Genome:
	var g := Genome.new()
	for n in GENE_NAMES:
		g.genes[n] = rng.randf()
	return g


## Croisement de deux parents avec mutations (servira à la reproduction).
static func cross(a: Genome, b: Genome, rng: RandomNumberGenerator, mutation_rate: float = 0.05) -> Genome:
	var child := Genome.new()
	for n in GENE_NAMES:
		var v: float = a.get_gene(n) if rng.randf() < 0.5 else b.get_gene(n)
		if rng.randf() < mutation_rate:
			v = clampf(v + rng.randfn(0.0, 0.15), 0.0, 1.0)
		child.genes[n] = v
	return child


func get_gene(gene_name: String) -> float:
	return float(genes.get(gene_name, 0.5))


func to_dict() -> Dictionary:
	return genes.duplicate()


static func from_dict(d: Dictionary) -> Genome:
	var g := Genome.new()
	for n in GENE_NAMES:
		g.genes[n] = clampf(float(d.get(n, 0.5)), 0.0, 1.0)
	return g
