"""Décor de CreaLife rendu en 3D, dans l'esprit des décors peints de Creatures 3.

Utilisation : python background.py <dossier_sortie> [test]

Échelle : 1 unité Blender = 120 pixels de jeu. Le sol jouable est à z = 0
sur le plan y = 0 ; la caméra orthographique regarde vers +Y.
"""
import math
import random
import sys
from pathlib import Path

import bpy
import bmesh  # doit être importé après bpy
from mathutils import Euler, Vector

OUT = Path(sys.argv[1] if len(sys.argv) > 1 else "out")
MODE = sys.argv[2] if len(sys.argv) > 2 else "test"
PX_PER_UNIT = 120
rng = random.Random(7)


def reset_scene(width_px, height_px):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    sc = bpy.context.scene
    sc.render.engine = "CYCLES"
    sc.cycles.device = "CPU"
    sc.cycles.samples = 28
    sc.cycles.use_denoising = True
    sc.render.resolution_x = width_px
    sc.render.resolution_y = height_px
    sc.render.image_settings.file_format = "PNG"
    sc.view_settings.view_transform = "Standard"
    sc.view_settings.exposure = -0.2
    w = bpy.data.worlds.new("World")
    sc.world = w
    w.use_nodes = True
    bg = w.node_tree.nodes["Background"]
    bg.inputs["Color"].default_value = (0.45, 0.55, 0.7, 1)
    bg.inputs["Strength"].default_value = 0.4
    return sc


def material(name, base, rough=0.8, noise_scale=0.0, noise_mix=0.0, dark=None, sss=0.0, emit=0.0):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    b = nt.nodes["Principled BSDF"]
    b.inputs["Roughness"].default_value = rough
    b.inputs["Subsurface Weight"].default_value = sss
    if noise_scale > 0:
        tc = nt.nodes.new("ShaderNodeTexCoord")
        nz = nt.nodes.new("ShaderNodeTexNoise")
        nz.inputs["Scale"].default_value = noise_scale
        nz.inputs["Detail"].default_value = 10
        nz.inputs["Roughness"].default_value = 0.6
        nt.links.new(tc.outputs["Object"], nz.inputs["Vector"])
        mix = nt.nodes.new("ShaderNodeMix")
        mix.data_type = "RGBA"
        mix.inputs["A"].default_value = (*base, 1)
        mix.inputs["B"].default_value = (*(dark or [c * 0.5 for c in base]), 1)
        ramp = nt.nodes.new("ShaderNodeMapRange")
        ramp.inputs["From Min"].default_value = 0.5 - noise_mix
        ramp.inputs["From Max"].default_value = 0.5 + noise_mix
        nt.links.new(nz.outputs["Fac"], ramp.inputs["Value"])
        nt.links.new(ramp.outputs["Result"], mix.inputs["Factor"])
        nt.links.new(mix.outputs["Result"], b.inputs["Base Color"])
        bump = nt.nodes.new("ShaderNodeBump")
        bump.inputs["Strength"].default_value = 0.4
        nt.links.new(nz.outputs["Fac"], bump.inputs["Height"])
        nt.links.new(bump.outputs["Normal"], b.inputs["Normal"])
    else:
        b.inputs["Base Color"].default_value = (*base, 1)
    if emit > 0:
        b.inputs["Emission Color"].default_value = (*base, 1)
        b.inputs["Emission Strength"].default_value = emit
    return m


def link(obj):
    bpy.context.collection.objects.link(obj)
    return obj


def mesh_obj(name, bm, mat, smooth=True):
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    for p in me.polygons:
        p.use_smooth = smooth
    me.materials.append(mat)
    return link(bpy.data.objects.new(name, me))


