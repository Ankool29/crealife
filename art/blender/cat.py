"""Chat quadrupède de CreaLife, rendu en sprites par couches.

Utilisation :
  python cat.py <dossier> test      # une pose, toutes couches réunies (aperçu)
  python cat.py <dossier> sprites   # toutes les poses, couches et masques

Comme la créature d'avant, le chat est rendu en niveaux de gris : le jeu le
colore selon ses gènes de pelage. Couches séparées (le corps sert de masque
aux autres) : corps, 3 têtes (en coin, moyenne, ronde), 2 queues (longue,
courte), chacune en poil court et en poil long. Pour chaque image et chaque
couche, deux masques :
  m1 : rouge = tigré maquereau, vert = tigré classique, bleu = moucheté
  m2 : rouge = extrémités (siamois), vert = ordre d'apparition du blanc
       (bas = blanchit en premier), bleu = plaques d'écaille de tortue
Le chat regarde vers +X, le sol est à z = 0.
"""
import json
import math
import sys
from pathlib import Path

import bpy
import bmesh  # après bpy
from mathutils import Euler, Vector

sys.path.insert(0, str(Path(__file__).parent))
import creature as cr  # noqa: E402  (scène, lumières, formes organiques)

OUT = Path(sys.argv[1] if len(sys.argv) > 1 else "out")
MODE = sys.argv[2] if len(sys.argv) > 2 else "test"
SPRITE_RES = 320
HEADS = ["coin", "moyenne", "ronde"]
TAILS = ["longue", "courte"]
FURS = ["c", "l"]                     # poil court, poil long

# Articulations
NECK = (0.47, 0, 0.66)
TAIL_ROOT = (-0.42, 0, 0.56)
LEGS = {   # nom : (épaule ou hanche, coude ou genou, côté y)
    "fl": ((0.32, 0, 0.5), (0.3, 0, 0.27), -0.09),
    "fr": ((0.32, 0, 0.5), (0.3, 0, 0.27), 0.09),
    "hl": ((-0.27, 0, 0.47), (-0.16, 0, 0.3), -0.09),
    "hr": ((-0.27, 0, 0.47), (-0.16, 0, 0.3), 0.09),
}


def seg(a, b, ra, rb, steps=10):
    return cr._seg(a, b, ra, rb, steps)


# ------------------------------------------------------------ matériaux ----
def fur_material():
    """Pelage gris uniforme ; le relief du poil vient d'un bruit fin."""
    m = bpy.data.materials.new("Fur")
    m.use_nodes = True
    nt = m.node_tree
    b = nt.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (0.5, 0.5, 0.5, 1)
    b.inputs["Roughness"].default_value = 0.75
    b.inputs["Sheen Weight"].default_value = 0.6
    b.inputs["Sheen Roughness"].default_value = 0.4
    tc = nt.nodes.new("ShaderNodeTexCoord")
    nz = nt.nodes.new("ShaderNodeTexNoise")
    nz.inputs["Scale"].default_value = 140.0
    nz.inputs["Detail"].default_value = 4.0
    nt.links.new(tc.outputs["Object"], nz.inputs["Vector"])
    bump = nt.nodes.new("ShaderNodeBump")
    bump.inputs["Strength"].default_value = 0.35
    nt.links.new(nz.outputs["Fac"], bump.inputs["Height"])
    nt.links.new(bump.outputs["Normal"], b.inputs["Normal"])
    return m


def hair_material():
    m = bpy.data.materials.new("Hair")
    m.use_nodes = True
    nt = m.node_tree
    for node in list(nt.nodes):
        nt.nodes.remove(node)
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    h = nt.nodes.new("ShaderNodeBsdfHairPrincipled")
    h.parametrization = "COLOR"
    h.inputs["Color"].default_value = (0.5, 0.5, 0.5, 1)
    h.inputs["Roughness"].default_value = 0.5
    nt.links.new(h.outputs[0], out.inputs["Surface"])
    return m


