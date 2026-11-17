# CreaLife

Jeu de vie artificielle inspiré de la série *Creatures*, conçu pour le mobile (Godot 4, GDScript).
Tout le contenu est original : aucun fichier ni code du jeu Creatures n'est utilisé.

## État actuel : phase 2 (cerveau et monde)

- **Monde** : arbres à fruits, buissons à baies violettes (toxiques),
  distributeur de graines, balle, pierres. Chaque objet décrit sa réaction
  aux verbes dans `data/objects.json`.
- **Cerveau à lobes** : pulsions, vision par catégorie d'objet, attention,
  concepts « pulsion × objet », décision parmi 14 verbes (approcher, fuir,
  examiner, prendre, lâcher, manger, pousser, tirer, frapper, parler,
  dormir, explorer...). Il apprend par récompense et punition, avec une
  mémoire à court et à long terme, et naît avec quelques instincts écrits
  dans ses gènes.
- **Elle découvre seule** que les graines se mangent, que les baies font
  mal et que pousser le distributeur donne des graines.
- **Biologie** (phase 1) : 36 substances, 6 organes, cycle de vie de 10 h.
- **Graphismes** rendus en 3D avec Blender (voir `art/`).

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
