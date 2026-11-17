"""Décors des zones ajoutées en phase 5.

Utilisation : python zones.py <dossier_sortie> salle|loisirs
- salle   : salle d'apprentissage, intérieur chaud et éclairé (1800 px)
- loisirs : aire de jeux en plein air, ciel transparent (2400 px)
Même échelle et même bande verticale que background.py (sol à z = 0).
"""
import math
import random
import sys
from pathlib import Path

import bpy
import bmesh  # après bpy
from mathutils import Euler, Vector

sys.path.insert(0, str(Path(__file__).parent))
import background as bg  # noqa: E402

OUT = Path(sys.argv[1] if len(sys.argv) > 1 else "out")
MODE = sys.argv[2] if len(sys.argv) > 2 else "salle"
PPU = bg.PX_PER_UNIT
rng = random.Random(11)
# Doit correspondre à src/sim/world_sim.gd
ROOM_PX = 1800
LEISURE_PX = 2400


def box(name, center, size, mat, bevel=0.0):
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    bmesh.ops.scale(bm, vec=Vector(size), verts=bm.verts)
    o = bg.mesh_obj(name, bm, mat, smooth=False)
    o.location = center
    if bevel:
        b = o.modifiers.new("Bevel", "BEVEL")
        b.width = bevel
        b.segments = 2
    return o


def cyl(name, loc, r, depth, mat, rot=(0, 0, 0)):
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, segments=24, radius1=r, radius2=r, depth=depth, cap_ends=True)
    o = bg.mesh_obj(name, bm, mat)
    o.location = loc
    o.rotation_euler = Euler([math.radians(a) for a in rot])
    return o


def front_soil(x0, x1, mats):
    """Tranche de terre sous le sol, identique à celle du jardin."""
    box("Soil", ((x0 + x1) / 2, -4.0, -3.02), (x1 - x0 + 4, 3.0, 6.0), mats["soil"])
    for k in range(int((x1 - x0) * 4)):
        px = rng.uniform(x0, x1)
        pz = -rng.uniform(0.25, 2.5)
        r = rng.uniform(0.04, 0.13)
        bg.blob("Pebble", (px, -5.5 + r * 0.6, pz), (r * 1.4, r, r), mats["pebble"], 0.03, 0.2, 0)


def render(out_name, w_px):
    sc = bpy.context.scene
    width = w_px / PPU
    bg.layer_camera(width, w_px, bg.BOTTOM_PX - bg.TOP_PX)
    sc.render.filepath = str(OUT / out_name)
    bpy.ops.render.render(write_still=True)


