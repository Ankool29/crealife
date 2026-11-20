"""Pièces du chat dessinées par le code (essai, à comparer avec la planche
ChatGPT de tools/build_cat_rig.py).

Chaque pièce est une forme lisse (courbes) tracée en grand, réduite aux
pixels du jeu, puis ombrée (lumière venant du haut, bords plus sombres,
léger grain de fourrure) et cernée d'un contour sombre. Les proportions
sont réglables (PROPORTIONS) : c'est ce qui permettra plus tard des
silhouettes différentes (trapu, élancé, grandes oreilles...) sans dessin.

Sortie : assets/chat_rig_code/ (mêmes noms de pièces et masques que
assets/chat_rig, pour que le même squelette les anime).
"""
import json
import os
import sys

import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage

sys.path.insert(0, os.path.dirname(__file__))
from build_cat_rig import PIVOTS, masks, save  # noqa: E402

OUT = "assets/chat_rig_code"
SS = 8                       # sur-échantillonnage du tracé
GREY = 0.62
OUTLINE = (0.16, 0.13, 0.14)
PINK = (0.93, 0.62, 0.66)


def spline(pts, n=24):
    """Courbe fermée lisse (Catmull-Rom) passant par les points."""
    pts = np.array(pts, float)
    out = []
    for i in range(len(pts)):
        p0, p1, p2, p3 = pts[i - 1], pts[i], pts[(i + 1) % len(pts)], pts[(i + 2) % len(pts)]
        for t in np.linspace(0, 1, n, endpoint=False):
            t2, t3 = t * t, t * t * t
            out.append(0.5 * ((2 * p1) + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2
                              + (-p0 + 3 * p1 - 3 * p2 + p3) * t3))
    return [tuple(p) for p in out]


class Canvas:
    def __init__(self, w, h):
        self.w, self.h = w, h
        self.mask = Image.new("L", (w * SS, h * SS), 0)
        self.d = ImageDraw.Draw(self.mask)
        self.pink = Image.new("L", (w * SS, h * SS), 0)
        self.dp = ImageDraw.Draw(self.pink)
        self.dark = Image.new("L", (w * SS, h * SS), 0)
        self.dd = ImageDraw.Draw(self.dark)

    def S(self, pts):
        return [(x * SS, y * SS) for x, y in pts]

    def shape(self, pts, layer="mask"):
        d = {"mask": self.d, "pink": self.dp, "dark": self.dd}[layer]
        d.polygon(self.S(spline(pts)), fill=255)

    def ellipse(self, cx, cy, rx, ry, layer="mask"):
        d = {"mask": self.d, "pink": self.dp, "dark": self.dd}[layer]
        d.ellipse([(cx - rx) * SS, (cy - ry) * SS, (cx + rx) * SS, (cy + ry) * SS], fill=255)

    def line(self, pts, width, layer="dark"):
        d = {"mask": self.d, "pink": self.dp, "dark": self.dd}[layer]
        d.line(self.S(pts), fill=255, width=int(width * SS), joint="curve")

    def render(self, seed=0, light_top=True):
        def down(img):
            return np.asarray(img.resize((self.w, self.h), Image.BOX)).astype(float) / 255.0
        a = down(self.mask) > 0.5
        pink = (down(self.pink) > 0.5) & a
        dark = (down(self.dark) > 0.45) & a
        h, w = a.shape
        yy, xx = np.mgrid[0:h, 0:w].astype(float)
        # ombrage : lumière du haut-gauche, bords et dessous plus sombres
        dist = ndimage.distance_transform_edt(a)
        ys = np.where(a.any(1))[0]
        top, bot = (ys.min(), ys.max()) if len(ys) else (0, h)
        vert = (yy - top) / max(1.0, bot - top)
        lum = GREY + 0.09 * (0.5 - vert) - 0.10 * np.exp(-dist / 1.3) + 0.04 * np.clip(dist - 2, 0, 3) / 3
        rng = np.random.default_rng(seed)
        grain = (rng.random((h, w)) < 0.12) * -0.04 + (rng.random((h, w)) < 0.06) * 0.03
        lum = np.clip(lum + grain, 0.3, 0.8)
        rgba = np.zeros((h, w, 4))
        rgba[..., :3] = lum[..., None]
        rgba[pink, :3] = PINK
        rgba[dark, :3] = OUTLINE
        rgba[..., 3] = a
        edge = a & ~ndimage.binary_erosion(a)
        rgba[edge, :3] = OUTLINE
        return rgba


def tete(mouth=False):
    c = Canvas(22, 17)
    # profil : arrière du crâne, front, arête du nez, truffe, babines, menton, gorge
    c.shape([(1.0, 9.5), (2.8, 4.5), (7.0, 1.6), (12.5, 1.8), (16.0, 4.0), (18.6, 6.2), (21.2, 7.8),
             (21.0, 9.6), (19.6, 10.8), (18.6, 12.6), (15.5, 14.2), (10.5, 16.0), (4.0, 15.4)])
    c.ellipse(20.3, 8.3, 1.0, 0.8, "pink")                   # truffe
    c.line([(18.8, 10.9), (17.6, 12.0)], 0.5)                # babine
    c.line([(14.6, 9.6), (16.4, 11.6)], 0.4)                 # pli de la joue
    if mouth:
        c.shape([(19.4, 10.6), (21.0, 11.4), (19.8, 14.0), (17.4, 14.0)])
        c.shape([(19.0, 11.4), (20.3, 11.9), (19.4, 13.4), (17.9, 13.3)], "dark")
        c.ellipse(18.9, 13.0, 0.8, 0.45, "pink")
    return c.render(1)