def displaced(obj, strength, scale, subdiv=2):
    if subdiv:
        s = obj.modifiers.new("Sub", "SUBSURF")
        s.levels = subdiv
        s.render_levels = subdiv
    # Une seule texture par échelle de bruit : en créer une par objet coûte
    # plusieurs dizaines de Mo chacune lors de l'évaluation.
    key = f"Clouds{scale:.3f}"
    tex = bpy.data.textures.get(key)
    if tex is None:
        tex = bpy.data.textures.new(key, "CLOUDS")
        tex.noise_scale = scale
        tex.noise_depth = 3
    d = obj.modifiers.new("Disp", "DISPLACE")
    d.texture = tex
    d.strength = strength
    d.mid_level = 0.5
    d.texture_coords = "GLOBAL"
    return obj


def blob(name, loc, radii, mat, strength=0.3, scale=0.6, subdiv=2):
    # Icosphère directement plus fine plutôt qu'un modificateur de subdivision :
    # ce dernier coûte environ 15 Mo par objet à l'évaluation.
    bm = bmesh.new()
    bmesh.ops.create_icosphere(bm, subdivisions=3 + subdiv, radius=1.0)
    bmesh.ops.scale(bm, vec=Vector(radii), verts=bm.verts)
    o = mesh_obj(name, bm, mat)
    o.location = loc
    return displaced(o, strength, scale, 0)


# ---------------------------------------------------------------- éléments --
def ground(x0, x1, mats):
    """Sol : bande avant (jouable) + terrain qui s'éloigne en légère pente."""
    bm = bmesh.new()
    nx, ny = int((x1 - x0) * 3), 40
    ys = [-3 + 33 * (j / ny) ** 1.6 for j in range(ny + 1)]
    verts = []
    for j, y in enumerate(ys):
        row = []
        for i in range(nx + 1):
            x = x0 + (x1 - x0) * i / nx
            z = 0.0 if y < 0.6 else (y - 0.6) * 0.06 + 0.25 * math.sin(x * 0.35 + y * 0.2)
            row.append(bm.verts.new((x, y, z)))
        verts.append(row)
    for j in range(ny):
        for i in range(nx):
            bm.faces.new((verts[j][i], verts[j][i + 1], verts[j + 1][i + 1], verts[j + 1][i]))
    g = mesh_obj("Ground", bm, mats["grass"])
    # Terre visible sur la tranche avant
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    bmesh.ops.scale(bm, vec=Vector((x1 - x0 + 4, 3.0, 6.0)), verts=bm.verts)
    soil = mesh_obj("Soil", bm, mats["soil"], smooth=False)
    soil.location = ((x0 + x1) / 2, -4.0, -3.02)
    for k in range(int((x1 - x0) * 4)):
        px = rng.uniform(x0, x1)
        pz = -rng.uniform(0.25, 2.5)
        r = rng.uniform(0.04, 0.13)
        blob("Pebble", (px, -5.5 + r * 0.6, pz), (r * 1.4, r, r), mats["pebble"], 0.03, 0.2, 0)
    return g


def tree(x, y, h, mats):
    trunk_bm = bmesh.new()
    bmesh.ops.create_cone(trunk_bm, segments=16, radius1=0.42 * h / 5, radius2=0.2 * h / 5, depth=h * 0.75,
                          cap_ends=True)
    t = mesh_obj("Trunk", trunk_bm, mats["bark"])
    t.location = (x, y, h * 0.375 - 0.05)
    t.rotation_euler = Euler((0, math.radians(rng.uniform(-4, 4)), 0))
    displaced(t, 0.12, 0.3, 2)
    # Racines
    for k in range(3):
        a = rng.uniform(0, math.tau)
        blob("Root", (x + math.cos(a) * 0.35, y + math.sin(a) * 0.35, 0.05),
             (0.45, 0.18, 0.15), mats["bark"], 0.08, 0.3, 1)
    # Feuillage en grappes
    for k in range(14):
        cx = x + rng.uniform(-1.3, 1.3) * h / 5
        cz = h * rng.uniform(0.7, 1.05)
        r = rng.uniform(0.55, 0.95) * h / 5
        blob("Leaves", (cx, y + rng.uniform(-0.6, 0.6), cz), (r * 1.2, r, r * 0.85),
             mats["leaves"] if k % 3 else mats["leaves2"], 0.5, 0.45, 1)


