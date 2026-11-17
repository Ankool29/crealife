"""Modèle 3D de la créature de CreaLife, rendu en sprites (comme Creatures 3).

Utilisation (Python 3.11 avec le module bpy) :
    python creature.py <dossier_sortie> [test]

La créature est construite en « marionnette » : torse, tête, pattes et queue
sont des objets séparés avec leur pivot, ce qui permet de les poser pour
générer les images d'animation.
"""
import json
import math
import sys
from pathlib import Path

import bpy
from mathutils import Euler, Vector

OUT = Path(sys.argv[1] if len(sys.argv) > 1 else "out")
MODE = sys.argv[2] if len(sys.argv) > 2 else "test"


# ---------------------------------------------------------------- scène ----
def reset_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = 48
    scene.cycles.use_denoising = True
    scene.render.film_transparent = True
    scene.render.resolution_x = 512
    scene.render.resolution_y = 512
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"
    scene.view_settings.view_transform = "Standard"
    scene.view_settings.exposure = -0.35
    world = bpy.data.worlds.new("World")
    scene.world = world
    world.use_nodes = True
    bg = world.node_tree.nodes["Background"]
    bg.inputs["Color"].default_value = (0.32, 0.36, 0.42, 1.0)
    bg.inputs["Strength"].default_value = 0.35
    return scene


def add_light(name, kind, loc, rot_deg, energy, color=(1, 1, 1), size=1.0):
    data = bpy.data.lights.new(name, kind)
    data.energy = energy
    data.color = color
    if kind == "AREA":
        data.size = size
    if kind == "SUN":
        data.angle = math.radians(8)
    obj = bpy.data.objects.new(name, data)
    obj.location = loc
    obj.rotation_euler = Euler([math.radians(a) for a in rot_deg])
    bpy.context.collection.objects.link(obj)
    return obj


def setup_camera_and_lights():
    cam_data = bpy.data.cameras.new("Cam")
    cam_data.type = "ORTHO"
    cam_data.ortho_scale = 1.9
    cam = bpy.data.objects.new("Cam", cam_data)
    cam.location = (0.05, -6.0, 0.86)
    cam.rotation_euler = Euler((math.radians(90), 0, 0))
    bpy.context.collection.objects.link(cam)
    bpy.context.scene.camera = cam
    # Lumière chaude principale (haut, devant, gauche), contre-jour froid, fill doux.
    add_light("Key", "SUN", (0, 0, 0), (40, 0, -50), 4.0, (1.0, 0.93, 0.82))
    add_light("Rim", "AREA", (-1.5, 2.5, 2.2), (-60, 0, 210), 420, (0.7, 0.85, 1.0), 2.0)
    add_light("Fill", "AREA", (1.5, -3.0, 0.4), (80, 0, 25), 45, (0.85, 0.9, 1.0), 3.0)


# ------------------------------------------------------------ matériaux ----
def simple_material(name, color, roughness=0.5, coat=0.0, emission=None):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    b = mat.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (*color, 1)
    b.inputs["Roughness"].default_value = roughness
    b.inputs["Coat Weight"].default_value = coat
    return mat


# ------------------------------------------------------------- formes ----
def organic(name, pivot, ellipsoids, mat, parent, voxel=0.009, smooth=6):
    """Fusionne des ellipsoïdes (coordonnées monde) en une forme organique lisse.

    ellipsoids : liste de (centre, rayons (rx, ry, rz), rotation Y en degrés)
    pivot : point de rotation de la pièce (articulation), en coordonnées monde.
    """
    import bmesh
    from mathutils import Matrix
    bm = bmesh.new()
    for center, radii, rot_y in ellipsoids:
        geom = bmesh.ops.create_uvsphere(bm, u_segments=24, v_segments=12, radius=1.0)
        m = (Matrix.Translation(Vector(center) - Vector(pivot))
             @ Matrix.Rotation(math.radians(rot_y), 4, "Y")
             @ Matrix.Diagonal((*radii, 1.0)))
        bmesh.ops.transform(bm, matrix=m, verts=geom["verts"])
    mesh = bpy.data.meshes.new(name + "Src")
    bm.to_mesh(mesh)
    bm.free()
    tmp = bpy.data.objects.new(name + "Src", mesh)
    bpy.context.collection.objects.link(tmp)
    rem = tmp.modifiers.new("Remesh", "REMESH")
    rem.mode = "VOXEL"
    rem.voxel_size = voxel
    sm = tmp.modifiers.new("Smooth", "SMOOTH")
    sm.factor = 0.7
    sm.iterations = smooth
    dg = bpy.context.evaluated_depsgraph_get()
    final = bpy.data.meshes.new_from_object(tmp.evaluated_get(dg))
    bpy.data.objects.remove(tmp)
    bpy.data.meshes.remove(mesh)
    for poly in final.polygons:
        poly.use_smooth = True
    final.materials.append(mat)
    obj = bpy.data.objects.new(name, final)
    bpy.context.collection.objects.link(obj)
    obj.location = Vector(pivot)
    obj.parent = parent
    return obj