def add_long_fur(obj, hair_mat=None, length=0.05, count=0, flow=None):
    """Poil long : une enveloppe ébouriffée autour de la pièce (copie du
    maillage poussée vers l'extérieur par un bruit fin, en touffes).
    Bien plus rapide à rendre que des particules de poils."""
    shell = obj.copy()                      # même maillage, mêmes matériaux
    shell.name = obj.name + "_Poil"
    shell.data = obj.data
    for c in obj.users_collection:
        c.objects.link(shell)
    shell.parent = obj
    shell.location = (0, 0, 0)
    shell.rotation_euler = (0, 0, 0)
    tex = bpy.data.textures.get("Meches")
    if tex is None:
        tex = bpy.data.textures.new("Meches", "CLOUDS")
        tex.noise_scale = 0.045
        tex.noise_depth = 3
        tex.noise_basis = "BLENDER_ORIGINAL"
    # Les mèches s'étirent le long du corps (ou vers le bas pour les pattes) :
    # coordonnées d'un objet vide étiré dans cette direction.
    along = "Z" if obj.name.startswith("Up_") else "X"
    guide = bpy.data.objects.get("Guide" + along)
    if guide is None:
        guide = bpy.data.objects.new("Guide" + along, None)
        bpy.context.scene.collection.objects.link(guide)
        guide.scale = (4.0, 1.0, 1.0) if along == "X" else (1.0, 1.0, 4.0)
    d = shell.modifiers.new("Meches", "DISPLACE")
    d.texture = tex
    d.strength = length * 1.6
    d.mid_level = 0.35                      # surtout vers l'extérieur
    d.texture_coords = "OBJECT"
    d.texture_coords_object = guide
    sm = shell.modifiers.new("Lisse", "SMOOTH")
    sm.factor = 0.6
    sm.iterations = 4
    return shell


# ---------------------------------------------------------------- formes ----
def into(objs, name):
    col = bpy.data.collections.get(name) or bpy.data.collections.new(name)
    if col.name not in bpy.context.scene.collection.children:
        bpy.context.scene.collection.children.link(col)
    for o in objs:
        for c in list(o.users_collection):
            c.objects.unlink(o)
        col.objects.link(o)
        for ch in o.children:
            into([ch], name)


