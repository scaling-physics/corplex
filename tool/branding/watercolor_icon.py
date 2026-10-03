"""Paints Corplex's watercolour app icon.

A page with a highlighted line and a marker, painted the way watercolour
behaves: transparent washes that darken where they mix, pigment that pools
at the edges of each shape, granulation in the paper's grain, soft blooms
in the background wash, and the page itself left as unpainted paper.

Writes into assets/branding/:
  icon.png             1024² full-bleed icon (iOS, README)
  icon_background.png  Android adaptive background: the wash alone
  icon_foreground.png  Android adaptive foreground: page + marker, sized
                       for the adaptive safe zone, on transparency
  icon_monochrome.png  Android themed icon silhouette

Run from the repo root:  python3 tool/branding/watercolor_icon.py
Needs numpy, scipy and Pillow.
"""
import math
import os

import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage as ndi

N = 1024
OUT = 'assets/branding'


# ------------------------------------------------------------------ noise

def _norm(a):
    a = a - a.min()
    return a / (a.max() + 1e-9)


def fbm(seed, scales=(96, 48, 24, 12, 6), gain=0.55, n=N):
    """Fractal noise in 0..1, tileable-free (edges don't matter here)."""
    rng = np.random.default_rng(seed)
    out = np.zeros((n, n))
    w = 1.0
    for s in scales:
        out += w * ndi.gaussian_filter(rng.random((n, n)), s)
        w *= gain
    return _norm(out)


def grain(seed, n=N):
    """Cold-press paper: fine, slightly clumpy tooth."""
    rng = np.random.default_rng(seed)
    g = ndi.gaussian_filter(rng.random((n, n)), 1.2)
    g2 = ndi.gaussian_filter(rng.random((n, n)), 3.0)
    return _norm(0.65 * _norm(g) + 0.35 * _norm(g2))


# ----------------------------------------------------------------- shapes

def polygon_mask(points, n=N, ss=4):
    """Antialiased polygon mask (supersampled)."""
    img = Image.new('L', (n * ss, n * ss), 0)
    ImageDraw.Draw(img).polygon([(x * ss, y * ss) for x, y in points], fill=255)
    img = img.resize((n, n), Image.LANCZOS)
    return np.asarray(img, dtype=np.float64) / 255.0


def rotate(points, deg, cx=N / 2, cy=N / 2):
    t = math.radians(deg)
    c, s = math.cos(t), math.sin(t)
    return [(cx + (x - cx) * c - (y - cy) * s, cy + (x - cx) * s + (y - cy) * c)
            for x, y in points]


def rounded_rect(x0, y0, x1, y1, r, steps=10):
    pts = []
    for cx, cy, a0 in ((x1 - r, y0 + r, -90), (x1 - r, y1 - r, 0),
                       (x0 + r, y1 - r, 90), (x0 + r, y0 + r, 180)):
        for i in range(steps + 1):
            a = math.radians(a0 + 90 * i / steps)
            pts.append((cx + r * math.cos(a), cy + r * math.sin(a)))
    return pts


def stroke(x0, x1, y, h, wobble, seed):
    """A brush stroke: a bar whose width breathes and whose ends taper."""
    rng = np.random.default_rng(seed)
    k = 64
    top, bottom = [], []
    phase = rng.random() * 6
    for i in range(k + 1):
        t = i / k
        x = x0 + (x1 - x0) * t
        # Round, brush-like ends: the hair lands, then lifts.
        e = min(1.0, t / 0.07, (1 - t) / 0.05)
        taper = math.sin(e * math.pi / 2) ** 0.7
        half = h / 2 * taper * (1 + 0.12 * math.sin(phase + t * 7))
        dy = wobble * math.sin(phase * 1.3 + t * 3.1)
        top.append((x, y + dy - half))
        bottom.append((x, y + dy + half))
    return top + bottom[::-1]


