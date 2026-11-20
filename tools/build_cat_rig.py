"""Chat « en pièces détachées » (prototype d'animation par squelette).

Planche d'origine : art/pixel/rig/chat_pieces.png (ChatGPT) : le chat
assemblé, puis tête, oreilles, œil ouvert et fermé, tête gueule ouverte,
tronc, pattes (haut et bas, avant et arrière), segments de queue.

Chaque pièce est découpée, ramenée à sa taille en pixels du jeu (les
proportions sont prises sur le chat assemblé, pas sur les pièces, que
ChatGPT a dessinées à des échelles différentes), puis on calcule ses masques
de couleur comme pour les sprites des chats (voir art/README.md) :
_m1 = coordonnées sur le corps (u, v, région), _m2 = extrémités (siamois),
rang du blanc, plaques d'écaille. La queue n'est pas une image : le jeu la
trace (une bande texturée), on fabrique donc sa texture et ses masques.

Sortie : assets/chat_rig/*.png + rig.json (tailles et pivots).
"""
import json
import os
import sys

import numpy as np
from PIL import Image
from scipy import ndimage

sys.path.insert(0, os.path.dirname(__file__))
from build_cat_pixel import coord_noise  # noqa: E402

SRC = "art/pixel/rig/chat_pieces.png"
OUT = "assets/chat_rig"
REF_LUM = 0.62

# Pièces de la planche, dans l'ordre où on les repère (lignes, puis de gauche
# à droite), avec leur taille dans le jeu (hauteur en pixels) et leur région
# (0 tronc, 1 tête, 2 queue, 3 pattes).
PARTS = [
    ("assemble", None, None),
    ("tete", 18, 1),
    ("oreille_proche", 7, 1),
    ("oreille_loin", 7, 1),
    ("oeil", 4, 1),
    ("oeil_ferme", 2, 1),
    ("tete_miaule", 18, 1),
    ("tronc", 24, 0),
    ("avant_haut", 15, 3),
    ("avant_bas", 13, 3),
    ("arriere_haut", 16, 3),
    ("arriere_bas", 12, 3),
]
# Pivots (fraction de la pièce) : le point autour duquel elle tourne.
PIVOTS = {
    "tete": (0.3, 0.75), "tete_miaule": (0.3, 0.75),
    "oreille_proche": (0.5, 0.95), "oreille_loin": (0.5, 0.95),
    "oeil": (0.5, 0.5), "oeil_ferme": (0.5, 0.5),
    "tronc": (0.5, 0.5),
    "avant_haut": (0.55, 0.12), "avant_bas": (0.45, 0.1),
    "arriere_haut": (0.5, 0.12), "arriere_bas": (0.5, 0.1),
}