def build_cat():
    root = bpy.data.objects.new("Root", None)
    bpy.context.collection.objects.link(root)
    fur = fur_material()
    hair = None
    eye_mat = cr.glow_material("CatEye", (0.15, 0.85, 0.2), 0.6)       # recoloré en jeu
    pupil_mat = cr.simple_material("Pupil", (0.01, 0.01, 0.01), 0.2, 1.0)
    parts = {"root": root, "legs": {}, "heads": [], "tails": [], "fur": []}

    body = cr.organic("Body", (0, 0, 0.5),
        seg((-0.28, 0, 0.51), (0.06, 0, 0.49), 0.185, 0.175, 18)        # croupe -> ventre
        + seg((0.06, 0, 0.49), (0.32, 0, 0.53), 0.175, 0.19, 18)        # ventre -> poitrail
        + [((0.3, 0, 0.45), (0.13, 0.14, 0.13), 0),                      # épaules
           ((-0.26, 0, 0.43), (0.15, 0.145, 0.15), 0),                   # cuisses
           ((0.43, 0, 0.62), (0.11, 0.1, 0.14), -40)],                   # cou
        fur, root, smooth=14)
    parts["body"] = body
    parts["fur"].append(add_long_fur(body, hair, 0.075, 3500))

    for name, (top, mid, y) in LEGS.items():
        front = name[0] == "f"
        t = (top[0], y, top[2])
        m = (mid[0], y, mid[2])
        upper = cr.organic("Up_" + name, t, seg(t, m, 0.09 if front else 0.12, 0.062) +
                           ([((t[0] + 0.02, y, t[2] - 0.08), (0.12, 0.075, 0.15), 0)] if not front else
                            [((t[0], y, t[2] - 0.05), (0.08, 0.07, 0.11), 0)]),
                           fur, body, smooth=8)
        upper.location = Vector(t) - Vector((0, 0, 0.5))
        if front:
            low_pts = seg(m, (0.33, y, 0.06), 0.058, 0.045) + [((0.36, y, 0.032), (0.065, 0.05, 0.035), 0)]
        else:
            low_pts = (seg(m, (-0.3, y, 0.13), 0.065, 0.045) + seg((-0.3, y, 0.13), (-0.27, y, 0.04), 0.045, 0.042)
                       + [((-0.23, y, 0.032), (0.065, 0.05, 0.035), 0)])
        lower = cr.organic("Low_" + name, m, low_pts, fur, upper, smooth=6)
        lower.location = Vector(m) - Vector(t)
        parts["legs"][name] = (upper, lower)
        parts["fur"].append(add_long_fur(upper, hair, 0.04))

    # Têtes : en coin (orientale), moyenne, ronde (type persan, sans excès)
    shapes = [
        dict(cran=((0.6, 0, 0.79), (0.14, 0.12, 0.12)), muz=((0.78, 0, 0.73), (0.08, 0.06, 0.055)),
             cheek=((0.66, 0, 0.73), (0.1, 0.1, 0.08)), ear=((0.57, 0.07, 0.88), (0.53, 0.1, 1.05), 0.065),
             eye=(0.71, 0.75 + 0.06)),
        dict(cran=((0.6, 0, 0.79), (0.15, 0.14, 0.13)), muz=((0.75, 0, 0.73), (0.065, 0.075, 0.055)),
             cheek=((0.66, 0, 0.73), (0.11, 0.12, 0.09)), ear=((0.58, 0.08, 0.89), (0.56, 0.1, 0.99), 0.055),
             eye=(0.705, 0.8)),
        dict(cran=((0.61, 0, 0.79), (0.16, 0.16, 0.15)), muz=((0.735, 0, 0.75), (0.05, 0.08, 0.05)),
             cheek=((0.66, 0, 0.74), (0.12, 0.14, 0.1)), ear=((0.58, 0.1, 0.9), (0.57, 0.12, 0.96), 0.05),
             eye=(0.748, 0.8)),
    ]
    def big(p, f=1.22):
        return tuple(NECK[i] + (p[i] - NECK[i]) * f for i in range(3))

    for sh in shapes:
        for key in ("cran", "muz", "cheek"):
            c, r = sh[key]
            sh[key] = (big(c), tuple(v * 1.22 for v in r))
        a, b, r = sh["ear"]
        sh["ear"] = (big(a), big(b), r * 1.25)
        ex, ez = sh["eye"]
        e = big((ex, 0, ez))
        sh["eye"] = (e[0], e[2])
    for k, sh in enumerate(shapes):
        el = [(sh["cran"][0], sh["cran"][1], 0), (sh["muz"][0], sh["muz"][1], 0),
              (sh["cheek"][0], sh["cheek"][1], 0), ((0.53, 0, 0.7), (0.1, 0.09, 0.11), -30)]
        head = cr.organic(f"Head{k}", NECK, el, fur, root, smooth=10)
        objs = [head]
        for side, sy in (("L", -1), ("R", 1)):
            (a, b, r) = sh["ear"]
            back = 0.0 if sy < 0 else -0.06          # l'oreille du fond, un peu en arrière, reste visible
            ear = cr.organic(f"Ear{k}{side}", NECK,
                             seg((a[0] + back, a[1] * sy, a[2]), (b[0] + back, b[1] * sy, b[2]), r, 0.008, 8),
                             fur, head, voxel=0.006, smooth=3)
            ear.location = (0, 0, 0)
            ex, ez = sh["eye"]
            ey = 0.08 * sy
            eye = cr.sphere(f"Eye{k}{side}", (ex, ey, ez), 0.04, eye_mat, head, (0.8, 0.6, 1.0), NECK)
            cr.sphere(f"Pupil{k}{side}", (ex + 0.03, ey + 0.004 * sy, ez), 0.015, pupil_mat, head, (0.5, 0.6, 2.2), NECK)
            lid = cr.sphere(f"Lid{k}{side}", (ex + 0.004, ey, ez), 0.045, fur, head, (0.85, 0.65, 1.05), NECK)
            lid.hide_render = True
        parts["fur"].append(add_long_fur(head, hair, 0.012))   # fin : les yeux restent visibles
        into(objs, f"Tete{k}")
        parts["heads"].append(head)

    tails = [
        seg((-0.4, 0, 0.56), (-0.62, 0, 0.5), 0.065, 0.055) + seg((-0.62, 0, 0.5), (-0.82, 0, 0.6), 0.055, 0.048)
        + seg((-0.82, 0, 0.6), (-0.9, 0, 0.78), 0.048, 0.038),
        seg((-0.4, 0, 0.56), (-0.52, 0, 0.6), 0.06, 0.05),
    ]
    for k, el in enumerate(tails):
        tail = cr.organic(f"Tail{k}", TAIL_ROOT, el, fur, root, smooth=6)
        parts["fur"].append(add_long_fur(tail, hair, 0.085))
        into([tail], f"Queue{k}")
        parts["tails"].append(tail)
    return parts


