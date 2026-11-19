"""Construit les sprites pixel art des chats à partir des planches dessinées
(art/pixel/sources/*.png : cases à cadre noir, fond magenta, chat gris uni
regardant à droite, yeux vert pur).

Pour chaque image : le sprite en gris (relief et lumière), et deux masques
de pelage que le shader du jeu colore selon les gènes :
  _m1 : r = tigré maquereau, v = tigré classique, b = moucheté
  _m2 : r = extrémités (siamois), v = ordre d'apparition du blanc,
        b = plaques d'écaille de tortue
Les planches de art/pixel/sources/long/ donnent la version à poil long
(images suffixées « _l »).
Sortie : assets/chat_px/ (PNG + chat.json).

Usage : python tools/build_cat_pixel.py
"""
import json
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "art/pixel/sources"
OUT = ROOT / "assets/chat_px"
W, H = 76, 60                 # taille des images de sortie (le chat fait ~60 px de long)
CELL = 64                     # une case de planche = 64 pixels de jeu
# planche -> (animation du jeu, pose pour les zones du corps)
SHEETS = {
    "repos": ("repos", "debout"), "assis": ("assis", "assis"), "marche": ("marche", "debout"),
    "mange": ("manger", "tete_basse"), "pousse": ("pousser", "debout"), "frappe": ("frapper", "debout"),
    "prend": ("prendre", "tete_basse"), "renifle": ("examiner", "debout"), "miaule": ("parler", "debout"),
    "dort": ("dormir", "couche"), "mort": ("mort", "couche"),
}


# ------------------------------------------------------------- découpage ----
def find_cells(im):
    dark = im.sum(-1) < 120
    rows = np.where(dark.mean(1) > 0.5)[0]
    hl = np.split(rows, np.where(np.diff(rows) > 1)[0] + 1)
    y0, y1 = hl[0][-1] + 1, hl[-1][0]
    cols = np.where(dark[y0:y1].mean(0) > 0.8)[0]
    groups = np.split(cols, np.where(np.diff(cols) > 1)[0] + 1)
    edges = [(g[0], g[-1]) for g in groups]
    cells = [(edges[i][1] + 1, edges[i + 1][0]) for i in range(len(edges) - 1)]
    return cells, (y0, y1)


def largest_component(a):
    """Garde le chat (la plus grande tache) et les petits traits d'effet proches."""
    h, w = a.shape
    lab = np.zeros((h, w), int)
    n = 0
    sizes = {}
    for y in range(h):
        for x in range(w):
            if a[y, x] and not lab[y, x]:
                n += 1
                stack = [(y, x)]
                lab[y, x] = n
                cnt = 0
                while stack:
                    cy, cx = stack.pop()
                    cnt += 1
                    for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                        ny, nx = cy + dy, cx + dx
                        if 0 <= ny < h and 0 <= nx < w and a[ny, nx] and not lab[ny, nx]:
                            lab[ny, nx] = n
                            stack.append((ny, nx))
                sizes[n] = cnt
    main = max(sizes, key=sizes.get)
    return lab == main, lab


def cut_sheet(path):
    im = np.asarray(Image.open(path).convert("RGB")).astype(float)
    cells, (y0, y1) = find_cells(im.astype(int))
    px = np.mean([b - a for a, b in cells]) / CELL
    frames = []
    for a, b in cells:
        c = im[y0 + 3:y1 - 2, a + 3:b - 3]
        mag = (c[..., 0] > 150) & (c[..., 2] > 150) & (c[..., 0] - c[..., 1] > 80) & (c[..., 2] - c[..., 1] > 80)
        alpha = (~mag).astype(float)
        hh, ww = c.shape[:2]
        w, h = int(round(ww / px)), int(round(hh / px))
        prem = Image.fromarray(np.uint8(np.clip(c * alpha[..., None], 0, 255)))
        small = np.asarray(prem.resize((w, h), Image.BOX)).astype(float)
        sa = np.asarray(Image.fromarray(np.uint8(alpha * 255)).resize((w, h), Image.BOX)).astype(float) / 255
        rgb = np.where(sa[..., None] > 0.01, small / np.maximum(sa[..., None], 1e-3), 0) / 255
        a_ = sa > 0.5
        # liseré magenta résiduel : pixels de bord trop roses -> contour sombre
        fringe = a_ & (rgb[..., 0] - rgb[..., 1] > 0.12) & (rgb[..., 2] - rgb[..., 1] > 0.12)
        rgb[fringe] = (0.08, 0.06, 0.07)
        frames.append((np.clip(rgb, 0, 1), a_))
    return frames