def segment(img):
    r, g, b = img[..., 0], img[..., 1], img[..., 2]
    magenta = (r > 150) & (b > 150) & (g < 120)          # tolérant (images JPEG)
    lab, _ = ndimage.label(ndimage.binary_dilation(~magenta, iterations=3))
    boxes = [s for s in ndimage.find_objects(lab) if (s[0].stop - s[0].start) * (s[1].stop - s[1].start) > 150]
    boxes.sort(key=lambda s: (s[0].start // 120, s[1].start))
    return boxes, magenta


def resample(sub, key, out_h):
    """Ramène une pièce à out_h pixels de haut, en prenant la couleur au
    centre de chaque case (pixels nets, pas de flou)."""
    h, w = key.shape
    out_w = max(1, round(w * out_h / h))
    rgba = np.zeros((out_h, out_w, 4))
    for j in range(out_h):
        for i in range(out_w):
            y0, y1 = int(j * h / out_h), max(int(j * h / out_h) + 1, int((j + 1) * h / out_h))
            x0, x1 = int(i * w / out_w), max(int(i * w / out_w) + 1, int((i + 1) * w / out_w))
            k = key[y0:y1, x0:x1]
            if k.mean() < 0.5:
                continue
            cy, cx = (y0 + y1) // 2, (x0 + x1) // 2
            c = sub[cy, cx] if key[cy, cx] else np.median(sub[y0:y1, x0:x1][k], axis=0)
            if c[0] > c[1] + 50 and c[2] > c[1] + 50:      # liseré teinté de magenta -> contour
                c = np.array([40, 30, 34])
            rgba[j, i, :3] = c / 255.0
            rgba[j, i, 3] = 1.0
    return rgba


def light(rgba):
    a = rgba[..., 3] > 0
    rgb = rgba[..., :3]
    lum = rgb @ [0.299, 0.587, 0.114]
    sat = rgb.max(-1) - rgb.min(-1)
    fur = a & (lum > 0.3) & (sat < 0.12)
    if fur.any():
        k = REF_LUM / float(np.median(lum[fur]))
        rgb[fur] = np.clip(rgb[fur] * k, 0, 1)
    return rgba


def masks(name, rgba, reg):
    """Masques de couleur d'une pièce, en coordonnées sur la pièce."""
    h, w = rgba.shape[:2]
    a = rgba[..., 3] > 0
    yy, xx = np.mgrid[0:h, 0:w].astype(float)
    u = (xx + 0.5) / w
    v = (yy + 0.5) / h
    if reg == 3:                                   # pattes : v de l'épaule au pied
        v = v * 0.5 + (0.5 if name.endswith("_bas") else 0.0)
        u = np.full_like(u, 0.5)
    if name.startswith("oreille"):                 # oreilles : le haut de la tête
        u, v = 0.5 + 0.2 * u, 0.1 * v
    if name.startswith("oeil"):
        u, v = np.full_like(u, 0.75), np.full_like(v, 0.45)
    m1 = np.dstack([u, v, np.full_like(u, (reg + 0.5) / 4.0), a.astype(float)])
    # extrémités (siamois), rang d'apparition du blanc, plaques
    if reg == 1:
        points = 0.55 + 0.45 * np.maximum(u, 1 - v)
        rank = np.where((u > 0.55) & (v > 0.45), 0.3, 0.9 - 0.2 * v)
    elif reg == 3:
        points = np.clip((v - 0.35) / 0.4, 0, 1)
        rank = 0.3 - 0.25 * v
    else:
        points = np.zeros_like(u)
        rank = 0.9 - 0.8 * v
    nz = coord_noise(u, np.clip(v, 0, 1), 5, 8, 3 + reg) - 0.5
    rank = np.clip(rank + 0.12 * nz, 0, 1)
    tort = (coord_noise(np.clip(u, 0, 1), np.clip(v, 0, 1), 3, 2, 9 + reg) > 0.5).astype(float)
    m2 = np.dstack([points, rank, tort, a.astype(float)])
    return m1, m2


def tail_strip():
    """Texture de la queue (bande le long de la queue : x de la base au bout,
    y en travers) et ses masques. Le jeu l'enroule sur une courbe."""
    L, T = 32, 6
    rgba = np.zeros((T, L, 4))
    for j in range(T):
        shade = [0.30, 0.68, 0.66, 0.60, 0.50, 0.30][j]      # bords sombres = contour
        rgba[j, :, :3] = shade if j in (0, T - 1) else shade
        rgba[j, :, 3] = 1.0
    rgba[0, :, :3] = rgba[T - 1, :, :3] = 0.16
    u = np.tile((np.arange(L) + 0.5) / L, (T, 1))
    v = np.tile(((np.arange(T) + 0.5) / T)[:, None], (1, L))
    m1 = np.dstack([u, v, np.full_like(u, 2.5 / 4.0), np.ones_like(u)])
    m2 = np.dstack([0.55 + 0.45 * u, np.full_like(u, 0.95), (coord_noise(u, v, 3, 1, 11) > 0.5).astype(float),
                    np.ones_like(u)])
    return rgba, m1, m2


def save(arr, path):
    Image.fromarray(np.uint8(np.clip(arr, 0, 1) * 255), "RGBA").save(path, optimize=True)


# Planche Gemini (art/pixel/rig/gemini_pieces.jpg) : pattes entières (coupées
# ici en haut et bas), têtes avec orbites vides (comblées), queue tracée par
# le jeu. Pièces repérées par leur position (ligne, puis gauche à droite).
GEMINI = {
    "src": "art/pixel/rig/gemini_pieces.jpg", "out": "assets/chat_rig_gemini",
    # nom : (rang dans la planche, hauteur dans le jeu, région)
    "parts": {"tete": (1, 15, 1), "oreille_proche": (2, 9, 1), "oreille_loin": (3, 9, 1),
              "oeil": (4, 4, 1), "oeil_ferme": (5, 2, 1), "tete_miaule": (6, 16, 1), "tronc": (7, 22, 0)},
    # pattes entières : (rang, hauteur totale) ; coupées au genou
    "legs": {"avant": (10, 27), "arriere": (11, 27)},
}


# Deuxième planche Gemini : têtes de profil avec l'œil dessiné (effacé ici,
# l'œil est une pièce à part pour cligner), pattes déjà en deux morceaux.
# Tailles : échelle commune (SCALE) sauf pour les pièces que Gemini a grossies.
GEMINI2 = {
    "src": "art/pixel/rig/gemini_pieces2.jpg", "out": "assets/chat_rig_gemini2", "scale": 0.15,
    # pièces refaites à part : nom -> (image, hauteur, région)
    "extra": {"tronc": ("art/pixel/rig/gemini_tronc.jpg", 18, 0, 1.25)},
    # nom : (rang dans la planche, hauteur imposée ou None, région)
    "parts": {"tete": (2, None, 1), "tete_miaule": (3, None, 1), "oreille_proche": (4, 9, 1),
              "oreille_loin": (1, 8, 1), "oeil": (5, 3, 1), "oeil_ferme": (6, 2, 1), "tronc": (7, 19, 0),
              "avant_haut": (9, None, 3), "avant_bas": (13, None, 3)},
    # pattes d'un seul morceau à couper à la ligne magenta : (rang, nom)
    "split": {10: "arriere"},
    # repères sur la tête (fractions largeur, hauteur)
    "anchors": {"oeil": [0.67, 0.37], "oreille_proche": [0.52, 0.1], "oreille_loin": [0.68, 0.1],
                "tete_pivot": [0.25, 0.8], "cou": [0.47, -0.32], "genou": 0.9, "epaule_y": 0.28, "pieds": 0.05},
}


def erase_eye(rgba):
    """Efface l'œil dessiné (vert ou très sombre au milieu de la tête)."""
    a = rgba[..., 3] > 0
    r, g, b = rgba[..., 0], rgba[..., 1], rgba[..., 2]
    lum = rgba[..., :3] @ [0.299, 0.587, 0.114]
    inner = ndimage.binary_erosion(a, iterations=2)
    h, w = a.shape
    yy, xx = np.mgrid[:h, :w]
    zone = (xx > w * 0.5) & (xx < w * 0.85) & (yy > h * 0.2) & (yy < h * 0.55)
    eye = inner & zone & ((g > r + 0.08) | (lum < 0.2))
    eye = ndimage.binary_dilation(eye, iterations=1) & inner & zone
    fur = np.median(rgba[a & (lum > 0.3)][:, :3], axis=0)
    rgba[eye, :3] = fur
    return rgba


def split_row(sub, key):
    """Ligne de coupe : la rangée la plus « magenta » dans le tiers central."""
    h = key.shape[0]
    r, g, b = sub[..., 0], sub[..., 1], sub[..., 2]
    pink = (r - g > 35) & (b - g > 35)
    rows = range(h // 3, 2 * h // 3)
    return max(rows, key=lambda y: pink[y].sum() + (~key[y]).sum() * 0.2)


def gemini_order(boxes):
    """Rangs : par ligne (centre vertical par paquets de 110 px), puis x."""
    return sorted(boxes, key=lambda s: ((s[0].start + s[0].stop) // 2 // 110, s[1].start))


def fill_sockets(rgba):
    """Orbites vides (trous sombres dans la tête) : remplies de pelage,
    l'œil est une pièce à part posée par-dessus."""
    a = rgba[..., 3] > 0
    lum = rgba[..., :3] @ [0.299, 0.587, 0.114]
    inner = ndimage.binary_erosion(a, iterations=2)
    hole = inner & (lum < 0.18)
    hole = ndimage.binary_dilation(hole, iterations=1) & inner
    fur = np.median(rgba[a & (lum > 0.3)][:, :3], axis=0)
    rgba[hole, :3] = fur
    return rgba


def main():
    plan = GEMINI2 if "gemini2" in sys.argv else GEMINI if "gemini" in sys.argv else None
    src = plan["src"] if plan else SRC
    out = plan["out"] if plan else OUT
    os.makedirs(out, exist_ok=True)
    img = np.asarray(Image.open(src).convert("RGB")).astype(int)
    boxes, magenta = segment(img)
    meta = {"parts": {}}
    if plan:
        boxes = gemini_order(boxes)
        todo = [(n, h, r, boxes[i]) for n, (i, h, r) in plan["parts"].items()]
        for leg, (i, total) in plan.get("legs", {}).items():
            todo.append((leg, total, 3, boxes[i]))
        for i, leg in plan.get("split", {}).items():
            sy, sx = boxes[i]
            sub = img[sy, sx]
            cut = split_row(sub, ~magenta[sy, sx])
            todo.append((leg + "_haut", None, 3, (slice(sy.start, sy.start + cut), sx)))
            todo.append((leg + "_bas", None, 3, (slice(sy.start + cut + 1, sy.stop), sx)))
    else:
        todo = [(n, h, r, b) for (n, h, r), b in zip(PARTS, boxes) if h is not None]
    sources = {}
    if plan:
        for n, (path, h, r, stretch) in plan.get("extra", {}).items():
            pil = Image.open(path).convert("RGB")      # étiré en largeur (corps plus long)
            pil = pil.resize((round(pil.width * stretch), pil.height), Image.NEAREST)
            im2 = np.asarray(pil).astype(int)
            b2, m2 = segment(im2)
            big = max(b2, key=lambda b: (b[0].stop - b[0].start) * (b[1].stop - b[1].start))
            todo = [t for t in todo if t[0] != n] + [(n, h, r, big)]
            sources[n] = (im2, m2)
    for name, out_h, reg, (sy, sx) in todo:
        src_img, src_mag = sources.get(name, (img, magenta))
        sub, key = src_img[sy, sx], ~src_mag[sy, sx]
        ys, xs = np.where(key)
        sub = sub[ys.min():ys.max() + 1, xs.min():xs.max() + 1]
        key = key[ys.min():ys.max() + 1, xs.min():xs.max() + 1]
        if out_h is None:
            out_h = max(2, round(sub.shape[0] * plan["scale"]))
        rgba = light(resample(sub, key, out_h)) if not name.startswith("oeil") else resample(sub, key, out_h)
        if plan is GEMINI and name.startswith("tete"):
            rgba = fill_sockets(rgba)
        elif plan is GEMINI2 and name == "tete":
            rgba = erase_eye(rgba)
        pieces = [(name, rgba)]
        if plan and name in plan.get("legs", {}):
            # patte entière -> cuisse (haut) et bas, qui se chevauchent un peu
            cut = int(round(rgba.shape[0] * 0.5))
            top = rgba[:cut + 1].copy()
            low = rgba[cut - 1:].copy()
            def trim(r):
                cols = np.where(r[..., 3].any(0))[0]
                return r[:, cols.min():cols.max() + 1]
            pieces = [(name + "_haut", trim(top)), (name + "_bas", trim(low))]
        for pname, prgba in pieces:
            _write(out, meta, pname, prgba, reg)
    rgba, m1, m2 = tail_strip()
    save(rgba, f"{out}/queue.png")
    save(m1, f"{out}/queue_m1.png")
    save(m2, f"{out}/queue_m2.png")
    if plan and "anchors" in plan:
        meta["anchors"] = plan["anchors"]
        tw, th = meta["parts"]["tete"]["size"]
        px, py = plan["anchors"]["tete_pivot"]
        for n in ("tete", "tete_miaule"):
            w, h = meta["parts"][n]["size"]
            meta["parts"][n]["pivot"] = [round(px * w, 1), round(py * h, 1)]
    json.dump(meta, open(f"{out}/rig.json", "w"), indent=1)


def _write(out, meta, name, rgba, reg):
    if True:
        m1, m2 = masks(name, rgba, reg)
        save(rgba, f"{out}/{name}.png")
        save(m1, f"{out}/{name}_m1.png")
        save(m2, f"{out}/{name}_m2.png")
        h, w = rgba.shape[:2]
        px, py = PIVOTS[name]
        meta["parts"][name] = {"size": [w, h], "pivot": [round(px * w, 1), round(py * h, 1)]}
        print(name, w, "x", h)


if __name__ == "__main__":
    main()
