"""Génère les données de départ de CreaLife :
  data/chemicals.json            catalogue des substances (numéro, nom, famille)
  data/genomes/souche_depart.json génome de la première souche

Le génome reste ensuite modifiable à la main ; ce script sert de point de
départ lisible et reproductible.  Usage : python tools/make_starter_genome.py
"""
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

# --------------------------------------------------------------- substances --
CHEMICALS = [
    # (nom, famille, demi-vie en secondes de jeu (0 = stable), valeur initiale)
    ("Glucose", "énergie", 0, 0.6),
    ("Glycogène", "énergie", 0, 0.5),
    ("Graisse", "énergie", 0, 0.2),
    ("Protéines", "énergie", 0, 0.5),
    ("Eau", "énergie", 0, 0.7),
    ("Glucides (estomac)", "digestion", 0, 0.0),
    ("Protéines (estomac)", "digestion", 0, 0.0),
    ("Graisses (estomac)", "digestion", 0, 0.0),
    ("Déchets", "déchets", 0, 0.0),
    ("Toxines", "déchets", 0, 0.0),
    ("Adrénaline", "hormone", 20, 0.0),
    ("Croissance", "hormone", 300, 0.0),
    ("Hormone sexuelle", "hormone", 300, 0.0),
    ("Hormone du sommeil", "hormone", 60, 0.0),
    ("Faim", "pulsion", 30, 0.0),
    ("Soif", "pulsion", 30, 0.0),
    ("Fatigue", "pulsion", 2400, 0.1),
    ("Sommeil", "pulsion", 30, 0.0),
    ("Douleur", "pulsion", 20, 0.0),
    ("Peur", "pulsion", 20, 0.0),
    ("Ennui", "pulsion", 1200, 0.2),
    ("Solitude", "pulsion", 300, 0.0),
    ("Surpopulation", "pulsion", 60, 0.0),
    ("Froid", "pulsion", 60, 0.0),
    ("Chaud", "pulsion", 60, 0.0),
    ("Désir", "pulsion", 120, 0.0),
    ("Récompense", "renforcement", 5, 0.0),
    ("Punition", "renforcement", 5, 0.0),
] + [(f"Antigène {i}", "immunité", 600, 0.0) for i in range(1, 5)] \
  + [(f"Anticorps {i}", "immunité", 1200, 0.0) for i in range(1, 5)]

genes = []


def gene(gtype, params, stage="bebe", sex="tous", mut=1.0, dup=True, delete=True):
    genes.append({
        "id": len(genes) + 1, "type": gtype, "stage": stage, "sex": sex,
        "mut": mut, "dup": dup, "del": delete, "silent": False, "p": params,
    })


# Substances : vitales, ni dupliquées ni supprimées
for name, _fam, half_life, initial in CHEMICALS:
    gene("substance", {"chem": name, "half_life": half_life, "initial": initial},
         mut=0.5, dup=False, delete=False)

# Organes (longévité en heures de jeu)
for organ, longevity, repair in [
    ("Coeur", 9.5, 0.0005), ("Digestion", 12, 0.0005), ("Foie", 12, 0.0005),
    ("Reins", 12, 0.0005), ("Immunité", 12, 0.0005), ("Reproduction", 10, 0.0005),
]:
    gene("organe", {"organ": organ, "longevity_h": longevity, "repair": repair, "health": 1.0},
         mut=0.5, dup=False, delete=False)


def reaction(a, c, rate, organ, b="", d="", cond="", lo=0.0, hi=1.0, **kw):
    gene("reaction", {"a": a, "b": b, "c": c, "d": d, "rate": rate, "organ": organ,
                      "cond": cond, "lo": lo, "hi": hi}, **kw)


def emitter(source, chem, gain, threshold=0.0, invert=False, organ="Corps", **kw):
    gene("emetteur", {"source": source, "invert": invert, "threshold": threshold,
                      "gain": gain, "chem": chem, "organ": organ}, **kw)


def receptor(chem, locus, gain, threshold=0.0, invert=False, organ="Corps", **kw):
    gene("recepteur", {"chem": chem, "invert": invert, "threshold": threshold,
                       "gain": gain, "locus": locus, "organ": organ}, **kw)