def sphere(name, loc, radius, mat, parent, scale=(1, 1, 1), pivot=(0, 0, 0)):
    """Petite sphère (œil, nez) ; loc en coordonnées monde, relative au pivot du parent."""
    import bmesh
    mesh = bpy.data.meshes.new(name)
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=32, v_segments=16, radius=radius)
    bm.to_mesh(mesh)
    bm.free()
    for p in mesh.polygons:
        p.use_smooth = True
    mesh.materials.append(mat)
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    obj.location = Vector(loc) - Vector(pivot)
    obj.scale = scale
    obj.parent = parent
    return obj


# Articulations (coordonnées monde). La créature regarde vers +X, le sol est à z = 0.
HIP = (-0.02, 0, 0.66)
KNEE = (0.1, 0, 0.45)          # genou en avant...
ANKLE = (-0.08, 0, 0.23)        # ...cheville en arrière : pattes digitigrades
SHOULDER = (0.07, 0, 0.98)
NECK = (0.1, 0, 1.08)
LEG_Y = 0.1
ARM_Y = 0.15


def skin_material(root):
    """Peau lisse et légèrement translucide, dos sombre, taches luminescentes."""
    mat = bpy.data.materials.new("Skin")
    mat.use_nodes = True
    nt = mat.node_tree
    n, l = nt.nodes, nt.links
    bsdf = n["Principled BSDF"]
    coord = n.new("ShaderNodeTexCoord")
    coord.object = root
    sep = n.new("ShaderNodeSeparateXYZ")
    l.new(coord.outputs["Object"], sep.inputs[0])
    nsep = n.new("ShaderNodeSeparateXYZ")
    l.new(coord.outputs["Normal"], nsep.inputs[0])

    # Ventre clair (normale vers le bas / l'avant) -> dos sombre (normale vers le haut / l'arrière)
    side = n.new("ShaderNodeMath")
    side.operation = "SUBTRACT"
    l.new(nsep.outputs["Z"], side.inputs[0])
    l.new(nsep.outputs["X"], side.inputs[1])
    ramp = n.new("ShaderNodeValToRGB")
    ramp.color_ramp.elements[0].position = 0.25
    # Rendu en niveaux de gris : le jeu colorise selon les gènes.
    ramp.color_ramp.elements[0].color = (0.85, 0.85, 0.85, 1)   # ventre clair
    ramp.color_ramp.elements[1].position = 0.6
    ramp.color_ramp.elements[1].color = (0.42, 0.42, 0.42, 1)   # flancs
    e = ramp.color_ramp.elements.new(0.85)
    e.color = (0.16, 0.16, 0.16, 1)                             # dos sombre
    to01 = n.new("ShaderNodeMapRange")
    to01.inputs["From Min"].default_value = -1.0
    to01.inputs["From Max"].default_value = 1.0
    l.new(side.outputs[0], to01.inputs["Value"])
    l.new(to01.outputs["Result"], ramp.inputs[0])

    # Marbrures
    noise = n.new("ShaderNodeTexNoise")
    noise.inputs["Scale"].default_value = 9.0
    noise.inputs["Detail"].default_value = 6.0
    l.new(coord.outputs["Object"], noise.inputs["Vector"])
    marb = n.new("ShaderNodeMix")
    marb.data_type = "RGBA"
    marb.blend_type = "MULTIPLY"
    marb.inputs["Factor"].default_value = 0.35
    l.new(ramp.outputs["Color"], marb.inputs["A"])
    l.new(noise.outputs["Color"], marb.inputs["B"])
    l.new(marb.outputs["Result"], bsdf.inputs["Base Color"])

    # Taches luminescentes, seulement sur le dos
    vor = n.new("ShaderNodeTexVoronoi")
    vor.inputs["Scale"].default_value = 14.0
    l.new(coord.outputs["Object"], vor.inputs["Vector"])
    dots = n.new("ShaderNodeMapRange")
    dots.inputs["From Min"].default_value = 0.16
    dots.inputs["From Max"].default_value = 0.1
    l.new(vor.outputs["Distance"], dots.inputs["Value"])
    back = n.new("ShaderNodeMapRange")
    back.inputs["From Min"].default_value = 0.65
    back.inputs["From Max"].default_value = 0.85
    l.new(to01.outputs["Result"], back.inputs["Value"])
    glow = n.new("ShaderNodeMath")
    glow.operation = "MULTIPLY"
    l.new(dots.outputs["Result"], glow.inputs[0])
    l.new(back.outputs["Result"], glow.inputs[1])
    bsdf.inputs["Emission Color"].default_value = (0.3, 0.95, 0.85, 1)
    gain = n.new("ShaderNodeMath")
    gain.operation = "MULTIPLY"
    gain.inputs[1].default_value = 4.0
    l.new(glow.outputs[0], gain.inputs[0])
    l.new(gain.outputs[0], bsdf.inputs["Emission Strength"])

    bump = n.new("ShaderNodeBump")
    bump.inputs["Strength"].default_value = 0.12
    l.new(noise.outputs["Fac"], bump.inputs["Height"])
    l.new(bump.outputs["Normal"], bsdf.inputs["Normal"])
    bsdf.inputs["Roughness"].default_value = 0.38
    bsdf.inputs["Coat Weight"].default_value = 0.25
    bsdf.inputs["Coat Roughness"].default_value = 0.3
    bsdf.inputs["Subsurface Weight"].default_value = 0.25
    bsdf.inputs["Subsurface Radius"].default_value = (0.3, 0.3, 0.3)
    bsdf.inputs["Subsurface Scale"].default_value = 0.05
    # Reflets irisés
    bsdf.inputs["Thin Film Thickness"].default_value = 0.0      # pas d'irisation : elle colorerait le gris
    bsdf.inputs["Thin Film IOR"].default_value = 1.45
    return mat