def oreille(far=False):
    c = Canvas(7, 8)
    c.shape([(0.4, 7.6), (2.2, 2.0), (3.2, 0.3), (4.6, 2.2), (6.6, 7.4)])
    c.shape([(2.2, 6.9), (3.1, 3.0), (4.3, 6.7)], "pink")
    return c.render(2 + far)


def oeil(closed=False):
    if closed:
        c = Canvas(5, 2)
        c.line([(0.4, 0.6), (2.5, 1.4), (4.6, 0.6)], 0.7)
        c.shape([(0.3, 0.3), (4.7, 0.3), (4.7, 1.7), (0.3, 1.7)])
        r = c.render(3)
        r[..., 3] = 0
        r[1, 1:4, 3] = 1
        r[0, 0, 3] = r[0, 4, 3] = 1
        r[..., :3] = OUTLINE
        return r
    rgba = np.zeros((4, 5, 4))
    green = (0.35, 0.78, 0.3)
    rows = ["dddd.", "gpgwd", "gppgd", ".ddd."]
    for j, row in enumerate(rows):
        for i, ch in enumerate(row):
            col = {"d": OUTLINE, "g": green, "p": (0.06, 0.06, 0.06), "w": (0.95, 0.97, 0.95)}.get(ch)
            if col:
                rgba[j, i, :3] = col
                rgba[j, i, 3] = 1
    return rgba


def tronc():
    c = Canvas(38, 21)
    # croupe ronde, dos presque droit, omoplates, poitrail profond, ventre rentré
    c.shape([(2.0, 9.5), (3.8, 4.8), (8.5, 2.6), (16.0, 3.4), (24.0, 3.8), (30.0, 2.4), (34.0, 3.2),
             (37.0, 7.0), (37.2, 11.5), (35.0, 16.2), (30.5, 19.6), (25.0, 19.0), (19.0, 18.0),
             (12.0, 18.4), (6.5, 18.6), (3.0, 16.6), (1.8, 13.0)])
    return c.render(4)


def patte(kind):
    if kind == "avant_haut":
        c = Canvas(9, 14)
        c.shape([(0.8, 3.0), (4.5, 0.4), (8.2, 2.6), (7.2, 8.0), (6.4, 13.4), (2.6, 13.4), (1.6, 8.0)])
    elif kind == "arriere_haut":
        c = Canvas(12, 15)
        c.shape([(0.6, 5.0), (4.0, 0.5), (10.5, 1.2), (11.5, 6.0), (9.2, 10.5), (7.6, 14.4), (4.2, 14.4),
                 (2.6, 10.5)])
    else:
        c = Canvas(8, 12 if kind == "avant_bas" else 11)
        h = c.h
        # jambe, puis la patte en ovale qui avance vers l'avant
        c.shape([(1.6, 0.8), (4.0, 0.2), (6.0, 0.9), (5.6, h - 4.6), (7.6, h - 2.2), (7.0, h - 0.4),
                 (1.0, h - 0.4), (0.6, h - 2.4), (1.8, h - 4.6)])
        c.line([(3.6, h - 2.2), (3.6, h - 0.7)], 0.45)       # doigts
        c.line([(5.6, h - 2.0), (5.6, h - 0.7)], 0.45)
    return c.render(len(kind))


def main():
    os.makedirs(OUT, exist_ok=True)
    parts = {
        "tete": (tete(), 1), "tete_miaule": (tete(True), 1),
        "oreille_proche": (oreille(), 1), "oreille_loin": (oreille(True), 1),
        "oeil": (oeil(), 1), "oeil_ferme": (oeil(True), 1),
        "tronc": (tronc(), 0),
        "avant_haut": (patte("avant_haut"), 3), "avant_bas": (patte("avant_bas"), 3),
        "arriere_haut": (patte("arriere_haut"), 3), "arriere_bas": (patte("arriere_bas"), 3),
    }
    meta = {"parts": {}}
    for name, (rgba, reg) in parts.items():
        m1, m2 = masks(name, rgba, reg)
        save(rgba, f"{OUT}/{name}.png")
        save(m1, f"{OUT}/{name}_m1.png")
        save(m2, f"{OUT}/{name}_m2.png")
        h, w = rgba.shape[:2]
        px, py = PIVOTS[name]
        meta["parts"][name] = {"size": [w, h], "pivot": [round(px * w, 1), round(py * h, 1)]}
    for f in ("queue.png", "queue_m1.png", "queue_m2.png"):
        Image.open(f"assets/chat_rig/{f}").save(f"{OUT}/{f}")
    json.dump(meta, open(f"{OUT}/rig.json", "w"), indent=1)
    print("ok", list(parts))


if __name__ == "__main__":
    main()
