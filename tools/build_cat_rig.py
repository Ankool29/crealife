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
    magenta = (r > 170) & (b > 170) & (g < 110)
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


def main():
    os.makedirs(OUT, exist_ok=True)
    img = np.asarray(Image.open(SRC).convert("RGB")).astype(int)
    boxes, magenta = segment(img)
    meta = {"parts": {}}
    for (name, out_h, reg), (sy, sx) in zip(PARTS, boxes):
        if out_h is None:
            continue
        sub, key = img[sy, sx], ~magenta[sy, sx]
        ys, xs = np.where(key)
        sub = sub[ys.min():ys.max() + 1, xs.min():xs.max() + 1]
        key = key[ys.min():ys.max() + 1, xs.min():xs.max() + 1]
        rgba = light(resample(sub, key, out_h)) if not name.startswith("oeil") else resample(sub, key, out_h)
        m1, m2 = masks(name, rgba, reg)
        save(rgba, f"{OUT}/{name}.png")
        save(m1, f"{OUT}/{name}_m1.png")
        save(m2, f"{OUT}/{name}_m2.png")
        h, w = rgba.shape[:2]
        px, py = PIVOTS[name]
        meta["parts"][name] = {"size": [w, h], "pivot": [round(px * w, 1), round(py * h, 1)]}
        print(name, w, "x", h)
    rgba, m1, m2 = tail_strip()
    save(rgba, f"{OUT}/queue.png")
    save(m1, f"{OUT}/queue_m1.png")
    save(m2, f"{OUT}/queue_m2.png")
    json.dump(meta, open(f"{OUT}/rig.json", "w"), indent=1)


if __name__ == "__main__":
    main()
