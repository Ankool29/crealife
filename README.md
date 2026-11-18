# CreaLife

Jeu de vie artificielle inspiré de la série *Creatures*, conçu pour le mobile (Godot 4, GDScript).
Tout le contenu est original : aucun fichier ni code du jeu Creatures n'est utilisé.

## État actuel : les créatures sont des chats

- **Chats en pixel art** (quadrupèdes), dessinés d'après le concept : un
  chat gris uni en 11 animations (`art/pixel/sources`), que
  `tools/build_cat_pixel.py` découpe et accompagne de masques de pelage ; le
  shader les colore selon les gènes. Affichés nets, à ×3. Le cerveau, le
  langage, la biologie et l'apprentissage sont inchangés.
- **Génétique réelle du pelage**, mendélienne : chaque gène a deux
  allèles, un de chaque parent, dominants ou récessifs.
  - Couleurs : noir, chocolat, cannelle et leurs dilutions bleu, lilas,
    faon ; roux et crème, liés au chromosome X : les mâles roux sont
    fréquents, l'écaille de tortue et le calico sont (presque) toujours
    des femelles.
  - Tigré (agouti) ou uni ; motifs maquereau, classique, moucheté,
    tiqueté ; argenté ou « smoke ».
  - Colourpoint siamois : yeux bleus, extrémités qui foncent au froid,
    chatons qui naissent pâles.
  - Blanc : panachure (bicolore, arlequin, van) ou blanc dominant, avec
    yeux bleus ou vairons ; les blancs aux yeux bleus sont sourds (ils
    n'entendent pas les mots, mais lisent l'écran).
  - Poil long (récessif), queue courte (Manx, dominant).
  - Traits continus : forme de la tête (en coin, moyenne, ronde),
    couleur des yeux, intensité du roux, quantité de blanc, contraste.
  - Deux chats noirs peuvent avoir un chaton bleu ou siamois ; le nom du
    pelage s'affiche dans le panneau, les gènes dans l'onglet Gènes.

### Phase 5 (zones et climat)

- **Trois zones** côte à côte : la **salle d'apprentissage** (intérieur
  chaud et éclairé), le **jardin** (nourriture) et l'**aire de loisirs**
  (trampoline, boîte à musique, balles).
- **Écran d'apprentissage** : il fait défiler une image et son mot toutes
  les 6 s (noms, verbes ou besoins : toucher l'écran pour changer). Une
  créature qui le regarde apprend le mot, d'autant mieux qu'elle est
  **curieuse** (gène de tempérament) ; les curieuses aiment aussi le
  regarder.
- **Loisirs** : les **espiègles** (gène de tempérament) s'ennuient plus
  vite et s'amusent plus avec les jouets. Le trampoline fait sauter, la
  boîte à musique distrait et console toutes celles qui l'entendent.
- **Climat** : jour et nuit (24 min), saisons d'une heure (année de 4 h),
  beau temps, nuages, pluie ou neige. Dehors la température suit la
  saison, l'heure et la météo ; la salle reste à 19 °C. Froid et chaud
  sont ressentis (pulsions) : frissons qui brûlent de l'énergie,
  transpiration, hypothermie si ça dure ; se blottir contre les autres
  réchauffe, la nuit fatigue, la pluie désaltère. Moins de fruits l'hiver
  et pas de baies : le distributeur de graines devient précieux.
- Les naissances tendent à équilibrer mâles et femelles.
- **Langage** : chaque créature a un vocabulaire (8 noms d'objets, 13
  verbes, 12 besoins). Elle apprend un nom quand on le prononce pendant
  qu'elle regarde l'objet, un verbe pendant qu'elle fait l'action, un
  besoin quand elle le ressent. Elle comprend les ordres (« pousse la
  balle ») à proportion de ce qu'elle connaît des mots ; obéir reste une
  tendance, renforcée par les caresses. Elle dit ce qu'elle ressent
  (« faim ! ») dans une bulle, en babillant au début puis en écorchant
  les mots, et transmet son vocabulaire aux autres en leur parlant.
- **L'âge compte** : bébés et enfants apprennent vite (mots comme
  habitudes), les adultes plus lentement, les vieux encore moins et
  oublient peu à peu les mots qui ne servent plus. Un gène
  (« maturation ») règle à quel point l'esprit vieillit selon les lignées.
- **Apparence** : en plus des couleurs, chaque créature hérite d'une forme
  de queue (courte, longue, massue), d'antennes (courtes, longues,
  ramifiées), d'une corpulence et d'une couleur et intensité de lumière
  des antennes et des taches.
- **Vie de famille** : après un accouplement, 40 min de repos ; le désir
  retombe pendant la gestation, tant qu'il y a un bébé, et quand le monde
  est plein ; après un refus, on n'insiste pas. Les parents (instinct
  parental héréditaire) apportent à manger à leurs petits affamés et vont
  leur parler quand ils s'ennuient ou se sentent seuls, ce qui leur
  transmet leurs mots.
- **Brassage génétique** : chaque trait d'apparence vient de l'un ou
  l'autre parent ou d'un mélange des deux (couleurs intermédiaires).
  Motifs héréditaires : taches, rayures, grandes plaques, avec leur
  propre couleur ; un motif peut rester « dormant » et réapparaître chez
  un descendant, ou naître d'une mutation.
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
| **Parler** | Ouvre le bandeau de paroles : toucher un mot le dit aussitôt ; une phrase s'écrit puis **Dire**. La créature sélectionnée (et ses voisines) l'entend |
| Bandeau ouvert : toucher un objet ou une autre créature | Le lui montre (flèche jaune) : elle le regarde 15 s, le temps de lui en dire le nom |
| Toucher l'écran de la salle | Change ce qu'il montre (noms, verbes, besoins) |
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