def warp(mask, amount, seed, scale=28):
    """Irregular, wet edges: push the mask around with smooth noise."""
    dx = (fbm(seed, (scale, scale / 2)) - 0.5) * 2 * amount
    dy = (fbm(seed + 1, (scale, scale / 2)) - 0.5) * 2 * amount
    yy, xx = np.mgrid[0:N, 0:N].astype(np.float64)
    return ndi.map_coordinates(mask, [yy + dy, xx + dx], order=1, mode='nearest')


# ------------------------------------------------------------------ paint

PAPER = np.array([0.985, 0.972, 0.945])
GRAIN = grain(11)


def hexrgb(h):
    h = h.lstrip('#')
    return np.array([int(h[i:i + 2], 16) / 255 for i in (0, 2, 4)])


def wash(canvas, mask, color, opacity, seed, *, edge=0.55, gran=0.35,
         wobble=6, soft=1.2, mottle=0.35, alpha_out=None):
    """Glazes one transparent layer of pigment over the canvas.

    Pigment is subtractive: each wash multiplies what's under it, so
    overlaps darken and mix the way real glazes do. Edges get extra
    pigment (it migrates there as a wash dries); granulation settles in
    the paper's hollows.
    """
    m = warp(mask, wobble, seed) if wobble else mask
    m = ndi.gaussian_filter(m, soft)
    # Ragged edge: noise decides how far the wet front crept.
    m = np.clip((m - 0.5) * 1.6 + 0.5 + (fbm(seed + 2, (6, 3)) - 0.5) * 0.35,
                0, 1) * (m > 0.02)
    inner = ndi.gaussian_filter(m, 7)
    rim = np.clip(m - inner, 0, 1)
    density = opacity * (1 - mottle / 2 + mottle * fbm(seed + 3, (40, 20, 10)))
    density = density + edge * rim * 2.2
    density = density * (1 - gran / 2 + gran * GRAIN)
    a = np.clip(m * density, 0, 1)[..., None]
    canvas *= 1 - a * (1 - color)
    if alpha_out is not None:
        alpha_out[:] = np.maximum(alpha_out, a[..., 0])
    return m


def splatter(canvas, color, count, seed, region, opacity=0.5):
    rng = np.random.default_rng(seed)
    img = Image.new('L', (N, N), 0)
    d = ImageDraw.Draw(img)
    x0, y0, x1, y1 = region
    for _ in range(count):
        x, y = rng.uniform(x0, x1), rng.uniform(y0, y1)
        r = rng.choice([2, 3, 4, 6, 9], p=[0.35, 0.3, 0.2, 0.1, 0.05])
        d.ellipse((x - r, y - r, x + r, y + r), fill=255)
    m = np.asarray(img, dtype=np.float64) / 255
    wash(canvas, m, color, opacity, seed + 9, edge=0.8, wobble=1.5, soft=0.8)


# ------------------------------------------------------------- the motif

GREEN_DEEP = hexrgb('#1E5E46')
GREEN = hexrgb('#3E8F6A')
TEAL = hexrgb('#2F7F86')
MINT = hexrgb('#9FD8B6')
SAGE = hexrgb('#6FAE8C')
INK = hexrgb('#24463A')
CORAL = hexrgb('#F2545B')
AMBER = hexrgb('#FFB547')
ORANGE = hexrgb('#FF8A3D')
CREAM = hexrgb('#FBE2A8')


def page_shape(scale, cx, cy, tilt):
    """The page outline (a sheet with a folded corner) and its fold."""
    w, h, r, fold = 560 * scale, 700 * scale, 48 * scale, 170 * scale
    x0, y0 = cx - w / 2, cy - h / 2
    x1, y1 = x0 + w, y0 + h
    def arc(cx_, cy_, a0, steps=10):
        return [(cx_ + r * math.cos(math.radians(a0 + 90 * i / steps)),
                 cy_ + r * math.sin(math.radians(a0 + 90 * i / steps)))
                for i in range(steps + 1)]
    body = (arc(x0 + r, y0 + r, 180) + [(x1 - fold, y0), (x1, y0 + fold)]
            + arc(x1 - r, y1 - r, 0) + arc(x0 + r, y1 - r, 90))
    # The folded-over corner, lying on the page.
    flap = [(x1 - fold, y0), (x1 - fold * 0.92, y0 + fold * 0.92), (x1, y0 + fold)]
    return rotate(body, tilt, cx, cy), rotate(flap, tilt, cx, cy), (x0, y0, x1, y1)


