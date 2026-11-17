"""Sprites des objets du monde (fruit, graine, baie, balle, pierre, distributeur).

Utilisation : python objects.py <dossier_sortie>
Même échelle que le décor : 1 unité Blender = 120 pixels de jeu.
Chaque image a son point d'ancrage (le sol) dans objects.json.
"""
import json
import math
import sys
from pathlib import Path

import bpy
import bmesh  # après bpy
from mathutils import Euler, Vector

sys.path.insert(0, str(Path(__file__).parent))
import background as bg  # noqa: E402  (réutilise matériaux et formes)

OUT = Path(sys.argv[1] if len(sys.argv) > 1 else "out")
PPU = bg.PX_PER_UNIT


def scene_for(res):
    """Cadre de res pixels de jeu, rendu en double résolution pour la netteté."""
    bg.reset_scene(res * 2, res * 2)
    sc = bpy.context.scene
    sc.render.film_transparent = True
    sc.cycles.samples = 48
    sc.world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.6
    bg.lights()
    fill = bpy.data.lights.new("Fill", "AREA")
    fill.energy = 60
    fill.size = 3
    o = bg.link(bpy.data.objects.new("Fill", fill))
    o.location = (1.5, -3, 1.0)
    o.rotation_euler = Euler((math.radians(75), 0, math.radians(25)))
    size = res / PPU
    cd = bpy.data.cameras.new("Cam")
    cd.type = "ORTHO"
    cd.ortho_scale = size
    cam = bg.link(bpy.data.objects.new("Cam", cd))
    cam.location = (0, -10, 0.4 * size)        # le sol tombe à 90 % de la hauteur
    cam.rotation_euler = Euler((math.radians(90), 0, 0))
    sc.camera = cam
    return {"size": res * 2, "anchor": [res, 1.8 * res], "scale": 0.5}


def glossy(name, color, rough=0.25, coat=0.6, sss=0.0, noise=0.0, dark=None, emit=0.0):
    m = bg.material(name, color, rough, noise, 0.3 if noise else 0.0, dark, sss, emit)
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Coat Weight"].default_value = coat
    return m


def ellipsoid(name, loc, radii, mat, rot=(0, 0, 0), subdiv=2):
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=32, v_segments=16, radius=1.0)
    bmesh.ops.scale(bm, vec=Vector(radii), verts=bm.verts)
    o = bg.mesh_obj(name, bm, mat)
    o.location = loc
    o.rotation_euler = Euler([math.radians(a) for a in rot])
    return o


def cylinder(name, loc, r1, r2, depth, mat):
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, segments=32, radius1=r1, radius2=r2, depth=depth, cap_ends=True)
    o = bg.mesh_obj(name, bm, mat)
    o.location = loc
    return o


