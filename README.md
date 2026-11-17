# CreaLife

Jeu de vie artificielle inspiré de la série *Creatures*, conçu pour le mobile (Godot 4, GDScript).
Tout le contenu est original : aucun fichier ni code du jeu Creatures n'est utilisé.

## État actuel : phase 4 (langage et apparence)

- **Langage** : chaque créature a un vocabulaire (8 noms d'objets, 13
  verbes, 12 besoins). Elle apprend un nom quand on le prononce pendant
  qu'elle regarde l'objet, un verbe pendant qu'elle fait l'action, un
  besoin quand elle le ressent. Elle comprend les ordres (« pousse la
  balle ») à proportion de ce qu'elle connaît des mots ; obéir reste une
  tendance, renforcée par les caresses. Elle dit ce qu'elle ressent
  (« faim ! ») dans une bulle, en babillant au début puis en écorchant
  les mots, et transmet son vocabulaire aux autres en leur parlant.
- **Apparence** : en plus des couleurs, chaque créature hérite d'une forme
  de queue (courte, longue, massue), d'antennes (courtes, longues,
  ramifiées), d'une corpulence et d'une couleur et intensité de lumière
  des antennes et des taches.
- Phases précédentes : population et reproduction, observation et
  sauvegarde (phase 3), cerveau à lobes qui apprend (phase 2), 36
  substances et 6 organes, vie d'environ 10 h (phase 1), graphismes
  rendus en 3D.

### Commandes

| Geste | Effet |
|---|---|
| Toucher une créature | La sélectionner (la caméra la suit) |
| Toucher la créature sélectionnée / **Caresser** | Récompense ce qu'elle est en train de faire |
| **Suivante** | Sélectionne la créature suivante |
| **Parler** | Écrire une phrase ou toucher des mots, puis **Dire** : la créature sélectionnée (et ses voisines) l'entend |
| **Observer** | Chimie, cerveau, mots connus, gènes, famille de la créature sélectionnée |
| Bouton **Gronder** | Punit ce qu'elle fait (elle le fera moins dans cette situation) |
| Toucher le décor / bouton **Fruit** | Fait tomber un fruit |
| Glisser | Déplace la caméra (**Suivre** pour la recentrer) |
| **x1 / x2 / x4 / x16** | Vitesse du temps |
| **Nouvelle lignée** | Apparaît si toutes les créatures sont mortes |
| **Menu** → **Recommencer** | Efface la partie et repart avec deux nouvelles créatures |

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
src/sim/brain/        Cerveau à lobes, langage
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