# Digestion et stockage
reaction("Glucides (estomac)", "Glucose", 0.08, "Digestion")
reaction("Protéines (estomac)", "Protéines", 0.05, "Digestion")
reaction("Graisses (estomac)", "Graisse", 0.03, "Digestion")
reaction("Glucose", "Glycogène", 0.02, "Foie", cond="Glucose", lo=0.7, hi=1.0)
reaction("Glycogène", "Glucose", 0.05, "Foie", cond="Glucose", lo=0.0, hi=0.4)
reaction("Glucose", "Graisse", 0.005, "Foie", cond="Glycogène", lo=0.9, hi=1.0)
reaction("Graisse", "Glucose", 0.01, "Foie", cond="Glycogène", lo=0.0, hi=0.05)
# Élimination
reaction("Toxines", "Déchets", 0.02, "Foie")
reaction("Déchets", "", 0.01, "Reins")
reaction("Protéines", "", 0.0005, "Corps")

# Consommation d'énergie et d'eau
emitter("corps.metabolisme", "Glucose", -0.0008)
emitter("corps.activite", "Glucose", -0.002)
emitter("corps.metabolisme", "Déchets", 0.001)
emitter("corps.metabolisme", "Eau", -0.0007)
# Pulsions
emitter("chem:Glucose", "Faim", 0.05, threshold=0.5, invert=True)
emitter("chem:Glycogène", "Faim", 0.02, threshold=0.5, invert=True)
emitter("chem:Eau", "Soif", 0.05, threshold=0.5, invert=True)
emitter("corps.activite", "Fatigue", 0.0002)
emitter("corps.metabolisme", "Fatigue", 0.0001)
emitter("corps.dort", "Fatigue", -0.003)
emitter("chem:Fatigue", "Sommeil", 0.05, threshold=0.6)
emitter("corps.ennui", "Ennui", 0.008)
emitter("corps.seul", "Solitude", 0.004)                                   # personne autour
emitter("chem:Toxines", "Douleur", 0.05, threshold=0.3)
# Hormones
emitter("chem:Douleur", "Adrénaline", 0.05, threshold=0.2)
emitter("chem:Fatigue", "Hormone du sommeil", 0.02, threshold=0.5)
emitter("corps.metabolisme", "Croissance", 0.004)                          # bébé : croissance
emitter("corps.metabolisme", "Croissance", -0.004, stage="ado")            # ado : la croissance s'arrête
emitter("corps.metabolisme", "Hormone sexuelle", 0.005, organ="Reproduction", stage="adulte")
emitter("chem:Hormone sexuelle", "Désir", 0.01, threshold=0.3, stage="adulte")

# Récepteurs : dégâts aux organes et effets sur le corps
receptor("Toxines", "organe.Foie.degats", 0.002, threshold=0.2, organ="Foie")
receptor("Déchets", "organe.Reins.degats", 0.002, threshold=0.6, organ="Reins")
receptor("Glucose", "organe.Coeur.degats", 0.02, threshold=0.97, invert=True)   # famine
receptor("Eau", "organe.Coeur.degats", 0.02, threshold=0.97, invert=True)       # déshydratation
receptor("Toxines", "organe.Coeur.degats", 0.003, threshold=0.6)
receptor("Adrénaline", "corps.vitesse_bonus", 1.0, threshold=0.1)

# Punition : la douleur est désagréable
emitter("chem:Douleur", "Punition", 0.5, threshold=0.05)

# Cerveau : les pulsions arrivent au lobe des pulsions par des récepteurs
DRIVES = ["Faim", "Soif", "Fatigue", "Sommeil", "Douleur", "Peur", "Ennui",
          "Solitude", "Surpopulation", "Froid", "Chaud", "Désir"]
for d in DRIVES:
    receptor(d, f"pulsion.{d}", 1.0)
gene("lobe", {"lobe": "attention", "noise": 0.4, "learning_rate": 0.5})
gene("lobe", {"lobe": "decision", "noise": 0.4, "learning_rate": 0.5,
              "ltw_rate": 0.0005, "stw_relax": 0.002, "ageing": 0.5})
# Langage : vitesse d'apprentissage des mots, envie de parler, tendance à obéir.
gene("lobe", {"lobe": "langage", "learning_rate": 0.5, "talk": 0.5, "obey": 0.5})