def build(kind, variant=""):
    if kind == "fruit":
        skin = glossy("FruitSkin", (0.85, 0.28, 0.06), 0.3, 0.5, 0.2, 18, (0.6, 0.12, 0.04))
        ellipsoid("Fruit", (0, 0, 0.1), (0.095, 0.095, 0.11), skin)
        ellipsoid("FruitBottom", (0, 0, 0.06), (0.085, 0.085, 0.07), skin)
        cylinder("Stem", (0.01, 0, 0.225), 0.008, 0.005, 0.05, bg.material("Stem", (0.2, 0.12, 0.05)))
        ellipsoid("Leaf", (0.05, 0, 0.235), (0.05, 0.012, 0.02), bg.material("Leaf", (0.15, 0.4, 0.08), 0.6), (0, -25, 0))
    elif kind == "graine":
        mat = glossy("Seed", (0.62, 0.45, 0.22), 0.5, 0.2, 0, 40, (0.35, 0.22, 0.1))
        ellipsoid("Seed", (0, 0, 0.045), (0.07, 0.05, 0.045), mat, (0, 15, 0))
    elif kind == "baie":
        mat = glossy("Berry", (0.28, 0.04, 0.38), 0.15, 1.0, 0.15, 25, (0.12, 0.02, 0.2))
        for i, (x, z) in enumerate([(-0.045, 0.045), (0.045, 0.045), (0.0, 0.11)]):
            ellipsoid(f"Berry{i}", (x, 0.01 * i, z), (0.05, 0.05, 0.05), mat)
        ellipsoid("BerryLeaf", (0.0, 0.02, 0.16), (0.05, 0.01, 0.015), bg.material("Leaf2", (0.12, 0.3, 0.1), 0.6), (0, 20, 0))
    elif kind == "balle":
        ellipsoid("Ball", (0, 0, 0.14), (0.14, 0.14, 0.14), glossy("Ball", (0.95, 0.7, 0.1), 0.35, 0.4))
        bm = bmesh.new()
        bmesh.ops.create_cone(bm, segments=48, radius1=0.143, radius2=0.143, depth=0.05, cap_ends=False)
        band = bg.mesh_obj("Band", bm, glossy("Band", (0.75, 0.15, 0.25), 0.35, 0.4))
        band.location = (0, 0, 0.14)
        band.rotation_euler = Euler((math.radians(90), 0, math.radians(25)))
    elif kind == "pierre":
        rock = bg.blob("Stone", (0, 0, 0.09), (0.15, 0.11, 0.1), bg.material("Stone", (0.42, 0.4, 0.37), 0.85, 6, 0.3, (0.22, 0.21, 0.2)), 0.05, 0.15, 2)
        rock.name = "Stone"
    elif kind == "oeuf":
        shell = glossy("Shell", (0.86, 0.84, 0.78), 0.35, 0.6, 0.3, 30, (0.55, 0.5, 0.45))
        ellipsoid("Egg", (0, 0, 0.13), (0.1, 0.1, 0.13), shell)
        spots = glossy("EggGlow", (0.3, 0.95, 0.75), 0.2, 1.0, emit=2.5)
        for i, (x, z) in enumerate([(0.07, 0.17), (-0.05, 0.08), (0.02, 0.22), (0.08, 0.07), (-0.08, 0.16)]):
            ellipsoid(f"Spot{i}", (x, -0.07, z), (0.014, 0.01, 0.014), spots)
    elif kind == "distributeur":
        metal = glossy("Metal", (0.32, 0.34, 0.38), 0.35, 0.3, 0, 8, (0.18, 0.19, 0.22))
        metal.node_tree.nodes["Principled BSDF"].inputs["Metallic"].default_value = 0.8
        organic = glossy("Pod", (0.2, 0.42, 0.42), 0.4, 0.5, 0.25, 6, (0.12, 0.08, 0.25))
        cylinder("Base", (0, 0, 0.05), 0.24, 0.2, 0.1, metal)
        cylinder("Stalk", (0, 0, 0.32), 0.06, 0.05, 0.46, metal)
        for i in range(3):
            ring = cylinder(f"Ring{i}", (0, 0, 0.2 + 0.13 * i), 0.075, 0.075, 0.025, metal)
        ellipsoid("Pod", (0, 0, 0.72), (0.2, 0.18, 0.24), organic)
        ellipsoid("Mouth", (0.17, 0, 0.62), (0.05, 0.09, 0.05), bg.material("MouthDark", (0.03, 0.02, 0.04)))
        on = variant == "on"
        ellipsoid("Light", (0, 0, 0.99), (0.055, 0.055, 0.055),
                  glossy("Light", (0.3, 0.95, 0.75) if on else (0.12, 0.2, 0.18), 0.2, 1.0, emit=4.0 if on else 0.0))
        for side in (-1, 1):
            ellipsoid(f"Fin{side}", (-0.12, 0.12 * side, 0.8), (0.12, 0.02, 0.06), organic, (0, -30, 0))


SPRITES = [("fruit", "", 64), ("graine", "", 48), ("baie", "", 48), ("balle", "", 64),
           ("pierre", "", 64), ("oeuf", "", 64), ("distributeur", "on", 160), ("distributeur", "off", 160)]

if __name__ == "__main__":
    OUT.mkdir(parents=True, exist_ok=True)
    manifest = {}
    for kind, variant, res in SPRITES:
        info = scene_for(res)
        build(kind, variant)
        name = kind + ("_" + variant if variant else "")
        bpy.context.scene.render.filepath = str(OUT / f"{name}.png")
        bpy.ops.render.render(write_still=True)
        manifest[name] = info
    (OUT / "objects.json").write_text(json.dumps(manifest, indent="\t"))