def glow_material(name, color, strength):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    b = mat.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (*color, 1)
    b.inputs["Emission Color"].default_value = (*color, 1)
    b.inputs["Emission Strength"].default_value = strength
    b.inputs["Roughness"].default_value = 0.2
    b.inputs["Coat Weight"].default_value = 1.0
    return mat


def _seg(a, b, r_a, r_b, steps=12):
    """Ellipsoïdes en chaîne entre deux points (os d'un membre)."""
    out = []
    a, b = Vector(a), Vector(b)
    d = b - a
    ang = math.degrees(math.atan2(-d.z, d.x)) if d.length > 0 else 0
    for i in range(steps + 1):
        t = i / steps
        r = r_a + (r_b - r_a) * t
        c = a + d * t
        out.append(((c.x, c.y, c.z), (r * 1.3, r, r), ang))
    return out


def build_creature():
    root = bpy.data.objects.new("Root", None)
    bpy.context.collection.objects.link(root)
    skin = skin_material(root)
    eye_mat = simple_material("EyeDark", (0.01, 0.015, 0.03), 0.04, 1.0)
    iris_mat = glow_material("IrisGlow", (0.2, 0.8, 0.7), 0.8)
    bulb_mat = glow_material("Bulb", (0.3, 0.95, 0.7), 2.0)

    parts = {}
    parts["torso"] = organic("Torso", HIP, [
        ((-0.02, 0, 0.67), (0.13, 0.13, 0.11), 0),     # bassin
        ((-0.01, 0, 0.78), (0.12, 0.11, 0.12), 10),    # taille fine
        ((0.03, 0, 0.9), (0.14, 0.14, 0.15), 15),      # poitrine
        ((0.07, 0, 1.0), (0.1, 0.13, 0.08), 0),        # épaules
        ((0.1, 0, 1.08), (0.05, 0.05, 0.1), -15),      # base du cou
    ], skin, root, smooth=12)

    head = organic("Head", NECK, [
        ((0.12, 0, 1.15), (0.05, 0.05, 0.09), -20),    # cou
        ((0.08, 0, 1.36), (0.21, 0.12, 0.13), -28),    # crâne allongé vers l'arrière
        ((0.21, 0, 1.27), (0.1, 0.1, 0.09), 0),        # face
        ((0.3, 0, 1.22), (0.06, 0.06, 0.05), 10),      # petit museau
    ], skin, root, smooth=12)
    parts["head"] = head
    for side, y in (("L", -1), ("R", 1)):
        eye = (0.25, 0.085 * y, 1.3)
        e = sphere("Eye" + side, eye, 0.07, eye_mat, head, (1.0, 0.55, 1.25), NECK)
        e.rotation_euler = Euler((math.radians(-20 * y), math.radians(-25), 0))
        sphere("Iris" + side, (eye[0] + 0.03, eye[1] + 0.03 * y, eye[2] + 0.01), 0.022,
               iris_mat, head, (1, 0.5, 1.2), NECK)
        lid = sphere("Lid" + side, eye, 0.075, skin, head, (1.05, 0.62, 1.3), NECK)
        lid.rotation_euler = e.rotation_euler
        lid.hide_render = True

    for key, y in (("l", -LEG_Y), ("r", LEG_Y)):
        hip = (HIP[0], y, HIP[2])
        knee = (KNEE[0], y, KNEE[2])
        ankle = (ANKLE[0], y, ANKLE[2])
        thigh = organic("Thigh" + key.upper(), hip, _seg(hip, knee, 0.085, 0.05), skin, root)
        shin = organic("Shin" + key.upper(), knee,
                       _seg(knee, ankle, 0.048, 0.032)
                       + _seg(ankle, (0.02, y, 0.035), 0.032, 0.028, 8)
                       + _seg((0.0, y, 0.03), (0.13, y, 0.022), 0.035, 0.018, 8), skin, thigh)
        shin.location = Vector(knee) - Vector(hip)  # relatif à la cuisse
        parts["thigh_" + key] = thigh
        parts["shin_" + key] = shin

    for key, y in (("l", -ARM_Y), ("r", ARM_Y)):
        sh = (SHOULDER[0], y, SHOULDER[2])
        elbow = (0.12, y, 0.8)
        wrist = (0.2, y, 0.64)
        arm = organic("Arm" + key.upper(), sh,
                      _seg(sh, elbow, 0.045, 0.032) + _seg(elbow, wrist, 0.032, 0.022)
                      + [((0.23, y, 0.6), (0.035, 0.022, 0.03), -40),
                         ((0.27, y - 0.012, 0.55), (0.012, 0.012, 0.04), -20),   # trois doigts
                         ((0.26, y, 0.54), (0.012, 0.012, 0.045), 0),
                         ((0.24, y + 0.012, 0.545), (0.012, 0.012, 0.04), 15)],
                      skin, root, voxel=0.006, smooth=14)
        parts["arm_" + key] = arm
    _build_variants(root, head, skin, bulb_mat)
    return root, parts


