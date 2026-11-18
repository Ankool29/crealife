"""Planche d'objets ChatGPT (fond magenta) -> assets/objects/<nom>.png en vrais pixels.

Même densité que les chats : une case de la planche (~6,9 px) = 1 pixel,
affiché ×3 dans le jeu. Les objets sont repérés automatiquement, de gauche
à droite, ligne du haut puis ligne du bas, et nommés selon NAMES.
"""
import json, os
import numpy as np
from PIL import Image
from scipy import ndimage

SRC = "art/pixel/sources/objets.png"
OUT = "assets/objects"
CELL = 2172 / 313               # taille d'un « gros pixel » de la planche
SCALE = 3.0                     # comme les chats
# quelques objets dessinés trop gros pour des chats : un peu réduits
SCALE_OF = {"balle": 2.0, "graine": 2.0, "fruit": 2.4}
# noms dans l'ordre de la planche ; ceux du jeu remplacent les anciens rendus 3D
NAMES = ["distributeur_on", "eau", "panier", "balle", "trampoline", "boite_musique",
         "fruit", "carotte", "graine", "pousse", "plante", "papillon", "oiseau", "souris"]


def main():
    img = np.asarray(Image.open(SRC).convert("RGB")).astype(int)
    r, g, b = img[..., 0], img[..., 1], img[..., 2]
    magenta = (r > 170) & (b > 170) & (g < 110)
    lab, _ = ndimage.label(ndimage.binary_dilation(~magenta, iterations=12))
    boxes = [s for s in ndimage.find_objects(lab) if (s[0].stop - s[0].start) * (s[1].stop - s[1].start) > 2000]
    boxes.sort(key=lambda s: (s[0].start > img.shape[0] * 0.5, s[1].start))
    assert len(boxes) == len(NAMES), len(boxes)
    meta = json.load(open(os.path.join(OUT, "objects.json")))
    for name, (sy, sx) in zip(NAMES, boxes):
        sub, key = img[sy, sx], ~magenta[sy, sx]
        ys, xs = np.where(key)
        sub, key = sub[ys.min():ys.max() + 1, xs.min():xs.max() + 1], key[ys.min():ys.max() + 1, xs.min():xs.max() + 1]
        gh, gw = max(1, round(sub.shape[0] / CELL)), max(1, round(sub.shape[1] / CELL))
        out = np.zeros((gh, gw, 4), np.uint8)
        for j in range(gh):
            for i in range(gw):
                y0, y1 = int(j * sub.shape[0] / gh), int((j + 1) * sub.shape[0] / gh)
                x0, x1 = int(i * sub.shape[1] / gw), int((i + 1) * sub.shape[1] / gw)
                k = key[y0:y1, x0:x1]
                if k.mean() < 0.5:
                    continue
                cy, cx = (y0 + y1) // 2, (x0 + x1) // 2
                blk = sub[max(y0, cy - 1):cy + 2, max(x0, cx - 1):cx + 2][key[max(y0, cy - 1):cy + 2, max(x0, cx - 1):cx + 2]]
                col = np.median(blk if len(blk) else sub[y0:y1, x0:x1][k], axis=0)
                if col[0] > 150 and col[2] > 150 and col[1] < 120:     # liseré magenta : contour sombre
                    col = np.array([40, 22, 30])
                out[j, i, :3], out[j, i, 3] = col, 255
        im = Image.fromarray(out)
        im.save(os.path.join(OUT, name + ".png"))
        if name == "distributeur_on":
            _empty_bowl(out).save(os.path.join(OUT, "distributeur_off.png"))
            meta["distributeur_off"] = {"size": [gw, gh], "anchor": [gw / 2, gh], "scale": SCALE, "pixel": True}
        meta[name] = {"size": [gw, gh], "anchor": [gw / 2, gh], "scale": SCALE_OF.get(name, SCALE), "pixel": True}
        print(name, gw, "x", gh)
    json.dump(meta, open(os.path.join(OUT, "objects.json"), "w"), indent=1)


def _empty_bowl(px):
    """Gamelle vide : les croquettes (brun-orangé, en haut) deviennent le fond sombre."""
    out = px.copy()
    h = out.shape[0]
    for j in range(int(h * 0.45)):
        for i in range(out.shape[1]):
            r, g, b, a = (int(v) for v in out[j, i])
            if a and r > 90 and r > b + 50 and g < r * 0.75:
                out[j, i, :3] = (92, 62, 44)
    return Image.fromarray(out)


if __name__ == "__main__":
    main()
