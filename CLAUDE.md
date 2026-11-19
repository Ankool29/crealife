# CLAUDE.md — consignes pour travailler sur CreaLife

CreaLife est un jeu de vie artificielle inspiré de *Creatures*, en Godot 4.5
(GDScript), où les créatures sont des chats en pixel art : génétique du
pelage réelle, chimie, cerveau qui apprend, langage, famille, élevage. Le
joueur teste sur Android (Samsung S25 Ultra) : il récupère la branche
`main` avec un script Termux (`majcl`) puis ouvre le projet dans Godot sur
son téléphone. Le README décrit l'état du jeu et la **feuille de route**.

## Langue

Tout est en **français** : textes du jeu, commentaires, noms de tests,
messages de commit, réponses à l'utilisateur (qui n'est pas développeur :
expliquer simplement ce qui change en jeu).

## Mise en route (machine sans Godot)

```sh
mkdir -p ~/tools && cd ~/tools
curl -sLO https://github.com/godotengine/godot/releases/download/4.5.1-stable/Godot_v4.5.1-stable_linux.x86_64.zip
unzip -o Godot_v4.5.1-stable_linux.x86_64.zip && chmod +x Godot_v4.5.1-stable_linux.x86_64
cd -  # retour au dépôt
~/tools/Godot_v4.5.1-stable_linux.x86_64 --headless --import   # une fois, et après tout ajout d'image
```

## Tests (obligatoires avant chaque commit)

```sh
G=~/tools/Godot_v4.5.1-stable_linux.x86_64
$G --headless --script res://tests/test_sim.gd -- rapide   # ~20 s : à chaque modification
$G --headless --script res://tests/test_sim.gd             # ~10 min : avant de livrer une étape
```

La dernière ligne doit être `RÉSULTAT : OK`. Toute nouvelle mécanique a son
test (fonction `_test_...` ajoutée à `QUICK` ou `LONG` dans
`tests/test_sim.gd`). Les comportements dépendent du hasard : mesurer sur
plusieurs mondes (graines) ou neutraliser les traits qui ne sont pas testés,
plutôt que d'assouplir un seuil sans comprendre. Vérifier aussi, par une
petite simulation de 2 h avec 6 chats, que personne ne meurt de faim ou de
soif après un changement de comportement.

## Architecture

- `src/sim/` : simulation pure, sans affichage (testable en headless).
  - `world_sim.gd` : maison en coupe (chambre, cuisine, salle de jeux,
    salle d'apprentissage, entrée) puis jardin ; objets, proies, climat,
    sauvegarde (`to_dict` / `from_dict`).
  - `creature_sim.gd` : un chat (corps, chimie, cerveau, actions) ;
    modules dans `src/sim/creature/` : `cat_family.gd` (accouplement, mise
    bas, allaitement, soins), `cat_food.gd` (goûts, chasse, réflexe de
    survie), `cat_character.gd` (peur, querelles, amitiés), `cat_garden.gd`
    (herbe à chat, lys, jeu avec les papillons).
  - `world/` : climat, catalogue d'objets, `garden.gd` (écosystème du
    jardin : plantes et leurs stades, papillons, population de souris).
  - `genetics/` (gènes typés, croisement, `cat_coat.gd` pour le pelage),
    `biology/` (substances, réactions, organes), `brain/` (cerveau à lobes,
    langage), `adoption.gd`.
- `src/view/`, `src/ui/` : affichage et interface tactile. Le pelage est
  colorié par `src/view/shaders/cat.gdshader`.
- `src/save_store.gd` : sauvegarde sûre (fichier temporaire, copie de
  secours, validation).
- `data/` : catalogue des substances, des objets (`objects.json`), souche
  de départ (`genomes/souche_depart.json`, générée).
- `tools/` : outils Python (souche, découpe des sprites). `art/` : planches
  d'origine générées avec ChatGPT, ignorées par Godot (`.gdignore`).

## Règles à respecter

- **Gènes** : la souche se génère avec `python3 tools/make_starter_genome.py`.
  Un nouveau gène s'ajoute **à la fin** du script (les numéros des gènes
  existants ne doivent pas bouger). Les chats déjà nés n'ont pas le
  nouveau gène : l'ajouter dans `CreatureSim.ensure_cat_genes` (valeurs
  tirées au hasard) pour les parties en cours.
- **Catégories d'objets** : il y en a exactement 8 (`data/objects.json`),
  elles dimensionnent le cerveau. On peut renommer une catégorie inutilisée,
  jamais en ajouter ou en retirer. Les mots du langage suivent les noms
  des catégories (alias dans `src/sim/brain/language.gd`).
- **Verbes et pulsions** : ne pas en ajouter (taille du cerveau) sans
  prévoir la conversion des parties en cours.
- **Sauvegardes** : une partie existante doit toujours se recharger.
  Champ nouveau : lu avec `d.get(clé, défaut)`. Changement de structure :
  augmenter `"version"` dans `WorldSim.to_dict` et convertir dans
  `from_dict`. Garder `SaveStore.valid` cohérent. Le test de chargement
  d'ancienne sauvegarde doit passer.
- **Réflexes** : quand un réflexe impose une action, utiliser
  `brain.force(catégorie, verbe)` (le cerveau apprend de ce qui suit), pas
  `brain.clear_trace()` (réservé aux soins instinctifs).
- **Récompenses** : éviter les plaisirs génériques (`Récompense`) qui
  renforcent n'importe quelle action ; préférer
  `brain.reinforce_drive(pulsion, r)` lié au besoin concerné.
- **Shader** : `COLOR` contient déjà la texture en Godot 4, ne pas écrire
  `* COLOR`. Les masques des chats sont en coordonnées « sur le corps »
  (voir `art/README.md`) pour que les couleurs ne bougent pas d'une pose
  à l'autre.
- **Graphismes** : pixel art net (filtre « nearest »), même échelle que les
  chats (×3). Les nouvelles images viennent de l'utilisateur (ChatGPT) ;
  faute d'image, dériver un sprite existant dans
  `tools/build_objects_pixel.py` (`_derived`).
- **Performances** : penser au téléphone (jusqu'à 14 chats). Pas de boucle
  coûteuse à chaque pas pour chaque paire de chats sans nécessité.

## Livraison

- Commits en français, petits et clairs. Mettre à jour le README (état du
  jeu, feuille de route) quand une étape est finie.
- Terminer par un résumé pour l'utilisateur : ce qui change en jeu, et lui
  rappeler de fermer le projet dans Godot puis de lancer `majcl` une fois
  la branche intégrée à `main`.
