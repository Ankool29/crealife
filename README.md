# CreaLife

Jeu de vie artificielle inspiré de la série *Creatures*, conçu pour le mobile (Godot 4, GDScript).
Tout le contenu est original : aucun fichier ni code du jeu Creatures n'est utilisé.

## Prototype actuel

- **Nina**, une créature dont l'apparence et le caractère viennent de son **génome**
  (couleur, taille, vitesse, métabolisme, endurance, curiosité, capacité d'apprentissage).
- Une **chimie** simplifiée : faim, fatigue et ennui montent avec le temps.
- Un **cerveau** qui choisit entre se reposer, se promener, manger, dormir et jouer,
  et qui **apprend** : satisfaire un besoin est agréable, et le joueur peut récompenser ou punir.

### Commandes

| Geste | Effet |
|---|---|
| Toucher la créature / bouton **Caresser** | Récompense ce qu'elle est en train de faire |
| Bouton **Gronder** | Punit ce qu'elle fait (elle le fera moins dans cette situation) |
| Toucher le décor / bouton **Fruit** | Fait tomber un fruit |
| Glisser | Déplace la caméra (**Suivre** pour la recentrer) |
| **x1 / x2 / x4** | Vitesse du temps |

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
src/sim/     Simulation pure, sans affichage (testable seule)
  genome.gd         gènes, croisement, mutations
  biochemistry.gd   pulsions (faim, fatigue, ennui) et renforcements
  brain.gd          choix des actions + apprentissage
  creature_sim.gd   comportement d'une créature
  world_sim.gd      monde, arbres, fruits
src/view/    Dessin du monde et des créatures (formes procédurales)
src/ui/      Interface tactile
src/main.gd  Assemble le tout, caméra et gestes
tests/       Tests de la simulation
```

Tests (sur PC ou Termux avec Godot en ligne de commande) :

```sh
godot --headless --script res://tests/test_sim.gd
```
