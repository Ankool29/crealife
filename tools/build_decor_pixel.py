"""Décors pixel art (planches ChatGPT) -> assets/decor/px_<nom>.png

Les images générées ne sont pas sur une grille parfaite : on rééchantillonne
au centre de chaque « gros pixel » (grille GRID), puis on agrandit au plus
proche (SCALE) pour obtenir des pixels nets et réguliers.
Le JSON décrit la position du sol (haut du plancher, en fraction de hauteur).
"""
import json, os
import numpy as np
from PIL import Image

SRC = "art/pixel/decor"
OUT = "assets/decor"
SCALE = 8
# nom : (largeur de la grille en gros pixels, haut du plancher en fraction de l'image)
DECORS = {
    "cuisine": (256, 0.745),
}


def resample(img, gw):
    w, h = img.size
    cell = w / gw
    gh = int(round(h / cell))
    a = np.asarray(img.convert("RGB"))
    xs = ((np.arange(gw) + 0.5) * cell).astype(int).clip(0, w - 1)
    ys = ((np.arange(gh) + 0.5) * (h / gh)).astype(int).clip(0, h - 1)
    # médiane d'un petit voisinage au centre de chaque case : robuste au flou
    out = np.zeros((gh, gw, 3), np.uint8)
    r = max(1, int(cell * 0.25))
    for j, y in enumerate(ys):
        for i, x in enumerate(xs):
            block = a[max(0, y - r):y + r + 1, max(0, x - r):x + r + 1].reshape(-1, 3)
            out[j, i] = np.median(block, axis=0)
    return Image.fromarray(out)


def main():
    meta = {}
    for name, (gw, floor) in DECORS.items():
        small = resample(Image.open(os.path.join(SRC, name + ".png")), gw)
        big = small.resize((small.width * SCALE, small.height * SCALE), Image.NEAREST)
        big.save(os.path.join(OUT, "px_" + name + ".png"))
        meta[name] = {"size": [big.width, big.height], "floor": round(floor * big.height)}
        print(name, big.size, "sol à", meta[name]["floor"])
    with open(os.path.join(OUT, "px_decors.json"), "w") as f:
        json.dump(meta, f, indent=1)


if __name__ == "__main__":
    main()