def paint_motif(canvas, scale, cx, cy, alpha=None, shadow=True):
    tilt = -6
    body, flap, (x0, y0, x1, y1) = page_shape(scale, cx, cy, tilt)
    page = polygon_mask(body)

    if shadow:
        # A cool, soft shadow down and to the right lifts the page off.
        sh = ndi.shift(page, (26 * scale, 22 * scale), order=1)
        wash(canvas, ndi.gaussian_filter(sh, 18 * scale), hexrgb('#123B30'),
             0.55, 401, edge=0.1, wobble=0, soft=0, gran=0.2, alpha_out=alpha)

    # A second sheet behind, in mint, fanned out.
    back, _, _ = page_shape(scale, cx + 40 * scale, cy - 6 * scale, 8)
    wash(canvas, polygon_mask(back), MINT, 0.62, 402, edge=0.7, wobble=5,
         alpha_out=alpha)

    # The page is paper: knock everything back to white inside it, then a
    # whisper of warm wash so it reads as a sheet, not a hole.
    if alpha is not None:
        alpha[:] = np.maximum(alpha, ndi.gaussian_filter(page, 1.0))
    soft_page = ndi.gaussian_filter(warp(page, 3, 403), 1.0)
    canvas[:] = canvas * (1 - soft_page[..., None]) + \
        (PAPER * (1 - 0.05 * GRAIN[..., None]))[..., :] * soft_page[..., None]
    # Where the background wash met the dry page, pigment pooled into a
    # fine dark line.
    ring = np.clip(ndi.grey_dilation(page, size=(6, 6)) - page, 0, 1)
    ring *= np.clip(fbm(407, (30, 15)) * 1.6 - 0.2, 0, 1)  # broken, not drawn
    wash(canvas, ring, GREEN_DEEP, 0.3, 406, edge=0.2, wobble=2, soft=1.4)
    wash(canvas, page, hexrgb('#EFE0C2'), 0.22, 404, edge=1.1, wobble=3,
         mottle=0.7)
    wash(canvas, polygon_mask(flap), MINT, 0.55, 405, edge=0.8, wobble=2)

    # Lines of text, brushed in ink; the second is the highlighted one.
    lx0 = x0 + 90 * scale
    rows = [(y0 + 290 * scale, 1.00, 0.85), (y0 + 380 * scale, 0.92, 0.95),
            (y0 + 470 * scale, 0.86, 0.45), (y0 + 560 * scale, 0.60, 0.45)]
    width = (x1 - x0) - 170 * scale
    hl = None
    lines = np.zeros((N, N))
    for i, (y, frac, op) in enumerate(rows):
        pts = rotate(stroke(lx0, lx0 + width * frac, y, 30 * scale, 3, 500 + i),
                     tilt, cx, cy)
        if i == 1:
            # The highlighter: a broad, juicy wash in two hues.
            band = rotate(stroke(lx0 - 26 * scale, lx0 + width * frac + 30 * scale,
                                 y + 5 * scale, 84 * scale, 7, 520), tilt, cx, cy)
            hl = polygon_mask(band)
            wash(canvas, hl, AMBER, 0.62, 521, edge=0.3, wobble=9, mottle=0.6)
            grad = np.clip((np.mgrid[0:N, 0:N][1] - lx0) / (width * 1.1), 0, 1)
            wash(canvas, hl * grad, ORANGE, 0.5, 522, edge=0.25, wobble=9,
                 mottle=0.6)
        lines = np.maximum(lines, polygon_mask(pts))
        wash(canvas, polygon_mask(pts), INK if i != 1 else hexrgb('#5A2414'),
             op, 510 + i, edge=0.45, wobble=2, gran=0.5)

    # The marker, laid diagonally, its nib on the end of the highlight.
    tip_x = lx0 + width * 0.92 + 26 * scale
    tip_y = rows[1][0]
    tip = rotate([(tip_x, tip_y)], tilt, cx, cy)[0]
    ang = -34
    L, W = 420 * scale, 104 * scale
    bx = tip[0] + 46 * scale
    body_pts = rotate(rounded_rect(bx, tip[1] - W / 2, bx + L, tip[1] + W / 2,
                                   44 * scale), ang, tip[0], tip[1])
    cap_pts = rotate(rounded_rect(bx + L - 80 * scale, tip[1] - W / 2,
                                  bx + L + 8 * scale, tip[1] + W / 2, 30 * scale),
                     ang, tip[0], tip[1])
    nib = rotate([(tip[0] - 4 * scale, tip[1]), (bx + 30 * scale, tip[1] - W * 0.36),
                  (bx + 30 * scale, tip[1] + W * 0.36)], ang, tip[0], tip[1])
    shine = rotate(rounded_rect(bx + 30 * scale, tip[1] - W * 0.36,
                                bx + L - 110 * scale, tip[1] - W * 0.16, 9 * scale),
                   ang, tip[0], tip[1])
    pen = polygon_mask(body_pts)
    if shadow:
        sh = ndi.shift(pen, (30 * scale, 18 * scale), order=1)
        wash(canvas, ndi.gaussian_filter(sh, 14 * scale), hexrgb('#123B30'),
             0.45, 601, edge=0.1, wobble=0, soft=0, gran=0.2, alpha_out=alpha)
    # Leave the pen's own area as paper first, so it glows, then glaze.
    if alpha is not None:
        alpha[:] = np.maximum(alpha, ndi.gaussian_filter(pen, 1.0))
        alpha[:] = np.maximum(alpha, ndi.gaussian_filter(polygon_mask(nib), 1.0))
    canvas[:] = canvas * (1 - pen[..., None]) + PAPER * pen[..., None]
    wash(canvas, pen, AMBER, 0.8, 602, edge=0.6, wobble=3, mottle=0.6)
    yy, xx = np.mgrid[0:N, 0:N]
    along = np.clip(((xx - tip[0]) * math.cos(math.radians(ang)) +
                     (yy - tip[1]) * math.sin(math.radians(ang))) / (L * 1.2), 0, 1)
    wash(canvas, pen * (1 - along), CORAL, 0.75, 603, edge=0.5, wobble=3,
         mottle=0.6)
    wash(canvas, polygon_mask(cap_pts), CREAM, 0.7, 604, edge=0.7, wobble=2)
    wash(canvas, polygon_mask(nib), hexrgb('#C9303A'), 0.9, 605, edge=0.6,
         wobble=1.5)
    # A dry-brush highlight lifted out of the wet paint.
    lift = ndi.gaussian_filter(polygon_mask(shine), 3.5)[..., None] * 0.35
    canvas[:] = canvas * (1 - lift) + PAPER * lift
    return {'page': page, 'flap': polygon_mask(flap), 'lines': lines,
            'pen': np.maximum(pen, polygon_mask(nib))}