def instinct(drive, category, verb, reward=1.0, repeat=6):
    gene("instinct", {"drive": drive, "category": category, "verb": verb,
                      "reward": reward, "repeat": repeat},
         stage="adulte" if verb == "accoupler" else "bebe")


# Instincts : réflexes appris avant la naissance (catégorie "" = aucun objet).
# Rien sur les graines, les baies ou la machine : elle doit les découvrir.
instinct("Faim", "fruit", "manger")
instinct("Soif", "fruit", "manger", repeat=4)
instinct("Faim", "", "explorer", 0.6, 3)
instinct("Fatigue", "", "dormir")
instinct("Sommeil", "", "dormir")
instinct("Ennui", "jouet", "pousser", 1.0, 4)
instinct("Ennui", "", "explorer", 0.8, 3)
instinct("Douleur", "", "rien", 0.5, 2)
instinct("Solitude", "créature", "parler", 0.8, 4)
instinct("Désir", "créature", "accoupler", 1.0, 6)                       # actif à l'âge adulte
# Couleurs : teinte principale, teinte secondaire (ventre, reflets),
# saturation, luminosité et couleur des parties lumineuses. Tirées au hasard pour chaque nouvelle créature.
gene("apparence", {"part": "corps", "hue": 0.5, "hue2": 0.6, "saturation": 0.7,
                   "brightness": 0.7, "glow": 0.47, "glow_power": 0.5, "size": 0.5, "speed": 0.5})
# Silhouette : forme de la queue (courte, longue, massue), des antennes
# (courtes, longues, ramifiées) et corpulence (fine à trapue).
gene("apparence", {"part": "silhouette", "tail": 0.5, "antennae": 0.5, "corpulence": 0.5})
# Motifs : intensité des taches, rayures et plaques (visibles au-delà de
# 0,2 environ), teinte et clarté du motif. Une mutation peut les faire apparaître.
gene("apparence", {"part": "motif", "spots": 0.0, "stripes": 0.0, "patches": 0.0, "hue3": 0.1, "light3": 0.5})
# Instinct parental : envie de nourrir et de parler à ses petits (bébés, enfants).
# Nouveaux gènes : toujours à la fin, pour garder les numéros des anciens.
gene("lobe", {"lobe": "parental", "care": 0.6}, stage="adulte")

# --- Phase 5 : climat et tempérament (à la fin, voir plus haut) ---
# Froid et chaud ressentis (température de la zone, blottie contre les autres)
emitter("corps.froid_ext", "Froid", 0.01)
emitter("corps.chaud_ext", "Chaud", 0.01)
emitter("chem:Froid", "Glucose", -0.0006, threshold=0.3)                  # frissons : énergie
emitter("chem:Chaud", "Eau", -0.0006, threshold=0.3)                      # transpiration
receptor("Froid", "organe.Coeur.degats", 0.004, threshold=0.85)           # hypothermie
receptor("Chaud", "organe.Coeur.degats", 0.004, threshold=0.85)           # coup de chaleur
emitter("corps.nuit", "Fatigue", 0.00015)                                  # sommeil la nuit
emitter("corps.pluie", "Eau", 0.001)                                       # boit la pluie
instinct("Froid", "créature", "approcher", 0.8, 4)                         # se blottir
instinct("Chaud", "", "rien", 0.5, 2)                                      # se reposer
# Tempérament : curiosité (apprend à l'écran) et espièglerie (aime jouer)
gene("lobe", {"lobe": "temperament", "curiosity": 0.5, "playfulness": 0.5})

catalog = [{"id": i + 1, "name": n, "family": f} for i, (n, f, _h, _v) in enumerate(CHEMICALS)]
(ROOT / "data").mkdir(exist_ok=True)
(ROOT / "data/genomes").mkdir(exist_ok=True)
(ROOT / "data/chemicals.json").write_text(json.dumps(catalog, ensure_ascii=False, indent="\t") + "\n", encoding="utf-8")
genome = {"format": "crealife-genome", "version": 2, "name": "Souche de départ", "genes": genes}
(ROOT / "data/genomes/souche_depart.json").write_text(json.dumps(genome, ensure_ascii=False, indent="\t") + "\n", encoding="utf-8")
print(f"{len(catalog)} substances, {len(genes)} gènes")