def rock(x, y, s, mats):
    blob("Rock", (x, y, s * 0.25), (s * 1.1, s * 0.8, s * 0.6), mats["rock"], 0.3 * s, 0.5, 2)
    blob("Moss", (x, y, s * 0.55), (s * 0.85, s * 0.6, s * 0.25), mats["moss"], 0.2 * s, 0.3, 2)


def bush(x, y, s, mats):
    for k in range(3):
        blob("Bush", (x + rng.uniform(-0.4, 0.4) * s, y, s * rng.uniform(0.35, 0.6)),
             (s * 0.6, s * 0.5, s * 0.45), mats["leaves2"], 0.25 * s, 0.35, 1)


def grass(ground_obj, mats, count):
    ps = ground_obj.modifiers.new("Grass", "PARTICLE_SYSTEM").particle_system
    st = ps.settings
    st.type = "HAIR"
    st.count = count
    st.hair_length = 0.13
    st.use_advanced_hair = True
    st.use_rotations = True
    st.rotation_mode = "NOR"
    st.phase_factor_random = 2.0
    st.factor_random = 0.6
    st.child_type = "INTERPOLATED"
    st.child_percent = 3
    st.rendered_child_count = 3
    st.root_radius = 0.6
    st.tip_radius = 0.0
    st.radius_scale = 0.007
    vg = ground_obj.vertex_groups.new(name="Front")
    for v in ground_obj.data.vertices:
        w = max(0.0, 1.0 - max(0.0, v.co.y - 1.0) / 5.0)
        if w > 0:
            vg.add([v.index], w, "REPLACE")
    ps.vertex_group_density = "Front"
    st.material = 2
    ground_obj.data.materials.append(mats["blade"])


def hills(x0, x1, mats):
    for i in range(10):
        x = x0 + (x1 - x0) * i / 9 + rng.uniform(-1, 1)
        blob("Hill", (x, 34, -1.0), (rng.uniform(4, 7), 2.0, rng.uniform(3.2, 5.0)), mats["far"], 0.6, 1.5, 2)
    for i in range(14):
        x = x0 + (x1 - x0) * i / 13 + rng.uniform(-1, 1)
        blob("Hill2", (x, 24, -0.6), (rng.uniform(3, 5), 2.0, rng.uniform(2.0, 3.2)), mats["mid"], 0.5, 1.2, 2)


def sky(x0, x1):
    m = bpy.data.materials.new("Sky")
    m.use_nodes = True
    nt = m.node_tree
    nt.nodes.remove(nt.nodes["Principled BSDF"])
    em = nt.nodes.new("ShaderNodeEmission")
    tc = nt.nodes.new("ShaderNodeTexCoord")
    sep = nt.nodes.new("ShaderNodeSeparateXYZ")
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.elements[0].color = (0.95, 0.85, 0.65, 1)
    ramp.color_ramp.elements[1].position = 0.6
    ramp.color_ramp.elements[1].color = (0.35, 0.55, 0.8, 1)
    nt.links.new(tc.outputs["Generated"], sep.inputs[0])
    nt.links.new(sep.outputs["Y"], ramp.inputs[0])     # plan redressé : Y local = hauteur
    nt.links.new(ramp.outputs["Color"], em.inputs["Color"])
    nt.links.new(em.outputs[0], nt.nodes["Material Output"].inputs["Surface"])
    bm = bmesh.new()
    bmesh.ops.create_grid(bm, x_segments=1, y_segments=1, size=1.0)
    o = mesh_obj("Sky", bm, m, False)
    o.location = ((x0 + x1) / 2, 45, 4)
    o.rotation_euler = Euler((math.radians(90), 0, 0))
    o.scale = ((x1 - x0) / 2 + 5, 9, 1)