REF_LUM = 0.62     # luminosité médiane du pelage du chat de référence (poil court)


def normalize_light(frames):
    """Égalise la luminosité du pelage d'une planche sur celle de référence,
    sans toucher aux contours, aux yeux ni aux parties roses."""
    vals = []
    for rgb, a in frames:
        lum = rgb @ [0.299, 0.587, 0.114]
        sat = rgb.max(-1) - rgb.min(-1)
        fur = a & (lum > 0.3) & (sat < 0.12)
        vals.append(lum[fur])
    med = float(np.median(np.concatenate(vals)))
    k = REF_LUM / med
    out = []
    for rgb, a in frames:
        lum = rgb @ [0.299, 0.587, 0.114]
        sat = rgb.max(-1) - rgb.min(-1)
        fur = a & (lum > 0.25) & (sat < 0.12)
        rgb = rgb.copy()
        rgb[fur] = np.clip(rgb[fur] * k, 0, 1)
        out.append((rgb, a))
    return out


def place(frames):
    """Pose chaque image sur une toile W×H : pattes sur la dernière ligne,
    centre du corps (plus grande tache) au milieu."""
    out = []
    for rgb, a in frames:
        body, _ = largest_component(a)
        ys, xs = np.where(body)
        cx = (xs.min() + xs.max()) / 2.0
        dy = H - 1 - ys.max()
        dx = int(round(W / 2 - cx))
        img = np.zeros((H, W, 4))
        yy, xx = np.where(a)
        for y, x in zip(yy, xx):
            ty, tx = y + dy, x + dx
            if 0 <= ty < H and 0 <= tx < W:
                img[ty, tx, :3] = rgb[y, x]
                img[ty, tx, 3] = 1
        out.append(img)
    return out