# ---------------------------------------------------------------- poses ----
def pose(p, fl=(0, 0), fr=(0, 0), hl=(0, 0), hr=(0, 0), head=0.0, tail=0.0, body_z=0.0, lean=0.0,
         body_x=0.0):
    """Angles en degrés autour de Y : membres, négatif = vers l'avant ;
    tête, positif = vers le bas ; queue, positif = vers le bas."""
    for name, (u, lo) in zip(["fl", "fr", "hl", "hr"], [fl, fr, hl, hr]):
        up, low = p["legs"][name]
        up.rotation_euler = Euler((0, math.radians(u), 0))
        low.rotation_euler = Euler((0, math.radians(lo), 0))
    for h in p["heads"]:
        h.rotation_euler = Euler((0, math.radians(head), 0))
    for t in p["tails"]:
        t.rotation_euler = Euler((0, math.radians(tail), 0))
    p["root"].location = (body_x, 0, body_z)
    p["root"].rotation_euler = Euler((0, math.radians(lean), 0))


def set_lids(closed):
    for o in bpy.data.objects:
        if o.name.startswith("Lid"):
            o.hide_render = not closed
        if o.name.startswith(("Eye", "Pupil")):
            o.hide_render = closed


def walk(phase):
    a = math.tau * phase
    s = math.sin(a)
    lift_f = max(0.0, math.sin(a + 1.4))
    lift_b = max(0.0, math.sin(a + 1.4 + math.pi))
    return dict(fl=(-22 * s, 35 * lift_f), hr=(-22 * s, -30 * lift_f),
                fr=(22 * s, 35 * lift_b), hl=(22 * s, -30 * lift_b),
                head=2 * math.sin(2 * a), tail=8 + 6 * math.sin(a), body_z=-0.012 * abs(math.cos(a)))


ANIMATIONS = {
    "repos": [dict(tail=10, head=-3), dict(tail=16, head=0, fl=(-3, 0), hl=(3, 0))],
    "marche": [walk(i / 8.0) for i in range(8)],
    "manger": [dict(head=50, fl=(10, -20), fr=(10, -20), lean=12, body_z=-0.03, tail=5),
               dict(head=56, fl=(10, -20), fr=(10, -20), lean=12, body_z=-0.03, tail=12)],
    "pousser": [dict(fl=(-55, -25), head=12, tail=20, lean=5), dict(fl=(-35, -10), head=10, tail=25, lean=4)],
    "frapper": [dict(fl=(-95, -70), head=-8, tail=35, lean=-6, body_z=0.03),
                dict(fl=(-40, 20), head=10, tail=30, lean=6)],
    "prendre": [dict(head=52, fl=(8, -18), fr=(8, -18), lean=12, body_z=-0.03, tail=10)],
    "examiner": [dict(head=25, fl=(-10, 0), lean=6, tail=25)],
    "parler": [dict(head=-28, tail=30, lean=-4)],
    "dormir": ["loaf"],
    "mort": ["sprawl"],
}


def apply_pose(p, spec):
    set_lids(False)
    if spec == "loaf":          # en pain de chat : pattes repliées sous le corps
        pose(p, fl=(-88, 172), fr=(-88, 172), hl=(88, -172), hr=(88, -172), head=30, tail=-35,
             body_z=-0.29)
        set_lids(True)
    elif spec == "sprawl":      # étendu au sol, pattes allongées
        pose(p, fl=(-85, 0), fr=(-80, 0), hl=(85, 0), hr=(80, 0), head=35, tail=-25, body_z=-0.33)
        set_lids(True)
    else:
        pose(p, **spec)


# --------------------------------------------------------------- rendu ----
def setup():
    cr.reset_scene()
    cr.setup_camera_and_lights()
    cam = bpy.context.scene.camera
    cam.data.ortho_scale = 2.4
    cam.location = (-0.05, -6.0, 0.62)
    sc = bpy.context.scene
    sc.render.resolution_x = SPRITE_RES
    sc.render.resolution_y = SPRITE_RES
    sc.cycles.samples = 32


def set_fur(parts, long_fur):
    for shell in parts["fur"]:
        shell.hide_render = not long_fur


def show_layer(layer):
    """layer : "corps", "tete<k>" ou "queue<k>". Le corps sert de masque aux autres."""
    vl = bpy.context.view_layer.layer_collection
    for lc in vl.children:
        if lc.name.startswith("Tete"):
            lc.exclude = layer != "tete" + lc.name[4:]
        elif lc.name.startswith("Queue"):
            lc.exclude = layer != "queue" + lc.name[5:]
    holdout = layer != "corps"
    for o in bpy.context.scene.collection.objects:
        o.is_holdout = holdout
    for o in bpy.data.objects:
        if o.parent and o.parent.name == "Body" or o.name.startswith(("Up_", "Low_")):
            o.is_holdout = holdout


