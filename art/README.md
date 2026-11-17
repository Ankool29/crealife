# Graphismes de CreaLife

Comme dans *Creatures 3*, la créature, les objets et le décor sont modélisés
en 3D puis rendus en images. Les scripts utilisent le module Python de
Blender (`pip install bpy`, Python 3.11) ; les images produites sont copiées
dans `assets/`.

```sh
python art/blender/cat.py <dossier> sprites        # chat : poses, couches, masques -> assets/chat/
python art/blender/creature.py <dossier> sprites   # ancienne créature (plus utilisée)
python art/blender/objects.py <dossier>            # objets -> assets/objects/
python art/blender/background.py <dossier> far     # ciel et collines (parallaxe)
python art/blender/background.py <dossier> near    # sol, arbres, buissons
python art/blender/zones.py <dossier> salle        # salle d'apprentissage (intérieur)
python art/blender/zones.py <dossier> loisirs      # aire de loisirs
python art/blender/objects.py <dossier> ecran,trampoline   # seulement certains objets
```

- Échelle commune : 1 unité Blender = 120 pixels de jeu, sol à z = 0.
- La créature est rendue avec une seule teinte ; chaque individu reçoit la
  sienne en jeu par un shader (`src/view/shaders/creature.gdshader`) selon
  son gène d'apparence.
- La queue et les antennes existent en trois variantes chacune, rendues
  dans des couches séparées (`*_queueN.png`, `*_antennesN.png`), le corps
  servant de masque ; le jeu superpose les couches choisies par les gènes.
- Chaque image a aussi un masque de motifs (`*_motifs.png` : rouge =
  taches, vert = rayures, bleu = plaques), calculé dans l'espace de chaque
  partie du corps pour suivre ses mouvements ; le shader le colore selon
  les gènes. `creature.py <dossier> masks` ne refait que les masques.
- Les positions des arbres et buissons dans `background.py` doivent
  correspondre à `src/sim/world_sim.gd`.

## Le chat

`cat.py` construit un chat articulé (corps, quatre pattes en deux pièces,
trois têtes, deux queues) et le rend en gris, couche par couche (corps,
tête, queue), en poil court et en poil long (une enveloppe ébouriffée,
bien plus rapide à rendre que des poils). Pour chaque image et chaque
couche, deux masques guident le shader du pelage
(`src/view/shaders/cat.gdshader`) :

- `_m1` : rouge = tigré maquereau, vert = tigré classique, bleu = moucheté ;
- `_m2` : rouge = extrémités (siamois), vert = ordre d'apparition du blanc
  (le dessous blanchit d'abord, la tête et la queue en dernier),
  bleu = plaques d'écaille de tortue.

Les images sont réduites à 240 px, les masques à 120 px.
