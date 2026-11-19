# CreaLife

Jeu de vie artificielle inspiré de la série *Creatures*, conçu pour le mobile (Godot 4, GDScript).
Tout le contenu est original : aucun fichier ni code du jeu Creatures n'est utilisé.

## État actuel : un élevage de chats

### Graphismes (pixel art, style Stardew Valley)

- **Chats** : un chat gris dessiné en 11 animations, poil court et poil
  long (`art/pixel/sources`). `tools/build_cat_pixel.py` les découpe et
  calcule des masques (position sur le corps, extrémités, blanc, plaques) ;
  un shader colore chaque chat selon ses gènes. **Rayures** calculées sur
  le corps et déformées par du bruit : ondulées, irrégulières et uniques à
  chaque chat (maquereau, marbré, moucheté, tiqueté ; bracelets aux pattes,
  anneaux à la queue, « M » sur le front). Marche calée sur la vitesse,
  clignement des yeux, demi-tour adouci. Affichés nets, à ×3.
- **Maison en coupe** : chambre, cuisine, salle de jeux, salle
  d'apprentissage, entrée, puis le **jardin** (pommier, potager, mare) et un
  fond lointain en parallaxe. `tools/build_decor_pixel.py`.
- **Objets** : gamelle (pleine ou vide), pelote, trampoline, boîte à
  musique, pomme, graine ; prêts pour plus tard : carotte, pousse, plante,
  papillon, oiseau, souris, panier, eau. `tools/build_objects_pixel.py`.

### Génétique du pelage (réelle, mendélienne)

- Deux allèles par gène, un de chaque parent, dominants ou récessifs.
- Noir, chocolat, cannelle et leurs dilutions (bleu, lilas, faon) ; roux
  et crème liés à l'X (écaille de tortue et calico presque toujours
  femelles).
- Tigré ou uni ; maquereau, classique, moucheté, tiqueté ; argenté/smoke.
- Colourpoint siamois : yeux bleus, extrémités qui foncent au froid,
  chatons pâles.
- Blanc : panachure (bicolore, arlequin, van) ou blanc dominant ; blancs
  aux yeux bleus sourds.
- Poil long (récessif), queue courte Manx (gène présent, pas encore
  dessiné), traits continus (tête, yeux, roux, blanc, contraste).
- Chaque chaton d'une portée a son propre mélange.

### Vie, cerveau et langage

- 36 substances et 6 organes, vie d'environ 10 h de jeu en 5 stades.
- Cerveau à lobes qui apprend par récompense et punition (caresser,
  gronder) ; l'âge règle la vitesse d'apprentissage.
- Langage : noms, verbes, besoins appris en écoutant, en regardant ou à
  l'écran ; ordres compris à proportion des mots connus ; ils parlent
  (bulles) et se transmettent leurs mots.
- Tempéraments héréditaires : curiosité (va devant l'écran, apprend
  mieux), espièglerie (va jouer), instinct parental.
- **Caractère** héréditaire : sociabilité (besoin de compagnie, câlins,
  ronronne ; un indépendant donne un coup de patte si on le câline trop),
  audace (un peureux s'enfuit devant ce qui l'effraie), agressivité (les
  bagarreurs cherchent querelle aux adultes de même sexe), énergie
  (fatigue, vitesse). **Amitiés et rivalités** : se parler, dormir côte à
  côte, s'accoupler rapproche ; les coups font des rivaux ; on va plus
  volontiers vers ses amis. Résumé dans le panneau, détail dans
  Observer → Famille.
- Climat : jour et nuit, saisons, météo, température ressentie ; la
  maison est tempérée.

### Famille et élevage

- Accouplements espacés, refus respectés ; gestation de 25 min puis
  **portée de 1 à 5 chatons**.
- **Allaitement** : les bébés tètent collés à leur mère et la suivent ;
  sevrage au stade enfant. Les parents apportent à manger et parlent aux
  petits.
- **Demandes d'adoption** : des familles cherchent un chat selon le
  pelage, le sexe, l'âge, le caractère ou les mots connus ; on choisit qui
  leur confier, la chatterie gagne de la réputation.