# Masques : un matériau par type de partie (direction des rayures, extrémités...)
def mask_material(name, kind, which):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    n, ln = nt.nodes, nt.links
    for node in list(n):
        n.remove(node)
    out = n.new("ShaderNodeOutputMaterial")
    emit = n.new("ShaderNodeEmission")
    ln.new(emit.outputs[0], out.inputs["Surface"])
    tc = n.new("ShaderNodeTexCoord")
    comb = n.new("ShaderNodeCombineColor")
    ln.new(comb.outputs[0], emit.inputs["Color"])

    def remap(src, a, b):
        r = n.new("ShaderNodeMapRange")
        r.inputs["From Min"].default_value = a
        r.inputs["From Max"].default_value = b
        ln.new(src, r.inputs["Value"])
        return r.outputs["Result"]

    def const(v):
        c = n.new("ShaderNodeValue")
        c.outputs[0].default_value = v
        return c.outputs[0]

    if which == 1:
        direction = {"corps": "X", "patte": "Z", "queue": "X", "tete": "X"}[kind]
        wave = n.new("ShaderNodeTexWave")
        wave.wave_type = "BANDS"
        wave.bands_direction = direction
        wave.inputs["Scale"].default_value = 3.2 if kind != "tete" else 5.0
        wave.inputs["Distortion"].default_value = 3.0
        wave.inputs["Detail"].default_value = 1.5
        ln.new(tc.outputs["Object"], wave.inputs["Vector"])
        ln.new(remap(wave.outputs["Fac"], 0.58, 0.7), comb.inputs[0])
        if kind == "corps":     # tigré classique : grands cercles sur le flanc
            rings = n.new("ShaderNodeTexWave")
            rings.wave_type = "RINGS"
            rings.inputs["Scale"].default_value = 3.5
            rings.inputs["Distortion"].default_value = 4.0
            rings.inputs["Detail"].default_value = 1.0
            ln.new(tc.outputs["Object"], rings.inputs["Vector"])
            ln.new(remap(rings.outputs["Fac"], 0.45, 0.6), comb.inputs[1])
        else:                   # ailleurs : bandes plus épaisses
            ln.new(remap(wave.outputs["Fac"], 0.42, 0.62), comb.inputs[1])
        vor = n.new("ShaderNodeTexVoronoi")
        vor.inputs["Scale"].default_value = 9.0 if kind != "tete" else 14.0
        ln.new(tc.outputs["Object"], vor.inputs["Vector"])
        ln.new(remap(vor.outputs["Distance"], 0.32, 0.26), comb.inputs[2])
    else:
        # extrémités : tête, pattes (surtout le bas), queue ; pas le corps
        pts = {"corps": 0.0, "patte": 0.85, "queue": 1.0, "tete": 0.9}[kind]
        ln.new(const(pts), comb.inputs[0])
        # ordre du blanc : le dessous blanchit d'abord, puis pattes, flancs, dos,
        # et en dernier le dessus de la tête et la queue (motif « van »)
        sep = n.new("ShaderNodeSeparateXYZ")
        ln.new(tc.outputs["Normal"], sep.inputs[0])
        nz = n.new("ShaderNodeTexNoise")
        nz.inputs["Scale"].default_value = 3.0
        ln.new(tc.outputs["Object"], nz.inputs["Vector"])
        base = {"corps": (0.15, 0.7), "patte": (0.05, 0.35), "queue": (0.88, 0.95), "tete": (0.3, 0.92)}[kind]
        rank = remap(sep.outputs["Z"], -1.0, 1.0)
        r2 = n.new("ShaderNodeMapRange")
        r2.inputs["To Min"].default_value = base[0]
        r2.inputs["To Max"].default_value = base[1]
        ln.new(rank, r2.inputs["Value"])
        mix = n.new("ShaderNodeMix")
        mix.data_type = "FLOAT"
        mix.inputs["Factor"].default_value = 0.18
        ln.new(r2.outputs["Result"], mix.inputs["A"])
        ln.new(nz.outputs["Fac"], mix.inputs["B"])
        ln.new(mix.outputs["Result"], comb.inputs[1])
        tort = n.new("ShaderNodeTexNoise")
        tort.inputs["Scale"].default_value = 3.5
        tort.inputs["Detail"].default_value = 3.0
        ln.new(tc.outputs["Object"], tort.inputs["Vector"])
        ln.new(remap(tort.outputs["Fac"], 0.47, 0.53), comb.inputs[2])
    return m