# ------------------------------------------------------ variantes génétiques --
# Chaque variante est rendue dans sa propre couche ; le jeu les superpose
# selon les gènes de la créature.
TAILS = ["courte", "longue", "massue"]
ANTENNAE = ["courtes", "longues", "ramifiees"]


def _into_collection(objs, name):
    col = bpy.data.collections.get(name) or bpy.data.collections.new(name)
    if col.name not in bpy.context.scene.collection.children:
        bpy.context.scene.collection.children.link(col)
    for o in objs:
        for c in list(o.users_collection):
            c.objects.unlink(o)
        col.objects.link(o)


def _build_variants(root, head, skin, bulb_mat):
    tails = [
        _seg((-0.1, 0, 0.66), (-0.25, 0, 0.6), 0.06, 0.03),
        _seg((-0.1, 0, 0.66), (-0.48, 0, 0.5), 0.065, 0.022)
        + _seg((-0.48, 0, 0.5), (-0.62, 0, 0.6), 0.022, 0.014),
        _seg((-0.1, 0, 0.66), (-0.4, 0, 0.57), 0.055, 0.03)
        + [((-0.46, 0, 0.57), (0.085, 0.075, 0.075), 0)],
    ]
    for i, elems in enumerate(tails):
        t = organic(f"Tail{i}", HIP, elems, skin, root, smooth=10)
        _into_collection([t], f"Queue{i}")
    for i in range(3):
        objs = []
        for side, y in (("L", -1), ("R", 1)):
            if i == 0:      # courtes
                elems = _seg((0.1, 0.045 * y, 1.44), (0.05, 0.06 * y, 1.54), 0.026, 0.02)
                tips = [((0.04, 0.062 * y, 1.565), 0.032)]
            elif i == 1:    # longues
                elems = (_seg((0.1, 0.045 * y, 1.44), (0.05, 0.06 * y, 1.57), 0.026, 0.02)
                         + _seg((0.05, 0.06 * y, 1.57), (-0.03, 0.07 * y, 1.67), 0.02, 0.016))
                tips = [((-0.04, 0.07 * y, 1.7), 0.038)]
            else:           # ramifiées
                elems = (_seg((0.1, 0.045 * y, 1.44), (0.05, 0.06 * y, 1.57), 0.026, 0.02)
                         + _seg((0.05, 0.06 * y, 1.57), (-0.03, 0.07 * y, 1.67), 0.02, 0.016)
                         + _seg((0.06, 0.06 * y, 1.56), (0.14, 0.08 * y, 1.64), 0.016, 0.012))
                tips = [((-0.04, 0.07 * y, 1.7), 0.033), ((0.155, 0.082 * y, 1.66), 0.024)]
            a = organic(f"Ant{i}{side}", NECK, elems, skin, head, voxel=0.004, smooth=2)
            a.location = (0, 0, 0)
            objs.append(a)
            for k, (pos, r) in enumerate(tips):
                objs.append(sphere(f"Bulb{i}{side}{k}", pos, r, bulb_mat, head, pivot=NECK))
        _into_collection(objs, f"Antennes{i}")