def materials():
    return {
        "grass": material("Grass", (0.2, 0.32, 0.08), 0.9, 1.5, 0.25, (0.28, 0.24, 0.1)),
        "blade": material("Blade", (0.22, 0.38, 0.08), 0.7, sss=0.2),
        "soil": material("Soil", (0.26, 0.16, 0.08), 0.95, 1.2, 0.45, (0.1, 0.06, 0.03)),
        "bark": material("Bark", (0.22, 0.14, 0.08), 0.9, 6.0, 0.3, (0.1, 0.07, 0.04)),
        "leaves": material("Leaves", (0.13, 0.3, 0.06), 0.7, 14.0, 0.35, (0.03, 0.11, 0.03), sss=0.15),
        "leaves2": material("Leaves2", (0.2, 0.36, 0.06), 0.7, 14.0, 0.35, (0.06, 0.15, 0.03), sss=0.15),
        "pebble": material("Pebble", (0.34, 0.29, 0.23), 0.9, 5.0, 0.25, (0.2, 0.16, 0.12)),
        "rock": material("Rock", (0.38, 0.36, 0.32), 0.85, 3.0, 0.25, (0.2, 0.19, 0.17)),
        "moss": material("Moss", (0.2, 0.33, 0.07), 0.95, 4.0, 0.3, (0.12, 0.2, 0.05)),
        "far": material("Far", (0.36, 0.47, 0.56), 1.0, 2.0, 0.2, (0.3, 0.4, 0.5), emit=0.25),
        "mid": material("Mid", (0.2, 0.32, 0.2), 1.0, 2.0, 0.25, (0.14, 0.24, 0.16), emit=0.08),
    }


def lights():
    sun = bpy.data.lights.new("Sun", "SUN")
    sun.energy = 4.5
    sun.color = (1.0, 0.9, 0.75)
    sun.angle = math.radians(3)
    o = link(bpy.data.objects.new("Sun", sun))
    o.rotation_euler = Euler((math.radians(58), 0, math.radians(-68)))


def camera(cx, cz, width_units, w_px, h_px):
    cd = bpy.data.cameras.new("Cam")
    cd.type = "ORTHO"
    cd.ortho_scale = width_units
    cd.clip_end = 200
    cd.clip_start = 0.1
    c = link(bpy.data.objects.new("Cam", cd))
    c.location = (cx, -40, cz)
    c.rotation_euler = Euler((math.radians(90), 0, 0))
    bpy.context.scene.camera = c


# Doit correspondre à src/sim/world_sim.gd (positions en pixels de jeu)
WORLD_WIDTH_PX = 3000
TREES_PX = [450, 1350, 2350]
BUSHES_PX = [900, 2000]
# Bande verticale couverte par le décor, en pixels de jeu (sol = 0, ciel négatif)
TOP_PX, BOTTOM_PX = -560, 200


def layer_camera(width_units, w_px, h_px):
    top, bottom = -TOP_PX / PX_PER_UNIT, -BOTTOM_PX / PX_PER_UNIT
    camera(width_units / 2, (top + bottom) / 2, width_units, w_px, h_px)


def render_near(out):
    """Couche du sol jouable : terre, herbe, arbres, buissons. Ciel transparent."""
    w_px, h_px = WORLD_WIDTH_PX, BOTTOM_PX - TOP_PX
    width = w_px / PX_PER_UNIT
    reset_scene(w_px, h_px)
    bpy.context.scene.render.film_transparent = True
    bpy.context.scene.cycles.samples = 24
    mats = materials()
    g = ground(-1, width + 1, mats)
    for tx in TREES_PX:
        tree(tx / PX_PER_UNIT, rng.uniform(2.5, 3.5), rng.uniform(3.8, 4.4), mats)
    for x in [3.0, 9.0, 15.5, 22.0]:                      # arbres plus lointains
        tree(x + rng.uniform(-1, 1), rng.uniform(9, 12), rng.uniform(3.2, 3.8), mats)
    for bx in BUSHES_PX:
        bush(bx / PX_PER_UNIT, 0.9, 0.9, mats)
    for i in range(10):
        rock(rng.uniform(0, width), rng.uniform(1.2, 5.0), rng.uniform(0.25, 0.5), mats)
    grass(g, mats, int(250 * width))
    lights()
    layer_camera(width, w_px, h_px)
    bpy.context.scene.render.filepath = str(out / "decor_proche.png")
    bpy.ops.render.render(write_still=True)


