# Graphismes de CreaLife

Comme dans *Creatures 3*, la créature, les objets et le décor sont modélisés
en 3D puis rendus en images. Les scripts utilisent le module Python de
Blender (`pip install bpy`, Python 3.11) ; les images produites sont copiées
dans `assets/`.

```sh
python art/blender/creature.py <dossier> sprites   # poses animées -> assets/creature/
python art/blender/objects.py <dossier>            # objets -> assets/objects/
python art/blender/background.py <dossier> far     # ciel et collines (parallaxe)
python art/blender/background.py <dossier> near    # sol, arbres, buissons
```

- Échelle commune : 1 unité Blender = 120 pixels de jeu, sol à z = 0.
- La créature est rendue avec une seule teinte ; chaque individu reçoit la
  sienne en jeu par un shader (`src/view/shaders/creature.gdshader`) selon
  son gène d'apparence.
- Les positions des arbres et buissons dans `background.py` doivent
  correspondre à `src/sim/world_sim.gd`.