# ---------------------------------------------------------------- poses ----
def pose(parts, thighs=(0, 0), knees=(0, 0), arms=(0, 0), head=(0, 0), body_z=0.0, lean=0.0):
    """Angles en degrés (rotation autour de Y). Membres : négatif = vers l'avant.
    Tête : négatif = vers le bas."""
    for k, a in zip(("l", "r"), thighs):
        parts["thigh_" + k].rotation_euler = Euler((0, math.radians(a), 0))
    for k, a in zip(("l", "r"), knees):
        parts["shin_" + k].rotation_euler = Euler((0, math.radians(a), 0))
    for k, a in zip(("l", "r"), arms):
        parts["arm_" + k].rotation_euler = Euler((0, math.radians(a), 0))
    parts["head"].rotation_euler = Euler((0, math.radians(head[0]), math.radians(head[1])))
    root = parts["torso"].parent
    root.location = (0, 0, body_z)
    parts["torso"].rotation_euler = Euler((0, math.radians(lean), 0))


def render(path):
    bpy.context.scene.render.filepath = str(path)
    bpy.ops.render.render(write_still=True)


# ------------------------------------------------------------ sprites ----
SPRITE_RES = 320


def set_lids(closed):
    for side in ("L", "R"):
        bpy.data.objects["Lid" + side].hide_render = not closed


def walk_pose(phase):
    """Cycle de marche digitigrade : phase dans [0, 1[."""
    a = math.tau * phase
    thigh = 28.0 * math.sin(a)
    knee_l = -30.0 * max(0.0, math.sin(a + 1.2))
    knee_r = -30.0 * max(0.0, math.sin(a + 1.2 + math.pi))
    return dict(thighs=(thigh, -thigh), knees=(knee_l, knee_r),
                arms=(-18.0 * math.sin(a), 18.0 * math.sin(a)),
                head=(2.0 * math.sin(2 * a), 0.0), body_z=-0.015 * abs(math.cos(a)))


def lying(parts, face_down):
    root = parts["torso"].parent
    if face_down:
        root.rotation_euler = Euler((0, math.radians(90), 0))
        root.location = (-0.72, 0, 0.28)
    else:
        root.rotation_euler = Euler((0, math.radians(-90), 0))
        root.location = (0.9, 0, 0.16)


