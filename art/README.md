# Graphismes de CreaLife

Tout est en pixel art, dans le style de Stardew Valley. Les planches
d'origine sont générées avec ChatGPT, puis des outils Python les découpent et
les mettent à l'échelle du jeu. Ce dossier contient un fichier `.gdignore` :
Godot ne l'importe pas, seuls les résultats dans `assets/` sont utilisés.

```sh
python3 tools/build_cat_pixel.py      # pixel/sources/*.png (+ long/) -> assets/chat_px/
python3 tools/build_decor_pixel.py    # pixel/decor/*.png             -> assets/decor/px_*.png
python3 tools/build_objects_pixel.py  # pixel/sources/objets.png      -> assets/objects/
```

## Chats (`pixel/sources`, `pixel/sources/long`)

Un chat gris uni sur fond magenta (#FF00FF), yeux verts, nez et oreilles
roses, une planche par animation : repos, assis, marche, mange, pousse,
frappe, prend, renifle, miaule, dort, mort ; même chose en poil long.

L'outil calcule pour chaque image deux masques :
- `_m1` : position sur le corps (le long du dos, du dos au ventre) et région
  (tronc, tête, queue, pattes). Le shader y dessine les rayures, différentes
  pour chaque chat.
- `_m2` : extrémités (siamois), rang du blanc (panachure), plaques
  (écaille de tortue).

Le shader `src/view/shaders/cat.gdshader` colore ensuite chaque chat selon
ses gènes.

## Décors (`pixel/decor`)

Une image par pièce, vue de côté en coupe : chambre, cuisine, salle de jeux,
salle d'apprentissage, entrée (retournée en miroir), jardin, et la couche
lointaine (ciel, collines). L'outil rééchantillonne l'image sur sa grille de
gros pixels et note la hauteur du plancher (`assets/decor/px_decors.json`).

## Objets (`pixel/sources/objets.png`)

Une planche d'objets sur fond magenta, repérés automatiquement de gauche à
droite. La pâtée et le tas de croquettes sont fabriqués par l'outil.