def ridge(name, x0, x1, y, base, amp, waves, mat):
    """Crête de collines : une bande verticale dont le bord haut ondule."""
    phases = [rng.uniform(0, math.tau) for _ in waves]
    bm = bmesh.new()
    n = 240
    prev = None
    for i in range(n + 1):
        x = x0 + (x1 - x0) * i / n
        z = base + sum(amp * w[1] * math.sin(x / w[0] + ph) for w, ph in zip(waves, phases))
        top = bm.verts.new((x, y, z))
        bottom = bm.verts.new((x, y, -4.0))
        if prev:
            bm.faces.new((prev[1], bottom, top, prev[0]))
        prev = (top, bottom)
    o = mesh_obj(name, bm, mat)
    return o


def far_hills(x0, x1, mats):
    """Deux crêtes de collines lointaines (bleutée puis verte) et quelques nuages."""
    ridge("RidgeFar", x0, x1, 34, 2.9, 0.45, [(3.1, 1.0), (1.3, 0.35), (7.0, 0.8)], mats["far"])
    ridge("RidgeMid", x0, x1, 24, 2.1, 0.35, [(2.3, 1.0), (0.9, 0.25), (5.5, 0.7)], mats["mid"])
    cloud = material("Cloud", (0.95, 0.96, 1.0), 1.0, emit=0.9)
    for i in range(6):
        x = x0 + (x1 - x0) * (i + 0.5) / 6 + rng.uniform(-1, 1)
        z = rng.uniform(3.4, 4.3)
        for k in range(3):
            blob("Cloud", (x + k * 0.5 - 0.5, 40, z + rng.uniform(-0.1, 0.1)),
                 (rng.uniform(0.6, 0.9), 0.4, rng.uniform(0.2, 0.3)), cloud, 0.1, 1.0, 2)


def render_far(out, w_px=2400):
    """Couche lointaine : ciel et collines, défile plus lentement (parallaxe)."""
    h_px = BOTTOM_PX - TOP_PX
    width = w_px / PX_PER_UNIT
    reset_scene(w_px, h_px)
    bpy.context.scene.cycles.samples = 20
    mats = materials()
    sky(-2, width + 2)
    far_hills(-2, width + 2, mats)
    lights()
    layer_camera(width, w_px, h_px)
    bpy.context.scene.render.filepath = str(out / "decor_lointain.png")
    bpy.ops.render.render(write_still=True)


if __name__ == "__main__":
    OUT.mkdir(parents=True, exist_ok=True)
    if MODE == "near":
        render_near(OUT)
    elif MODE == "far":
        render_far(OUT)
    if MODE == "test":
        w_px, h_px = 1600, 900
        width = w_px / PX_PER_UNIT
        x0, x1 = -2, width + 2
        reset_scene(w_px, h_px)
        mats = materials()
        g = ground(x0, x1, mats)
        sky(x0, x1)
        hills(x0, x1, mats)
        tree(2.2, 3.0, 5.2, mats)
        tree(10.5, 6.0, 4.4, mats)
        tree(6.0, 14.0, 3.6, mats)
        rock(4.6, 1.4, 0.7, mats)
        rock(12.3, 1.0, 0.5, mats)
        bush(8.2, 2.0, 0.9, mats)
        bush(0.6, 1.5, 0.7, mats)
        grass(g, mats, 6000)
        lights()
        # Sol jouable à 22 % du bas de l'image
        camera(width / 2, (0.5 - 0.22) * h_px / PX_PER_UNIT, width, w_px, h_px)
        bpy.context.scene.render.filepath = str(OUT / "test_background.png")
        bpy.ops.render.render(write_still=True)