def background(canvas, seed=21):
    """A wet-in-wet wash over the whole square: deep green pooling at the
    bottom left, lightening toward the top right, with blooms."""
    yy, xx = np.mgrid[0:N, 0:N] / N
    diag = np.clip((xx + (1 - yy)) / 2, 0, 1)
    full = np.ones((N, N))
    wash(canvas, full, SAGE, 0.75, seed, edge=0, wobble=0, mottle=0.5)
    wash(canvas, full * (1 - diag) ** 1.2, GREEN, 0.85, seed + 1, edge=0,
         wobble=0, mottle=0.6)
    wash(canvas, full * np.clip(1 - diag * 1.5, 0, 1), GREEN_DEEP, 0.9,
         seed + 2, edge=0, wobble=0, mottle=0.5)
    # Teal drifting in from the top edge.
    tealm = np.clip(fbm(seed + 3, (120, 60)) * 1.8 - 0.75, 0, 1) * (1 - yy) ** 0.8
    wash(canvas, tealm, TEAL, 0.55, seed + 4, edge=0.3, wobble=0, soft=4)
    # Blooms: water dropped into a drying wash pushes pigment out into a
    # pale centre with a dark, frilly rim.
    rng = np.random.default_rng(seed + 5)
    for i in range(3):
        bx, by, br = rng.uniform(0.1, 0.9), rng.uniform(0.1, 0.9), rng.uniform(0.07, 0.16)
        d = np.sqrt((xx - bx) ** 2 + (yy - by) ** 2) / br
        frill = d + (fbm(seed + 10 + i, (14, 7)) - 0.5) * 0.5
        inside = np.clip(1 - frill, 0, 1)
        lift = (inside > 0) * np.clip(inside * 3, 0, 1) * 0.22
        canvas[:] = canvas + (PAPER - canvas) * lift[..., None]
        ring = np.exp(-((frill - 1) / 0.03) ** 2) * 0.2
        canvas *= 1 - ring[..., None] * (1 - GREEN_DEEP)
    # A breath of light, top right.
    glow = np.exp(-(((xx - 0.82) ** 2 + (yy - 0.12) ** 2) / 0.06))
    canvas[:] = canvas + (PAPER - canvas) * (glow * 0.28)[..., None]
    splatter(canvas, GREEN_DEEP, 16, seed + 30, (40, 40, N - 40, N - 40), 0.3)
    splatter(canvas, MINT, 12, seed + 31, (40, 40, N - 40, N - 40), 0.45)