# ----------------------------------------------------------------- masques ----
def smooth_noise(h, w, scale, seed):
    r = np.random.default_rng(seed)
    g = r.random((h // scale + 3, w // scale + 3))
    ys, xs = np.arange(h) / scale, np.arange(w) / scale
    y0, x0 = ys.astype(int), xs.astype(int)
    fy = (ys - y0)[:, None]
    fx = (xs - x0)[None, :]
    fy, fx = fy * fy * (3 - 2 * fy), fx * fx * (3 - 2 * fx)
    a, b = g[y0][:, x0], g[y0][:, x0 + 1]
    c, d = g[y0 + 1][:, x0], g[y0 + 1][:, x0 + 1]
    return a * (1 - fx) * (1 - fy) + b * fx * (1 - fy) + c * (1 - fx) * fy + d * fx * fy


def blur(v, a, r=2):
    """Flou simple limité à la silhouette (transitions douces du siamois)."""
    acc = np.zeros_like(v)
    n = np.zeros_like(v)
    for dy in range(-r, r + 1):
        for dx in range(-r, r + 1):
            acc += np.roll(np.roll(v * a, dy, 0), dx, 1)
            n += np.roll(np.roll(a.astype(float), dy, 0), dx, 1)
    return np.where(a, acc / np.maximum(n, 1), 0)


def regions(a, pose):
    """0 corps, 1 tête, 2 queue, 3 pattes, d'après la silhouette et la pose."""
    ys, xs = np.where(a)
    x0, x1, y0, y1 = xs.min(), xs.max(), ys.min(), ys.max()
    X, Y = np.meshgrid((np.arange(W) - x0) / max(1, x1 - x0), (np.arange(H) - y0) / max(1, y1 - y0))
    reg = np.zeros((H, W), int)
    if pose == "debout":
        reg[(X > 0.66) & (Y < 0.6)] = 1
        reg[(X < 0.24) & (Y < 0.62)] = 2
        reg[(Y > 0.74) & (reg == 0)] = 3
    elif pose == "tete_basse":
        reg[(X > 0.68) & (Y > 0.2)] = 1
        reg[(X < 0.22) & (Y < 0.62)] = 2
        reg[(Y > 0.76) & (reg == 0)] = 3
    elif pose == "assis":
        reg[(X > 0.42) & (Y < 0.42)] = 1
        reg[(X < 0.32) & (Y > 0.58)] = 2          # queue enroulée en bas, derrière
        reg[(Y > 0.82) & (X > 0.55)] = 3
    else:                                   # couché : tête à droite, queue à gauche
        reg[(X > 0.7)] = 1
        reg[(X < 0.2)] = 2
        reg[(Y > 0.75) & (reg == 0)] = 3
    return reg, X, Y


def make_masks(img, pose):
    a = img[..., 3] > 0
    reg, X, Y = regions(a, pose)
    yy, xx = np.mgrid[0:H, 0:W].astype(float)
    n1 = smooth_noise(H, W, 6, 1)
    body = reg == 0
    cx, cy = (np.average(xx[body]), np.average(yy[body])) if body.any() else (W / 2, H / 2)
    # Coordonnées « sur le corps » pour les rayures, calculées dans le shader :
    # u le long de la colonne vertébrale (queue -> tête), v du dos au ventre
    # (pour les pattes : de l'épaule au pied). Les mêmes d'une image à l'autre,
    # donc les rayures ne bougent pas pendant l'animation.
    if pose == "assis":
        u, v = 1.0 - Y, X                       # assis : le dos est vertical, à gauche
    else:
        u, v = X, Y
        top = np.full(W, np.nan)
        bot = np.full(W, np.nan)
        trunk = (reg <= 1) & a
        for i in range(W):                      # dos et ventre colonne par colonne
            col = np.where(trunk[:, i])[0]
            if len(col):
                top[i], bot[i] = col.min(), col.max()
        top = np.interp(np.arange(W), np.where(~np.isnan(top))[0], top[~np.isnan(top)])
        bot = np.interp(np.arange(W), np.where(~np.isnan(bot))[0], bot[~np.isnan(bot)])
        v = np.where(reg <= 1, (yy - top[None, :]) / np.maximum(4.0, bot - top)[None, :], Y)
    legs = reg == 3
    if legs.any():                               # pattes : de leur haut jusqu'au pied
        ly = Y[legs].min()
        v = np.where(legs, (Y - ly) / max(0.05, 1.0 - ly), v)
    coords = np.dstack([np.clip(u, 0, 1), np.clip(v, 0, 1), (reg + 0.5) / 4.0])
    # Siamois : plus c'est loin du tronc (plus froid), plus c'est foncé.
    span = max(1.0, float(np.hypot(*np.ptp(np.argwhere(a), axis=0))))
    dist = np.hypot(xx - cx, (yy - cy) * 1.2) / span
    far = np.clip((dist * np.select([reg == 1, reg == 2], [1.5, 1.3], 1.0) - 0.30) / 0.22, 0, 1)   # masque facial marqué
    points = np.where(reg > 0, far, 0.0) * np.select([reg == 3], [np.clip((Y - 0.8) / 0.15, 0, 1)], 1.0)
    points = blur(points, a, 2)
    rank = 0.85 - 0.75 * Y
    rank = np.where(reg == 3, 0.05 + 0.2 * (1 - Y), rank)
    rank = np.where((reg == 1) & (Y > 0.55 * (Y.max() if pose == "debout" else 1)), 0.3, np.where(reg == 1, 0.92, rank))
    rank = np.where(reg == 2, 0.95, rank)
    rank = np.clip(rank + 0.12 * (n1 - 0.5), 0, 1)
    tort = (smooth_noise(H, W, 5, 9) > 0.5).astype(float)
    alpha = a.astype(float)
    m1 = np.dstack([coords, alpha]).astype(float)
    m2 = np.dstack([points, rank, tort, alpha])
    return m1, m2


def save(arr, path):
    Image.fromarray(np.uint8(np.clip(arr, 0, 1) * 255), "RGBA").save(path, optimize=True)


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    for old in OUT.glob("*.png"):
        old.unlink()
    manifest = {"size": [W, H], "anchor": [W / 2, H - 1], "animations": {},
                # positions en pixels de sprite, depuis l'ancre (bas, milieu)
                "head_top": -48, "body_center": [0, -22], "mouth": [26, -14]}
    manifest["long_fur"] = True
    for sheet, (anim, pose) in SHEETS.items():
        for folder, suffix in ((SRC, ""), (SRC / "long", "_l")):
            frames = place(normalize_light(cut_sheet(folder / f"{sheet}.png")))
            names = []
            for i, img in enumerate(frames):
                name = f"{anim}_{i}"
                m1, m2 = make_masks(img, pose)
                save(img, OUT / f"{name}{suffix}.png")
                save(m1, OUT / f"{name}{suffix}_m1.png")
                save(m2, OUT / f"{name}{suffix}_m2.png")
                names.append(name)
            if suffix == "":
                manifest["animations"][anim] = names
            elif len(names) != len(manifest["animations"][anim]):
                raise SystemExit(f"{sheet} : {len(names)} images à poil long contre "
                                 f"{len(manifest['animations'][anim])} à poil court")
            print(f"{sheet:8s} -> {anim:9s}{suffix:3s} {len(frames)} images")
    (OUT / "chat.json").write_text(json.dumps(manifest, indent="\t"))


if __name__ == "__main__":
    main()
