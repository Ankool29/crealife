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
SCALE_OF = {"balle": 2.0, "graine": 2.0, "pomme": 2.4, "souris": 1.8, "oiseau": 1.8}
# noms dans l'ordre de la planche ; ceux du jeu remplacent les anciens rendus 3D
NAMES = ["distributeur_on", "eau", "panier", "balle", "trampoline", "boite_musique",
         "pomme", "carotte", "graine", "pousse", "plante", "papillon", "oiseau", "souris"]


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
    _derived(meta)
    json.dump(meta, open(os.path.join(OUT, "objects.json"), "w"), indent=1)


def _derived(meta):
    """Sprites fabriqués à partir des autres : la pâtée (gamelle d'eau dont
    l'eau devient de la pâtée), un petit tas de croquettes dessiné ici, le
    lys et l'herbe à chat (la plante, fleurie)."""
    eau = np.asarray(Image.open(os.path.join(OUT, "eau.png"))).copy()
    for j in range(eau.shape[0]):
        for i in range(eau.shape[1]):
            r, g, b, a = (int(v) for v in eau[j, i])
            if a and b > r + 40 and b > 120:          # l'eau bleue -> pâtée
                k = (r + g + b) / 3 / 255 + ((i * 7 + j * 13) % 5 - 2) * 0.12   # morceaux
                eau[j, i, :3] = (int(np.clip(130 + 90 * k, 0, 255)), int(np.clip(70 + 55 * k, 0, 255)),
                                 int(np.clip(50 + 40 * k, 0, 255)))
    Image.fromarray(eau).save(os.path.join(OUT, "patee.png"))
    h, w = eau.shape[:2]
    meta["patee"] = {"size": [w, h], "anchor": [w / 2, h], "scale": SCALE, "pixel": True}
    # croquettes : petit tas de grains bruns cernés de sombre
    pile = ["..oo.o..", ".oOooOo.", "oOoOOoOo"]
    W, H = len(pile[0]) + 2, len(pile) + 2
    out = np.zeros((H, W, 4), np.uint8)
    col = {"o": (150, 92, 45), "O": (190, 125, 60)}
    for j, row in enumerate(pile):
        for i, ch in enumerate(row):
            if ch in col:
                out[j + 1, i + 1] = (*col[ch], 255)
    a = out[..., 3] > 0                                   # contour
    edge = np.zeros_like(a)
    for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
        edge |= np.roll(np.roll(a, dy, 0), dx, 1)
    out[edge & ~a] = (60, 35, 20, 255)
    Image.fromarray(out).save(os.path.join(OUT, "croquettes.png"))
    meta["croquettes"] = {"size": [W, H], "anchor": [W / 2, H], "scale": SCALE, "pixel": True}
    _flowered(meta)
    for gone in ("fruit", "baie", "pierre", "oeuf"):
        meta.pop(gone, None)


def _leaf_tips(px):
    """Bouts des feuilles de la plante : haut, gauche et droite de chaque moitié."""
    a = px[..., 3] > 0
    green = a & (px[..., 1].astype(int) > px[..., 0].astype(int) + 20)
    ys, xs = np.where(green)
    h = px.shape[0]
    tips = [(ys.min(), xs[ys == ys.min()].mean())]
    for top in (True, False):
        sel = (ys < h * 0.45) if top else (ys >= h * 0.45) & (ys < h * 0.75)
        if sel.any():
            for side in (xs[sel].min(), xs[sel].max()):
                tips.append((ys[sel][xs[sel] == side].mean(), side))
    out = []
    for y, x in tips:
        p = (int(round(y)), int(round(x)))
        if all(abs(p[0] - q[0]) + abs(p[1] - q[1]) > 4 for q in out):
            out.append(p)
    return out


def _flowered(meta):
    """Lys (grandes fleurs blanches au cœur jaune) et herbe à chat (feuillage
    gris-vert, petits épis mauves), dérivés de la plante."""
    base = np.asarray(Image.open(os.path.join(OUT, "plante.png")).convert("RGBA")).copy()
    h, w = base.shape[:2]
    tips = _leaf_tips(base)
    # lys : grande fleur étoilée (pétales blancs, cœur jaune, contour sombre)
    flower = ["..d.d..", ".dwdwd.", "dwwywwd", ".dwywd.", "..dwd..", "...d..."]
    cols = {"d": (40, 22, 30), "w": (250, 250, 240), "y": (240, 200, 60)}
    lys = base.copy()
    for y, x in tips:
        y, x = min(max(y, 2), h - 5), min(max(x, 3), w - 4)
        for j, row in enumerate(flower):
            for i, ch in enumerate(row):
                if ch in cols:
                    lys[y - 2 + j, x - 3 + i] = (*cols[ch], 255)
    Image.fromarray(lys).save(os.path.join(OUT, "lys.png"))
    meta["lys"] = dict(meta["plante"])
    # herbe à chat : feuillage plus gris, épis mauves au bout des tiges
    herbe = base.copy()
    for j in range(h):
        for i in range(w):
            r, g, b, a = (int(v) for v in herbe[j, i])
            if a and g + 40 >= r and g > b + 30:     # feuillage (vert ou jaune-vert)
                m = (r + g + b) / 3
                herbe[j, i, :3] = (int(0.35 * r + 0.55 * m), int(0.6 * g + 0.4 * m), int(0.3 * b + 0.6 * m + 25))
    spike = ["d.d", "lml", "mdm", "lml", ".d."]
    cols = {"d": (60, 35, 70), "m": (160, 110, 195), "l": (210, 175, 235)}
    for y, x in tips:
        y, x = min(max(y, 1), h - 5), min(max(x, 1), w - 2)
        for j, row in enumerate(spike):
            for i, ch in enumerate(row):
                if ch in cols:
                    herbe[y - 1 + j, x - 1 + i] = (*cols[ch], 255)
    Image.fromarray(herbe).save(os.path.join(OUT, "herbe_chat.png"))
    meta["herbe_chat"] = dict(meta["plante"])


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
