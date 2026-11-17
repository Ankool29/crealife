# CreaLife

Jeu de vie artificielle inspiré de la série *Creatures*, conçu pour le mobile (Godot 4, GDScript).
Tout le contenu est original : aucun fichier ni code du jeu Creatures n'est utilisé.

## État actuel : phase 1 (génome et biochimie)

Le comportement n'est pas écrit à la main : il découle du **génome**
(`data/genomes/souche_depart.json`, 79 gènes typés), qui configure :

- **36 substances** (glucose, glycogène, eau, toxines, hormones, pulsions...)
  avec leurs demi-vies ;
- des **réactions** (digestion, stockage du sucre, élimination des déchets) ;
- des **émetteurs** et **récepteurs** qui relient la chimie au corps ;
- **6 organes** (cœur, digestion, foie, reins, immunité, reproduction) qui
  s'abîment, se réparent et vieillissent ;
- un **cycle de vie** : bébé, enfant, ado, adulte, vieux, puis mort vers 10 h
  de jeu. Certains gènes ne s'activent qu'à un stade donné (hormone sexuelle
  à l'âge adulte, par exemple).

Le cerveau reste provisoire (5 actions apprises par renforcement) ; le cerveau
à lobes arrive en phase 2. Conception complète : voir le document de
conception technique.

### Commandes

| Geste | Effet |
|---|---|
| Toucher la créature / bouton **Caresser** | Récompense ce qu'elle est en train de faire |
| Bouton **Gronder** | Punit ce qu'elle fait (elle le fera moins dans cette situation) |
| Toucher le décor / bouton **Fruit** | Fait tomber un fruit |
| Glisser | Déplace la caméra (**Suivre** pour la recentrer) |
| **x1 / x2 / x4 / x16** | Vitesse du temps |
| **Chimie** | Affiche les substances et la santé des organes |
| **Nouvelle créature** | Apparaît quand la créature est morte |

## Jouer sur Android (Galaxy S25 Ultra)

Une seule fois :

```sh
# Dans Termux
pkg install git
termux-setup-storage            # autorise l'accès au stockage partagé
mkdir -p ~/storage/shared/Godot
cd ~/storage/shared/Godot
git clone https://github.com/Ankool29/crealife.git
```

Puis dans l'appli **Godot Editor** (Play Store) : *Importer* → dossier
`Godot/crealife` → `project.godot`, et appuyer sur ▶.

Pour récupérer les mises à jour :

```sh
cd ~/storage/shared/Godot/crealife && git pull
```

## Architecture

```
data/                 Catalogue des substances, souche de départ
src/sim/genetics/     Gènes typés, génome, croisement, mutations
src/sim/biology/      Substances, réactions, émetteurs, récepteurs,
                      organes, cycle de vie
src/sim/brain.gd      Cerveau provisoire (phase 1)
src/sim/creature_sim.gd  Assemble corps, chimie et cerveau
src/sim/world_sim.gd  Monde, arbres, fruits
src/view/, src/ui/    Affichage et interface tactile
tools/                Générateur de la souche de départ (Python)
tests/                Tests de la simulation
```

Tests (sur PC ou Termux avec Godot en ligne de commande) :

```sh
godot --headless --script res://tests/test_sim.gd
```