- Population maximale de 14 chats ; les naissances équilibrent les sexes.
- **Nourriture de chat** : distributeur de croquettes en cuisine (il se
  remplit seul, le pousser en donne plus), gamelle d'eau et mare, **pâtée**
  donnée par le joueur (3 portions, une revient toutes les 10 min),
  **proies** au jardin (souris qui fuient, oiseaux qui s'envolent) avec un
  **instinct de chasse** héréditaire. **Goûts** héréditaires : chaque
  aliment fait plus ou moins plaisir, le cerveau apprend ce qu'il préfère
  (affiché dans le panneau). Le foie fabrique du glucose à partir des
  protéines (carnivore). Réflexe de survie : affamé, un chat mange ce qu'il
  voit ou part chercher. On dort mieux dans la chambre.

## Feuille de route

Prochaines étapes, dans l'ordre proposé :

1. **Écosystème du jardin** : graines qui germent, plantes qui poussent,
   papillons, oiseaux, souris ; herbe à chat, plante toxique à éviter.
2. **Soins et santé** : litière, brossage des poils longs, maladies,
   vétérinaire ; handicaps (membre en moins, aveugle, sourd) avec
   adaptation naturelle.
3. **Outils d'éleveur** : stérilisation, test génétique, prédiction des
   portées, races reconnues, consanguinité.
4. **Chatterie** : la réputation débloque des choses (étage avec escalier,
   expositions, meilleures familles).
5. **Animations plus fluides** : transitions (s'asseoir, se coucher, se
   relever, sauter) et planches avec plus d'images (8 au lieu de 2 à 4).
6. Dessins à venir : formes de tête, queue courte (Manx).

### Commandes

| Geste | Effet |
|---|---|
| Toucher une créature | La sélectionner (la caméra la suit) |
| Toucher la créature sélectionnée / **Caresser** | Récompense ce qu'elle est en train de faire |
| **Suivante** | Sélectionne la créature suivante |
| **Parler** | Ouvre le bandeau de paroles : toucher un mot le dit aussitôt ; une phrase s'écrit puis **Dire**. La créature sélectionnée (et ses voisines) l'entend |
| Bandeau ouvert : toucher un objet ou une autre créature | Le lui montre (flèche jaune) : elle le regarde 15 s, le temps de lui en dire le nom |
| Toucher l'écran de la salle d'apprentissage | Change ce qu'il montre (noms, verbes, besoins) |
| **Observer** | Chimie, cerveau, mots connus, gènes, famille de la créature sélectionnée |
| Bouton **Gronder** | Punit ce qu'elle fait (elle le fera moins dans cette situation) |
| Toucher le décor / bouton **Pâtée** | Donne de la pâtée (stock limité, qui revient) |
| Glisser | Déplace la caméra (**Suivre** pour la recentrer) |
| **x1 / x2 / x4 / x16** | Vitesse du temps |
| **Adoptions** | Les demandes des familles ; toucher un chat pour le leur confier |
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
src/sim/creature_sim.gd  Un chat : corps, chimie, cerveau, actions
src/sim/creature/     Ses modules : famille (accouplement, mise bas,
                      allaitement, soins), alimentation (goûts, chasse,
                      réflexe de survie), caractère (peur, amitiés)
src/sim/world_sim.gd  Monde : maison, jardin, climat, objets
src/sim/adoption.gd   Demandes d'adoption, réputation
src/save_store.gd     Sauvegarde sûre (fichier temporaire, copie de secours)
src/view/, src/ui/    Affichage (shader du pelage) et interface tactile
art/                  Planches pixel art d'origine (ChatGPT), ignorées par Godot
tools/                Souche de départ, découpe des chats, décors et objets (Python)
tests/                Tests de la simulation
```

Tests (sur PC ou Termux avec Godot en ligne de commande) :

```sh
godot --headless --script res://tests/test_sim.gd -- rapide   # ~20 s, à chaque modification
godot --headless --script res://tests/test_sim.gd             # tout, ~10 min (vies entières, générations)
```