# Nom de l'animation -> liste de poses (une image par pose)
ANIMATIONS = {
    "repos": [dict(thighs=(-6, 6), arms=(4, -4)), dict(thighs=(-6, 6), arms=(6, -2), head=(-3, 0), body_z=-0.01)],
    "marche": [walk_pose(i / 8) for i in range(8)],
    "manger": [dict(thighs=(-20, 10), knees=(30, 30), arms=(-55, -40), head=(-30, 0), body_z=-0.06),
               dict(thighs=(-20, 10), knees=(30, 30), arms=(-75, -60), head=(-40, 0), body_z=-0.07)],
    "pousser": [dict(thighs=(-30, 25), knees=(-10, 5), arms=(-70, -60), head=(-5, 0)),
                dict(thighs=(-35, 30), knees=(-10, 5), arms=(-95, -85), head=(-8, 0))],
    "frapper": [dict(thighs=(-15, 15), arms=(130, -10), head=(-5, 0)),
                dict(thighs=(-30, 25), arms=(-100, -10), head=(5, 0))],
    "prendre": [dict(thighs=(-45, 20), knees=(60, 40), arms=(-60, -20), head=(-25, 0), body_z=-0.12)],
    "examiner": [dict(thighs=(-10, 10), arms=(-20, 10), head=(-24, 15))],
    "parler": [dict(thighs=(-6, 6), arms=(-30, 20), head=(16, 0))],
    "dormir": ["couche"],
    "mort": ["dos"],
}


def _layers(show):
    """show : None = corps seul ; sinon nom de la collection de variante à rendre,
    le corps servant de masque (holdout) pour les parties cachées derrière lui."""
    vl = bpy.context.view_layer.layer_collection
    for lc in vl.children:
        if lc.name.startswith(("Queue", "Antennes")):
            lc.exclude = lc.name != show
            lc.holdout = False
    # le corps (collection de la scène) : masque quand on rend une variante
    for o in bpy.context.scene.collection.objects:
        o.is_holdout = show is not None


def render_sprites(out):
    scene = bpy.context.scene
    scene.render.resolution_x = SPRITE_RES
    scene.render.resolution_y = SPRITE_RES
    scene.cycles.samples = 32
    cam = scene.camera
    ppu = SPRITE_RES / cam.data.ortho_scale
    manifest = {"size": SPRITE_RES, "px_per_unit": ppu,
                "anchor": [SPRITE_RES / 2 - cam.location.x * ppu, SPRITE_RES / 2 + cam.location.z * ppu],
                "animations": {}, "tails": TAILS, "antennae": ANTENNAE}
    _, parts = build_creature()
    for name, poses in ANIMATIONS.items():
        frames = []
        for i, p in enumerate(poses):
            root = parts["torso"].parent
            root.rotation_euler = Euler((0, 0, 0))
            set_lids(False)
            if p == "couche":
                pose(parts, thighs=(-70, -60), knees=(100, 95), arms=(-40, -30), head=(10, 0))
                lying(parts, True)
                set_lids(True)
            elif p == "dos":
                pose(parts, thighs=(-40, -20), knees=(30, 50), arms=(-60, -20), head=(-10, 0))
                lying(parts, False)
                set_lids(True)
            else:
                pose(parts, **p)
            fname = f"{name}_{i}.png"
            _layers(None)
            render(out / fname)
            for k in range(len(TAILS)):
                _layers(f"Queue{k}")
                render(out / f"{name}_{i}_queue{k}.png")
            for k in range(len(ANTENNAE)):
                _layers(f"Antennes{k}")
                render(out / f"{name}_{i}_antennes{k}.png")
            frames.append(fname)
        manifest["animations"][name] = frames
    (out / "creature.json").write_text(json.dumps(manifest, indent="\t"))


if __name__ == "__main__":
    OUT.mkdir(parents=True, exist_ok=True)
    reset_scene()
    setup_camera_and_lights()
    if MODE == "sprites":
        render_sprites(OUT)
        sys.exit(0)
    root, parts = build_creature()
    if MODE == "layers":
        bpy.context.scene.render.resolution_x = SPRITE_RES
        bpy.context.scene.render.resolution_y = SPRITE_RES
        bpy.context.scene.cycles.samples = 16
        pose(parts, thighs=(-15, 12), knees=(5, -4), arms=(18, -14), head=(0, 0))
        _layers(None)
        render(OUT / "base.png")
        for k in range(3):
            _layers(f"Queue{k}"); render(OUT / f"queue{k}.png")
            _layers(f"Antennes{k}"); render(OUT / f"antennes{k}.png")
        sys.exit(0)
    if MODE == "test":
        pose(parts, thighs=(-15, 12), knees=(5, -4), arms=(18, -14), head=(0, 0))
        render(OUT / "test_creature.png")
