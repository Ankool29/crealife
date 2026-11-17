# CreaLife

Jeu de vie artificielle inspiré de la série *Creatures*, conçu pour le mobile (Godot 4, GDScript).
Tout le contenu est original : aucun fichier ni code du jeu Creatures n'est utilisé.

## État actuel : phase 3 (reproduction et observation)

- **Population** : deux fondateurs au départ, jusqu'à 10 créatures. Elles
  se voient, se parlent contre la solitude, se bousculent, s'accouplent
  entre adultes consentants. La femelle pond un œuf qui éclot 10 min plus
  tard : le bébé hérite d'un mélange des gènes de ses parents, avec
  quelques mutations (couleurs comprises).
- **Observer** : chimie en direct, cerveau (pulsions, ce qu'elle voit,
  envie de chaque verbe, associations apprises), liste des gènes, arbre
  généalogique.
- **Sauvegarde automatique** toutes les 2 minutes et quand l'appli passe en
  arrière-plan ; le jeu est en pause quand l'appli est fermée.
- Phases précédentes : cerveau à lobes qui apprend (phase 2), 36 substances
  et 6 organes, vie d'environ 10 h (phase 1), graphismes rendus en 3D.

### Commandes

| Geste | Effet |
|---|---|
| Toucher une créature | La sélectionner (la caméra la suit) |
| Toucher la créature sélectionnée / **Caresser** | Récompense ce qu'elle est en train de faire |
| **Suivante** | Sélectionne la créature suivante |
| **Observer** | Chimie, cerveau, gènes, famille de la créature sélectionnée |
| Bouton **Gronder** | Punit ce qu'elle fait (elle le fera moins dans cette situation) |
| Toucher le décor / bouton **Fruit** | Fait tomber un fruit |
| Glisser | Déplace la caméra (**Suivre** pour la recentrer) |
| **x1 / x2 / x4 / x16** | Vitesse du temps |
| **Nouvelle lignée** | Apparaît si toutes les créatures sont mortes |

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

Pour récupérer les mises à jour (projet fermé dans Godot), avec la
commande `majcl` installée dans Termux :

```sh
majcl
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