def paper():
    c = np.ones((N, N, 3)) * PAPER
    return c * (1 - 0.06 * GRAIN[..., None])


def save(canvas, path, alpha=None):
    rgb = (np.clip(canvas, 0, 1) * 255).astype(np.uint8)
    if alpha is None:
        Image.fromarray(rgb, 'RGB').save(path, optimize=True)
    else:
        a = (np.clip(alpha, 0, 1) * 255).astype(np.uint8)
        Image.fromarray(np.dstack([rgb, a]), 'RGBA').save(path, optimize=True)
    print('wrote', path)


def main():
    os.makedirs(OUT, exist_ok=True)

    # iOS / README: the full painting, motif large.
    c = paper()
    background(c)
    paint_motif(c, 1.18, 470, 530)
    save(c, f'{OUT}/icon.png')

    # Android adaptive background: the wash alone.
    bg = paper()
    background(bg)
    save(bg, f'{OUT}/icon_background.png')

    # Android adaptive foreground: the motif on transparency, sized so the
    # page sits inside the safe zone of any launcher mask (circle included).
    fg = paper()
    alpha = np.zeros((N, N))
    shapes = paint_motif(fg, 0.62, 492, 516, alpha=alpha)
    save(fg, f'{OUT}/icon_foreground.png', alpha)

    # Themed (monochrome) icon: page and marker in one colour, with the
    # lines, the fold and a gap around the marker cut out so it reads.
    pen = shapes['pen'] > 0.5
    gap = ndi.binary_dilation(pen, iterations=10)
    fold = ndi.binary_dilation(shapes['flap'] > 0.5, iterations=3) & \
        ~ndi.binary_erosion(shapes['flap'] > 0.5, iterations=3)
    mono = (shapes['page'] > 0.5) & ~(shapes['lines'] > 0.5) & ~gap & ~fold
    mono = (mono | pen).astype(np.float64)
    save(np.ones((N, N, 3)), f'{OUT}/icon_monochrome.png',
         ndi.gaussian_filter(mono, 1.0))


if __name__ == '__main__':
    main()