# ------------------------------------------------------ salle d'apprentissage --
def render_room():
    w_px, h_px = ROOM_PX, bg.BOTTOM_PX - bg.TOP_PX
    width = w_px / PPU
    bg.reset_scene(w_px, h_px)
    sc = bpy.context.scene
    sc.render.film_transparent = True
    sc.cycles.samples = 32
    sc.world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.25
    mats = bg.materials()
    floor = bg.material("Floor", (0.45, 0.28, 0.14), 0.5, 3.0, 0.3, (0.3, 0.17, 0.08))
    plaster = bg.material("Plaster", (0.78, 0.66, 0.48), 0.9, 2.0, 0.15, (0.66, 0.53, 0.37))
    wood = bg.material("Wood", (0.36, 0.21, 0.1), 0.6, 6.0, 0.3, (0.2, 0.11, 0.05))
    dark = bg.material("DarkWood", (0.2, 0.11, 0.06), 0.6, 6.0, 0.3, (0.1, 0.05, 0.02))
    sky = bg.material("WindowSky", (0.45, 0.68, 0.92), 0.5, emit=0.45)
    rug = bg.material("Rug", (0.55, 0.16, 0.2), 0.95, 12.0, 0.3, (0.35, 0.1, 0.14))
    lamp = bg.material("LampGlow", (1.0, 0.85, 0.55), 0.5, emit=6.0)

    front_soil(-1, width + 1, mats)
    box("Floor", (width / 2, 1.0, -0.05), (width + 2, 8.0, 0.1), floor)
    box("BackWall", (width / 2, 4.6, 2.6), (width + 2, 0.2, 5.4), plaster)
    box("Wainscot", (width / 2, 4.45, 0.55), (width + 2, 0.12, 1.1), wood)
    box("Skirting", (width / 2, 4.38, 1.12), (width + 2, 0.16, 0.08), dark)
    box("Ceiling", (width / 2, 1.5, 4.75), (width + 2, 7.0, 0.5), dark)
    for x in [0.3, width - 0.3]:                                   # piliers aux extrémités
        box("Pillar", (x, 4.2, 2.4), (0.6, 0.8, 4.8), wood, 0.03)
    # Fenêtres (ciel lumineux, croisillons)
    for x in [3.0, 7.5, 12.0]:
        box("Window", (x, 4.48, 2.6), (2.0, 0.05, 1.7), sky)
        box("WinFrameH", (x, 4.42, 2.6), (2.1, 0.08, 0.08), dark)
        box("WinFrameV", (x, 4.42, 2.6), (0.08, 0.08, 1.8), dark)
        box("Sill", (x, 4.3, 1.68), (2.3, 0.35, 0.08), wood)
        for side in (-1, 1):
            box("WinSide", (x + side * 1.05, 4.42, 2.6), (0.1, 0.1, 1.8), dark)
        box("WinTop", (x, 4.42, 3.5), (2.2, 0.1, 0.1), dark)
    # Étagères de livres
    colors = [(0.6, 0.15, 0.12), (0.15, 0.35, 0.55), (0.2, 0.45, 0.2), (0.75, 0.6, 0.2), (0.45, 0.2, 0.45)]
    for sx, sz in [(5.25, 1.6), (5.25, 2.4), (9.75, 1.6), (9.75, 2.4)]:
        box("Shelf", (sx, 4.3, sz), (1.6, 0.35, 0.06), wood)
        x = sx - 0.7
        while x < sx + 0.7:
            w = rng.uniform(0.06, 0.12)
            h = rng.uniform(0.22, 0.36)
            box("Book", (x + w / 2, 4.3, sz + 0.03 + h / 2), (w, 0.28, h),
                bg.material("Book", rng.choice(colors), 0.7))
            x += w + 0.01
    # Tapis, plantes et lampes suspendues
    rugo = bg.blob("Rug", (width / 2, 2.4, 0.0), (3.2, 1.2, 0.02), rug, 0.0, 0.5, 0)
    for px in [1.4, width - 1.4]:
        cyl("Pot", (px, 3.6, 0.3), 0.28, 0.6, bg.material("Pot", (0.65, 0.3, 0.15), 0.6))
        for k in range(5):
            bg.blob("Plant", (px + rng.uniform(-0.3, 0.3), 3.6, 0.8 + k * 0.18),
                    (0.35, 0.3, 0.28), mats["leaves2"], 0.15, 0.3, 1)
    for x in [2.5, 7.5, 12.5]:
        cyl("Cord", (x, 2.5, 4.2), 0.01, 0.6, dark)
        bg.blob("Lamp", (x, 2.5, 3.85), (0.22, 0.22, 0.16), lamp, 0.0, 0.5, 0)
        light = bpy.data.lights.new("Lamp", "POINT")
        light.energy = 260
        light.color = (1.0, 0.85, 0.6)
        o = bg.link(bpy.data.objects.new("Lamp", light))
        o.location = (x, 1.5, 3.4)
    fill = bpy.data.lights.new("Fill", "AREA")
    fill.energy = 900
    fill.size = 12
    o = bg.link(bpy.data.objects.new("Fill", fill))
    o.location = (width / 2, -6, 3)
    o.rotation_euler = Euler((math.radians(80), 0, 0))
    render("decor_salle.png", w_px)