def part_kind(o):
    if o.name.startswith(("Up_", "Low_")):
        return "patte"
    if o.name.startswith(("Head", "Ear", "Lid")):
        return "tete"
    if o.name.startswith("Tail"):
        return "queue"
    return "corps"


def render_mask(path, which):
    sc = bpy.context.scene
    saved = {}               # par maillage : la pièce et son poil long partagent le même
    holdouts = {}
    for o in bpy.data.objects:
        if o.type != "MESH":
            continue
        if o.name.startswith(("Eye", "Pupil")):
            holdouts[o.name] = o.is_holdout
            o.is_holdout = True
            continue
        if o.data.name in saved:
            continue
        kind = part_kind(o)
        mat = bpy.data.materials.get(f"Mask{which}_{kind}") or mask_material(f"Mask{which}_{kind}", kind, which)
        saved[o.data.name] = list(o.data.materials)
        for i in range(len(o.data.materials)):
            o.data.materials[i] = mat
    exposure, samples, denoise = sc.view_settings.exposure, sc.cycles.samples, sc.cycles.use_denoising
    sc.view_settings.exposure = 0.0
    sc.cycles.samples = 8
    sc.cycles.use_denoising = False
    cr.render(path)
    sc.view_settings.exposure, sc.cycles.samples, sc.cycles.use_denoising = exposure, samples, denoise
    for name, mats in saved.items():
        me = bpy.data.meshes[name]
        for i, mat in enumerate(mats):
            me.materials[i] = mat
    for name, h in holdouts.items():
        bpy.data.objects[name].is_holdout = h


def render_sprites(out, parts):
    sc = bpy.context.scene
    cam = sc.camera
    ppu = SPRITE_RES / cam.data.ortho_scale
    manifest = {"size": SPRITE_RES, "px_per_unit": ppu,
                "anchor": [SPRITE_RES / 2 - cam.location.x * ppu, SPRITE_RES / 2 + cam.location.z * ppu],
                "animations": {}, "heads": HEADS, "tails": TAILS, "furs": FURS,
                "mouth": [0.8 * ppu, -0.12 * ppu], "head_top": -1.05 * ppu, "body_center": [0.0, -0.5 * ppu]}
    layers = ["corps"] + [f"tete{k}" for k in range(len(HEADS))] + [f"queue{k}" for k in range(len(TAILS))]
    for name, poses in ANIMATIONS.items():
        frames = []
        for i, spec in enumerate(poses):
            apply_pose(parts, spec)
            base = f"{name}_{i}"
            for f, fur in enumerate(FURS):
                set_fur(parts, fur == "l")
                for layer in layers:
                    show_layer(layer)
                    cr.render(out / f"{base}_{layer}_{fur}.png")
                    render_mask(out / f"{base}_{layer}_{fur}_m1.png", 1)
                    render_mask(out / f"{base}_{layer}_{fur}_m2.png", 2)
            frames.append(base)
        manifest["animations"][name] = frames
    show_layer("corps")
    (out / "chat.json").write_text(json.dumps(manifest, indent="\t"))


if __name__ == "__main__":
    OUT.mkdir(parents=True, exist_ok=True)
    setup()
    parts = build_cat()
    if MODE == "sprites":
        render_sprites(OUT, parts)
        sys.exit(0)
    # Aperçu : plusieurs poses, toutes les couches visibles (tête moyenne, queue longue)
    bpy.context.scene.render.resolution_x = 480
    bpy.context.scene.render.resolution_y = 480
    vl = bpy.context.view_layer.layer_collection
    head_k = int(sys.argv[4]) if len(sys.argv) > 4 else 1
    for lc in vl.children:
        lc.exclude = lc.name.startswith("Tete") and lc.name != f"Tete{head_k}" or lc.name == "Queue1"
    set_fur(parts, len(sys.argv) > 3 and sys.argv[3] == "l")
    for spec_name, spec in [("repos", ANIMATIONS["repos"][0]), ("marche", ANIMATIONS["marche"][2]),
                            ("manger", ANIMATIONS["manger"][0]), ("frapper", ANIMATIONS["frapper"][0]),
                            ("dormir", "loaf"), ("mort", "sprawl")]:
        apply_pose(parts, spec)
        cr.render(OUT / f"test_{spec_name}.png")
