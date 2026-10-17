"""Makes the macOS app icon set from the full-bleed watercolour icon.

A Mac icon isn't full-bleed: Apple's grid puts an 824 px rounded square
(continuous corners) in a 1024 px canvas, with a soft shadow below, and
macOS 26+ boxes anything else in a grey tile. This crops the painted icon
into that shape and writes every size the asset catalog lists:

    python3 tool/branding/macos_icon.py
"""

import math
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "assets/branding/icon.png"
OUT = ROOT / "macos/Runner/Assets.xcassets/AppIcon.appiconset"

CANVAS = 1024
BODY = 824  # Apple's macOS icon grid
SCALE = 4  # supersampling for smooth edges


def squircle_mask(size: int) -> Image.Image:
    """A continuous-corner rounded square (superellipse, n=5), like Apple's."""
    big = size * SCALE
    mask = Image.new("L", (big, big), 0)
    draw = ImageDraw.Draw(mask)
    n = 5.0
    r = big / 2
    points = []
    steps = 2000
    for i in range(steps):
        t = 2 * math.pi * i / steps
        c, s = math.cos(t), math.sin(t)
        x = r + r * math.copysign(abs(c) ** (2 / n), c)
        y = r + r * math.copysign(abs(s) ** (2 / n), s)
        points.append((x, y))
    draw.polygon(points, fill=255)
    return mask.resize((size, size), Image.LANCZOS)


def main() -> None:
    art = Image.open(SOURCE).convert("RGBA").resize((BODY, BODY), Image.LANCZOS)
    mask = squircle_mask(BODY)
    art.putalpha(ImageChops.multiply(art.getchannel("A"), mask))

    canvas = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
    offset = (CANVAS - BODY) // 2
    # Shadow: the shape, blurred, a little below — as on Apple's template.
    shadow = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
    shadow_shape = Image.new("RGBA", (BODY, BODY), (0, 0, 0, 90))
    shadow_shape.putalpha(ImageChops.multiply(mask, Image.new("L", mask.size, 90)))
    shadow.paste(shadow_shape, (offset, offset + 10), shadow_shape)
    shadow = shadow.filter(ImageFilter.GaussianBlur(14))
    canvas = Image.alpha_composite(canvas, shadow)
    layer = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
    layer.paste(art, (offset, offset), art)
    canvas = Image.alpha_composite(canvas, layer)

    for size in (16, 32, 64, 128, 256, 512, 1024):
        canvas.resize((size, size), Image.LANCZOS).save(OUT / f"app_icon_{size}.png")
    print(f"Wrote {OUT}")


if __name__ == "__main__":
    main()