# ---------------------------------------------------------- aire de loisirs --
def render_leisure():
    w_px, h_px = LEISURE_PX, bg.BOTTOM_PX - bg.TOP_PX
    width = w_px / PPU
    bg.reset_scene(w_px, h_px)
    sc = bpy.context.scene
    sc.render.film_transparent = True
    sc.cycles.samples = 24
    mats = bg.materials()
    g = bg.ground(-1, width + 1, mats)
    for tx, ty in [(1.5, 3.2), (18.5, 3.0), (9.0, 10.0)]:
        bg.tree(tx, ty, rng.uniform(3.6, 4.2), mats)
    white = bg.material("Paint", (0.85, 0.82, 0.75), 0.6)
    red = bg.material("Red", (0.75, 0.15, 0.1), 0.4)
    yellow = bg.material("Yellow", (0.9, 0.7, 0.1), 0.4)
    blue = bg.material("Blue", (0.15, 0.35, 0.75), 0.4)
    sand = bg.material("Sand", (0.78, 0.66, 0.42), 0.95, 8.0, 0.3, (0.6, 0.5, 0.3))
    wood = bg.material("Wood", (0.42, 0.26, 0.12), 0.6, 6.0, 0.3, (0.25, 0.14, 0.06))
    # Barrière au fond
    x = 0.0
    while x <= width:
        box("Post", (x, 5.5, 0.55), (0.1, 0.1, 1.1 + 0.2), white, 0.02)
        x += 1.2
    for z in [0.45, 0.9]:
        box("Rail", (width / 2, 5.5, z), (width, 0.06, 0.08), white)
    # Toboggan (décor)
    sx = 11.5
    for dx in (0.0, 0.5):
        box("Ladder", (sx + dx, 3.2, 1.0), (0.08, 0.08, 2.0), blue)
    for k in range(5):
        box("Rung", (sx + 0.25, 3.2, 0.3 + k * 0.38), (0.5, 0.06, 0.05), yellow)
    box("Platform", (sx + 0.25, 3.2, 2.0), (0.7, 0.7, 0.08), blue)
    slide = box("Slide", (sx + 1.6, 3.2, 1.05), (2.6, 0.6, 0.06), red, 0.02)
    slide.rotation_euler = Euler((0, math.radians(38), 0))
    # Bac à sable
    box("SandBox", (5.0, 2.8, 0.15), (2.4, 1.4, 0.3), wood, 0.03)
    box("Sand", (5.0, 2.8, 0.22), (2.2, 1.2, 0.2), sand)
    # Guirlande de fanions
    poles = [0.8, 7.5, 14.5, width - 0.8]
    for px in poles:
        cyl("Pole", (px, 4.6, 1.6), 0.05, 3.2, white)
    flag_cols = [red, yellow, blue, bg.material("Green", (0.2, 0.6, 0.25), 0.4)]
    for a, b in zip(poles, poles[1:]):
        n = int((b - a) / 0.5)
        for k in range(n):
            t = (k + 0.5) / n
            fx = a + (b - a) * t
            fz = 3.1 - 0.5 * math.sin(math.pi * t)
            bm = bmesh.new()
            v = [bm.verts.new(p) for p in [(-0.15, 0, 0), (0.15, 0, 0), (0, 0, -0.32)]]
            bm.faces.new(v)
            f = bg.mesh_obj("Flag", bm, flag_cols[k % 4], smooth=False)
            f.location = (fx, 4.55, fz)
    # Fleurs
    petal_cols = [(0.9, 0.3, 0.4), (0.95, 0.85, 0.2), (0.6, 0.4, 0.9), (1.0, 1.0, 1.0)]
    for i in range(60):
        fx, fy = rng.uniform(0, width), rng.uniform(1.2, 5.0)
        bg.blob("Flower", (fx, fy, 0.18), (0.07, 0.07, 0.05),
                bg.material("Petal", rng.choice(petal_cols), 0.5, sss=0.2), 0.0, 0.5, 0)
    bg.grass(g, mats, int(150 * width))
    bg.lights()
    render("decor_loisirs.png", w_px)


if __name__ == "__main__":
    OUT.mkdir(parents=True, exist_ok=True)
    if MODE == "salle":
        render_room()
    elif MODE == "loisirs":
        render_leisure()
