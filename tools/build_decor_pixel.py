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
    "jeux": (256, 0.742),
    "salle": (256, 0.758),
    "chambre": (256, 0.766),
    "entree": (256, 0.79),      # planche retournée : la porte donne à droite, sur le jardin
    # jardin : on coupe la bande de planches du bas (au-delà de 612 px sur 724)
    "jardin": (313, 0.758, 612 / 724),
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
    for name, spec in DECORS.items():
        gw, floor = spec[0], spec[1]
        src = Image.open(os.path.join(SRC, name + ".png"))
        if len(spec) > 2:              # on coupe le bas, le sol se mesure sur l'image coupée
            h = round(src.height * spec[2])
            floor = floor / spec[2]
            src = src.crop((0, 0, src.width, h))
        small = resample(src, gw)
        big = small.resize((small.width * SCALE, small.height * SCALE), Image.NEAREST)
        big.save(os.path.join(OUT, "px_" + name + ".png"))
        meta[name] = {"size": [big.width, big.height], "floor": round(floor * big.height)}
        print(name, big.size, "sol à", meta[name]["floor"])
    with open(os.path.join(OUT, "px_decors.json"), "w") as f:
        json.dump(meta, f, indent=1)


if __name__ == "__main__":
    main()
